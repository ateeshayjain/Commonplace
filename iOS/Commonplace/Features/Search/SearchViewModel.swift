import Foundation
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var results: [DocumentService.SearchResult] = []
    @Published var isSearching = false
    @Published var error: Error?

    @Published var recentSearches: [String] = []
    let suggestedSearches = ["AI", "Startups", "Technology", "Business", "Design", "Health"]

    private let documentService = DocumentService.shared
    private var searchTask: Task<Void, Never>?
    private let recentSearchesKey = "recent_searches"

    init() {
        loadRecentSearches()
    }

    // MARK: - Search

    func search() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        isSearching = true
        error = nil

        do {
            results = try await documentService.searchDocuments(query: searchText)
            saveRecentSearch(searchText)
        } catch {
            self.error = error
            results = []
        }

        isSearching = false
    }

    func debouncedSearch() {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            guard !Task.isCancelled else { return }

            if searchText.count >= 2 {
                await search()
            } else if searchText.isEmpty {
                results = []
            }
        }
    }

    // MARK: - Recent Searches

    private func loadRecentSearches() {
        if let saved = UserDefaults.standard.stringArray(forKey: recentSearchesKey) {
            recentSearches = saved
        }
    }

    private func saveRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Remove if already exists
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }

        // Add to front
        recentSearches.insert(trimmed, at: 0)

        // Keep only last 10
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }

        UserDefaults.standard.set(recentSearches, forKey: recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }
}
