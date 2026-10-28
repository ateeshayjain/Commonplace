import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .library

    enum Tab: Hashable {
        case library
        case search
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

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(Tab.profile)
        }
        .tint(.cpTint)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService.shared)
}
