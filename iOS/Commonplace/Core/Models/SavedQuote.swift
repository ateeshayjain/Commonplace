import Foundation

/// A quote the reader bookmarked (table `saved_quotes`). The Quotes tab lists
/// these across the library; `document` is embedded on fetch so a row can show
/// its credit line and open the save it came from.
struct SavedQuote: Identifiable, Codable, Hashable {
    let id: UUID
    let documentId: UUID
    let text: String
    let isVerbatim: Bool
    let createdAt: Date
    var document: Document?

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case text
        case isVerbatim = "is_verbatim"
        case createdAt = "created_at"
        case document
    }

    var shareable: ShareableQuote {
        ShareableQuote(text: text, isVerbatim: isVerbatim)
    }

    static func == (lhs: SavedQuote, rhs: SavedQuote) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
