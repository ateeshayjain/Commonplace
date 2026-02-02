import SwiftUI

struct CPCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(CPSpacing.cardPadding)
            .background(Color.cpBackgroundSecondary)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
    }
}

// MARK: - Elevated Card

struct CPElevatedCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(CPSpacing.cardPadding)
            .background(Color.cpBackground)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Category Pill

struct CategoryPill: View {
    let name: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.selection()
            action()
        }) {
            HStack(spacing: CPSpacing.xxs) {
                if let icon = icon {
                    Text(icon)
                        .font(.system(size: 12))
                }

                Text(name)
                    .font(.cpSubhead)
            }
            .padding(.horizontal, CPSpacing.sm)
            .padding(.vertical, CPSpacing.xs)
            .background(isSelected ? Color.cpTint : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .cpText)
            .cornerRadius(CPSpacing.cornerRadiusLarge)
        }
    }
}

// MARK: - Empty State

struct CPEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: CPSpacing.md) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.cpTextTertiary)

            Text(title)
                .font(.cpTitle3)
                .foregroundColor(.cpText)

            Text(message)
                .font(.cpBody)
                .foregroundColor(.cpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CPSpacing.xxl)

            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle) {
                    action()
                }
                .font(.cpHeadline)
                .foregroundColor(.cpTint)
                .padding(.top, CPSpacing.sm)
            }

            Spacer()
        }
    }
}

// MARK: - Loading View

struct CPLoadingView: View {
    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: CPSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            if let message = message {
                Text(message)
                    .font(.cpSubhead)
                    .foregroundColor(.cpTextSecondary)
            }
        }
    }
}

// MARK: - Skeleton Loading

struct SkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(.systemGray5),
                        Color(.systemGray4),
                        Color(.systemGray5)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(isAnimating ? 0.5 : 1)
            .animation(
                Animation.easeInOut(duration: 1)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            CPCard {
                VStack(alignment: .leading) {
                    Text("Card Title")
                        .font(.cpHeadline)
                    Text("Card content goes here")
                        .font(.cpBody)
                }
            }

            CPElevatedCard {
                Text("Elevated Card")
                    .font(.cpHeadline)
            }

            HStack {
                CategoryPill(name: "Technology", icon: "💻", isSelected: true) {}
                CategoryPill(name: "Business", icon: "📊", isSelected: false) {}
            }

            CPEmptyState(
                icon: "books.vertical",
                title: "No Documents",
                message: "Save your first article to get started",
                actionTitle: "Learn How"
            ) {}

            CPLoadingView("Loading documents...")
        }
        .padding()
    }
}
