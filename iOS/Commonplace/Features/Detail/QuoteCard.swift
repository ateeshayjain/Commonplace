import SwiftUI

// MARK: - Shareable quotes

/// A line to put on a share card. Verbatim lines (documents.ai_quotable_lines,
/// checked word for word against the saved text) are credited to the author in
/// quotation marks; the hook is Sangrah's own summary, so it is shown as a key
/// idea "from" the piece instead of as the author's words.
struct ShareableQuote: Identifiable, Hashable {
    let text: String
    let isVerbatim: Bool
    var id: String { text }

    /// The hook first (the line people see at the top), then the author's own lines
    static func all(for document: Document) -> [ShareableQuote] {
        var quotes: [ShareableQuote] = []
        if let hook = document.aiHook?.trimmingCharacters(in: .whitespacesAndNewlines), !hook.isEmpty {
            quotes.append(ShareableQuote(text: hook, isVerbatim: false))
        }
        for line in document.aiQuotableLines ?? [] {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !quotes.contains(where: { $0.text.caseInsensitiveCompare(text) == .orderedSame }) else { continue }
            quotes.append(ShareableQuote(text: text, isVerbatim: true))
        }
        return quotes
    }

    /// Sentence case for display: each sentence starts with a capital, and a
    /// standalone "i" is "I". The stored line stays word for word as the author
    /// wrote it (that is what the verbatim check compares); this only changes
    /// how it reads on a card, as a quote would be set in print.
    var displayText: String { Self.sentenceCased(text) }

    /// Stops that end a word, not a sentence
    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "cf.", "mr.", "mrs.", "ms.", "dr.", "st."]

    static func sentenceCased(_ text: String) -> String {
        var result = ""
        var word = ""                  // the current word, to spot abbreviations
        var capitalizeNext = true      // start of the line, or after ". " "! " "? "
        var afterTerminator = false    // just saw . ! ? and waiting for a space
        for character in text {
            if character.isWhitespace {
                if afterTerminator && !abbreviations.contains(word.lowercased()) { capitalizeNext = true }
                afterTerminator = false
                word = ""
                result.append(character)
                continue
            }
            word.append(character)
            if character.isLetter {
                result += capitalizeNext ? character.uppercased() : String(character)
                capitalizeNext = false
                afterTerminator = false
                continue
            }
            result.append(character)
            if ".!?\u{2026}".contains(character) {
                afterTerminator = true
            } else if !"\"'\u{201C}\u{201D}\u{2018}\u{2019}()[]".contains(character) {
                // "3.5", "e.g" and the like: a terminator not followed by a space
                afterTerminator = false
                capitalizeNext = false
            }
        }
        return result.replacingOccurrences(
            of: #"(?<![\p{L}'\u2019])i(?=\s|['\u2019](?:m|ve|ll|d)\b|[,!?;:]|\.(?!\w)|$)"#,
            with: "I",
            options: .regularExpression
        )
    }

    /// The credit under a quote, one part per line on the cards
    struct Credit {
        let title: String
        let author: String?
        let source: String?
    }

    static func credit(for document: Document) -> Credit {
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        return Credit(
            title: document.title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: clean(document.authorName) ?? clean(document.authorHandle),
            source: clean(sourceName(for: document))
        )
    }

    /// The credit on one line ("Title, Author, Source"), for search
    static func creditLine(for document: Document) -> String {
        let credit = Self.credit(for: document)
        return [credit.title, credit.author, credit.source].compactMap { $0 }.joined(separator: ", ")
    }

    /// The platform's name, or the site's for plain articles ("stratechery.com", not "Article")
    static func sourceName(for document: Document) -> String? {
        switch document.sourceType {
        case .article, .unknown, .manual: return document.sourceDomain?.replacingOccurrences(of: "www.", with: "")
        // Read off the screenshots by Claude ("Substack", "The Atlantic"), when visible
        case .screenshot: return document.sourceDomain ?? document.sourceType.displayName
        default: return document.sourceType.displayName
        }
    }

    /// Caption for the post: links on an image can't be tapped, so the source link
    /// travels here (pasted into the caption, or into a Stories link sticker)
    func caption(for document: Document) -> String {
        let credit = Self.credit(for: document)
        var lines = [isVerbatim ? "\u{201C}\(displayText)\u{201D}" : displayText, ""]
        lines.append(isVerbatim ? "\u{2014} \(credit.title)" : "From \(credit.title)")
        if let author = credit.author { lines.append(author) }
        if let source = credit.source { lines.append(source) }
        if let url = document.sourceUrl {
            lines.append("")
            lines.append("Read it: \(url)")
        }
        lines.append("")
        lines.append("Saved with Sangrah")
        return lines.joined(separator: "\n")
    }
}

