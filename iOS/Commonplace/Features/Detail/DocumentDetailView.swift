import SwiftUI
import PDFKit

struct DocumentDetailView: View {
    let document: Document

    @StateObject private var viewModel: DocumentDetailViewModel
    @State private var showingPDF = false
    @State private var showingCategorySheet = false
    @State private var showingNotes = false
    @State private var showingCampaign = false

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
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.screenVertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    toolbarMenuContent
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $showingPDF) {
            if let pdfUrl = document.pdfUrl, let url = URL(string: pdfUrl) {
                PDFViewerView(url: url, title: document.title)
            }
        }
        .sheet(isPresented: $showingCategorySheet) {
            CategorySelectionSheet(
                categories: Category.systemCategories,
                selectedCategories: $viewModel.selectedCategories
            )
        }
        .sheet(isPresented: $showingCampaign) {
            CampaignView(document: document)
        }
    }

    // MARK: - Sections

    private var sourceHeader: some View {
        HStack {
            // Source type badge
            HStack(spacing: CPSpacing.xxs) {
                Text(document.sourceType.icon)
                    .font(.system(size: 14))

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
            showingPDF = true
        } label: {
            VStack(spacing: CPSpacing.sm) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundColor(.cpTint)

                Text("Read Full Article")
                    .font(.cpHeadline)
                    .foregroundColor(.cpTint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Color.cpBackgroundSecondary)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
        }
    }

    private var contentPreviewSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Content")
                .sectionHeaderStyle()

            Text(document.bodyPlain)
                .font(.cpBody)
                .foregroundColor(.cpText)
                .lineLimit(20)

            if document.bodyPlain.count > 500 {
                Button("Read More") {
                    // Expand or show full view
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
            viewModel.deleteDocument()
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
