import Foundation

// Named DocumentCollection to avoid clashing with Swift's Collection protocol
struct DocumentCollection: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var description: String?
    var isPublic: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case description
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
