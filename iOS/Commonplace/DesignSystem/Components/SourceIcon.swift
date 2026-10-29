import SwiftUI

// MARK: - Source Icon

/// The platform's own logo (Instagram, YouTube, X, ...) for a saved item, or an
/// SF Symbol for generic sources (articles, PDFs, notes). Logos are single-colour
/// vectors from Simple Icons (CC0) in Assets.xcassets/Sources, tinted here.
struct SourceIcon: View {
    let type: SourceType
    var size: CGFloat = 14
    /// Overrides the platform colour, e.g. for logos on a dark share card
    var tint: Color?

    var body: some View {
        Group {
            if let asset = type.logoAsset {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: type.symbolName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(tint ?? type.logoColor)
        .accessibilityLabel(type.displayName)
    }
}

extension SourceType {
    /// Image set in Assets.xcassets/Sources, nil for sources without a platform logo
    var logoAsset: String? {
        switch self {
        case .twitter: return "Sources/x"
        case .linkedin, .linkedinArticle: return "Sources/linkedin"
        case .youtube: return "Sources/youtube"
        case .instagram: return "Sources/instagram"
        case .medium: return "Sources/medium"
        case .substack: return "Sources/substack"
        case .reddit: return "Sources/reddit"
        case .threads: return "Sources/threads"
        case .hackernews: return "Sources/ycombinator"
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .podcast: return "mic.fill"
        case .pdf: return "doc.richtext.fill"
        case .email: return "envelope.fill"
        case .screenshot: return "camera.viewfinder"
        case .manual: return "square.and.pencil"
        case .bookOcr: return "book.fill"
        default: return "doc.text.fill"
        }
    }

    /// X, Medium and Threads are black marks; the label colour keeps them visible in dark mode
    var logoColor: Color {
        switch self {
        case .twitter, .medium, .threads: return .cpText
        case .hackernews: return Color(hex: "#FF6600")
        default: return color
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(SourceType.allCases, id: \.self) { type in
            Label { Text(type.displayName) } icon: { SourceIcon(type: type, size: 18) }
        }
    }
    .padding()
}
