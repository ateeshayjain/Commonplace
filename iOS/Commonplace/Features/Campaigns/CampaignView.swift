import SwiftUI

struct CampaignView: View {
    let document: Document

    @StateObject private var viewModel: CampaignViewModel
    @State private var showingConnectSheet = false
    @Environment(\.dismiss) private var dismiss

    init(document: Document) {
        self.document = document
        _viewModel = StateObject(wrappedValue: CampaignViewModel(document: document))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CPSpacing.lg) {
                    // Document summary
                    documentHeader

                    Divider()

                    // Platform selection
                    platformSection

                    // Generate button
                    if !viewModel.selectedPlatforms.isEmpty && viewModel.generatedPosts.isEmpty {
                        generateButton
                    }

                    // Generated posts
                    if !viewModel.generatedPosts.isEmpty {
                        postsSection
                    }

                    // PDF Generation
                    pdfSection
                }
                .padding(.horizontal, CPSpacing.screenHorizontal)
                .padding(.vertical, CPSpacing.screenVertical)
            }
            .navigationTitle("Share & Publish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadData()
            }
            .overlay {
                if viewModel.isLoading && viewModel.connections.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.cpBackground.opacity(0.8))
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An error occurred")
            }
            .sheet(isPresented: $showingConnectSheet) {
                ConnectPlatformsSheet(
                    connections: viewModel.connections,
                    onConnect: { platform in
                        // Handle OAuth flow
                        Task {
                            await initiateOAuth(for: platform)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Document Header

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack(spacing: CPSpacing.xs) {
                Text(document.sourceType.icon)
                    .font(.system(size: 14))

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
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Platform Section

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                Text("Platforms")
                    .sectionHeaderStyle()

                Spacer()

                Button("Connect More") {
                    showingConnectSheet = true
                }
                .font(.cpSubhead)
                .foregroundColor(.cpTint)
            }

            if viewModel.connectedPlatforms.isEmpty {
                CPCard {
                    VStack(spacing: CPSpacing.sm) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 32))
                            .foregroundColor(.cpTextSecondary)

                        Text("No connected platforms")
                            .font(.cpCallout)
                            .foregroundColor(.cpTextSecondary)

                        Button("Connect Platform") {
                            showingConnectSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CPSpacing.md)
                }
            } else {
                ForEach(SocialPlatform.allCases, id: \.self) { platform in
                    if viewModel.connectedPlatforms.contains(platform) {
                        PlatformRow(
                            platform: platform,
                            isSelected: viewModel.selectedPlatforms.contains(platform),
                            hasVoiceProfile: viewModel.hasVoiceProfile[platform] ?? false,
                            connection: viewModel.connections.first { $0.platform == platform },
                            onToggle: {
                                viewModel.togglePlatform(platform)
                            },
                            onAnalyze: {
                                Task {
                                    await viewModel.analyzeStyle(for: platform)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            Task {
                await viewModel.generatePosts()
            }
        } label: {
            HStack {
                if viewModel.isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(viewModel.isGenerating ? "Generating..." : "Generate Posts")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.isGenerating)
    }

    // MARK: - Posts Section

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            Text("Generated Posts")
                .sectionHeaderStyle()

            ForEach(viewModel.generatedPosts, id: \.platform) { platformPosts in
                if let platform = SocialPlatform(rawValue: platformPosts.platform) {
                    PostVariationsCard(
                        platform: platform,
                        variations: platformPosts.variations,
                        selectedIndex: viewModel.selectedVariations[platform] ?? 0,
                        onSelect: { index in
                            viewModel.selectVariation(index, for: platform)
                        },
                        onCopy: {
                            viewModel.copyToClipboard(platform)
                        }
                    )
                }
            }
        }
    }

    // MARK: - PDF Section

    private var pdfSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            Text("Export")
                .sectionHeaderStyle()

            Button {
                Task {
                    await viewModel.generatePDF()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.fill")
                    Text("Generate PDF")
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.cpTextSecondary)
                    }
                }
                .padding()
                .background(Color.cpBackgroundSecondary)
                .cornerRadius(CPSpacing.cornerRadiusMedium)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - OAuth

    private func initiateOAuth(for platform: SocialPlatform) async {
        do {
            let (authUrl, _, _) = try await CampaignService.shared.initiateOAuth(for: platform)
            // Open auth URL in Safari
            if let url = URL(string: authUrl) {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
        } catch {
            viewModel.error = error
        }
    }
}

// MARK: - Platform Row

struct PlatformRow: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let hasVoiceProfile: Bool
    let connection: SocialConnection?
    let onToggle: () -> Void
    let onAnalyze: () -> Void

    var body: some View {
        CPCard {
            HStack(spacing: CPSpacing.sm) {
                // Platform icon
                ZStack {
                    Circle()
                        .fill(Color(hex: platform.color).opacity(0.1))
                        .frame(width: 44, height: 44)

                    Text(platform.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: platform.color))
                }

                // Platform info
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.displayName)
                        .font(.cpHeadline)
                        .foregroundColor(.cpText)

                    if let username = connection?.platformUsername {
                        Text("@\(username)")
                            .font(.cpFootnote)
                            .foregroundColor(.cpTextSecondary)
                    }
                }

                Spacer()

                // Voice profile indicator
                if hasVoiceProfile {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.cpTint)
                        .help("Voice profile active")
                } else {
                    Button("Analyze") {
                        onAnalyze()
                    }
                    .font(.cpCaption1)
                    .foregroundColor(.cpTint)
                }

                // Selection toggle
                Toggle("", isOn: .constant(isSelected))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .cpTint))
                    .onTapGesture {
                        onToggle()
                    }
            }
        }
    }
}

