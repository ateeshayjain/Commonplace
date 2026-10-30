import Foundation

/// The reader's bookmarked quotes, shared by the quote cards (filled bookmark)
/// and the Quotes tab. Changes show at once and are rolled back if the server
/// refuses them.
@MainActor
final class SavedQuoteService: ObservableObject {
    static let shared = SavedQuoteService()

    /// Newest first
    @Published private(set) var quotes: [SavedQuote] = [] {
        didSet { WidgetQuoteSync.shared.bookmarksChanged(quotes) }
    }
    @Published private(set) var isLoading = false
    @Published var error: Error?

    private let supabase = SupabaseService.shared
    /// Whose quotes `quotes` holds, so a different sign-in starts empty
    private var loadedUserId: UUID?

    private var isDemo: Bool {
        AuthService.shared.currentUser?.email == "demo@commonplace.app"
    }

    private init() {}

    /// Drops the signed-out account's quotes from memory
    func reset() {
        quotes = []
        loadedUserId = nil
    }

    // MARK: - Reading

    func load(force: Bool = false) async {
        let userId = AuthService.shared.currentUser?.id
        if loadedUserId != userId {
            quotes = []
            loadedUserId = nil
        }
        guard force || loadedUserId == nil, let userId else { return }

        // Demo bookmarks live only in memory
        if isDemo {
            loadedUserId = userId
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            quotes = try await supabase.fetch(
                from: "saved_quotes",
                select: "*,document:documents(*)",
                order: "created_at.desc"
            )
            loadedUserId = userId
        } catch {
            self.error = error
        }
    }

    func isSaved(_ quote: ShareableQuote, in documentId: UUID) -> Bool {
        savedQuote(quote.text, in: documentId) != nil
    }

    private func savedQuote(_ text: String, in documentId: UUID) -> SavedQuote? {
        quotes.first { $0.documentId == documentId && $0.text == text }
    }

    // MARK: - Changes

    func toggle(_ quote: ShareableQuote, in document: Document) {
        if isSaved(quote, in: document.id) {
            remove(quote.text, in: document.id)
        } else {
            save(quote, in: document)
        }
    }

    func save(_ quote: ShareableQuote, in document: Document) {
        guard !isSaved(quote, in: document.id) else { return }

        let local = SavedQuote(
            id: UUID(),
            documentId: document.id,
            text: quote.text,
            isVerbatim: quote.isVerbatim,
            createdAt: Date(),
            document: document
        )
        quotes.insert(local, at: 0)
        HapticManager.saveSuccess()
        guard !isDemo else { return }

        Task {
            do {
                _ = try await supabase.insert(
                    into: "saved_quotes",
                    values: NewRow(id: local.id, documentId: document.id, text: quote.text, isVerbatim: quote.isVerbatim)
                )
            } catch {
                // Most likely saved already from another device; take the server's list
                quotes.removeAll { $0.id == local.id }
                self.error = error
                await load(force: true)
            }
        }
    }

    func remove(_ text: String, in documentId: UUID) {
        guard let saved = savedQuote(text, in: documentId) else { return }
        remove(saved)
    }

    func remove(_ saved: SavedQuote) {
        guard let index = quotes.firstIndex(of: saved) else { return }
        quotes.remove(at: index)
        guard !isDemo else { return }

        let owner = loadedUserId
        Task {
            do {
                try await supabase.delete(from: "saved_quotes", id: saved.id)
            } catch {
                // Only put it back for the account it came from
                guard loadedUserId == owner else { return }
                quotes.insert(saved, at: min(index, quotes.count))
                self.error = error
            }
        }
    }

    /// The insert body; the id is chosen here so the row matches the one shown
    private struct NewRow: Codable {
        let id: UUID
        let documentId: UUID
        let text: String
        let isVerbatim: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case documentId = "document_id"
            case text
            case isVerbatim = "is_verbatim"
        }
    }
}
