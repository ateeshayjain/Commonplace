import Foundation

// Mirrors generated_assets (supabase/migrations/004_sangrah_data_model.sql)
// and supabase/functions/_shared/generation.ts — keep the three in sync.

struct GeneratedAsset: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let documentId: UUID?
    let sourceDocumentIds: [UUID]
    let collectionId: UUID?
    let format: ExportFormat
    var status: AssetStatus
    let content: GeneratedContent?
    let storagePaths: [String]
    let error: String?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case documentId = "document_id"
        case sourceDocumentIds = "source_document_ids"
        case collectionId = "collection_id"
        case format
        case status
        case content
        case storagePaths = "storage_paths"
        case error
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        documentId = try container.decodeIfPresent(UUID.self, forKey: .documentId)
        sourceDocumentIds = try container.decodeIfPresent([UUID].self, forKey: .sourceDocumentIds) ?? []
        collectionId = try container.decodeIfPresent(UUID.self, forKey: .collectionId)
        format = try container.decode(ExportFormat.self, forKey: .format)
        status = try container.decode(AssetStatus.self, forKey: .status)
        storagePaths = try container.decodeIfPresent([String].self, forKey: .storagePaths) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)

        // The content shape depends on the format
        guard container.contains(.content), try !container.decodeNil(forKey: .content) else {
            content = nil
            return
        }
        switch format {
        case .pdfDossier:
            content = .dossier(try container.decode(DossierContent.self, forKey: .content))
        case .carouselImagePack:
            content = .carousel(try container.decode(CarouselContent.self, forKey: .content))
        case .quoteGraphic:
            content = .quoteGraphic(try container.decode(QuoteGraphicContent.self, forKey: .content))
        case .shortVideoScript, .generatedVideo:
            content = .videoScript(try container.decode(VideoScriptContent.self, forKey: .content))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(documentId, forKey: .documentId)
        try container.encode(sourceDocumentIds, forKey: .sourceDocumentIds)
        try container.encodeIfPresent(collectionId, forKey: .collectionId)
        try container.encode(format, forKey: .format)
        try container.encode(status, forKey: .status)
        try container.encode(storagePaths, forKey: .storagePaths)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)

        switch content {
        case .dossier(let value): try container.encode(value, forKey: .content)
        case .carousel(let value): try container.encode(value, forKey: .content)
        case .quoteGraphic(let value): try container.encode(value, forKey: .content)
        case .videoScript(let value): try container.encode(value, forKey: .content)
        case nil: try container.encodeNil(forKey: .content)
        }
    }
}

// MARK: - Supporting Types

enum ExportFormat: String, Codable, CaseIterable, Hashable {
    case pdfDossier = "pdf_dossier"
    case carouselImagePack = "carousel_image_pack"
    case quoteGraphic = "quote_graphic"
    case shortVideoScript = "short_video_script"
    case generatedVideo = "generated_video"

    var displayName: String {
        switch self {
        case .pdfDossier: return "PDF Dossier"
        case .carouselImagePack: return "Carousel"
        case .quoteGraphic: return "Quote Graphic"
        case .shortVideoScript: return "Video Script"
        case .generatedVideo: return "Video"
        }
    }
}

enum AssetStatus: String, Codable, Hashable {
    case queued
    case processing
    case completed
    case failed
}

enum CarouselTheme: String, Codable, CaseIterable, Hashable {
    case light
    case dark
}

enum QuoteStylePreset: String, Codable, CaseIterable, Hashable {
    case minimalCard = "minimal_card"
    case darkChart = "dark_chart"
    case boldOverlay = "bold_overlay"
}

enum GenerationLimits {
    static let hookMaxChars = 150
    static let carouselSlides = 5...10
    static let videoDurationSec = 15...90
    static let defaultVideoDurationSec = 60
    static let dossierMaxDocuments = 25
}

// MARK: - Generated Content

enum GeneratedContent: Hashable {
    case dossier(DossierContent)
    case carousel(CarouselContent)
    case quoteGraphic(QuoteGraphicContent)
    case videoScript(VideoScriptContent)
}

struct DossierContent: Codable, Hashable {
    let title: String
    let pageCount: Int
    let tableOfContents: [Entry]

    struct Entry: Codable, Hashable {
        let documentId: UUID
        let title: String
        let page: Int
    }
}

struct CarouselContent: Codable, Hashable {
    let title: String
    let slides: [Slide]

    struct Slide: Codable, Hashable, Identifiable {
        let index: Int
        let role: Role
        let headline: String
        let body: String?

        var id: Int { index }

        enum Role: String, Codable, Hashable {
            case hook
            case body
            case cta
        }
    }
}

struct QuoteGraphicContent: Codable, Hashable {
    let quote: String
    let attribution: String?
}

struct VideoScriptContent: Codable, Hashable {
    let hook: Segment
    let body: [Segment]
    let callToAction: Segment
    let totalDurationSec: Int

    struct Segment: Codable, Hashable {
        let startSec: Int
        let endSec: Int
        let voiceover: String
        let onScreenText: String?
        let visualCue: String?
    }
}
