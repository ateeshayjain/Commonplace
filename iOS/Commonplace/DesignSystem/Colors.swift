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

    /// Primary tint/accent color: the ribbon indigo from the app icon
    /// (#3F51B5 light / #8C9EFF dark, defined in Assets.xcassets/AccentColor)
    static let cpTint = Color("AccentColor")
    static let cpAccent = Color("AccentColor")

    // Brand palette (cpBrandNavy, cpBrandCream, cpBrandRibbon): BrandColors.swift,
    // shared with the quote widget

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
