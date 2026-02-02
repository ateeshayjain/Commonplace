import Foundation

// MARK: - Models

struct SocialConnection: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let platform: SocialPlatform
    let platformUsername: String?
    let platformDisplayName: String?
    let platformAvatarUrl: String?
    let isActive: Bool
    let connectedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case platform
        case platformUsername = "platform_username"
        case platformDisplayName = "platform_display_name"
        case platformAvatarUrl = "platform_avatar_url"
        case isActive = "is_active"
        case connectedAt = "connected_at"
    }
}

enum SocialPlatform: String, Codable, CaseIterable {
    case twitter
    case linkedin

    var displayName: String {
        switch self {
        case .twitter: return "X (Twitter)"
        case .linkedin: return "LinkedIn"
        }
    }

    var icon: String {
        switch self {
        case .twitter: return "𝕏"
        case .linkedin: return "in"
        }
    }

    var color: String {
        switch self {
        case .twitter: return "000000"
        case .linkedin: return "0A66C2"
        }
    }

    var maxLength: Int {
        switch self {
        case .twitter: return 280
        case .linkedin: return 3000
        }
    }
}

struct VoiceProfile: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let platform: SocialPlatform
    let tone: String?
    let vocabularyLevel: Int?
    let postStructure: String?
    let hashtagUsage: String?
    let engagementStyle: String?
    let topTopics: [String]?
    let samplePhrases: [String]?
    let postsAnalyzed: Int?
    let lastAnalyzedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case platform
        case tone
        case vocabularyLevel = "vocabulary_level"
        case postStructure = "post_structure"
        case hashtagUsage = "hashtag_usage"
        case engagementStyle = "engagement_style"
        case topTopics = "top_topics"
        case samplePhrases = "sample_phrases"
        case postsAnalyzed = "posts_analyzed"
        case lastAnalyzedAt = "last_analyzed_at"
    }
}

struct Campaign: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let documentId: UUID
    let status: CampaignStatus
    let platforms: [SocialPlatform]
    let scheduledAt: Date?
    let publishedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case documentId = "document_id"
        case status
        case platforms
        case scheduledAt = "scheduled_at"
        case publishedAt = "published_at"
        case createdAt = "created_at"
    }
}

enum CampaignStatus: String, Codable {
    case draft
    case scheduled
    case publishing
    case published
    case failed
}

struct CampaignPost: Codable, Identifiable {
    let id: UUID
    let campaignId: UUID
    let platform: SocialPlatform
    let content: String
    let hashtags: [String]?
    let variationIndex: Int
    var isSelected: Bool
    let status: PostStatus
    let publishedUrl: String?
    let publishedAt: Date?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case platform
        case content
        case hashtags
        case variationIndex = "variation_index"
        case isSelected = "is_selected"
        case status
        case publishedUrl = "published_url"
        case publishedAt = "published_at"
        case errorMessage = "error_message"
    }
}

enum PostStatus: String, Codable {
    case draft
    case scheduled
    case publishing
    case published
    case failed
}

struct GeneratedPostVariation: Codable {
    let content: String
    let hashtags: [String]
    let characterCount: Int
    let isOptimal: Bool
}

struct GeneratedPlatformPosts: Codable {
    let platform: String
    let variations: [GeneratedPostVariation]
}

struct GeneratePostsResponse: Codable {
    let success: Bool
    let campaignId: UUID?
    let posts: [GeneratedPlatformPosts]
}

// MARK: - Campaign Service

@MainActor
final class CampaignService: ObservableObject {
    static let shared = CampaignService()

    @Published var connections: [SocialConnection] = []
    @Published var voiceProfiles: [VoiceProfile] = []
    @Published var isLoading = false
    @Published var error: Error?

    private init() {}

    // MARK: - Connections

