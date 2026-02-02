import Foundation

class DocumentService {
    static let shared = DocumentService()

    private let supabase = SupabaseService.shared

    private init() {}

    // MARK: - Fetch Documents

    func fetchDocuments(
        category: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [Document] {
        var filters: [String: String] = [
            "processing_status": "eq.completed"
        ]

        if let category = category {
            filters["user_categories"] = "cs.[\"\(category)\"]"
        }

        return try await supabase.fetch(
            from: "documents",
            filters: filters,
            order: "created_at.desc",
            limit: limit
        )
    }

    func fetchDocument(id: UUID) async throws -> Document? {
        let documents: [Document] = try await supabase.fetch(
            from: "documents",
            filters: ["id": "eq.\(id.uuidString)"],
            limit: 1
        )
        return documents.first
    }

    func fetchFavorites(limit: Int = 50) async throws -> [Document] {
        return try await supabase.fetch(
            from: "documents",
            filters: [
                "is_favorite": "eq.true",
                "processing_status": "eq.completed"
            ],
            order: "created_at.desc",
            limit: limit
        )
    }

    // MARK: - Search

    struct SearchResult: Codable, Identifiable, Hashable {
        let id: UUID
        let title: String
        let aiSummaryShort: String?
        let sourceType: SourceType
        let authorName: String?
        let createdAt: Date
        let rank: Double

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case aiSummaryShort = "ai_summary_short"
            case sourceType = "source_type"
            case authorName = "author_name"
            case createdAt = "created_at"
            case rank
        }
    }

    func searchDocuments(query: String, limit: Int = 20) async throws -> [SearchResult] {
        return try await supabase.rpc(
            function: "search_documents",
            params: [
                "p_query": query,
                "p_limit": limit
            ]
        )
    }

    // MARK: - Save URL

    struct SaveURLResponse: Codable {
        let id: UUID
        let status: String
        let message: String
    }

    func saveURL(_ url: String, categories: [String] = []) async throws -> SaveURLResponse {
        return try await supabase.invokeFunction(
            name: "process-url",
            body: [
                "url": url,
                "categories": categories
            ]
        )
    }

    // MARK: - Update Document

    func toggleFavorite(_ id: UUID, isFavorite: Bool) async throws {
        try await supabase.update(
            table: "documents",
            id: id,
            values: ["is_favorite": isFavorite]
        )
    }

    func updateCategories(_ id: UUID, categories: [String]) async throws {
        try await supabase.update(
            table: "documents",
            id: id,
            values: ["user_categories": categories]
        )
    }

