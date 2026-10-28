import Foundation
import SwiftUI

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var filteredDocuments: [Document] = []
    @Published var categories: [Category] = Category.systemCategories
    @Published var tags: [Tag] = []
    @Published var isLoading = false
    /// Links saved from this device whose AI processing has not finished yet.
    @Published var pendingSaveCount = 0
    /// Second filter axis next to categories: where the item came from.
    @Published var selectedSource: SourceType? {
        didSet { applyFilters() }
    }

    /// Sources present in the loaded documents, most common first.
    var availableSources: [SourceType] {
        var counts: [SourceType: Int] = [:]
        for document in documents { counts[document.sourceType, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key.displayName < $1.key.displayName : $0.value > $1.value }
            .map(\.key)
    }
    @Published var error: Error?
    @Published var sortOrder: SortOrder = .newest {
        didSet {
            sortDocuments()
        }
    }

    private let documentService = DocumentService.shared
    private var deletionObserver: NSObjectProtocol?

    init() {
        deletionObserver = NotificationCenter.default.addObserver(
            forName: .documentDeleted, object: nil, queue: .main
        ) { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor in self?.removeDocument(id: id) }
        }
    }

    deinit {
        if let deletionObserver { NotificationCenter.default.removeObserver(deletionObserver) }
    }

    /// Drop a document deleted elsewhere (e.g. from its detail screen) without a reload.
    func removeDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        filteredDocuments.removeAll { $0.id == id }
    }
    private var searchQuery = ""

    enum SortOrder {
        case newest
        case oldest
        case favorites
    }

    struct DocumentGroup: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let documents: [Document]
    }

    var groupedDocuments: [DocumentGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredDocuments) { document in
            calendar.startOfDay(for: document.createdAt)
        }

        return grouped.map { date, docs in
            DocumentGroup(
                date: date,
                title: formatGroupTitle(date),
                documents: docs.sorted {
                    switch sortOrder {
                    case .newest: return $0.createdAt > $1.createdAt
                    case .oldest: return $0.createdAt < $1.createdAt
                    case .favorites: return $0.isFavorite && !$1.isFavorite
                    }
                }
            )
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: - Loading

    func loadDocuments(category: String? = nil, tagId: UUID? = nil) async {
        isLoading = true
        error = nil

        do {
            // For demo mode, use local data
            if AuthService.shared.currentUser?.email == "demo@commonplace.app" {
                documents = documentService.fetchDemoDocuments()
                if let category = category {
                    documents = documents.filter { $0.userCategories.contains(category) }
                }
                // Demo tags mirror AI topics, so filter on the tag's name
                if let tagId = tagId, let tag = tags.first(where: { $0.id == tagId }) {
                    documents = documents.filter { $0.aiTopics?.contains(tag.name) == true }
                }
            } else {
                documents = try await documentService.fetchDocuments(category: category, tagId: tagId)
            }

            applyFilters()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func loadTags() async {
        if isDemoMode {
            // Demo tags get fresh ids each time, so build them once to keep a selection valid
            if tags.isEmpty {
                let userId = AuthService.shared.currentUser?.id ?? UUID()
                tags = documentService.demoTags(for: documentService.fetchDemoDocuments(), userId: userId)
            }
            return
        }

        do {
            tags = try await documentService.fetchAllTags()
        } catch {
            // The filter row simply stays hidden if tags can't be loaded
            tags = []
        }
    }

    func refresh(category: String? = nil, tagId: UUID? = nil) async {
        await loadTags()
        await loadDocuments(category: category, tagId: tagId)
    }

    // MARK: - Filtering & Sorting

    func filterDocuments(query: String) {
        searchQuery = query
        applyFilters()
    }

    /// Client-side filters on top of what the server returned: source and search text.
    private func applyFilters() {
        var result = documents
        if let source = selectedSource {
            result = result.filter { $0.sourceType == source }
        }
        if !searchQuery.isEmpty {
            let lowercased = searchQuery.lowercased()
            result = result.filter { document in
                document.title.lowercased().contains(lowercased) ||
                document.authorName?.lowercased().contains(lowercased) == true ||
                document.aiSummaryShort?.lowercased().contains(lowercased) == true ||
                document.userCategories.contains { $0.lowercased().contains(lowercased) }
            }
        }
        filteredDocuments = result
        sortDocuments()
    }

    private func sortDocuments() {
        switch sortOrder {
        case .newest:
            filteredDocuments.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            filteredDocuments.sort { $0.createdAt < $1.createdAt }
        case .favorites:
            filteredDocuments.sort { $0.isFavorite && !$1.isFavorite }
        }
    }

    // MARK: - Demo Mode Check

    private var isDemoMode: Bool {
        AuthService.shared.currentUser?.email == "demo@commonplace.app"
    }

    // MARK: - Actions

    func toggleFavorite(_ document: Document) async {
        // Demo mode: just toggle locally
        if isDemoMode {
            if let index = documents.firstIndex(where: { $0.id == document.id }) {
                documents[index].isFavorite.toggle()
            }
            if let index = filteredDocuments.firstIndex(where: { $0.id == document.id }) {
                filteredDocuments[index].isFavorite.toggle()
            }
            HapticManager.saveSuccess()
            return
        }

        do {
            try await documentService.toggleFavorite(document.id, isFavorite: !document.isFavorite)

            if let index = documents.firstIndex(where: { $0.id == document.id }) {
                documents[index].isFavorite.toggle()
            }
            if let index = filteredDocuments.firstIndex(where: { $0.id == document.id }) {
                filteredDocuments[index].isFavorite.toggle()
            }

            HapticManager.saveSuccess()
        } catch {
            self.error = error
            HapticManager.error()
        }
    }

    func delete(_ document: Document) async {
        // Demo mode: just remove locally
        if isDemoMode {
            documents.removeAll { $0.id == document.id }
            filteredDocuments.removeAll { $0.id == document.id }
            HapticManager.deleteWarning()
            return
        }

        do {
            try await documentService.deleteDocument(document.id)

            documents.removeAll { $0.id == document.id }
            filteredDocuments.removeAll { $0.id == document.id }

            HapticManager.deleteWarning()
        } catch {
            self.error = error
            HapticManager.error()
        }
    }

    // MARK: - Add Document (Demo Mode)

    func addDocumentFromURL(_ urlString: String) async {
        // Demo mode: create a mock document locally
        if isDemoMode {
            let domain = URL(string: urlString)?.host ?? "example.com"
            let newDoc = Document(
                id: UUID(),
                userId: UUID(),
                sourceType: .article,
                sourceUrl: urlString,
                sourceDomain: domain,
                capturedAt: Date(),
                originalPublishedAt: Date(),
                isSourceDeleted: false,
                authorName: "Demo Author",
                authorHandle: nil,
                authorUrl: nil,
                authorAvatarUrl: nil,
                title: "New Article from \(domain)",
                subtitle: nil,
                bodyPlain: "This is a demo article. In the real app, AI would extract and summarize the content.",
                wordCount: 500,
                readingTimeMinutes: 3,
                language: "en",
                engagement: nil,
                commentsSummary: nil,
                sentiment: .neutral,
                isThread: false,
                threadPosition: nil,
                threadTotal: nil,
                threadId: nil,
                aiSummaryShort: "This is a demo article saved from \(domain). In the real app, Claude AI would generate a smart summary with key insights.",
                aiSummaryLong: nil,
                aiKeyPoints: ["Demo insight 1", "Demo insight 2", "Demo insight 3"],
                aiCategories: ["General"],
                aiTopics: ["Demo"],
                aiComplexityScore: 5,
                aiReadingLevel: .intermediate,
                aiContentType: .analysis,
                aiQuotableLines: nil,
                pdfUrl: "demo://pdf/\(UUID().uuidString)",
                pdfVersion: 1,
                thumbnailUrl: nil,
                screenshotUrl: nil,
                userCategories: [],
                userNotes: nil,
                isFavorite: false,
                isArchived: false,
                readProgress: 0,
                lastReadAt: nil,
                processingStatus: .completed,
                processingError: nil,
                createdAt: Date(),
                updatedAt: Date(),
                processedAt: Date()
            )

            documents.insert(newDoc, at: 0)
            filteredDocuments.insert(newDoc, at: 0)
            HapticManager.saveSuccess()
            return
        }

        // Real mode: process-url returns as soon as the row exists and keeps
        // working in the background (fetching, extracting, enriching), so the
        // Library, which lists completed documents only, would miss it if we
        // refreshed just once. Return now so the sheet can close, then poll.
        do {
            let response = try await documentService.saveURL(urlString)
            HapticManager.saveSuccess()
            pendingSaveCount += 1
            Task { await waitForProcessing(of: response.id) }
        } catch {
            self.error = error
            HapticManager.error()
        }
    }

    /// Polls one document until it leaves the processing pipeline, then
    /// refreshes the list. Gives up after about two minutes.
    private func waitForProcessing(of id: UUID) async {
        defer { pendingSaveCount = max(0, pendingSaveCount - 1) }
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(2))
            guard let document = try? await documentService.fetchDocument(id: id) else { continue }
            switch document.processingStatus {
            case .completed:
                await loadDocuments()
                return
            case .failed:
                self.error = DocumentProcessingError(
                    message: document.processingError ?? "We couldn't process that link."
                )
                return
            default:
                continue
            }
        }
        await loadDocuments()
    }

    // MARK: - Helpers

    private func formatGroupTitle(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        }
    }
}

/// Surfaced when process-url marks a document as failed.
struct DocumentProcessingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
