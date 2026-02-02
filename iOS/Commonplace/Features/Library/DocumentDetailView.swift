import SwiftUI

struct DocumentDetailView: View {
    let document: Document
    @State private var showingOpenOptions = false
    @State private var showingPDFViewer = false
    @State private var isGeneratingPDF = false
    @Environment(\.dismiss) private var dismiss

    private var hasPDF: Bool {
        document.pdfUrl != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                // Header
                headerSection

                // Quick Actions - Open Article
                openArticleSection

                // AI Summary Card
                if let summary = document.aiSummaryShort {
                    aiSummaryCard(summary)
                }

                // Key Points
                if let keyPoints = document.aiKeyPoints, !keyPoints.isEmpty {
                    keyPointsSection(keyPoints)
                }

                // Article Body
                bodySection

                // Metadata
                metadataSection

                Spacer(minLength: 100)
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .padding(.top, CPSpacing.md)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if let urlString = document.sourceUrl, let url = URL(string: urlString) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Open Original", systemImage: "arrow.up.right")
                        }

                        Button {
                            UIPasteboard.general.string = urlString
                            HapticManager.saveSuccess()
                        } label: {
                            Label("Copy Link", systemImage: "link")
                        }
                    }

                    if hasPDF {
                        Button {
                            showingPDFViewer = true
                        } label: {
                            Label("View Saved PDF", systemImage: "doc.fill")
                        }
                    }

                    Divider()

                    Button {
                        // Share
                        shareArticle()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingPDFViewer) {
            PDFViewerSheet(document: document)
        }
    }

    // MARK: - Open Article Section

    private var openArticleSection: some View {
        VStack(spacing: CPSpacing.sm) {
            HStack(spacing: CPSpacing.sm) {
                // Open Original Button
                Button {
                    if let urlString = document.sourceUrl, let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "safari")
                        Text("Open Original")
                    }
                    .font(.cpHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CPSpacing.sm)
                    .background(Color(.systemGray5))
                    .foregroundColor(.cpText)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }

                // View as PDF Button
                Button {
                    if hasPDF {
                        showingPDFViewer = true
                    }
                } label: {
                    HStack {
                        Image(systemName: hasPDF ? "doc.fill" : "doc.badge.clock")
                        Text(hasPDF ? "View PDF" : "PDF Pending")
                    }
                    .font(.cpHeadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CPSpacing.sm)
                    .background(hasPDF ? Color.cpTint : Color(.systemGray5))
                    .foregroundColor(hasPDF ? .white : .cpTextSecondary)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }
                .disabled(!hasPDF)
            }

            if hasPDF {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("PDF saved - content preserved even if original is deleted")
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)
                }
            }
        }
    }

    private func shareArticle() {
        var items: [Any] = []

        if let urlString = document.sourceUrl, let url = URL(string: urlString) {
            items.append(url)
        }

        items.append(document.title)

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            // Source info
            HStack(spacing: CPSpacing.xs) {
                Text(document.sourceType.icon)
                    .font(.system(size: 14))

                Text(document.sourceType.displayName)
                    .font(.cpCaption1)
                    .foregroundColor(.cpTextSecondary)

                if let domain = document.sourceDomain {
                    Text("•")
                        .foregroundColor(.cpTextTertiary)
                    Text(domain)
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)
                }

                Spacer()

                if let minutes = document.readingTimeMinutes {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text("\(minutes) min")
                    }
                    .font(.cpCaption1)
                    .foregroundColor(.cpTextSecondary)
                }
            }

            // Title
            Text(document.title)
                .font(.cpTitle1)
                .foregroundColor(.cpText)

            // Author & Date
            HStack(spacing: CPSpacing.sm) {
                if let author = document.authorName {
                    Text("by \(author)")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)
                }

                if let date = document.originalPublishedAt {
                    Text("•")
                        .foregroundColor(.cpTextTertiary)
                    Text(date, style: .date)
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)
                }
            }
        }
    }

    // MARK: - AI Summary Card

    private func aiSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Summary")
                    .font(.cpHeadline)
                Spacer()
            }

            Text(summary)
                .font(.cpBody)
                .foregroundColor(.cpText)
        }
        .padding(CPSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium)
                .fill(Color.purple.opacity(0.1))
        )
    }

    // MARK: - Key Points

    private func keyPointsSection(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Key Points")
                .font(.cpHeadline)
                .foregroundColor(.cpText)

            VStack(alignment: .leading, spacing: CPSpacing.xs) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .top, spacing: CPSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                            .padding(.top, 2)

                        Text(point)
                            .font(.cpBody)
                            .foregroundColor(.cpText)
                    }
                }
            }
        }
        .padding(CPSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Body

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            Text("Article Content")
                .font(.cpHeadline)
                .foregroundColor(.cpText)

            Text(document.bodyPlain)
                .font(.cpBody)
                .foregroundColor(.cpText)
                .lineSpacing(6)

            // If it's demo content, show a note
            if document.bodyPlain.contains("demo article") || document.bodyPlain.contains("Demo") {
                demoModeNote
            }
        }
    }

    private var demoModeNote: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Demo Mode")
                    .font(.cpHeadline)
            }

            Text("In the real app with your Supabase API key configured, this would show the full article content extracted by AI. The AI would also provide:")
                .font(.cpSubhead)
                .foregroundColor(.cpTextSecondary)

            VStack(alignment: .leading, spacing: 4) {
                bulletPoint("Complete article text")
                bulletPoint("Smart summaries")
                bulletPoint("Key insights and quotes")
                bulletPoint("Reading time estimates")
                bulletPoint("PDF export option")
            }
            .padding(.leading, CPSpacing.sm)
        }
        .padding(CPSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: CPSpacing.xs) {
            Text("•")
                .foregroundColor(.cpTextSecondary)
            Text(text)
                .font(.cpSubhead)
                .foregroundColor(.cpTextSecondary)
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Details")
                .font(.cpHeadline)
                .foregroundColor(.cpText)

            VStack(spacing: CPSpacing.xs) {
                if let wordCount = document.wordCount {
                    metadataRow("Words", value: "\(wordCount)")
                }

                if let level = document.aiReadingLevel {
                    metadataRow("Reading Level", value: level.rawValue.capitalized)
                }

                if let sentiment = document.sentiment {
                    metadataRow("Sentiment", value: sentiment.rawValue.capitalized)
                }

                if let categories = document.aiCategories, !categories.isEmpty {
                    metadataRow("Categories", value: categories.joined(separator: ", "))
                }

                if let topics = document.aiTopics, !topics.isEmpty {
                    metadataRow("Topics", value: topics.joined(separator: ", "))
                }

                metadataRow("Saved", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding(CPSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusMedium)
                .fill(Color(.systemGray6))
        )
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.cpSubhead)
                .foregroundColor(.cpTextSecondary)
            Spacer()
            Text(value)
                .font(.cpSubhead)
                .foregroundColor(.cpText)
        }
    }
}

