import SwiftUI

struct ComposeView: View {
    let documents: [Document]
    let onDismiss: () -> Void

    @StateObject private var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss

    init(documents: [Document], onDismiss: @escaping () -> Void) {
        self.documents = documents
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: ComposeViewModel(documents: documents))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CPSpacing.lg) {
                    // Source articles summary
                    sourceArticlesSection

                    Divider()

                    // Content type selection
                    contentTypeSection

                    // Platform selection
                    platformSection

                    // Thinking depth
                    thinkingDepthSection

                    // Custom prompt (optional)
                    customPromptSection

                    // Generate button
                    generateButton

                    // Results
                    if viewModel.synthesis != nil {
                        Divider()
                        insightsSection
                        generatedContentSection
                    }
                }
                .padding(.horizontal, CPSpacing.screenHorizontal)
                .padding(.vertical, CPSpacing.screenVertical)
            }
            .navigationTitle("Create Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "")
            }
        }
    }

    // MARK: - Source Articles

    private var sourceArticlesSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.cpTint)
                Text(viewModel.documentSummary)
                    .font(.cpHeadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CPSpacing.xs) {
                    ForEach(documents) { doc in
                        SourceChip(document: doc)
                    }
                }
            }
        }
    }

    // MARK: - Content Type Selection

    private var contentTypeSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Content Type")
                .sectionHeaderStyle()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: CPSpacing.sm) {
                ForEach(OutputFormat.allCases) { type in
                    OutputFormatCard(
                        type: type,
                        isSelected: viewModel.selectedOutputFormats.contains(type),
                        onToggle: {
                            if viewModel.selectedOutputFormats.contains(type) {
                                viewModel.selectedOutputFormats.remove(type)
                            } else {
                                viewModel.selectedOutputFormats.insert(type)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Platform Selection

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Platforms")
                .sectionHeaderStyle()

            HStack(spacing: CPSpacing.sm) {
                ForEach(SocialPlatform.allCases, id: \.self) { platform in
                    PlatformChip(
                        platform: platform,
                        isSelected: viewModel.selectedPlatforms.contains(platform),
                        onToggle: {
                            if viewModel.selectedPlatforms.contains(platform) {
                                viewModel.selectedPlatforms.remove(platform)
                            } else {
                                viewModel.selectedPlatforms.insert(platform)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Thinking Depth

    private var thinkingDepthSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Text("Analysis Depth")
                    .sectionHeaderStyle()

                Spacer()

                Image(systemName: "brain.head.profile")
                    .foregroundColor(.cpTint)
            }

            VStack(spacing: CPSpacing.xs) {
                ForEach(ThinkingDepth.allCases) { depth in
                    ThinkingDepthRow(
                        depth: depth,
                        isSelected: viewModel.thinkingDepth == depth,
                        onSelect: { viewModel.thinkingDepth = depth }
                    )
                }
            }
        }
    }

    // MARK: - Custom Prompt

    private var customPromptSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Text("Custom Instructions")
                    .sectionHeaderStyle()
                Text("(optional)")
                    .font(.cpCaption1)
                    .foregroundColor(.cpTextSecondary)
            }

            TextField("e.g., Focus on AI implications, write for tech executives...", text: $viewModel.customPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            Task {
                await viewModel.generateContent()
            }
        } label: {
            HStack {
                if viewModel.isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(viewModel.isGenerating ? "Synthesizing \(documents.count) articles..." : "Generate Content")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.selectedOutputFormats.isEmpty || viewModel.isGenerating)
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            if let synthesis = viewModel.synthesis {
                Text("AI Analysis")
                    .sectionHeaderStyle()

                // Tabs for different insight levels
                Picker("Insights", selection: $viewModel.activeTab) {
                    Text("1st Order").tag(0)
                    Text("2nd Order").tag(1)
                    Text("3rd Order").tag(2)
                }
                .pickerStyle(.segmented)

                switch viewModel.activeTab {
                case 0:
                    InsightsList(
                        title: "What the articles say",
                        icon: "1.circle.fill",
                        insights: synthesis.firstOrderInsights,
                        color: .blue
                    )
                case 1:
                    InsightsList(
                        title: "Patterns & Connections",
                        icon: "2.circle.fill",
                        insights: synthesis.secondOrderInsights,
                        color: .purple
                    )
                case 2:
                    InsightsList(
                        title: "Implications & Predictions",
                        icon: "3.circle.fill",
                        insights: synthesis.thirdOrderInsights,
                        color: .orange
                    )
                default:
                    EmptyView()
                }

                // Common themes
                if !synthesis.commonThemes.isEmpty {
                    ThemesSection(themes: synthesis.commonThemes)
                }
            }
        }
    }

    // MARK: - Generated Content Section

    private var generatedContentSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            Text("Generated Content")
                .sectionHeaderStyle()

            ForEach(viewModel.generatedContent) { content in
                GeneratedContentCard(
                    content: content,
                    onCopy: { viewModel.copyToClipboard(content) },
                    onCopyThread: { viewModel.copyThread(content) }
                )
            }
        }
    }
}

// MARK: - Supporting Views

struct SourceChip: View {
    let document: Document

    var body: some View {
        HStack(spacing: CPSpacing.xxs) {
            SourceIcon(type: document.sourceType, size: 12)
            Text(document.title)
                .font(.cpCaption1)
                .lineLimit(1)
        }
        .padding(.horizontal, CPSpacing.sm)
        .padding(.vertical, CPSpacing.xxs)
        .background(Color.cpBackgroundSecondary)
        .cornerRadius(CPSpacing.cornerRadiusSmall)
    }
}

struct OutputFormatCard: View {
    let type: OutputFormat
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: CPSpacing.xs) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .cpTint)

                Text(type.rawValue)
                    .font(.cpSubhead)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .cpText)

                Text(type.description)
                    .font(.cpCaption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .cpTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(CPSpacing.sm)
            .background(isSelected ? Color.cpTint : Color.cpBackgroundSecondary)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
        }
        .buttonStyle(.plain)
    }
}

