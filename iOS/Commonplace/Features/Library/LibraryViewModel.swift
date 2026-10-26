import Foundation
import SwiftUI

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var filteredDocuments: [Document] = []
    @Published var categories: [Category] = Category.systemCategories
    @Published var tags: [Tag] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var sortOrder: SortOrder = .newest {
        didSet {
            sortDocuments()
        }
    }

    private let documentService = DocumentService.shared
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

            filteredDocuments = documents
            sortDocuments()
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

        if query.isEmpty {
            filteredDocuments = documents
        } else {
            let lowercased = query.lowercased()
            filteredDocuments = documents.filter { document in
                document.title.lowercased().contains(lowercased) ||
                document.authorName?.lowercased().contains(lowercased) == true ||
                document.aiSummaryShort?.lowercased().contains(lowercased) == true ||
                document.userCategories.contains { $0.lowercased().contains(lowercased) }
            }
        }

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

        // Real mode: call the API
        isLoading = true
        do {
            let response = try await documentService.saveURL(urlString)
            print("Saved URL: \(response)")
            await loadDocuments() // Refresh to get the new document
            HapticManager.saveSuccess()
        } catch {
            self.error = error
            HapticManager.error()
        }
        isLoading = false
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
