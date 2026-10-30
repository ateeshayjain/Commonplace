import AppIntents
import SwiftUI
import WidgetKit

// Home-screen widget: one quote a day from the reader's bookmarks and Key
// Ideas, with a shuffle button for another. The pool comes from the app via
// the App Group (WidgetQuoteStore); the widget never touches the network.

// MARK: - Timeline

struct QuoteEntry: TimelineEntry {
    let date: Date
    let quote: WidgetQuote?
}

struct QuoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(date: Date(), quote: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuoteEntry) -> Void) {
        // The widget gallery shows a sample until there's something saved
        let quote = WidgetQuoteStore.quote() ?? (context.isPreview ? .sample : nil)
        completion(QuoteEntry(date: Date(), quote: quote))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuoteEntry>) -> Void) {
        let now = Date()
        let entry = QuoteEntry(date: now, quote: WidgetQuoteStore.quote(on: now))
        // A new quote at midnight; the app reloads sooner when the pool changes
        completion(Timeline(entries: [entry], policy: .after(WidgetQuoteStore.nextChange(after: now))))
    }
}

// MARK: - Shuffle

struct ShuffleQuoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle Quote"
    static var description = IntentDescription("Shows a different saved quote until midnight.")

    func perform() async throws -> some IntentResult {
        WidgetQuoteStore.shuffle()
        return .result()
    }
}

// MARK: - Views

struct QuoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuoteEntry

    var body: some View {
        Group {
            if let quote = entry.quote {
                content(quote)
            } else {
                emptyState
            }
        }
        .containerBackground(Color.cpBrandNavy, for: .widget)
        .widgetURL(URL(string: "commonplace://quotes"))
    }

    private var quoteSize: CGFloat {
        switch family {
        case .systemSmall: return 15
        case .systemLarge: return 24
        default: return 18
        }
    }

    private func content(_ quote: WidgetQuote) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
            HStack(alignment: .center) {
                Text(quote.isKeyIdea ? "KEY IDEA" : "QUOTE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.cpBrandCream.opacity(0.6))
                Spacer(minLength: 4)
                Button(intent: ShuffleQuoteIntent()) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.cpBrandCream)
                        .frame(width: 28, height: 28)
                        .background(Color.cpBrandCream.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Shuffle quote")
            }

            Text(quote.isVerbatim ? "\u{201C}\(quote.text)\u{201D}" : quote.text)
                .font(.system(size: quoteSize, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Color.cpBrandCream)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            credit(quote)
        }
    }

    /// Same wording as the quote cards in the app: "— Title" for a quote,
    /// "From Title" for a Key Idea, then author and source
    private func credit(_ quote: WidgetQuote) -> some View {
        let detail = [quote.author.map { "By \($0)" }, quote.source.map { "On \($0)" }]
            .compactMap { $0 }
            .joined(separator: " \u{00B7} ")

        return VStack(alignment: .leading, spacing: 1) {
            Text(quote.isVerbatim ? "\u{2014} \(quote.title)" : "From \(quote.title)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.cpBrandCream)
                .lineLimit(family == .systemLarge ? 2 : 1)
            if family != .systemSmall && !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.cpBrandCream.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 20, weight: .semibold))
            Text("Save an article or bookmark a quote in Sangrah to see it here.")
                .font(.system(size: family == .systemSmall ? 13 : 15, weight: .medium, design: .serif))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.cpBrandCream)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget

@main
struct SangrahQuoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetQuoteStore.widgetKind, provider: QuoteProvider()) { entry in
            QuoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Quote")
        .description("A quote from your Sangrah library each day. Tap shuffle for another.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension WidgetQuote {
    static let sample = WidgetQuote(
        id: "sample",
        text: "In a world that wants you to rush, the ultimate act of rebellion is presence.",
        isVerbatim: false,
        isKeyIdea: true,
        title: "Your life in weeks",
        author: "Sahil Bloom",
        source: "X",
        documentId: UUID()
    )
}
