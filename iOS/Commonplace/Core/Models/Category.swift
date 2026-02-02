import Foundation
import SwiftUI

struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID?
    let name: String
    let slug: String
    let icon: String?
    let color: String?
    let isSystem: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case slug
        case icon
        case color
        case isSystem = "is_system"
        case sortOrder = "sort_order"
    }

    var displayColor: Color {
        if let hex = color {
            return Color(hex: hex)
        }
        return .cpTint
    }
}

// MARK: - System Categories

extension Category {
    static let systemCategories: [Category] = [
        Category(id: UUID(), userId: nil, name: "Technology", slug: "technology", icon: "💻", color: "#007AFF", isSystem: true, sortOrder: 1),
        Category(id: UUID(), userId: nil, name: "Business", slug: "business", icon: "📊", color: "#34C759", isSystem: true, sortOrder: 2),
        Category(id: UUID(), userId: nil, name: "Health", slug: "health", icon: "🏥", color: "#FF3B30", isSystem: true, sortOrder: 3),
        Category(id: UUID(), userId: nil, name: "Science", slug: "science", icon: "🔬", color: "#AF52DE", isSystem: true, sortOrder: 4),
        Category(id: UUID(), userId: nil, name: "Culture", slug: "culture", icon: "🎭", color: "#FF9500", isSystem: true, sortOrder: 5),
        Category(id: UUID(), userId: nil, name: "Politics", slug: "politics", icon: "🏛️", color: "#5856D6", isSystem: true, sortOrder: 6),
        Category(id: UUID(), userId: nil, name: "Design", slug: "design", icon: "🎨", color: "#FF2D55", isSystem: true, sortOrder: 7),
        Category(id: UUID(), userId: nil, name: "Personal Dev", slug: "personal-dev", icon: "🧠", color: "#00C7BE", isSystem: true, sortOrder: 8)
    ]
}

