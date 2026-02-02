import Foundation
import SwiftUI

@MainActor
final class CampaignViewModel: ObservableObject {
    let document: Document

    @Published var selectedPlatforms: Set<SocialPlatform> = []
    @Published var generatedPosts: [GeneratedPlatformPosts] = []
    @Published var selectedVariations: [SocialPlatform: Int] = [:]
    @Published var connections: [SocialConnection] = []
    @Published var voiceProfiles: [VoiceProfile] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var isPublishing = false
    @Published var error: Error?
    @Published var successMessage: String?
    @Published var campaignId: UUID?

    private let campaignService = CampaignService.shared

    init(document: Document) {
        self.document = document
    }

    var connectedPlatforms: [SocialPlatform] {
        connections.filter { $0.isActive }.map { $0.platform }
    }

    var hasVoiceProfile: [SocialPlatform: Bool] {
        Dictionary(uniqueKeysWithValues: SocialPlatform.allCases.map { platform in
            (platform, voiceProfiles.contains { $0.platform == platform })
        })
    }

    // MARK: - Load Data

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        await campaignService.loadConnections()
        await campaignService.loadVoiceProfiles()

        connections = campaignService.connections
        voiceProfiles = campaignService.voiceProfiles

        // Auto-select connected platforms
        selectedPlatforms = Set(connectedPlatforms)

        // Check for existing campaign
        do {
            if let campaign = try await campaignService.getCampaign(for: document.id) {
                campaignId = campaign.id
                let posts = try await campaignService.getCampaignPosts(campaignId: campaign.id)
                // Group by platform and convert to GeneratedPlatformPosts format
                convertCampaignPostsToGenerated(posts)
            }
        } catch {
            print("No existing campaign:", error)
        }
    }

    private func convertCampaignPostsToGenerated(_ posts: [CampaignPost]) {
        let grouped = Dictionary(grouping: posts) { $0.platform }

        generatedPosts = grouped.map { platform, platformPosts in
            let sortedPosts = platformPosts.sorted { $0.variationIndex < $1.variationIndex }
            return GeneratedPlatformPosts(
                platform: platform.rawValue,
                variations: sortedPosts.map { post in
                    GeneratedPostVariation(
                        content: post.content,
                        hashtags: post.hashtags ?? [],
                        characterCount: post.content.count,
                        isOptimal: post.content.count <= platform.maxLength
                    )
                }
            )
        }

        // Set selected variations
        for (platform, platformPosts) in grouped {
            if let selectedPost = platformPosts.first(where: { $0.isSelected }) {
                selectedVariations[platform] = selectedPost.variationIndex
            } else {
                selectedVariations[platform] = 0
            }
        }
    }

    // MARK: - Generate Posts

    func generatePosts() async {
        guard !selectedPlatforms.isEmpty else {
            error = CampaignError.noConnection
            return
        }

        isGenerating = true
        error = nil

        do {
            let response = try await campaignService.generatePosts(
                for: document.id,
                platforms: Array(selectedPlatforms)
            )

            generatedPosts = response.posts
            campaignId = response.campaignId

            // Initialize selected variations
            for post in response.posts {
                if let platform = SocialPlatform(rawValue: post.platform) {
                    selectedVariations[platform] = 0
                }
            }

            HapticManager.saveSuccess()

        } catch {
            self.error = error
            HapticManager.error()
        }

        isGenerating = false
    }

    // MARK: - Analyze Style

    func analyzeStyle(for platform: SocialPlatform) async {
        isLoading = true
        error = nil

        do {
            _ = try await campaignService.analyzeStyle(for: platform)
            voiceProfiles = campaignService.voiceProfiles
            successMessage = "Voice profile created for \(platform.displayName)"
            HapticManager.saveSuccess()
        } catch {
            self.error = error
            HapticManager.error()
        }

        isLoading = false
    }

    // MARK: - Platform Selection

    func togglePlatform(_ platform: SocialPlatform) {
        if selectedPlatforms.contains(platform) {
            selectedPlatforms.remove(platform)
        } else {
            selectedPlatforms.insert(platform)
        }
    }

    // MARK: - Variation Selection

    func selectVariation(_ index: Int, for platform: SocialPlatform) {
        selectedVariations[platform] = index
        HapticManager.selection()
    }

    func getSelectedPost(for platform: SocialPlatform) -> GeneratedPostVariation? {
        guard let platformPosts = generatedPosts.first(where: { $0.platform == platform.rawValue }),
              let index = selectedVariations[platform],
              index < platformPosts.variations.count else {
            return nil
        }
        return platformPosts.variations[index]
    }

    // MARK: - Copy to Clipboard

    func copyToClipboard(_ platform: SocialPlatform) {
        guard let post = getSelectedPost(for: platform) else { return }

        var fullText = post.content
        if !post.hashtags.isEmpty {
            fullText += "\n\n" + post.hashtags.map { "#\($0)" }.joined(separator: " ")
        }

        UIPasteboard.general.string = fullText
        successMessage = "Copied to clipboard!"
        HapticManager.saveSuccess()
    }

    // MARK: - Generate PDF

    func generatePDF() async {
        isLoading = true
        error = nil

        do {
            let pdfUrl = try await campaignService.generatePDF(for: document.id)
            successMessage = "PDF generated successfully"
            print("PDF URL:", pdfUrl)
            HapticManager.saveSuccess()
        } catch {
            self.error = error
            HapticManager.error()
        }

        isLoading = false
    }
}
