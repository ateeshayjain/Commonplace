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

            Text(quote.text)
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

    private var attribution: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xxs) {
            Rectangle()
                .fill(ribbon)
                .frame(width: 32, height: 3)
                .padding(.bottom, CPSpacing.xs)

            if quote.isVerbatim {
                Text("\u{2014} \(authorLine)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.cpBrandCream)
                Text(document.title)
                    .font(.system(size: 12))
                    .foregroundColor(.cpBrandCream.opacity(0.7))
                    .lineLimit(2)
            } else {
                // Sangrah's summary: credit the piece and its author, not as their words
                Text("From \u{201C}\(document.title)\u{201D}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cpBrandCream)
                    .lineLimit(2)
                Text("by \(authorLine)")
                    .font(.system(size: 12))
                    .foregroundColor(.cpBrandCream.opacity(0.7))
            }

            if let link = displayLink {
                HStack(spacing: 5) {
                    SourceIcon(type: document.sourceType, size: 11, tint: .cpBrandCream.opacity(0.6))
                    Text(link)
                        .font(.system(size: 11))
                        .foregroundColor(.cpBrandCream.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, CPSpacing.xxs)
            }
        }
    }

    private var authorLine: String {
        document.authorName ?? document.authorHandle ?? document.sourceDomain ?? document.sourceType.displayName
    }

    /// host/path without the scheme, "www." or share-tracking parameters
    private var displayLink: String? {
        guard let raw = document.sourceUrl, var parts = URLComponents(string: raw), let host = parts.host else { return nil }
        parts.query = nil
        parts.fragment = nil
        let path = parts.path == "/" ? "" : parts.path
        return host.replacingOccurrences(of: "www.", with: "") + path
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

                CPButton("Share", icon: "square.and.arrow.up") {
                    if let image = render() {
                        shareItem = SharedImage(image: image)
                    }
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
                ActivityView(items: [item.image])
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