enum QuoteCardFormat: String, CaseIterable, Identifiable {
    case story, post
    var id: String { rawValue }

    var label: String {
        switch self {
        case .story: return "Story"
        case .post: return "Post"
        }
    }

    /// Layout size in points; rendered at 3x, so 1080 x 1920 (9:16) and 1080 x 1350 (4:5)
    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 360, height: 640)
        case .post: return CGSize(width: 360, height: 450)
        }
    }
}

// MARK: - The card (rendered to an image)

/// Sangrah's quote card: navy ground, cream type, the indigo ribbon as accent.
/// Fixed colours, not the adaptive tokens: the image must look the same
/// whatever mode the phone is in.
struct QuoteCardView: View {
    let quote: ShareableQuote
    let document: Document
    let format: QuoteCardFormat

    private let ribbon = Color(hex: "#8C9EFF") // indigo ribbon, dark-ground variant

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow

            Spacer(minLength: CPSpacing.lg)

            if quote.isVerbatim {
                Text("\u{201C}")
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundColor(ribbon)
                    .frame(height: 40, alignment: .top)
            } else {
                Text("KEY IDEA")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(ribbon)
                    .padding(.bottom, CPSpacing.sm)
            }

            Text(quote.displayText)
                .font(.system(size: format == .story ? 30 : 25, weight: .semibold, design: .serif))
                .foregroundColor(.cpBrandCream)
                .lineSpacing(4)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: format == .post)

            Spacer(minLength: CPSpacing.lg)

            attribution
        }
        .padding(.horizontal, 28)
        // Instagram covers a story's top (profile bar) and bottom (reply box)
        .padding(.vertical, format == .story ? 64 : 28)
        .frame(width: format.size.width, height: format.size.height, alignment: .topLeading)
        .background(Color.cpBrandNavy)
    }

    private var brandRow: some View {
        HStack(spacing: CPSpacing.xs) {
            Image("SangrahMark")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.cpBrandCream.opacity(0.25), lineWidth: 0.5)
                )
            Text("Sangrah")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.cpBrandCream)
        }
    }

    /// Title, author and source on their own lines; the link goes in the caption instead
    private var attribution: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xs) {
            Rectangle()
                .fill(ribbon)
                .frame(width: 32, height: 3)

            QuoteCreditView(
                document: document,
                isVerbatim: quote.isVerbatim,
                titleFont: .system(size: 14, weight: .semibold),
                detailFont: .system(size: 13),
                primary: .cpBrandCream,
                secondary: .cpBrandCream.opacity(0.7),
                iconTint: .cpBrandCream.opacity(0.8),
                titleLineLimit: 3
            )
        }
    }
}

// MARK: - Credit

/// "— Article title" / author / [logo] source, each on its own line. Shared by
/// the share image, the detail page's quote cards and the Quotes tab.
struct QuoteCreditView: View {
    let document: Document
    let isVerbatim: Bool
    var titleFont: Font = .cpFootnote.weight(.semibold)
    var detailFont: Font = .cpFootnote
    var primary: Color = .cpText
    var secondary: Color = .cpTextSecondary
    /// nil keeps the platform's own colour
    var iconTint: Color?
    var titleLineLimit = 2

