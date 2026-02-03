import Foundation

enum Config {
    // MARK: - Supabase Configuration
    // Reads from Info.plist (via xcconfig) if available, otherwise uses defaults.
    // To use xcconfig: set Config.xcconfig as the project's base configuration in Xcode.
    static let supabaseURL: String = {
        if let value = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String, !value.isEmpty {
            return "https://\(value)"
        }
        return "https://mliivcgiyezaltfbnpzb.supabase.co"
    }()

    static let supabaseAnonKey: String = {
        if let value = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !value.isEmpty {
            return value
        }
        return "sb_publishable_YjzWV4ADSZUq8c5zb6ddMA_Ys-zxYCB"
    }()

    // MARK: - App Configuration
    static let appGroupIdentifier = "group.app.commonplace"
    static let keychainService = "app.commonplace.keychain"

    // MARK: - Feature Flags
    static let enableOfflineMode = true
    static let enableAISummaries = true

    // MARK: - API Endpoints
    static var processURLEndpoint: String {
        "\(supabaseURL)/functions/v1/process-url"
    }

    static var generatePostsEndpoint: String {
        "\(supabaseURL)/functions/v1/generate-posts"
    }
}
