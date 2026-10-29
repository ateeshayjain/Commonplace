import Foundation

@MainActor
final class QuotesViewModel: ObservableObject {
    @Published var searchText = ""

    /// Quotes whose words, title, author or source match the search
    func filtered(_ quotes: [SavedQuote]) -> [SavedQuote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = quotes.filter { $0.document != nil }
        guard !query.isEmpty else { return visible }

        return visible.filter { quote in
            let fields = [quote.text, quote.document.map(ShareableQuote.credit(for:)) ?? ""]
            return fields.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}