    var body: some View {
        let credit = ShareableQuote.credit(for: document)

        VStack(alignment: .leading, spacing: 3) {
            // The key idea is Sangrah's line, so it is "from" the piece, not quoted from it
            Text(isVerbatim ? "\u{2014} \(credit.title)" : "From \(credit.title)")
                .font(titleFont)
                .foregroundColor(primary)
                .lineLimit(titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            if let author = credit.author {
                Text(author)
                    .font(detailFont)
                    .foregroundColor(secondary)
                    .lineLimit(1)
            }

            if let source = credit.source {
                HStack(spacing: 5) {
                    SourceIcon(type: document.sourceType, size: 13, tint: iconTint)
                    Text(source)
                        .font(detailFont)
                        .foregroundColor(secondary)
                        .lineLimit(1)
                }
            }
        }
        .multilineTextAlignment(.leading)
    }
}

/// The caption for apps that take text with an image (WhatsApp, Messages, Mail):
/// it travels with the picture. Left out where it gets in the way: Instagram
/// (which ignores it; the caption is on the clipboard), Save Image and Copy.
final class QuoteCaptionItem: NSObject, UIActivityItemSource {
    let caption: String

    init(_ caption: String) {
        self.caption = caption
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        caption
    }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let type = activityType?.rawValue else { return caption }
        let imageOnly: Set<UIActivity.ActivityType> = [.saveToCameraRoll, .copyToPasteboard, .assignToContact, .print, .airDrop]
        if imageOnly.contains(UIActivity.ActivityType(type)) || type.localizedCaseInsensitiveContains("instagram") {
            return nil
        }
        return caption
    }
}

// MARK: - Share sheet

/// Preview of a quote card with a Story / Post switch and a Share button. The
/// share sheet offers Instagram (Stories or Feed), Save Image, Messages, etc.
struct QuoteShareSheet: View {
    let quote: ShareableQuote
    let document: Document

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var format: QuoteCardFormat = .story
    @State private var shareItem: SharedImage?

    struct SharedImage: Identifiable {
        let image: UIImage
        let caption: String
        let id = UUID()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CPSpacing.lg) {
                Picker("Format", selection: $format) {
                    ForEach(QuoteCardFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                GeometryReader { geometry in
                    let size = format.size
                    let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
                    QuoteCardView(quote: quote, document: document, format: format)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .clipShape(RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(spacing: CPSpacing.xs) {
                    CPButton("Share", icon: "square.and.arrow.up") {
                        if let image = render() {
                            // Only the image goes to the share sheet (Instagram's extension
                            // takes images); the caption with the link waits on the clipboard
                            UIPasteboard.general.string = quote.caption(for: document)
                            shareItem = SharedImage(image: image, caption: quote.caption(for: document))
                        }
                    }

                    Label("WhatsApp and Messages get the caption with the source link. For Instagram it's on your clipboard: paste it into the post or a link sticker.", systemImage: "doc.on.clipboard")
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(CPSpacing.screenHorizontal)
            .navigationTitle("Share Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.image, QuoteCaptionItem(item.caption)])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    /// Renders at 3x whatever the screen, so the image is 1080 px wide for Instagram
    @MainActor
    private func render() -> UIImage? {
        let renderer = ImageRenderer(content: QuoteCardView(quote: quote, document: document, format: format))
        renderer.scale = max(3, displayScale)
        renderer.proposedSize = ProposedViewSize(format.size)
        return renderer.uiImage
    }
}

#Preview {
    QuoteCardView(
        quote: ShareableQuote(text: "The future belongs to those who embrace AI as a tool, not a threat.", isVerbatim: true),
        document: .preview,
        format: .story
    )
}
