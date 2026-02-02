import SwiftUI

extension Font {
    // MARK: - Apple Type Scale

    /// Large title - 34pt Bold
    static let cpLargeTitle = Font.system(size: 34, weight: .bold)

    /// Title 1 - 28pt Bold
    static let cpTitle1 = Font.system(size: 28, weight: .bold)

    /// Title 2 - 22pt Bold
    static let cpTitle2 = Font.system(size: 22, weight: .bold)

    /// Title 3 - 20pt Semibold
    static let cpTitle3 = Font.system(size: 20, weight: .semibold)

    /// Headline - 17pt Semibold
    static let cpHeadline = Font.system(size: 17, weight: .semibold)

    /// Body - 17pt Regular
    static let cpBody = Font.system(size: 17, weight: .regular)

    /// Callout - 16pt Regular
    static let cpCallout = Font.system(size: 16, weight: .regular)

    /// Subhead - 15pt Regular
    static let cpSubhead = Font.system(size: 15, weight: .regular)

    /// Footnote - 13pt Regular
    static let cpFootnote = Font.system(size: 13, weight: .regular)

    /// Caption 1 - 12pt Regular
    static let cpCaption1 = Font.system(size: 12, weight: .regular)

    /// Caption 2 - 11pt Regular
    static let cpCaption2 = Font.system(size: 11, weight: .regular)
}

// MARK: - Section Header Style

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.cpTextSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

extension View {
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderStyle())
    }
}

// MARK: - Link Style

struct LinkTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.cpBody)
            .foregroundColor(.cpTint)
    }
}

extension View {
    func linkTextStyle() -> some View {
        modifier(LinkTextStyle())
    }
}

// MARK: - Label Style

struct LabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.cpFootnote)
            .foregroundColor(.cpTextSecondary)
    }
}

extension View {
    func labelStyle() -> some View {
        modifier(LabelStyle())
    }
}
