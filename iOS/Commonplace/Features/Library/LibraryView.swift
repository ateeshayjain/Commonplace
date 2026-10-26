import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedCategory: String? = nil
    @State private var selectedTagId: UUID? = nil
    @State private var searchText = ""
    @State private var showingAddURL = false
    @State private var urlToAdd = ""
    @State private var isAddingURL = false

    // Multi-select mode
    @State private var isSelectMode = false
    @State private var selectedDocuments: Set<UUID> = []
    @State private var showingCompose = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Search bar
                    CPSearchBar(text: $searchText, placeholder: "Search your library")
                        .padding(.horizontal, CPSpacing.screenHorizontal)
                        .padding(.bottom, CPSpacing.sm)
                        .onChange(of: searchText) { _, newValue in
                            viewModel.filterDocuments(query: newValue)
                        }

                    // Category filter
                    CategoryFilterView(
                        categories: viewModel.categories,
                        selected: $selectedCategory
                    )
                    .padding(.bottom, viewModel.tags.isEmpty ? CPSpacing.md : CPSpacing.xs)
                    .onChange(of: selectedCategory) { _, newValue in
                        Task {
                            await viewModel.loadDocuments(category: newValue, tagId: selectedTagId)
                        }
                    }

                    // Tag filter (hidden until the user has tags)
                    if !viewModel.tags.isEmpty {
                        tagFilterRow
                            .padding(.bottom, CPSpacing.md)
                            .onChange(of: selectedTagId) { _, newValue in
                                Task {
                                    await viewModel.loadDocuments(category: selectedCategory, tagId: newValue)
                                }
                            }
                    }

                    // Content
                    if viewModel.isLoading && viewModel.documents.isEmpty {
                        loadingView
                    } else if viewModel.filteredDocuments.isEmpty {
                        emptyView
                    } else {
                        documentsList
                    }
                }
            }
            .navigationTitle("Library")
            .refreshable {
                await viewModel.refresh(category: selectedCategory, tagId: selectedTagId)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectMode {
                        Button("Cancel") {
                            isSelectMode = false
                            selectedDocuments.removeAll()
                        }
                    } else {
                        Button {
                            showingAddURL = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelectMode {
                        Button("Select All") {
                            selectedDocuments = Set(viewModel.filteredDocuments.map { $0.id })
                        }
                    } else {
                        Menu {
                            Button {
                                isSelectMode = true
                            } label: {
                                Label("Select Articles", systemImage: "checkmark.circle")
                            }

                            Divider()

                            Button {
                                viewModel.sortOrder = .newest
                            } label: {
                                HStack {
                                    Text("Newest First")
                                    Spacer()
                                    if viewModel.sortOrder == .newest {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                viewModel.sortOrder = .oldest
                            } label: {
                                HStack {
                                    Text("Oldest First")
                                    Spacer()
                                    if viewModel.sortOrder == .oldest {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Button {
                                viewModel.sortOrder = .favorites
                            } label: {
                                HStack {
                                    Text("Favorites")
                                    Spacer()
                                    if viewModel.sortOrder == .favorites {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectMode && !selectedDocuments.isEmpty {
                    composeBar
                }
            }
            .sheet(isPresented: $showingAddURL) {
                AddURLSheet(
                    url: $urlToAdd,
                    isLoading: $isAddingURL,
                    onAdd: {
                        Task {
                            await addURL()
                        }
                    }
                )
            }
            .sheet(isPresented: $showingCompose) {
                ComposeView(
                    documents: viewModel.documents.filter { selectedDocuments.contains($0.id) },
                    onDismiss: {
                        isSelectMode = false
                        selectedDocuments.removeAll()
                    }
                )
            }
        }
        .task {
            await viewModel.loadTags()
            await viewModel.loadDocuments()
        }
    }

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CPSpacing.xs) {
                ForEach(viewModel.tags) { tag in
                    CPTagChip(name: tag.name, isSelected: selectedTagId == tag.id) {
                        if selectedTagId == tag.id {
                            selectedTagId = nil
                        } else {
                            selectedTagId = tag.id
                        }
                    }
                }
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
        }
    }

    private var composeBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: CPSpacing.md) {
                Text("\(selectedDocuments.count) selected")
                    .font(.cpSubhead)
                    .foregroundColor(.cpTextSecondary)

                Spacer()

                Button {
                    showingCompose = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Create Content")
                    }
                    .font(.cpHeadline)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.sm)
            .background(Color.cpBackground)
        }
    }

    private var documentsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.groupedDocuments, id: \.date) { group in
                Section {
                    ForEach(group.documents) { document in
                        if isSelectMode {
                            SelectableDocumentRow(
                                document: document,
                                isSelected: selectedDocuments.contains(document.id),
                                onToggle: {
                                    if selectedDocuments.contains(document.id) {
                                        selectedDocuments.remove(document.id)
                                    } else {
                                        selectedDocuments.insert(document.id)
                                    }
                                }
                            )
                        } else {
                            NavigationLink(value: document) {
                                DocumentRow(document: document)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                documentContextMenu(document)
                            }
                        }

                        Divider()
                            .padding(.leading, CPSpacing.screenHorizontal)
                    }
                } header: {
                    sectionHeader(group.title)
                }
            }
        }
        .navigationDestination(for: Document.self) { document in
            DocumentDetailView(document: document)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .sectionHeaderStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.xs)
            .background(Color.cpBackground)
    }

    @ViewBuilder
    private func documentContextMenu(_ document: Document) -> some View {
        Button {
            // Write about this - would open compose
        } label: {
            Label("Write About This", systemImage: "square.and.pencil")
        }

        Button {
            Task {
                await viewModel.toggleFavorite(document)
            }
        } label: {
            Label(
                document.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: document.isFavorite ? "star.fill" : "star"
            )
        }

        Button {
            if let url = document.sourceUrl {
                UIPasteboard.general.string = url
                HapticManager.saveSuccess()
            }
        } label: {
            Label("Copy Link", systemImage: "link")
        }

        if let url = document.sourceUrl, let sourceUrl = URL(string: url) {
            Button {
                UIApplication.shared.open(sourceUrl)
            } label: {
                Label("Open Original", systemImage: "arrow.up.right")
            }
        }

        Divider()

        Button(role: .destructive) {
            Task {
                await viewModel.delete(document)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var loadingView: some View {
        VStack(spacing: CPSpacing.md) {
            ForEach(0..<5, id: \.self) { _ in
                DocumentRowSkeleton()
            }
        }
        .padding(.horizontal, CPSpacing.screenHorizontal)
    }

    private var emptyView: some View {
        CPEmptyState(
            icon: "books.vertical",
            title: searchText.isEmpty ? "Your Library is Empty" : "No Results",
            message: searchText.isEmpty
                ? "Save articles, threads, and posts from any app using the share button."
                : "Try a different search term",
            actionTitle: searchText.isEmpty ? "Learn How to Save" : nil
        ) {
            // Show tutorial
        }
    }

    private func addURL() async {
        guard !urlToAdd.isEmpty else { return }

        isAddingURL = true

        // Use the ViewModel method which handles demo mode
        await viewModel.addDocumentFromURL(urlToAdd)

        isAddingURL = false
        urlToAdd = ""
        showingAddURL = false
    }
}

// MARK: - Add URL Sheet

struct AddURLSheet: View {
    @Binding var url: String
    @Binding var isLoading: Bool
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: CPSpacing.lg) {
                VStack(alignment: .leading, spacing: CPSpacing.sm) {
                    Text("Add a URL")
                        .font(.cpTitle2)

                    Text("Paste any article, tweet, or post URL to save it to your library.")
                        .font(.cpBody)
                        .foregroundColor(.cpTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("https://...", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button {
                    onAdd()
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(isLoading ? "Adding..." : "Add to Library")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(url.isEmpty || isLoading)

                Spacer()

                // Quick test URLs
                VStack(alignment: .leading, spacing: CPSpacing.sm) {
                    Text("Try these:")
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)

                    Button {
                        url = "https://paulgraham.com/read.html"
                    } label: {
                        Text("paulgraham.com/read.html")
                            .font(.cpFootnote)
                    }

                    Button {
                        url = "https://www.theverge.com/2024/1/25/24050478/microsoft-bing-ai-chatbot-birthday"
                    } label: {
                        Text("theverge.com (AI article)")
                            .font(.cpFootnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(CPSpacing.screenHorizontal)
            .navigationTitle("Add URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Selectable Document Row

struct SelectableDocumentRow: View {
    let document: Document
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: CPSpacing.sm) {
                // Selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.cpTint : Color.cpTextSecondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.cpTint)
                            .frame(width: 16, height: 16)
                    }
                }

                // Document content
                VStack(alignment: .leading, spacing: CPSpacing.xxs) {
                    HStack(spacing: CPSpacing.xs) {
                        Text(document.sourceType.icon)
                            .font(.system(size: 12))
                        Text(document.sourceType.displayName)
                            .font(.cpCaption1)
                            .foregroundColor(.cpTextSecondary)
                    }

                    Text(document.title)
                        .font(.cpHeadline)
                        .foregroundColor(.cpText)
                        .lineLimit(2)

                    if let summary = document.aiSummaryShort {
                        Text(summary)
                            .font(.cpFootnote)
                            .foregroundColor(.cpTextSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.sm)
            .background(isSelected ? Color.cpTint.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Document Row Skeleton

struct DocumentRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CPSpacing.xs) {
            HStack {
                SkeletonView()
                    .frame(width: 100, height: 16)
                    .cornerRadius(4)

                SkeletonView()
                    .frame(width: 60, height: 16)
                    .cornerRadius(4)
            }

            SkeletonView()
                .frame(height: 20)
                .cornerRadius(4)

            SkeletonView()
                .frame(height: 48)
                .cornerRadius(4)

            HStack {
                SkeletonView()
                    .frame(width: 80, height: 14)
                    .cornerRadius(4)

                Spacer()

                SkeletonView()
                    .frame(width: 40, height: 14)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, CPSpacing.listItemVertical)
    }
}

#Preview {
    LibraryView()
}
