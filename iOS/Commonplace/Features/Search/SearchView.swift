import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                CPSearchBar(
                    text: $viewModel.searchText,
                    placeholder: "Search your library",
                    onSubmit: {
                        Task {
                            await viewModel.search()
                        }
                    }
                )
                .padding(.horizontal, CPSpacing.screenHorizontal)
                .padding(.vertical, CPSpacing.sm)
                .focused($isSearchFocused)

                // Content
                if viewModel.searchText.isEmpty {
                    recentSearchesView
                } else if viewModel.isSearching {
                    CPLoadingView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    emptyResultsView
                } else {
                    searchResultsView
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.debouncedSearch()
        }
    }

    // MARK: - Recent Searches

    private var recentSearchesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                if !viewModel.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: CPSpacing.sm) {
                        HStack {
                            Text("Recent Searches")
                                .sectionHeaderStyle()

                            Spacer()

                            Button("Clear") {
                                viewModel.clearRecentSearches()
                            }
                            .font(.cpSubhead)
                            .foregroundColor(.cpTint)
                        }

                        ForEach(viewModel.recentSearches, id: \.self) { search in
                            Button {
                                viewModel.searchText = search
                                Task {
                                    await viewModel.search()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundColor(.cpTextSecondary)

                                    Text(search)
                                        .font(.cpBody)
                                        .foregroundColor(.cpText)

                                    Spacer()

                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 12))
                                        .foregroundColor(.cpTextTertiary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, CPSpacing.screenHorizontal)
                }

                // Suggested searches
                VStack(alignment: .leading, spacing: CPSpacing.sm) {
                    Text("Suggested")
                        .sectionHeaderStyle()

                    FlowLayout(spacing: CPSpacing.xs) {
                        ForEach(viewModel.suggestedSearches, id: \.self) { suggestion in
                            Button {
                                viewModel.searchText = suggestion
                                Task {
                                    await viewModel.search()
                                }
                            } label: {
                                Text(suggestion)
                                    .font(.cpSubhead)
                                    .foregroundColor(.cpTint)
                                    .padding(.horizontal, CPSpacing.sm)
                                    .padding(.vertical, CPSpacing.xs)
                                    .background(Color.cpTint.opacity(0.1))
                                    .cornerRadius(CPSpacing.cornerRadiusLarge)
                            }
                        }
                    }
                }
                .padding(.horizontal, CPSpacing.screenHorizontal)
            }
            .padding(.top, CPSpacing.md)
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Results count
                HStack {
                    Text("\(viewModel.results.count) results")
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)

                    Spacer()
                }
                .padding(.horizontal, CPSpacing.screenHorizontal)
                .padding(.vertical, CPSpacing.xs)

                ForEach(viewModel.results) { result in
                    NavigationLink(value: result) {
                        SearchResultRow(result: result, query: viewModel.searchText)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, CPSpacing.screenHorizontal)
                }
            }
            .navigationDestination(for: DocumentService.SearchResult.self) { result in
                // Navigate to document detail
                // Would need to fetch full document
                Text("Document: \(result.title)")
            }
        }
    }

    // MARK: - Empty Results

    private var emptyResultsView: some View {
        CPEmptyState(
            icon: "magnifyingglass",
            title: "No Results",
            message: "Try a different search term or check your spelling"
        )
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: DocumentService.SearchResult
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xs) {
            // Title with highlight
            Text(highlightedTitle)
                .font(.cpHeadline)
                .foregroundColor(.cpText)
                .lineLimit(2)

            // Summary
            if let summary = result.aiSummaryShort {
                Text(summary)
                    .font(.cpCallout)
                    .foregroundColor(.cpTextSecondary)
                    .lineLimit(2)
            }

            // Metadata
            HStack {
                Text(result.sourceType.displayName)
                    .font(.cpFootnote)
                    .foregroundColor(result.sourceType.color)

                if let author = result.authorName {
                    Text("·")
                        .foregroundColor(.cpTextSecondary)

                    Text(author)
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)
                }

                Spacer()

                Text(result.createdAt.timeAgo)
                    .font(.cpFootnote)
                    .foregroundColor(.cpTextTertiary)
            }
        }
        .padding(.horizontal, CPSpacing.screenHorizontal)
        .padding(.vertical, CPSpacing.listItemVertical)
        .contentShape(Rectangle())
    }

    private var highlightedTitle: AttributedString {
        var attributed = AttributedString(result.title)

        if let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = .cpTint
            attributed[range].font = .system(size: 17, weight: .bold)
        }

        return attributed
    }
}

#Preview {
    SearchView()
}