// MARK: - PDF Viewer Sheet

struct PDFViewerSheet: View {
    let document: Document
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let pdfUrl = document.pdfUrl {
                    // Real PDF would be loaded here
                    PDFContentView(pdfUrl: pdfUrl, document: document)
                } else {
                    // Demo mode - show simulated PDF
                    DemoPDFView(document: document)
                }
            }
            .navigationTitle("Saved PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        sharePDF()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func sharePDF() {
        // In real app, share the actual PDF file
        var items: [Any] = [document.title]
        if let urlString = document.sourceUrl, let url = URL(string: urlString) {
            items.append(url)
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - PDF Content View (for real PDFs)

struct PDFContentView: View {
    let pdfUrl: String
    let document: Document

    var body: some View {
        // In production, this would use PDFKit to display the actual PDF
        VStack(spacing: CPSpacing.lg) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.cpTint)

            Text("PDF Available")
                .font(.cpTitle2)

            Text("The article has been saved as a PDF and can be viewed offline.")
                .font(.cpBody)
                .foregroundColor(.cpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CPSpacing.xl)

            if let url = URL(string: pdfUrl) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Download PDF")
                    }
                    .font(.cpHeadline)
                    .padding()
                    .background(Color.cpTint)
                    .foregroundColor(.white)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }
            }
        }
        .padding()
    }
}

// MARK: - Demo PDF View

struct DemoPDFView: View {
    let document: Document

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CPSpacing.lg) {
                // PDF Header
                VStack(alignment: .center, spacing: CPSpacing.md) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.red)
                        Text("PDF PREVIEW")
                            .font(.cpCaption1)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, CPSpacing.sm)
                    .padding(.vertical, CPSpacing.xxs)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)

                    Text(document.title)
                        .font(.cpTitle1)
                        .multilineTextAlignment(.center)

                    if let author = document.authorName {
                        Text("by \(author)")
                            .font(.cpSubhead)
                            .foregroundColor(.cpTextSecondary)
                    }

                    if let date = document.originalPublishedAt {
                        Text(date, style: .date)
                            .font(.cpCaption1)
                            .foregroundColor(.cpTextTertiary)
                    }

                    Divider()
                        .padding(.vertical, CPSpacing.sm)
                }
                .frame(maxWidth: .infinity)

                // PDF Body
                Text(document.bodyPlain)
                    .font(.system(size: 14, design: .serif))
                    .foregroundColor(.cpText)
                    .lineSpacing(8)

                // PDF Footer
                VStack(spacing: CPSpacing.sm) {
                    Divider()

                    HStack {
                        if let domain = document.sourceDomain {
                            Text("Source: \(domain)")
                                .font(.cpCaption1)
                                .foregroundColor(.cpTextTertiary)
                        }
                        Spacer()
                        Text("Saved by Commonplace")
                            .font(.cpCaption1)
                            .foregroundColor(.cpTextTertiary)
                    }

                    Text("This PDF was automatically generated and saved when you added this article. Even if the original link is deleted, you'll always have access to this content.")
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(CPSpacing.cornerRadiusMedium)
                }
            }
            .padding(CPSpacing.screenHorizontal)
            .padding(.vertical, CPSpacing.lg)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    NavigationStack {
        DocumentDetailView(document: Document.preview)
    }
}