// MARK: - Post Variations Card

struct PostVariationsCard: View {
    let platform: SocialPlatform
    let variations: [GeneratedPostVariation]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onCopy: () -> Void

    var body: some View {
        CPCard {
            VStack(alignment: .leading, spacing: CPSpacing.sm) {
                // Platform header
                HStack {
                    Text(platform.icon)
                        .font(.system(size: 16, weight: .bold))

                    Text(platform.displayName)
                        .font(.cpHeadline)

                    Spacer()

                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .foregroundColor(.cpTint)
                }

                // Variation selector
                HStack(spacing: CPSpacing.xs) {
                    ForEach(0..<variations.count, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            Text("V\(index + 1)")
                                .font(.cpCaption1)
                                .fontWeight(selectedIndex == index ? .semibold : .regular)
                                .padding(.horizontal, CPSpacing.sm)
                                .padding(.vertical, CPSpacing.xxs)
                                .background(selectedIndex == index ? Color.cpTint : Color.cpBackgroundSecondary)
                                .foregroundColor(selectedIndex == index ? .white : .cpText)
                                .cornerRadius(CPSpacing.cornerRadiusSmall)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Selected variation content
                if selectedIndex < variations.count {
                    let variation = variations[selectedIndex]

                    Text(variation.content)
                        .font(.cpBody)
                        .foregroundColor(.cpText)
                        .padding(CPSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cpBackgroundSecondary)
                        .cornerRadius(CPSpacing.cornerRadiusSmall)

                    // Hashtags
                    if !variation.hashtags.isEmpty {
                        FlowLayout(spacing: CPSpacing.xxs) {
                            ForEach(variation.hashtags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.cpCaption1)
                                    .foregroundColor(.cpTint)
                            }
                        }
                    }

                    // Character count
                    HStack {
                        Text("\(variation.characterCount)/\(platform.maxLength)")
                            .font(.cpCaption2)
                            .foregroundColor(variation.isOptimal ? .cpTextSecondary : .red)

                        if !variation.isOptimal {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.cpCaption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Connect Platforms Sheet

struct ConnectPlatformsSheet: View {
    let connections: [SocialConnection]
    let onConnect: (SocialPlatform) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SocialPlatform.allCases, id: \.self) { platform in
                    let isConnected = connections.contains { $0.platform == platform && $0.isActive }

                    HStack {
                        Text(platform.icon)
                            .font(.title2)
                            .frame(width: 40)

                        Text(platform.displayName)
                            .font(.cpBody)

                        Spacer()

                        if isConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Connect") {
                                onConnect(platform)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, CPSpacing.xs)
                }
            }
            .navigationTitle("Connect Platforms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CampaignView(document: .preview)
}
