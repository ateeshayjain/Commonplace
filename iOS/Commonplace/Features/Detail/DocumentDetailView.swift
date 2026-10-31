import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    let document: Document

    @StateObject private var viewModel: DocumentDetailViewModel
    @ObservedObject private var speech = SpeechService.shared
    @State private var showingCategorySheet = false
    @State private var showingNotes = false
    @State private var showingTitleEditor = false
    @State private var titleDraft = ""
    @State private var showingCampaign = false
    @State private var showingDeleteConfirmation = false
    @State private var isContentExpanded = false
    @State private var sharingQuote: ShareableQuote?
    @State private var visibleQuoteID: ShareableQuote.ID?
    @State private var showingQuoteTooLong = false
    @State private var quoteSavedToast = false
    @ObservedObject private var savedQuotes = SavedQuoteService.shared
    @ObservedObject private var subscriptions = SubscriptionService.shared
    @State private var showingPaywall = false
    @Environment(\.dismiss) private var dismiss

    init(document: Document) {
        self.document = document
        _viewModel = StateObject(wrappedValue: DocumentDetailViewModel(document: document))
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                // Source badge
                sourceHeader

                // Title
                Text(viewModel.document.title)
                    .font(.cpTitle1)
                    .foregroundColor(.cpText)
                    .fixedSize(horizontal: false, vertical: true)

                // Author & metadata
                authorSection
                sourceLinkSection
                listenSection

                // Hook and the author's own lines, each shareable as a Sangrah card
                let quotes = ShareableQuote.all(for: viewModel.document)
                if !quotes.isEmpty {
                    quotesSection(quotes)
                }

                // No smart summary: a free save, or Pro past the month's fair use
                if viewModel.document.isWaitingForSummary {
                    smartSummarySection
                }

                // AI Summary
                if let summary = viewModel.document.aiSummaryShort {
                    summarySection(summary)
                }

                // Key Points
                if let keyPoints = viewModel.document.aiKeyPoints, !keyPoints.isEmpty {
                    keyPointsSection(keyPoints)
                }

                Divider()

                // Categories
                categoriesSection

                // Content preview, then the PDF. Every save gets both: the PDF is
                // made on first open, so a stored pdfUrl only means it was opened
                // or shared before
                if !viewModel.document.bodyPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contentPreviewSection(proxy: proxy)
                        .id(Self.contentAnchor)
                }
                pdfPreviewSection

                // User notes
                notesSection

                // AI Tags, last: they are for finding the item again, not for reading it
                if !viewModel.tags.isEmpty {
                    tagsSection(viewModel.tags)
                }
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.screenVertical)
        }
        // Mid-read, the way out of a long article without scrolling back up
        .safeAreaInset(edge: .bottom) {
            if quoteSavedToast {
                floatingPill("Saved to Quotes", systemImage: "bookmark.fill") {}
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isContentExpanded {
                floatingPill("Collapse article", systemImage: "chevron.up") {
                    collapseContent(proxy: proxy)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareMenu
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    toolbarMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $viewModel.sharedFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewModel.viewedFile) { file in
            PDFViewerView(url: file.url, title: viewModel.document.title)
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { viewModel.deleteDocument() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed from your library.")
        }
        .onChange(of: viewModel.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "Something went wrong.")
        }
        .alert("Edit Title", isPresented: $showingTitleEditor) {
            TextField("Title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { viewModel.updateTitle(titleDraft) }
        }
        .sheet(isPresented: $showingCategorySheet) {
            CategorySelectionSheet(
                categories: CategoryService.shared.categories,
                selectedCategories: $viewModel.selectedCategories
            )
        }
        .sheet(item: $sharingQuote) { quote in
            QuoteShareSheet(quote: quote, document: viewModel.document)
        }
        .alert("That's a long passage", isPresented: $showingQuoteTooLong) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pick up to \(DocumentDetailViewModel.maxQuoteLength) characters so the quote fits on a card.")
        }
        .sheet(isPresented: $showingCampaign) {
            CampaignView(document: document)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(reason: .summary)
        }
        .task {
            await viewModel.loadTags()
        }
        .task {
            await savedQuotes.load()
        }
    }

    // MARK: - Sections

    private var sourceHeader: some View {
        HStack {
            // Source type badge
            HStack(spacing: CPSpacing.xxs) {
                SourceIcon(type: document.sourceType, size: 14)

                Text(document.sourceType.displayName)
                    .font(.cpCaption1)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, CPSpacing.sm)
            .padding(.vertical, CPSpacing.xxs)
            .background(document.sourceType.color.opacity(0.1))
            .foregroundColor(document.sourceType.color)
            .cornerRadius(CPSpacing.cornerRadiusSmall)

            Spacer()

            // Complexity indicator
            if let complexity = document.aiComplexityScore {
                ComplexityIndicator(score: complexity)
            }
        }
    }

    private var authorSection: some View {
        HStack(spacing: CPSpacing.sm) {
            if let avatarUrl = document.authorAvatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.cpBackgroundSecondary)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.cpBackgroundSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String(document.authorName?.prefix(1) ?? "?"))
                            .font(.cpHeadline)
                            .foregroundColor(.cpTextSecondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(document.authorName ?? "Unknown Author")
                        .font(.cpHeadline)
                        .foregroundColor(.cpText)

                    if let handle = document.authorHandle {
                        Text(handle)
                            .font(.cpSubhead)
                            .foregroundColor(.cpTextSecondary)
                    }
                }

                HStack(spacing: CPSpacing.xs) {
                    if let readTime = document.readingTimeMinutes {
                        Label("\(readTime) min read", systemImage: "clock")
                    }

                    Text("·")

                    Text("Saved \(document.createdAt.displayDate)")
                }
                .font(.cpFootnote)
                .foregroundColor(.cpTextSecondary)
            }
        }
    }

    /// A visible way to the source. "Open Original" also lives in the toolbar
    /// menu, but nothing on the page itself looked tappable.
    @ViewBuilder
    private var sourceLinkSection: some View {
        if let urlString = document.sourceUrl, let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: CPSpacing.xs) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Read the original on \(document.sourceDomain ?? url.host ?? "the web")")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)
                }
                .font(.cpSubhead)
                .foregroundColor(.cpTint)
                .padding(.horizontal, CPSpacing.md)
                .padding(.vertical, CPSpacing.sm)
                .background(Color.cpBackgroundSecondary)
                .cornerRadius(CPSpacing.cornerRadiusMedium)
            }
        }
    }

    /// Read the save aloud with Apple's on-device voice; tapping again pauses
    private var listenSection: some View {
        let isThis = speech.isCurrent(viewModel.document)
        let playing = isThis && speech.isPlaying
        let minutes = SpeechService.listeningMinutes(for: viewModel.document, speed: speech.speed)

        return HStack(spacing: CPSpacing.sm) {
            Button {
                speech.toggle(viewModel.document)
            } label: {
                HStack(spacing: CPSpacing.xs) {
                    Image(systemName: playing ? "pause.fill" : "headphones")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 20)
                    Text(playing ? "Pause" : (isThis ? "Resume Listening" : "Listen"))
                        .fontWeight(.semibold)
                    if !isThis {
                        Text("\u{00B7} \(minutes) min")
                            .foregroundColor(.cpTextSecondary)
                    }
                    Spacer()
                }
            }
            .accessibilityLabel(playing ? "Pause listening" : "Listen to this article")
            SpeedMenu()
        }
        .font(.cpSubhead)
        .foregroundColor(.cpTint)
        .padding(.horizontal, CPSpacing.md)
        .padding(.vertical, CPSpacing.sm)
        .background(Color.cpBackgroundSecondary)
        .cornerRadius(CPSpacing.cornerRadiusMedium)
    }

    /// Swipeable cards, one quote each, with page dots like an Instagram carousel
    private func quotesSection(_ quotes: [ShareableQuote]) -> some View {
        let currentIndex = quotes.firstIndex { $0.id == visibleQuoteID } ?? 0

        return VStack(spacing: CPSpacing.sm) {
            ScrollView(.horizontal) {
                HStack(spacing: CPSpacing.sm) {
                    ForEach(quotes) { quote in
                        quoteCard(quote)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $visibleQuoteID)
            // Full-bleed, so the next card peeks in at the screen edge
            .contentMargins(.horizontal, CPSpacing.screenHorizontal, for: .scrollContent)
            .padding(.horizontal, -CPSpacing.screenHorizontal)

            if quotes.count > 1 {
                pageDots(count: quotes.count, current: currentIndex) { index in
                    withAnimation { visibleQuoteID = quotes[index].id }
                }
            }
        }
    }

    /// The pull-quote style of the hook, for every quote, with a share button
    private func quoteCard(_ quote: ShareableQuote) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.cpTint)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: CPSpacing.xs) {
                if !quote.isVerbatim {
                    Text("KEY IDEA")
                        .font(.cpCaption1)
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundColor(.cpTint)
                }

                Text(quote.isVerbatim ? "\u{201C}\(quote.displayText)\u{201D}" : quote.displayText)
                    .font(quote.isVerbatim ? .cpTitle3 : .cpTitle2)
                    .italic()
                    .foregroundColor(.cpText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // Icons sit on the baseline of the credit's last line ("On Substack")
                HStack(alignment: .lastTextBaseline) {
                    QuoteCreditView(document: viewModel.document, isVerbatim: quote.isVerbatim)
                    Spacer(minLength: CPSpacing.sm)
                    quoteActions(quote)
                }
            }
        }
        .padding(CPSpacing.cardPadding)
        // Every card as tall as the tallest, so the row doesn't jump while swiping
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cpBackgroundSecondary)
        .cornerRadius(CPSpacing.cornerRadiusLarge)
        .contextMenu {
            Button {
                sharingQuote = quote
            } label: {
                Label("Share as Image", systemImage: "square.and.arrow.up")
            }
            Button {
                savedQuotes.toggle(quote, in: viewModel.document)
            } label: {
                if savedQuotes.isSaved(quote, in: viewModel.document.id) {
                    Label("Remove from Quotes", systemImage: "bookmark.slash")
                } else {
                    Label("Save to Quotes", systemImage: "bookmark")
                }
            }
            Button {
                UIPasteboard.general.string = quote.caption(for: viewModel.document)
            } label: {
                Label("Copy Quote", systemImage: "doc.on.doc")
            }
            if quote.isVerbatim {
                Button(role: .destructive) {
                    viewModel.removeQuote(quote.text)
                } label: {
                    Label("Remove Quote", systemImage: "trash")
                }
            }
        }
    }

    /// Bookmark (to the Quotes tab) and share, icon-only like a post's actions
    private func quoteActions(_ quote: ShareableQuote) -> some View {
        let isSaved = savedQuotes.isSaved(quote, in: viewModel.document.id)

        // On a shared baseline, so the taller share glyph doesn't hang below the bookmark
        return HStack(alignment: .firstTextBaseline, spacing: CPSpacing.md) {
            Button {
                savedQuotes.toggle(quote, in: viewModel.document)
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(isSaved ? "Remove from saved quotes" : "Save quote")

            Button {
                sharingQuote = quote
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share this quote as an image")
        }
        .font(.system(size: 19, weight: .medium))
        .foregroundColor(.cpTint)
    }

    private func pageDots(count: Int, current: Int, select: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.cpTint : Color.cpTextSecondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .onTapGesture { select(index) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Quote \(current + 1) of \(count)")
    }

    private func tagsSection(_ tags: [Tag]) -> some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Tags")
                .sectionHeaderStyle()

            FlowLayout(spacing: CPSpacing.xs) {
                ForEach(tags) { tag in
                    CPTagChip(name: tag.name)
                }
            }
        }
    }

    /// In place of the AI sections on a save without a smart summary: what
    /// Pro adds (free accounts), or Summarise (Pro)
    private var smartSummarySection: some View {
        let plan = subscriptions.plan
        let isPro = plan?.isPro == true
        let monthUsedUp = isPro && plan?.smartSummaries.remaining == 0
        return CPCard {
            VStack(alignment: .leading, spacing: CPSpacing.sm) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.cpTint)
                    Text("Smart summary")
                        .sectionHeaderStyle()
                    if !isPro {
                        Spacer()
                        Text("PRO")
                            .font(.cpCaption2)
                            .fontWeight(.bold)
                            .foregroundColor(.cpTint)
                    }
                }

                Group {
                    if !isPro {
                        Text(ProCopy.smartSummary)
                    } else if monthUsedUp, let plan {
                        Text("You've used this month's \(plan.smartSummaries.limit ?? 0) smart summaries. This save gets its summary from \(PlanSummary.dayMonth(plan.smartSummaries.resetsAt, calendar: .current)).")
                    } else {
                        Text("This save doesn't have its smart summary yet.")
                    }
                }
                .font(.cpCallout)
                .foregroundColor(.cpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if !isPro {
                    CPButton("Upgrade to Pro", size: .medium, icon: "sparkles") { showingPaywall = true }
                } else if !monthUsedUp {
                    CPButton("Summarise Now", size: .medium, isLoading: viewModel.isSummarising, icon: "sparkles") {
                        Task { await viewModel.summarise() }
                    }
                }
            }
        }
        .onChange(of: viewModel.needsUpgrade) { _, needed in
            if needed {
                showingPaywall = true
                viewModel.needsUpgrade = false
            }
        }
    }

    private func summarySection(_ summary: String) -> some View {
        CPCard {
            VStack(alignment: .leading, spacing: CPSpacing.sm) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.cpTint)

                    Text("AI Summary")
                        .sectionHeaderStyle()
                }

                Text(summary)
                    .font(.cpBody)
                    .foregroundColor(.cpText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func keyPointsSection(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Key Points")
                .sectionHeaderStyle()

            VStack(alignment: .leading, spacing: CPSpacing.xs) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .top, spacing: CPSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.cpTint)

                        Text(point)
                            .font(.cpCallout)
                            .foregroundColor(.cpText)
                    }
                }
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Text("Categories")
                    .sectionHeaderStyle()

                Spacer()

                Button("Edit") {
                    showingCategorySheet = true
                }
                .font(.cpSubhead)
                .foregroundColor(.cpTint)
            }

            if document.userCategories.isEmpty {
                Text("No categories")
                    .font(.cpCallout)
                    .foregroundColor(.cpTextSecondary)
            } else {
                FlowLayout(spacing: CPSpacing.xs) {
                    ForEach(document.userCategories, id: \.self) { category in
                        CategoryBadge(name: category, color: .cpTint)
                    }
                }
            }
        }
    }

    private var pdfPreviewSection: some View {
        Button {
            viewModel.openPDF()
        } label: {
            HStack(spacing: CPSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusSmall)
                        .fill(Color.cpTint.opacity(0.15))
                        .frame(width: 40, height: 40)
                    if viewModel.isPreparingPDF {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.cpTint)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Read Full Article")
                        .font(.cpHeadline)
                        .foregroundColor(.cpText)
                    Text(fullArticleSubtitle)
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.cpCaption1)
                    .foregroundColor(.cpTextTertiary)
            }
            .padding(CPSpacing.sm)
            .background(Color.cpBackgroundSecondary)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
        }
        .disabled(viewModel.isPreparingPDF)
    }

    private var fullArticleSubtitle: String {
        if let minutes = document.readingTimeMinutes {
            return "Clean PDF \u{00B7} \(minutes) min read"
        }
        return "Clean PDF"
    }

    private static let contentAnchor = "content"

    private func contentPreviewSection(proxy: ScrollViewProxy) -> some View {
        let isLong = document.bodyPlain.count > 500

        return VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Text("Content")
                    .sectionHeaderStyle()
                Spacer()
                if isLong && isContentExpanded {
                    Button("Collapse") { collapseContent(proxy: proxy) }
                        .font(.cpSubhead)
                        .foregroundColor(.cpTint)
                }
            }

            // Select any passage and choose "Save as Quote" to add it to the cards
            SelectableText(
                text: document.bodyPlain,
                lineLimit: isContentExpanded ? nil : 20,
                actions: [
                    .init(title: "Save as Quote", systemImage: "quote.opening") { selection in
                        saveQuote(selection)
                    }
                ]
            )

            if isLong {
                Button(isContentExpanded ? "Show Less" : "Read More") {
                    if isContentExpanded {
                        collapseContent(proxy: proxy)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { isContentExpanded = true }
                    }
                }
                .font(.cpSubhead)
                .foregroundColor(.cpTint)
            }
        }
    }

    /// Back to the 20-line preview, with the top of the article in view
    private func collapseContent(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            isContentExpanded = false
            proxy.scrollTo(Self.contentAnchor, anchor: .top)
        }
    }

    private func saveQuote(_ selection: String) {
        guard viewModel.saveQuote(selection) != nil else {
            showingQuoteTooLong = true
            return
        }
        withAnimation { quoteSavedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { quoteSavedToast = false }
        }
    }

    private func floatingPill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.cpSubhead)
                .fontWeight(.semibold)
                .foregroundColor(.cpTint)
                .padding(.horizontal, CPSpacing.md)
                .padding(.vertical, CPSpacing.sm)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .padding(.bottom, CPSpacing.xs)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Text("Notes")
                    .sectionHeaderStyle()

                Spacer()

                Button(document.userNotes == nil ? "Add" : "Edit") {
                    showingNotes = true
                }
                .font(.cpSubhead)
                .foregroundColor(.cpTint)
            }

            if let notes = document.userNotes, !notes.isEmpty {
                Text(notes)
                    .font(.cpCallout)
                    .foregroundColor(.cpText)
                    .padding(CPSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cpBackgroundSecondary)
                    .cornerRadius(CPSpacing.cornerRadiusSmall)
            }
        }
    }

    private var shareMenu: some View {
        Menu {
            Button {
                viewModel.sharePDF()
            } label: {
                Label("Share as PDF", systemImage: "doc.richtext")
            }
            if let link = document.sourceUrl, let url = URL(string: link) {
                ShareLink(item: url) {
                    Label("Share Link", systemImage: "link")
                }
            }
        } label: {
            if viewModel.isPreparingPDF {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(viewModel.isPreparingPDF)
        .accessibilityLabel("Share")
    }

    @ViewBuilder
    private var toolbarMenuContent: some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            Label(
                document.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: document.isFavorite ? "star.fill" : "star"
            )
        }

        Button {
            showingCampaign = true
        } label: {
            Label("Write About", systemImage: "square.and.pencil")
        }

        Button {
            titleDraft = viewModel.document.title
            showingTitleEditor = true
        } label: {
            Label("Edit Title", systemImage: "pencil")
        }

        Button {
            showingCategorySheet = true
        } label: {
            Label("Edit Categories", systemImage: "folder")
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
            showingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Complexity Indicator

struct ComplexityIndicator: View {
    let score: Int

    var level: String {
        switch score {
        case 1...3: return "Easy"
        case 4...6: return "Medium"
        case 7...8: return "Advanced"
        default: return "Expert"
        }
    }

    var color: Color {
        switch score {
        case 1...3: return .green
        case 4...6: return .orange
        case 7...8: return .red
        default: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Circle()
                    .fill(index < (score / 2) ? color : Color(.systemGray4))
                    .frame(width: 6, height: 6)
            }

            Text(level)
                .font(.cpCaption2)
                .foregroundColor(.cpTextSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        DocumentDetailView(document: .preview)
    }
}

// MARK: - Share sheet

/// UIActivityViewController for SwiftUI sheets; presenting from the root view
/// controller fails silently when another screen is already presented.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
