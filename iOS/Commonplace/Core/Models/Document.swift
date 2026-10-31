import Foundation

struct Document: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID

    // Source Information
    let sourceType: SourceType
    let sourceUrl: String?
    let sourceDomain: String?
    let capturedAt: Date
    let originalPublishedAt: Date?
    var isSourceDeleted: Bool

    // Author Information
    let authorName: String?
    let authorHandle: String?
    let authorUrl: String?
    let authorAvatarUrl: String?

    // Content
    var title: String
    let subtitle: String?
    let bodyPlain: String
    let wordCount: Int?
    let readingTimeMinutes: Int?
    let language: String?

    // Social Context
    let engagement: Engagement?
    let commentsSummary: String?
    let sentiment: Sentiment?

    // Thread Information
    var isThread: Bool
    let threadPosition: Int?
    let threadTotal: Int?
    let threadId: UUID?

    // AI Enrichment
    var aiHook: String?
    let aiSummaryShort: String?
    let aiSummaryLong: String?
    let aiKeyPoints: [String]?
    let aiCategories: [String]?
    let aiTopics: [String]?
    let aiComplexityScore: Int?
    let aiReadingLevel: ReadingLevel?
    let aiContentType: ContentType?
    var aiQuotableLines: [String]?

    // Source-specific metadata (YouTube channel/chapters, OCR pages)
    var metadata: DocumentMetadata?

    // Output
    var pdfUrl: String?
    let pdfVersion: Int?
    let thumbnailUrl: String?
    let screenshotUrl: String?

    // User Data
    var userCategories: [String]
    var userNotes: String?
    var isFavorite: Bool
    var isArchived: Bool
    var readProgress: Double
    var lastReadAt: Date?

    // Processing Status
    var processingStatus: ProcessingStatus
    let processingError: String?
    /// Saved past the free month's AI credits: the text is here, the summary
    /// comes when the reader taps Summarise (or upgrades). Nil on rows from
    /// before migration 010 and in demo data.
    var aiWaiting: Bool?

    // Timestamps
    let createdAt: Date
    let updatedAt: Date
    let processedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sourceType = "source_type"
        case sourceUrl = "source_url"
        case sourceDomain = "source_domain"
        case capturedAt = "captured_at"
        case originalPublishedAt = "original_published_at"
        case isSourceDeleted = "is_source_deleted"
        case authorName = "author_name"
        case authorHandle = "author_handle"
        case authorUrl = "author_url"
        case authorAvatarUrl = "author_avatar_url"
        case title
        case subtitle
        case bodyPlain = "body_plain"
        case wordCount = "word_count"
        case readingTimeMinutes = "reading_time_minutes"
        case language
        case engagement
        case commentsSummary = "comments_summary"
        case sentiment
        case isThread = "is_thread"
        case threadPosition = "thread_position"
        case threadTotal = "thread_total"
        case threadId = "thread_id"
        case aiHook = "ai_hook"
        case aiSummaryShort = "ai_summary_short"
        case aiSummaryLong = "ai_summary_long"
        case aiKeyPoints = "ai_key_points"
        case aiCategories = "ai_categories"
        case aiTopics = "ai_topics"
        case aiComplexityScore = "ai_complexity_score"
        case aiReadingLevel = "ai_reading_level"
        case aiContentType = "ai_content_type"
        case aiQuotableLines = "ai_quotable_lines"
        case metadata
        case pdfUrl = "pdf_url"
        case pdfVersion = "pdf_version"
        case thumbnailUrl = "thumbnail_url"
        case screenshotUrl = "screenshot_url"
        case userCategories = "user_categories"
        case userNotes = "user_notes"
        case isFavorite = "is_favorite"
        case isArchived = "is_archived"
        case readProgress = "read_progress"
        case lastReadAt = "last_read_at"
        case processingStatus = "processing_status"
        case processingError = "processing_error"
        case aiWaiting = "ai_waiting"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case processedAt = "processed_at"
    }
}

extension Document {
    var isWaitingForSummary: Bool { aiWaiting == true }
}

// MARK: - Supporting Types

enum SourceType: String, Codable, CaseIterable, Hashable {
    case twitter
    case linkedin
    case linkedinArticle = "linkedin_article"
    case article
    case substack
    case medium
    case youtube
    case podcast
    case pdf
    case reddit
    case hackernews
    case instagram
    case threads
    case email
    case screenshot
    case manual
    case bookOcr = "book_ocr"
    case unknown

    var displayName: String {
        switch self {
        case .twitter: return "Twitter"
        case .linkedin: return "LinkedIn"
        case .linkedinArticle: return "LinkedIn Article"
        case .article: return "Article"
        case .substack: return "Substack"
        case .medium: return "Medium"
        case .youtube: return "YouTube"
        case .podcast: return "Podcast"
        case .pdf: return "PDF"
        case .reddit: return "Reddit"
        case .hackernews: return "Hacker News"
        case .instagram: return "Instagram"
        case .threads: return "Threads"
        case .email: return "Email"
        case .screenshot: return "Screenshot"
        case .manual: return "Manual"
        case .bookOcr: return "Book Scan"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .twitter: return "𝕏"
        case .linkedin: return "in"
        case .linkedinArticle: return "in"
        case .article: return "📄"
        case .substack: return "📧"
        case .medium: return "M"
        case .youtube: return "▶️"
        case .podcast: return "🎙️"
        case .pdf: return "📑"
        case .reddit: return "🤖"
        case .hackernews: return "Y"
        case .instagram: return "📷"
        case .threads: return "@"
        case .email: return "✉️"
        case .screenshot: return "📸"
        case .manual: return "✍️"
        case .bookOcr: return "📖"
        case .unknown: return "📄"
        }
    }
}

