import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    @Binding var isComplete: Bool

    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "books.vertical.fill",
            title: "Save Everything",
            description: "Save articles, threads, and posts from any app. We'll store them forever, even if the original is deleted.",
            color: .blue
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "AI-Powered Insights",
            description: "Get instant summaries, key points, and smart categorization for everything you save.",
            color: .purple
        ),
        OnboardingPage(
            icon: "magnifyingglass",
            title: "Find Anything",
            description: "Powerful search across your entire library. Never lose an important read again.",
            color: .green
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Pages
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.cpTint : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.bottom, CPSpacing.xl)

            // Buttons
            VStack(spacing: CPSpacing.sm) {
                if currentPage < pages.count - 1 {
                    CPButton("Continue") {
                        withAnimation {
                            currentPage += 1
                        }
                    }

                    Button("Skip") {
                        isComplete = false
                    }
                    .font(.cpBody)
                    .foregroundColor(.cpTextSecondary)
                } else {
                    CPButton("Get Started") {
                        isComplete = false
                    }
                }
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.bottom, CPSpacing.xxl)
        }
    }
}

// MARK: - Page Data

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Page View

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: CPSpacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(page.color)
            }

            // Text
            VStack(spacing: CPSpacing.sm) {
                Text(page.title)
                    .font(.cpTitle1)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.cpBody)
                    .foregroundColor(.cpTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CPSpacing.xl)
            }

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(isComplete: .constant(false))
}
