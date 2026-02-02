import Foundation
import SwiftUI

// MARK: - Content Types

enum OutputFormat: String, CaseIterable, Identifiable {
    case post = "Social Post"
    case thread = "Twitter Thread"
    case newsletter = "Newsletter"
    case article = "Long-form Article"
    case summary = "Executive Summary"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .post: return "square.and.pencil"
        case .thread: return "text.bubble"
        case .newsletter: return "envelope"
        case .article: return "doc.text"
        case .summary: return "list.bullet.clipboard"
        }
    }

    var description: String {
        switch self {
        case .post: return "Short-form content for social media"
        case .thread: return "Multi-part thread with numbered insights"
        case .newsletter: return "Weekly digest with commentary"
        case .article: return "Deep-dive analysis piece"
        case .summary: return "Key takeaways for busy readers"
        }
    }
}

enum ThinkingDepth: String, CaseIterable, Identifiable {
    case surface = "Surface Level"
    case secondOrder = "Second Order"
    case thirdOrder = "Third Order"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .surface: return "What the articles say"
        case .secondOrder: return "Patterns & connections across articles"
        case .thirdOrder: return "Future implications & contrarian insights"
        }
    }

    var icon: String {
        switch self {
        case .surface: return "1.circle"
        case .secondOrder: return "2.circle"
        case .thirdOrder: return "3.circle"
        }
    }
}

// MARK: - Generated Content

struct GeneratedContent: Identifiable {
    let id = UUID()
    let type: OutputFormat
    let platform: SocialPlatform?
    let title: String
    let content: String
    let hashtags: [String]
    let insights: [String]
    let threadParts: [String]?
    let characterCount: Int
    var isSelected: Bool = false
}

struct SynthesisResponse: Codable {
    let success: Bool
    let synthesis: SynthesisResult
}

struct SynthesisResult: Codable {
    let title: String
    let executiveSummary: String
    let firstOrderInsights: [String]
    let secondOrderInsights: [String]
    let thirdOrderInsights: [String]
    let commonThemes: [String]
    let contrasts: [String]
    let futureImplications: [String]
    let actionableAdvice: [String]
    let generatedContent: [GeneratedContentResult]

    enum CodingKeys: String, CodingKey {
        case title
        case executiveSummary = "executive_summary"
        case firstOrderInsights = "first_order_insights"
        case secondOrderInsights = "second_order_insights"
        case thirdOrderInsights = "third_order_insights"
        case commonThemes = "common_themes"
        case contrasts
        case futureImplications = "future_implications"
        case actionableAdvice = "actionable_advice"
        case generatedContent = "generated_content"
    }
}

struct GeneratedContentResult: Codable {
    let type: String
    let platform: String?
    let title: String
    let content: String
    let hashtags: [String]?
    let threadParts: [String]?
}

// MARK: - View Model

@MainActor
final class ComposeViewModel: ObservableObject {
    let documents: [Document]

    // Configuration
    @Published var selectedOutputFormats: Set<OutputFormat> = [.post]
    @Published var selectedPlatforms: Set<SocialPlatform> = [.twitter, .linkedin]
    @Published var thinkingDepth: ThinkingDepth = .thirdOrder
    @Published var includeHashtags = true
    @Published var customPrompt = ""

    // State
    @Published var isGenerating = false
    @Published var generatedContent: [GeneratedContent] = []
    @Published var synthesis: SynthesisResult?
    @Published var error: Error?
    @Published var activeTab = 0

    init(documents: [Document]) {
        self.documents = documents
    }

    var documentSummary: String {
        "\(documents.count) article\(documents.count == 1 ? "" : "s") selected"
    }

    var sourceTitles: [String] {
        documents.map { $0.title }
    }

    // MARK: - Generate Content

    func generateContent() async {
        isGenerating = true
        error = nil

        do {
            let response: SynthesisResponse = try await SupabaseService.shared.invokeFunction(
                name: "synthesize-content",
                body: [
                    "documentIds": documents.map { $0.id.uuidString },
                    "contentTypes": selectedOutputFormats.map { $0.rawValue },
                    "platforms": selectedPlatforms.map { $0.rawValue },
                    "thinkingDepth": thinkingDepth.rawValue,
                    "includeHashtags": includeHashtags,
                    "customPrompt": customPrompt
                ]
            )

            synthesis = response.synthesis

            // Convert to GeneratedContent
            generatedContent = response.synthesis.generatedContent.map { result in
                GeneratedContent(
                    type: OutputFormat(rawValue: result.type) ?? .post,
                    platform: result.platform.flatMap { SocialPlatform(rawValue: $0) },
                    title: result.title,
                    content: result.content,
                    hashtags: result.hashtags ?? [],
                    insights: [],
                    threadParts: result.threadParts,
                    characterCount: result.content.count
                )
            }

            HapticManager.saveSuccess()

        } catch {
            self.error = error
            HapticManager.error()
            print("Generation failed:", error)
        }

        isGenerating = false
    }

    // MARK: - Copy Content

    func copyToClipboard(_ content: GeneratedContent) {
        var text = content.content
        if !content.hashtags.isEmpty {
            text += "\n\n" + content.hashtags.map { "#\($0)" }.joined(separator: " ")
        }
        UIPasteboard.general.string = text
        HapticManager.saveSuccess()
    }

    func copyThread(_ content: GeneratedContent) {
        guard let parts = content.threadParts else { return }
        let text = parts.enumerated().map { "\($0.offset + 1)/\(parts.count) \($0.element)" }.joined(separator: "\n\n")
        UIPasteboard.general.string = text
        HapticManager.saveSuccess()
    }
}
