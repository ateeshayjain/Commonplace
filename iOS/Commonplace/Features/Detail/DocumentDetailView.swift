import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    let document: Document

    @StateObject private var viewModel: DocumentDetailViewModel
    @State private var showingCategorySheet = false
    @State private var showingNotes = false
    @State private var showingCampaign = false
    @State private var showingDeleteConfirmation = false
    @State private var isContentExpanded = false
    @State private var sharingQuote: ShareableQuote?
    @Environment(\.dismiss) private var dismiss

    init(document: Document) {
        self.document = document
        _viewModel = StateObject(wrappedValue: DocumentDetailViewModel(document: document))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                // Source badge
                sourceHeader

                // Title
                Text(document.title)
                    .font(.cpTitle1)
                    .foregroundColor(.cpText)
                    .fixedSize(horizontal: false, vertical: true)

                // Author & metadata
                authorSection
                sourceLinkSection

                // Hook and the author's own lines, each shareable as a Sangrah card
                let quotes = ShareableQuote.all(for: document)
                if !quotes.isEmpty {
                    quotesSection(quotes)
                }

                // AI Summary
                if let summary = document.aiSummaryShort {
                    summarySection(summary)
                }

                // Key Points
                if let keyPoints = document.aiKeyPoints, !keyPoints.isEmpty {
                    keyPointsSection(keyPoints)
                }

                Divider()

                // Categories
                categoriesSection

                // Content preview / PDF
                if document.pdfUrl != nil {
                    pdfPreviewSection
                } else {
                    contentPreviewSection
                }

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
            PDFViewerView(url: file.url, title: document.title)
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
        .sheet(isPresented: $showingCategorySheet) {
            CategorySelectionSheet(
                categories: Category.systemCategories,
                selectedCategories: $viewModel.selectedCategories
            )
        }
        .sheet(item: $sharingQuote) { quote in
            QuoteShareSheet(quote: quote, document: document)
        }
        .sheet(isPresented: $showingCampaign) {
            CampaignView(document: document)
        }
        .task {
            await viewModel.loadTags()
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

    private func quotesSection(_ quotes: [ShareableQuote]) -> some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            ForEach(quotes) { quote in
                quoteRow(quote)
            }
        }
    }

    /// The pull-quote style of the hook, for every quote, with a share button
    private func quoteRow(_ quote: ShareableQuote) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.cpTint)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: CPSpacing.xs) {
                Text(quote.isVerbatim ? "\u{201C}\(quote.text)\u{201D}" : quote.text)
                    .font(quote.isVerbatim ? .cpBody : .cpTitle3)
                    .italic()
                    .foregroundColor(.cpText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack {
                    if quote.isVerbatim, let author = document.authorName {
                        Text("\u{2014} \(author)")
                            .font(.cpFootnote)
                            .foregroundColor(.cpTextSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        sharingQuote = quote
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.cpSubhead)
                    }
                    .foregroundColor(.cpTint)
                    .accessibilityLabel("Share this quote as an image")
                }
            }
        }
        .padding(.vertical, CPSpacing.xxs)
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

    private var contentPreviewSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Content")
                .sectionHeaderStyle()

            Text(document.bodyPlain)
                .font(.cpBody)
                .foregroundColor(.cpText)
                .lineLimit(isContentExpanded ? nil : 20)
                .textSelection(.enabled)

            if document.bodyPlain.count > 500 {
                Button(isContentExpanded ? "Show Less" : "Read More") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isContentExpanded.toggle()
                    }
                }
                .font(.cpSubhead)
                .foregroundColor(.cpTint)
            }
        }
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