    func loadConnections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            connections = try await SupabaseService.shared.fetch(
                from: "social_connections",
                filters: ["is_active": "eq.true"]
            )
        } catch {
            self.error = error
            print("Failed to load connections:", error)
        }
    }

    func initiateOAuth(for platform: SocialPlatform) async throws -> (authUrl: String, state: String, codeVerifier: String) {
        let response: [String: String] = try await SupabaseService.shared.invokeFunction(
            name: "oauth-connect",
            body: [
                "platform": platform.rawValue,
                "action": "connect"
            ]
        )

        guard let authUrl = response["authUrl"],
              let state = response["state"],
              let codeVerifier = response["codeVerifier"] else {
            throw CampaignError.invalidResponse
        }

        return (authUrl, state, codeVerifier)
    }

    func completeOAuth(platform: SocialPlatform, code: String, codeVerifier: String) async throws {
        struct OAuthResponse: Codable {
            let success: Bool
        }
        let _: OAuthResponse = try await SupabaseService.shared.invokeFunction(
            name: "oauth-connect",
            body: [
                "platform": platform.rawValue,
                "action": "callback",
                "code": code,
                "codeVerifier": codeVerifier
            ]
        )

        await loadConnections()
    }

    func disconnect(platform: SocialPlatform) async throws {
        struct DisconnectResponse: Codable {
            let success: Bool
        }
        let _: DisconnectResponse = try await SupabaseService.shared.invokeFunction(
            name: "oauth-connect",
            body: [
                "platform": platform.rawValue,
                "action": "disconnect"
            ]
        )

        await loadConnections()
    }

    // MARK: - Voice Profiles

    func loadVoiceProfiles() async {
        do {
            voiceProfiles = try await SupabaseService.shared.fetch(
                from: "voice_profiles",
                filters: [:]
            )
        } catch {
            self.error = error
            print("Failed to load voice profiles:", error)
        }
    }

    func analyzeStyle(for platform: SocialPlatform) async throws -> VoiceProfile {
        let response: VoiceProfile = try await SupabaseService.shared.invokeFunction(
            name: "analyze-style",
            body: ["platform": platform.rawValue]
        )

        await loadVoiceProfiles()
        return response
    }

    // MARK: - Post Generation

    func generatePosts(for documentId: UUID, platforms: [SocialPlatform]) async throws -> GeneratePostsResponse {
        let response: GeneratePostsResponse = try await SupabaseService.shared.invokeFunction(
            name: "generate-posts",
            body: [
                "documentId": documentId.uuidString,
                "platforms": platforms.map { $0.rawValue }
            ]
        )

        return response
    }

    func getCampaign(for documentId: UUID) async throws -> Campaign? {
        let campaigns: [Campaign] = try await SupabaseService.shared.fetch(
            from: "campaigns",
            filters: ["document_id": "eq.\(documentId.uuidString)"]
        )
        return campaigns.first
    }

    func getCampaignPosts(campaignId: UUID) async throws -> [CampaignPost] {
        try await SupabaseService.shared.fetch(
            from: "campaign_posts",
            filters: ["campaign_id": "eq.\(campaignId.uuidString)"]
        )
    }

    func selectPostVariation(postId: UUID, campaignId: UUID) async throws {
        // Deselect all variations for this campaign first
        try await SupabaseService.shared.update(
            table: "campaign_posts",
            id: campaignId,
            values: ["is_selected": false]
        )

        // Select the chosen variation
        try await SupabaseService.shared.update(
            table: "campaign_posts",
            id: postId,
            values: ["is_selected": true]
        )
    }

    // MARK: - PDF Generation

    func generatePDF(for documentId: UUID) async throws -> String {
        struct PDFResponse: Codable {
            let success: Bool
            let pdfUrl: String
        }

        let response: PDFResponse = try await SupabaseService.shared.invokeFunction(
            name: "generate-pdf",
            body: ["documentId": documentId.uuidString]
        )

        return response.pdfUrl
    }
}

// MARK: - Errors

enum CampaignError: LocalizedError {
    case invalidResponse
    case noConnection
    case insufficientPosts
    case publishFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .noConnection:
            return "No social media connection found"
        case .insufficientPosts:
            return "Need at least 5 posts to analyze your style"
        case .publishFailed(let message):
            return "Failed to publish: \(message)"
        }
    }
}
