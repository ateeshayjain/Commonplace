import Foundation

struct User: Identifiable, Codable {
    let id: UUID
    let email: String
    var fullName: String?
    var avatarUrl: String?
    var subscriptionTier: SubscriptionTier
    var subscriptionExpiresAt: Date?
    var readingProfile: ReadingProfile
    var settings: UserSettings
    let createdAt: Date
    var updatedAt: Date
    var lastActiveAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case subscriptionTier = "subscription_tier"
        case subscriptionExpiresAt = "subscription_expires_at"
        case readingProfile = "reading_profile"
        case settings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastActiveAt = "last_active_at"
    }
}

enum SubscriptionTier: String, Codable {
    case free
    case pro
    case creator
    case team

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .creator: return "Creator"
        case .team: return "Team"
        }
    }

    var savesPerMonth: Int {
        switch self {
        case .free: return 50
        case .pro, .creator, .team: return Int.max
        }
    }

    var postsPerMonth: Int {
        switch self {
        case .free: return 10
        case .pro, .creator, .team: return Int.max
        }
    }
}

struct ReadingProfile: Codable {
    var complexityPreference: Int
    var topics: [String]
    var preferredSources: [String]
    var readingSpeedWpm: Int

    enum CodingKeys: String, CodingKey {
        case complexityPreference = "complexity_preference"
        case topics
        case preferredSources = "preferred_sources"
        case readingSpeedWpm = "reading_speed_wpm"
    }

    init(
        complexityPreference: Int = 5,
        topics: [String] = [],
        preferredSources: [String] = [],
        readingSpeedWpm: Int = 200
    ) {
        self.complexityPreference = complexityPreference
        self.topics = topics
        self.preferredSources = preferredSources
        self.readingSpeedWpm = readingSpeedWpm
    }
}

struct UserSettings: Codable {
    var notificationsEnabled: Bool
    var emailDigest: EmailDigestFrequency
    var defaultCategories: [String]
    var theme: ThemePreference

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case emailDigest = "email_digest"
        case defaultCategories = "default_categories"
        case theme
    }

    init(
        notificationsEnabled: Bool = true,
        emailDigest: EmailDigestFrequency = .weekly,
        defaultCategories: [String] = [],
        theme: ThemePreference = .system
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.emailDigest = emailDigest
        self.defaultCategories = defaultCategories
        self.theme = theme
    }
}

enum EmailDigestFrequency: String, Codable {
    case never
    case daily
    case weekly
    case monthly
}

enum ThemePreference: String, Codable {
    case light
    case dark
    case system
}

// MARK: - Preview Data

extension User {
    static var preview: User {
        User(
            id: UUID(),
            email: "user@example.com",
            fullName: "John Doe",
            avatarUrl: nil,
            subscriptionTier: .free,
            subscriptionExpiresAt: nil,
            readingProfile: ReadingProfile(),
            settings: UserSettings(),
            createdAt: Date(),
            updatedAt: Date(),
            lastActiveAt: Date()
        )
    }
}
