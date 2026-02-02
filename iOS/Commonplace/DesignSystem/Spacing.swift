import SwiftUI

/// Consistent spacing values used throughout the app
enum CPSpacing {
    /// 4pt
    static let xxs: CGFloat = 4

    /// 8pt
    static let xs: CGFloat = 8

    /// 12pt
    static let sm: CGFloat = 12

    /// 16pt
    static let md: CGFloat = 16

    /// 20pt
    static let lg: CGFloat = 20

    /// 24pt
    static let xl: CGFloat = 24

    /// 32pt
    static let xxl: CGFloat = 32

    /// 48pt
    static let xxxl: CGFloat = 48

    // MARK: - Specific Use Cases

    /// Horizontal padding for full-width screens (20pt)
    static let screenHorizontal: CGFloat = 20

    /// Vertical padding for screens (16pt)
    static let screenVertical: CGFloat = 16

    /// Internal padding for cards (16pt)
    static let cardPadding: CGFloat = 16

    /// Vertical spacing between list items (12pt)
    static let listItemVertical: CGFloat = 12

    /// Spacing between sections (24pt)
    static let sectionSpacing: CGFloat = 24

    /// Corner radius for small elements (8pt)
    static let cornerRadiusSmall: CGFloat = 8

    /// Corner radius for medium elements (12pt)
    static let cornerRadiusMedium: CGFloat = 12

    /// Corner radius for large elements (16pt)
    static let cornerRadiusLarge: CGFloat = 16
}

// MARK: - View Extensions

extension View {
    /// Apply standard screen padding
    func screenPadding() -> some View {
        self.padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.screenVertical)
    }

    /// Apply card-style padding
    func cardPadding() -> some View {
        self.padding(CPSpacing.cardPadding)
    }
}
