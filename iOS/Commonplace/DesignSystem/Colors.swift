import SwiftUI

extension Color {
    // MARK: - Semantic Colors

    /// Primary background color
    static let cpBackground = Color(uiColor: .systemBackground)

    /// Secondary background color (cards, grouped content)
    static let cpBackgroundSecondary = Color(uiColor: .secondarySystemBackground)

    /// Tertiary background color
    static let cpBackgroundTertiary = Color(uiColor: .tertiarySystemBackground)

    /// Primary text color
    static let cpText = Color(uiColor: .label)
    static let cpPrimary = Color(uiColor: .label)

    /// Secondary text color
    static let cpTextSecondary = Color(uiColor: .secondaryLabel)
    static let cpSecondary = Color(uiColor: .secondaryLabel)

    /// Tertiary text color
    static let cpTextTertiary = Color(uiColor: .tertiaryLabel)
    static let cpTertiary = Color(uiColor: .tertiaryLabel)

    /// Separator/divider color
    static let cpSeparator = Color(uiColor: .separator)

    /// Primary tint/accent color: the ribbon red from the app icon
    /// (#C0402A light / #D9573F dark, defined in Assets.xcassets/AccentColor)
    static let cpTint = Color("AccentColor")
    static let cpAccent = Color("AccentColor")

    /// Brand palette from the app icon. Use for marketing surfaces and the
    /// sign-in screen only; everyday UI stays on semantic tokens.
    static let cpBrandNavy = Color(hex: "#1C2140")
    static let cpBrandCream = Color(hex: "#F4EDE0")
    static let cpBrandRibbon = Color(hex: "#C0402A")

    // MARK: - Source Type Colors

    static let cpTwitter = Color(hex: "#1DA1F2")
    static let cpLinkedIn = Color(hex: "#0A66C2")
    static let cpYouTube = Color(hex: "#FF0000")
    static let cpInstagram = Color(hex: "#E4405F")
    static let cpMedium = Color(hex: "#000000")
    static let cpSubstack = Color(hex: "#FF6719")
    static let cpReddit = Color(hex: "#FF4500")

    // MARK: - Status Colors

    static let cpSuccess = Color.green
    static let cpWarning = Color.orange
    static let cpError = Color.red
    static let cpInfo = Color.blue

    // MARK: - Category Colors

    static let cpTechnology = Color(hex: "#007AFF")
    static let cpBusiness = Color(hex: "#34C759")
    static let cpHealth = Color(hex: "#FF3B30")
    static let cpScience = Color(hex: "#AF52DE")
    static let cpCulture = Color(hex: "#FF9500")
    static let cpPolitics = Color(hex: "#5856D6")
    static let cpDesign = Color(hex: "#FF2D55")
    static let cpPersonalDev = Color(hex: "#00C7BE")
}

// MARK: - Color for Source Type

extension SourceType {
    var color: Color {
        switch self {
        case .twitter: return .cpTwitter
        case .linkedin, .linkedinArticle: return .cpLinkedIn
        case .youtube: return .cpYouTube
        case .instagram: return .cpInstagram
        case .medium: return .cpMedium
        case .substack: return .cpSubstack
        case .reddit: return .cpReddit
        default: return .cpTint
        }
    }
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