struct PlatformChip: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: CPSpacing.xxs) {
                Text(platform.icon)
                    .font(.system(size: 14, weight: .bold))
                Text(platform.displayName)
                    .font(.cpSubhead)
            }
            .padding(.horizontal, CPSpacing.sm)
            .padding(.vertical, CPSpacing.xs)
            .background(isSelected ? Color.cpTint : Color.cpBackgroundSecondary)
            .foregroundColor(isSelected ? .white : .cpText)
            .cornerRadius(CPSpacing.cornerRadiusMedium)
        }
        .buttonStyle(.plain)
    }
}

struct ThinkingDepthRow: View {
    let depth: ThinkingDepth
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: CPSpacing.sm) {
                Image(systemName: depth.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .cpTint : .cpTextSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(depth.rawValue)
                        .font(.cpSubhead)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.cpText)

                    Text(depth.description)
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cpTint)
                }
            }
            .padding(CPSpacing.sm)
            .background(isSelected ? Color.cpTint.opacity(0.1) : Color.cpBackgroundSecondary)
            .cornerRadius(CPSpacing.cornerRadiusSmall)
        }
        .buttonStyle(.plain)
    }
}

struct InsightsList: View {
    let title: String
    let icon: String
    let insights: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.cpSubhead)
                    .fontWeight(.semibold)
            }

            ForEach(insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: CPSpacing.xs) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    Text(insight)
                        .font(.cpBody)
                        .foregroundColor(.cpText)
                }
            }
        }
        .padding(CPSpacing.sm)
        .background(color.opacity(0.1))
        .cornerRadius(CPSpacing.cornerRadiusMedium)
    }
}

struct ThemesSection: View {
    let themes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Common Themes")
                .font(.cpSubhead)
                .fontWeight(.semibold)

            FlowLayout(spacing: CPSpacing.xs) {
                ForEach(themes, id: \.self) { theme in
                    Text(theme)
                        .font(.cpCaption1)
                        .padding(.horizontal, CPSpacing.sm)
                        .padding(.vertical, CPSpacing.xxs)
                        .background(Color.cpTint.opacity(0.1))
                        .foregroundColor(.cpTint)
                        .cornerRadius(CPSpacing.cornerRadiusSmall)
                }
            }
        }
    }
}

struct GeneratedContentCard: View {
    let content: GeneratedContent
    let onCopy: () -> Void
    let onCopyThread: () -> Void

    var body: some View {
        CPCard {
            VStack(alignment: .leading, spacing: CPSpacing.sm) {
                // Header
                HStack {
                    Image(systemName: content.type.icon)
                        .foregroundColor(.cpTint)

                    Text(content.type.rawValue)
                        .font(.cpHeadline)

                    if let platform = content.platform {
                        Text("•")
                            .foregroundColor(.cpTextSecondary)
                        Text(platform.icon)
                        Text(platform.displayName)
                            .font(.cpCaption1)
                            .foregroundColor(.cpTextSecondary)
                    }

                    Spacer()

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .foregroundColor(.cpTint)
                }

                // Content
                if let threadParts = content.threadParts, !threadParts.isEmpty {
                    // Thread view
                    VStack(alignment: .leading, spacing: CPSpacing.sm) {
                        ForEach(Array(threadParts.enumerated()), id: \.offset) { index, part in
                            HStack(alignment: .top, spacing: CPSpacing.xs) {
                                Text("\(index + 1).")
                                    .font(.cpCaption1)
                                    .fontWeight(.bold)
                                    .foregroundColor(.cpTint)

                                Text(part)
                                    .font(.cpBody)
                            }
                            .padding(CPSpacing.xs)
                            .background(Color.cpBackgroundSecondary)
                            .cornerRadius(CPSpacing.cornerRadiusSmall)
                        }
                    }

                    Button("Copy Thread", action: onCopyThread)
                        .font(.cpCaption1)
                        .foregroundColor(.cpTint)
                } else {
                    Text(content.content)
                        .font(.cpBody)
                        .foregroundColor(.cpText)
                        .padding(CPSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cpBackgroundSecondary)
                        .cornerRadius(CPSpacing.cornerRadiusSmall)
                }

                // Hashtags
                if !content.hashtags.isEmpty {
                    FlowLayout(spacing: CPSpacing.xxs) {
                        ForEach(content.hashtags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.cpCaption1)
                                .foregroundColor(.cpTint)
                        }
                    }
                }

                // Character count
                HStack {
                    Text("\(content.characterCount) characters")
                        .font(.cpCaption2)
                        .foregroundColor(.cpTextSecondary)

                    if let platform = content.platform {
                        let isOverLimit = content.characterCount > platform.maxLength
                        if isOverLimit {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.cpCaption2)
                                .foregroundColor(.orange)
                            Text("Over \(platform.displayName) limit")
                                .font(.cpCaption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ComposeView(documents: [.preview], onDismiss: {})
}
