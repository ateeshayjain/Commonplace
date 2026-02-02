import SwiftUI

struct CPButton: View {
    enum Style {
        case primary
        case secondary
        case text
        case destructive
    }

    enum Size {
        case small
        case medium
        case large

        var height: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 44
            case .large: return 50
            }
        }

        var font: Font {
            switch self {
            case .small: return .cpSubhead
            case .medium: return .cpBody
            case .large: return .cpHeadline
            }
        }
    }

    let title: String
    let style: Style
    let size: Size
    let isLoading: Bool
    let icon: String?
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .primary,
        size: Size = .large,
        isLoading: Bool = false,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: {
            HapticManager.buttonTap()
            action()
        }) {
            HStack(spacing: CPSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(size.font)
                    }

                    Text(title)
                        .font(size.font)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: style == .text ? nil : .infinity)
            .frame(height: style == .text ? nil : size.height)
            .foregroundColor(textColor)
            .background(backgroundColor)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return .cpTint
        case .secondary: return Color(.systemGray5)
        case .text: return .clear
        case .destructive: return .red
        }
    }

    private var textColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary: return .cpTint
        case .text: return .cpTint
        }
    }
}

// MARK: - Icon Button

struct CPIconButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    init(_ icon: String, size: CGFloat = 24, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: {
            HapticManager.buttonTap()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.6))
                .frame(width: size, height: size)
                .foregroundColor(.cpText)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CPButton("Primary Button", style: .primary) {}
        CPButton("Secondary Button", style: .secondary) {}
        CPButton("Text Button", style: .text) {}
        CPButton("Destructive", style: .destructive) {}
        CPButton("Loading", isLoading: true) {}
        CPButton("With Icon", icon: "plus") {}

        HStack {
            CPIconButton("heart") {}
            CPIconButton("square.and.arrow.up") {}
            CPIconButton("ellipsis") {}
        }
    }
    .padding()
}
