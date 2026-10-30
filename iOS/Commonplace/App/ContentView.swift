import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .library

    enum Tab: Hashable {
        case library
        case quotes
        case profile
    }

    var body: some View {
        Group {
            if authService.isAuthenticated {
                mainTabView
            } else {
                AuthView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A launch while offline leaves the profile unloaded; try again
            if phase == .active {
                Task { await authService.loadProfile() }
            }
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(Tab.library)

            // Search lives in the Library's search box; the centre tab is the reader's quotes
            QuotesView()
                .tabItem {
                    Label("Quotes", systemImage: "bookmark")
                }
                .tag(Tab.quotes)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(Tab.profile)
        }
        .tint(.cpTint)
        // The quote widget opens commonplace://quotes
        .onOpenURL { url in
            if url.scheme == "commonplace", url.host == "quotes" {
                selectedTab = .quotes
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService.shared)
}
