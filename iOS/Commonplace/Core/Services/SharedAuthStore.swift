import Foundation
import Security

/// A Supabase session. The access token lasts about an hour; the refresh token
/// trades it for a new pair, and is single-use (Supabase rotates it on every refresh).
struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// The session, stored in the App Group keychain so the app and the Share
/// Extension use one token pair. Two copies would each spend the same
/// single-use refresh token, and Supabase revokes a session whose refresh
/// token is reused. Compiled into both the app and the extension targets.
enum SharedAuthStore {
    private static let service = "app.commonplace.shared"
    private static let account = "supabase_session"

    /// The shared (App Group) item, or the app-private fallback when `shared` is false
    private static func query(shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared { query[kSecAttrAccessGroup as String] = Config.appGroupIdentifier }
        return query
    }

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        // Shared first; if the App Group keychain is unavailable (e.g. an unsigned
        // simulator build), keep the session app-private so the app still stays
        // signed in (the Share Extension then asks the user to open the app)
        for shared in [true, false] {
            var attributes = query(shared: shared)
            attributes[kSecValueData as String] = data
            // After first unlock: the app may refresh in the background, and the
            // session never migrates to another device
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == errSecSuccess { return }
            print("SharedAuthStore: save (shared: \(shared)) failed (\(status))")
        }
    }

    static func load() -> AuthSession? {
        for shared in [true, false] {
            var query = query(shared: shared)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let session = try? JSONDecoder().decode(AuthSession.self, from: data) {
                return session
            }
        }
        return nil
    }

    static func clear() {
        SecItemDelete(query(shared: true) as CFDictionary)
        SecItemDelete(query(shared: false) as CFDictionary)
    }

    /// Builds 1-13 kept only the access token (app keychain "auth_token" and
    /// shared "supabase_token"). It cannot be refreshed, so drop it.
    static func removeLegacyTokens() {
        let legacy: [(service: String, account: String, group: String?)] = [
            (Config.keychainService, "auth_token", nil),
            (service, "supabase_token", Config.appGroupIdentifier),
        ]
        for item in legacy {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: item.service,
                kSecAttrAccount as String: item.account,
            ]
            if let group = item.group { query[kSecAttrAccessGroup as String] = group }
            SecItemDelete(query as CFDictionary)
        }
    }
}

enum SessionError: LocalizedError {
    /// No session, or Supabase rejected the refresh token: the user must sign in again
    case signedOut
    /// The refresh endpoint failed for another reason (server error); the session is kept
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Your session has expired. Please sign in again."
        case .refreshFailed: return "Couldn't renew your session. Please try again."
        }
    }
}

extension Notification.Name {
    /// Posted (on the main queue) when Supabase rejects the stored session
    static let authSessionEnded = Notification.Name("authSessionEnded")
}

/// Hands out an access token with at least a minute left, refreshing it first
/// when needed. One refresh at a time per process.
actor SessionManager {
    static let shared = SessionManager()

    private var refreshing: Task<AuthSession, Error>?

    var hasSession: Bool { SharedAuthStore.load() != nil }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let session = SharedAuthStore.load() else { throw SessionError.signedOut }
        if !forceRefresh && session.expiresAt.timeIntervalSinceNow > 60 {
            return session.accessToken
        }
        if let refreshing {
            return try await refreshing.value.accessToken
        }
        let task = Task { try await Self.refresh(session) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value.accessToken
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
    }

    /// Network errors are thrown as-is and keep the session: being offline is not being signed out.
    private static func refresh(_ session: AuthSession) async throws -> AuthSession {
        var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/auth/v1/token?grant_type=refresh_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if (200...299).contains(status) {
            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
            let renewed = AuthSession(
                accessToken: tokens.access_token,
                refreshToken: tokens.refresh_token,
                expiresAt: Date().addingTimeInterval(tokens.expires_in)
            )
            SharedAuthStore.save(renewed)
            return renewed
        }

        if status == 400 || status == 401 {
            // The other process (app or Share Extension) may have spent this
            // refresh token a moment ago; its new session is already stored
            if let latest = SharedAuthStore.load(), latest.refreshToken != session.refreshToken {
                return latest
            }
            SharedAuthStore.clear()
            await MainActor.run {
                NotificationCenter.default.post(name: .authSessionEnded, object: nil)
            }
            throw SessionError.signedOut
        }

        throw SessionError.refreshFailed
    }
}
