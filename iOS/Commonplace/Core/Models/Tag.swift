import Foundation

// Per-user tag; the database derives slug from name so near-duplicates collapse
struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let name: String
    let slug: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case slug
        case createdAt = "created_at"
    }
}

enum TagSource: String, Codable, Hashable {
    case ai
    case user
}