// One flat shape for every source; unused fields stay nil
struct DocumentMetadata: Codable, Hashable {
    // YouTube
    var channelName: String?
    var viewCount: Int?
    var uploadDate: String?
    var thumbnailUrl: String?
    var chapters: [Chapter]?

    // Book OCR
    var pageCount: Int?
    var bookTitle: String?
    var pageNumbers: [Int]?

    // Articles: section headings in bodyPlain, in order
    var headings: [String]?

    struct Chapter: Codable, Hashable {
        let startSec: Int
        let title: String
    }
}

struct Engagement: Codable, Hashable {
    let likes: Int?
    let shares: Int?
    let comments: Int?
    let views: Int?
}

enum Sentiment: String, Codable, Hashable {
    case positive
    case negative
    case mixed
    case neutral
}

enum ReadingLevel: String, Codable, Hashable {
    case casual
    case intermediate
    case advanced
    case expert
}

enum ContentType: String, Codable, Hashable {
    case news
    case opinion
    case analysis
    case tutorial
    case thread
    case discussion
}

enum ProcessingStatus: String, Codable, Hashable {
    case pending
    case fetching
    case extracting
    case enriching
    case rendering
    case completed
    case failed
}

// MARK: - Preview Data

extension Document {
    static var preview: Document {
        Document(
            id: UUID(),
            userId: UUID(),
            sourceType: .article,
            sourceUrl: "https://example.com/article",
            sourceDomain: "example.com",
            capturedAt: Date(),
            originalPublishedAt: Date().addingTimeInterval(-86400),
            isSourceDeleted: false,
            authorName: "John Doe",
            authorHandle: "@johndoe",
            authorUrl: nil,
            authorAvatarUrl: nil,
            title: "The Future of AI in Mobile Development",
            subtitle: "How artificial intelligence is changing the way we build apps",
            bodyPlain: "Lorem ipsum dolor sit amet, consectetur adipiscing elit...",
            wordCount: 1500,
            readingTimeMinutes: 7,
            language: "en",
            engagement: Engagement(likes: 245, shares: 89, comments: 34, views: 5600),
            commentsSummary: "Generally positive reactions with some concerns about privacy.",
            sentiment: .positive,
            isThread: false,
            threadPosition: nil,
            threadTotal: nil,
            threadId: nil,
            aiSummaryShort: "This article explores how AI is revolutionizing mobile development, from automated testing to intelligent UI generation.",
            aiSummaryLong: "A comprehensive look at the intersection of AI and mobile development...",
            aiKeyPoints: [
                "AI can automate 60% of routine testing tasks",
                "ML models are becoming small enough for on-device inference",
                "Natural language interfaces are the next frontier"
            ],
            aiCategories: ["Technology", "Development"],
            aiTopics: ["AI", "Mobile", "SwiftUI"],
            aiComplexityScore: 6,
            aiReadingLevel: .intermediate,
            aiContentType: .analysis,
            aiQuotableLines: ["The future belongs to those who embrace AI as a tool, not a threat."],
            pdfUrl: "demo://pdf/preview-article",
            pdfVersion: 1,
            thumbnailUrl: nil,
            screenshotUrl: nil,
            userCategories: ["Technology"],
            userNotes: nil,
            isFavorite: false,
            isArchived: false,
            readProgress: 0.0,
            lastReadAt: nil,
            processingStatus: .completed,
            processingError: nil,
            createdAt: Date(),
            updatedAt: Date(),
            processedAt: Date()
        )
    }

    static var previews: [Document] {
        [
            preview,
            Document(
                id: UUID(),
                userId: UUID(),
                sourceType: .twitter,
                sourceUrl: "https://twitter.com/paulg/status/123",
                sourceDomain: "twitter.com",
                capturedAt: Date().addingTimeInterval(-3600),
                originalPublishedAt: Date().addingTimeInterval(-3600),
                isSourceDeleted: false,
                authorName: "Paul Graham",
                authorHandle: "@paulg",
                authorUrl: nil,
                authorAvatarUrl: nil,
                title: "Thread on startup advice",
                subtitle: nil,
                bodyPlain: "Here's what I've learned about startups over 20 years...",
                wordCount: 800,
                readingTimeMinutes: 4,
                language: "en",
                engagement: Engagement(likes: 5000, shares: 1200, comments: 340, views: 150000),
                commentsSummary: nil,
                sentiment: .positive,
                isThread: true,
                threadPosition: 1,
                threadTotal: 12,
                threadId: UUID(),
                aiSummaryShort: "Paul Graham shares his hard-won wisdom on building startups, focusing on the importance of talking to users.",
                aiSummaryLong: nil,
                aiKeyPoints: ["Talk to users", "Ship fast", "Don't scale prematurely"],
                aiCategories: ["Business"],
                aiTopics: ["Startups", "Entrepreneurship"],
                aiComplexityScore: 4,
                aiReadingLevel: .casual,
                aiContentType: .thread,
                aiQuotableLines: nil,
                pdfUrl: "demo://pdf/paul-graham-thread",
                pdfVersion: 1,
                thumbnailUrl: nil,
                screenshotUrl: nil,
                userCategories: ["Business"],
                userNotes: nil,
                isFavorite: true,
                isArchived: false,
                readProgress: 0.5,
                lastReadAt: Date().addingTimeInterval(-1800),
                processingStatus: .completed,
                processingError: nil,
                createdAt: Date().addingTimeInterval(-3600),
                updatedAt: Date().addingTimeInterval(-3600),
                processedAt: Date().addingTimeInterval(-3500)
            )
        ]
    }
}
