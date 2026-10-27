import Foundation
import Security

/// The Supabase access token, stored in the App Group keychain so the Share
/// Extension can call Edge Functions as the signed-in user. Compiled into both
/// the app and the extension targets.
enum SharedAuthStore {
    private static let service = "app.commonplace.shared"
    private static let account = "supabase_token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: Config.appGroupIdentifier,
        ]
    }

    static func save(token: String) {
        guard let data = token.data(using: .utf8) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // Readable after first unlock so a share from the lock screen works
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            print("SharedAuthStore: save failed (\(status))")
        }
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
