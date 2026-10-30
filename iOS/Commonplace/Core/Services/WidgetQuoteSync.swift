import Foundation
import WidgetKit

/// Keeps the home-screen widget's quote pool (WidgetQuoteStore) in step with
/// the app: bookmarked quotes plus the Key Idea of every save the app has
/// loaded. Bookmarks are replaced as a whole; Key Ideas build up as the
/// Library loads saves and drop out when a save is deleted.
@MainActor
final class WidgetQuoteSync {
    static let shared = WidgetQuoteSync()

    private var bookmarks: [WidgetQuote] = []
    private var keyIdeas: [UUID: WidgetQuote] = [:]

    private init() {
        // Start from what was written last time, so a cold launch doesn't empty the widget
        for quote in WidgetQuoteStore.loadPool() {
            if quote.id.hasPrefix("idea:") {
                keyIdeas[quote.documentId] = quote
            } else {
                bookmarks.append(quote)
            }
        }
    }

    func bookmarksChanged(_ quotes: [SavedQuote]) {
        // A late rollback after sign-out mustn't put the old account back on the home screen
        guard AuthService.shared.isAuthenticated else { return }
        bookmarks = quotes.compactMap { saved in
            guard let document = saved.document else { return nil }
            return Self.widgetQuote(
                id: "bookmark:\(saved.id.uuidString)",
                quote: saved.shareable,
                document: document
            )
        }
        publish()
    }

    /// Adds or refreshes the Key Idea of each save
    func documentsLoaded(_ documents: [Document]) {
        guard AuthService.shared.isAuthenticated else { return }
        for document in documents {
            guard let idea = ShareableQuote.all(for: document).first(where: { !$0.isVerbatim }) else {
                keyIdeas[document.id] = nil
                continue
            }
            keyIdeas[document.id] = Self.widgetQuote(id: "idea:\(document.id.uuidString)", quote: idea, document: document)
        }
        publish()
    }

    func documentDeleted(_ id: UUID) {
        keyIdeas[id] = nil
        bookmarks.removeAll { $0.documentId == id }
        publish()
    }

    /// Signing out leaves nothing of the account on the home screen
    func clear() {
        bookmarks = []
        keyIdeas = [:]
        publish()
    }

    private func publish() {
        // A bookmarked Key Idea shows once, as the bookmark
        let bookmarked = Set(bookmarks.map { "\($0.documentId)|\($0.text)" })
        let ideas = keyIdeas.values.filter { !bookmarked.contains("\($0.documentId)|\($0.text)") }
        let pool = bookmarks + ideas
        guard pool != WidgetQuoteStore.loadPool() else { return }
        WidgetQuoteStore.savePool(pool)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetQuoteStore.widgetKind)
    }

    private static func widgetQuote(id: String, quote: ShareableQuote, document: Document) -> WidgetQuote {
        let credit = ShareableQuote.credit(for: document)
        return WidgetQuote(
            id: id,
            text: quote.displayText,
            isVerbatim: quote.isVerbatim,
            isKeyIdea: !quote.isVerbatim,
            title: credit.title,
            author: credit.author,
            source: credit.source,
            documentId: document.id
        )
    }
}
