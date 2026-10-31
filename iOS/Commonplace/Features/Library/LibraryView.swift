import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @ObservedObject private var categoryService = CategoryService.shared
    @State private var selectedCategory: String? = nil
    @State private var searchText = ""
    @State private var showingAddURL = false
    @State private var showingHowToSave = false
    @State private var urlToAdd = ""
    @State private var isAddingURL = false

    // Multi-select mode
    @State private var isSelectMode = false
    @State private var selectedDocuments: Set<UUID> = []
    @State private var showingCompose = false
    @State private var showingComposePaywall = false
    @State private var showingSavesPaywall = false
    @ObservedObject private var subscriptions = SubscriptionService.shared
    @Environment(\.scenePhase) private var scenePhase

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
                        categories: categoryService.categories,
                        selected: $selectedCategory
                    )
                    .padding(.bottom, viewModel.availableSources.count > 1 ? CPSpacing.xs : CPSpacing.md)
                    .onChange(of: selectedCategory) { _, newValue in
                        Task {
                            await viewModel.loadDocuments(category: newValue)
                        }
                    }

                    // Source filter (hidden until there is more than one source)
                    if viewModel.availableSources.count > 1 {
                        sourceFilterRow
                            .padding(.bottom, CPSpacing.md)
                    }

                    if viewModel.pendingSaveCount > 0 {
                        processingBanner
                    } else if let notice = viewModel.waitingNotice {
                        waitingBanner(notice)
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
            // Declared here, outside the lazy stacks: a navigationDestination
            // inside a LazyVStack is only registered once that row renders, so
            // taps silently did nothing.
            .navigationDestination(for: Document.self) { document in
                DocumentDetailView(document: document)
            }
            .navigationTitle("Library")
            .refreshable {
                await viewModel.refresh(category: selectedCategory)
            }
            // Saves made from the Share Extension land while the app is in the
            // background; reload when it comes back so they show without a pull.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await viewModel.refresh(category: selectedCategory)
                    // A share made seconds before switching back may still be
                    // summarizing; look once more after it has had time to finish.
                    try? await Task.sleep(for: .seconds(15))
                    await viewModel.refresh(category: selectedCategory)
                }
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
            .sheet(isPresented: $showingHowToSave) {
                HowToSaveSheet {
                    showingHowToSave = false
                    showingAddURL = true
                }
            }
            .sheet(isPresented: $showingComposePaywall) {
                PaywallView(reason: .compose)
            }
            .sheet(isPresented: $showingSavesPaywall) {
                PaywallView(reason: .dailyLimit)
            }
            .alert("Today's free saves are used up", isPresented: .init(
                get: { viewModel.saveLimitMessage != nil },
                set: { if !$0 { viewModel.saveLimitMessage = nil } }
            )) {
                Button("Go Pro") {
                    viewModel.saveLimitMessage = nil
                    showingSavesPaywall = true
                }
                Button("Not Now", role: .cancel) { viewModel.saveLimitMessage = nil }
            } message: {
                Text(viewModel.saveLimitMessage ?? "")
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
            await viewModel.loadDocuments()
        }
        .task {
            await categoryService.load()
        }
    }

    private var sourceFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CPSpacing.xs) {
                ForEach(viewModel.availableSources, id: \.self) { source in
                    CPTagChip(
                        name: source == .twitter ? "X" : source.displayName,
                        isSelected: viewModel.selectedSource == source,
                        prefix: source == .twitter ? "" : source.icon
                    ) {
                        viewModel.selectedSource = viewModel.selectedSource == source ? nil : source
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
                    // Compose is Pro only; the server enforces it too
                    if subscriptions.plan?.isPro == false {
                        showingComposePaywall = true
                    } else {
                        showingCompose = true
                    }
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

    private var processingBanner: some View {
        HStack(spacing: CPSpacing.sm) {
            ProgressView()
            Text(viewModel.pendingSaveCount == 1
                 ? "Summarizing 1 link…"
                 : "Summarizing \(viewModel.pendingSaveCount) links…")
                .font(.cpFootnote)
                .foregroundColor(.cpTextSecondary)
            Spacer()
        }
        .padding(.horizontal, CPSpacing.screenHorizontal)
        .padding(.bottom, CPSpacing.sm)
    }

    /// A save came back without a summary: the month's free AI saves are used up
    private func waitingBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.sm) {
            Image(systemName: "hourglass")
                .foregroundColor(.cpTint)
            Text(notice)
                .font(.cpFootnote)
                .foregroundColor(.cpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                viewModel.waitingNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.cpFootnote)
                    .foregroundColor(.cpTextTertiary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, CPSpacing.screenHorizontal)
        .padding(.bottom, CPSpacing.sm)
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
            showingHowToSave = true
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

// MARK: - How To Save Sheet

/// Explains the ways to get content into the library. `onAddLink` dismisses
/// this sheet and opens the Add URL sheet.
struct HowToSaveSheet: View {
    let onAddLink: () -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Step {
        let icon: String
        let title: String
        let detail: String
    }

    private let steps = [
        Step(
            icon: "plus.circle.fill",
            title: "Paste a link",
            detail: "Tap + in the Library, paste the URL of an article, thread, or post, and tap Add. Sangrah fetches it and writes the summary."
        ),
        Step(
            icon: "square.and.arrow.up",
            title: "Share from any app",
            detail: "From Safari, X, LinkedIn, or YouTube, tap Share and pick Sangrah. It saves in one tap and closes."
        ),
        Step(
            icon: "sparkles",
            title: "Read the summary",
            detail: "Each save gets a one-line hook, key points, and tags, so you can find it again by what it was about."
        )
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                ForEach(steps.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: CPSpacing.md) {
                        Image(systemName: steps[index].icon)
                            .font(.title2)
                            .foregroundColor(.cpTint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: CPSpacing.xs) {
                            Text(steps[index].title)
                                .font(.cpHeadline)
                            Text(steps[index].detail)
                                .font(.cpBody)
                                .foregroundColor(.cpTextSecondary)
                        }
                    }
                }

                Spacer()

                Button(action: onAddLink) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add a Link Now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(CPSpacing.screenHorizontal)
            .navigationTitle("How to Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
