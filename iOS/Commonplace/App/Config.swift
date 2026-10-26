import Foundation

enum Config {
    // MARK: - Supabase Configuration
    // Replace these with your actual Supabase project credentials
    static let supabaseURL = "https://gfnqjaombxxkiinxhahv.supabase.co"
    static let supabaseAnonKey = "sb_publishable_Ktsi2cXiPlIKronDz97NOg_Esfuctal"

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