    func updateReadProgress(_ id: UUID, progress: Double) async throws {
        try await supabase.update(
            table: "documents",
            id: id,
            values: [
                "read_progress": progress,
                "last_read_at": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    func updateNotes(_ id: UUID, notes: String) async throws {
        try await supabase.update(
            table: "documents",
            id: id,
            values: ["user_notes": notes]
        )
    }

    func archiveDocument(_ id: UUID, isArchived: Bool) async throws {
        try await supabase.update(
            table: "documents",
            id: id,
            values: ["is_archived": isArchived]
        )
    }

    // MARK: - Delete Document

    func deleteDocument(_ id: UUID) async throws {
        try await supabase.delete(from: "documents", id: id)
    }

    // MARK: - Categories

    func fetchCategories() async throws -> [Category] {
        return try await supabase.fetch(
            from: "categories",
            order: "sort_order.asc"
        )
    }

    // MARK: - Stats

    struct LibraryStats: Codable {
        let totalDocuments: Int
        let totalReadTime: Int
        let documentsThisWeek: Int
        let topCategories: [String]
    }

    func fetchStats() async throws -> LibraryStats {
        // For now, return computed stats
        let documents: [Document] = try await supabase.fetch(
            from: "documents",
            filters: ["processing_status": "eq.completed"]
        )

        let totalReadTime = documents.compactMap { $0.readingTimeMinutes }.reduce(0, +)

        let oneWeekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let documentsThisWeek = documents.filter { $0.createdAt > oneWeekAgo }.count

        let categoryCounts = documents.flatMap { $0.userCategories }
            .reduce(into: [:]) { counts, category in
                counts[category, default: 0] += 1
            }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        return LibraryStats(
            totalDocuments: documents.count,
            totalReadTime: totalReadTime,
            documentsThisWeek: documentsThisWeek,
            topCategories: Array(categoryCounts)
        )
    }
}

// MARK: - Demo Data

extension DocumentService {
    func fetchDemoDocuments() -> [Document] {
        return Document.previews + [
            Document(
                id: UUID(),
                userId: UUID(),
                sourceType: .youtube,
                sourceUrl: "https://youtube.com/watch?v=xyz",
                sourceDomain: "youtube.com",
                capturedAt: Date().addingTimeInterval(-7200),
                originalPublishedAt: Date().addingTimeInterval(-86400 * 3),
                isSourceDeleted: false,
                authorName: "Lex Fridman",
                authorHandle: nil,
                authorUrl: nil,
                authorAvatarUrl: nil,
                title: "Interview with Sam Altman: The Future of AI",
                subtitle: nil,
                bodyPlain: """
In this episode, we discuss the future of artificial intelligence with Sam Altman, CEO of OpenAI.

Sam shares his vision for AGI and why he believes we're closer than most people think. "The rate of progress has been extraordinary," he explains. "What took us years before now takes months."

Key topics covered:

1. The Path to AGI
Sam believes AGI could arrive within 5-10 years, though he emphasizes the uncertainty in such predictions. "We're building something unprecedented," he notes.

2. Safety First
OpenAI's approach prioritizes safety research alongside capability improvements. "We can't just build powerful AI and figure out safety later - they have to develop together."

3. Economic Implications
The conversation explores how AI will transform work. Sam argues it will create more jobs than it eliminates, but acknowledges the transition will be challenging.

4. Open vs Closed
Despite the company name, OpenAI has shifted toward keeping some research private. Sam defends this: "Being responsible sometimes means not sharing everything."

The interview concludes with Sam's optimistic vision: AI as a tool that amplifies human potential rather than replacing it.
""",
                wordCount: 15000,
                readingTimeMinutes: 120,
                language: "en",
                engagement: Engagement(likes: 50000, shares: nil, comments: 3400, views: 2000000),
                commentsSummary: nil,
                sentiment: .positive,
                isThread: false,
                threadPosition: nil,
                threadTotal: nil,
                threadId: nil,
                aiSummaryShort: "Sam Altman discusses OpenAI's mission, the path to AGI, and the importance of safety in AI development.",
                aiSummaryLong: nil,
                aiKeyPoints: ["AGI is 5-10 years away", "Safety is paramount", "Open collaboration needed"],
                aiCategories: ["Technology"],
                aiTopics: ["AI", "AGI", "OpenAI"],
                aiComplexityScore: 5,
                aiReadingLevel: .intermediate,
                aiContentType: .discussion,
                aiQuotableLines: nil,
                pdfUrl: "demo://pdf/sam-altman-interview",
                pdfVersion: 1,
                thumbnailUrl: nil,
                screenshotUrl: nil,
                userCategories: ["Technology"],
                userNotes: nil,
                isFavorite: false,
                isArchived: false,
                readProgress: 0.25,
                lastReadAt: nil,
                processingStatus: .completed,
                processingError: nil,
                createdAt: Date().addingTimeInterval(-7200),
                updatedAt: Date().addingTimeInterval(-7200),
                processedAt: Date().addingTimeInterval(-7100)
            ),
            Document(
                id: UUID(),
                userId: UUID(),
                sourceType: .substack,
                sourceUrl: "https://stratechery.com/article",
                sourceDomain: "stratechery.com",
                capturedAt: Date().addingTimeInterval(-86400),
                originalPublishedAt: Date().addingTimeInterval(-86400 * 2),
                isSourceDeleted: false,
                authorName: "Ben Thompson",
                authorHandle: nil,
                authorUrl: nil,
                authorAvatarUrl: nil,
                title: "Apple's AI Strategy: Analysis",
                subtitle: "Why Apple is taking a different approach to AI",
                bodyPlain: """
Apple's approach to artificial intelligence has always been different from its Silicon Valley peers, and that difference is becoming more pronounced as the AI race intensifies.

While Google, Microsoft, and OpenAI compete to build the most powerful cloud-based AI models, Apple is doubling down on on-device processing. This isn't just a technical choice—it's a strategic philosophy.

The Privacy Advantage

Apple's commitment to privacy isn't just marketing; it's infrastructure. By processing AI on-device, Apple sidesteps the data collection that fuels competitors' models. This is both a limitation and a differentiator.

"Your data never leaves your device" is a powerful message in an era of increasing AI anxiety.

Integration Over Innovation

Apple has never been first to market with new technologies. They weren't first with smartphones, tablets, or smartwatches. Their genius lies in integration—making technologies work seamlessly together.

The same pattern is emerging with AI. Apple Intelligence isn't trying to out-GPT GPT. Instead, it's weaving AI throughout the Apple ecosystem in ways that feel natural and useful.

The Strategic Implications

This approach has trade-offs:

Pros:
• Privacy protection builds trust
• On-device = faster, works offline
• Deep integration with Apple ecosystem
• No subscription fatigue

Cons:
• Less capable than cloud models
• Slower to improve
• Limited to Apple devices

Apple is betting that "good enough AI that respects privacy" beats "amazing AI that knows everything about you." Time will tell if they're right.
""",
                wordCount: 3500,
                readingTimeMinutes: 15,
                language: "en",
                engagement: nil,
                commentsSummary: nil,
                sentiment: .neutral,
                isThread: false,
                threadPosition: nil,
                threadTotal: nil,
                threadId: nil,
                aiSummaryShort: "Ben Thompson analyzes Apple's unique approach to AI, focusing on privacy-first on-device processing and its strategic implications.",
                aiSummaryLong: nil,
                aiKeyPoints: ["Privacy as differentiator", "On-device vs cloud", "Integration advantage"],
                aiCategories: ["Technology", "Business"],
                aiTopics: ["Apple", "AI", "Strategy"],
                aiComplexityScore: 7,
                aiReadingLevel: .advanced,
                aiContentType: .analysis,
                aiQuotableLines: ["Apple's AI strategy is fundamentally about integration, not innovation."],
                pdfUrl: "demo://pdf/apple-ai-strategy",
                pdfVersion: 1,
                thumbnailUrl: nil,
                screenshotUrl: nil,
                userCategories: ["Technology", "Business"],
                userNotes: nil,
                isFavorite: true,
                isArchived: false,
                readProgress: 1.0,
                lastReadAt: Date().addingTimeInterval(-3600),
                processingStatus: .completed,
                processingError: nil,
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date().addingTimeInterval(-86400),
                processedAt: Date().addingTimeInterval(-86300)
            )
        ]
    }
}
