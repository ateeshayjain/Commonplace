import Foundation
import AuthenticationServices
import SwiftUI
import Security

@MainActor
class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: Error?

    private let supabase = SupabaseService.shared
    private let keychain = KeychainManager.shared

    override private init() {
        super.init()
        Task {
            await checkExistingSession()
        }
    }

    // MARK: - Session Management

    func checkExistingSession() async {
        guard let token = keychain.getAuthToken() else {
            return
        }

        supabase.setAuthToken(token)

        do {
            // Verify token is still valid by fetching user
            let users: [User] = try await supabase.fetch(
                from: "users",
                limit: 1
            )

            if let user = users.first {
                currentUser = user
                isAuthenticated = true
            } else {
                // Token is invalid, clear it
                signOut()
            }
        } catch {
            // Token is invalid
            signOut()
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Email + Password Authentication

    func signUp(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let body: [String: Any] = [
            "email": email,
            "password": password
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/auth/v1/signup")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.signUpFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Check if user already exists
            if let responseString = String(data: data, encoding: .utf8),
               responseString.contains("already registered") {
                throw AuthError.userAlreadyExists
            }
            throw AuthError.signUpFailed
        }

        // Auto sign-in after signup (if email confirmation is disabled)
        let authResponse = try? JSONDecoder().decode(AuthResponse.self, from: data)
        if let authResponse = authResponse {
            await handleAuthResponse(authResponse)
        }
    }

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let body: [String: Any] = [
            "email": email,
            "password": password
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/auth/v1/token?grant_type=password")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.signInFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.invalidCredentials
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        await handleAuthResponse(authResponse)
    }

    // MARK: - Email OTP Authentication

    func sendOTP(email: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let body: [String: Any] = [
            "email": email,
            "create_user": true  // Create user if doesn't exist
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/auth/v1/otp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.otpSendFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("OTP send error: \(responseString)")
            }
            throw AuthError.otpSendFailed
        }
    }

    func verifyOTP(email: String, token: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let body: [String: Any] = [
            "email": email,
            "token": token,
            "type": "email"
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/auth/v1/verify")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.otpVerifyFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("OTP verify error: \(responseString)")
                if responseString.contains("expired") {
                    throw AuthError.otpExpired
                }
            }
            throw AuthError.invalidOTP
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        await handleAuthResponse(authResponse)
    }

    // MARK: - Demo Mode (for testing without Supabase)

    var isDemoMode: Bool {
        currentUser?.email == "demo@commonplace.app"
    }

    func signInDemo() {
        isLoading = true

        // Create a demo user for testing
        let demoUser = User(
            id: UUID(),
            email: "demo@commonplace.app",
            fullName: "Demo User",
            avatarUrl: nil,
            subscriptionTier: .pro,
            subscriptionExpiresAt: nil,
            readingProfile: ReadingProfile(),
            settings: UserSettings(),
            createdAt: Date(),
            updatedAt: Date(),
            lastActiveAt: Date()
        )

        currentUser = demoUser
        isAuthenticated = true
        keychain.setAuthToken("demo_token")
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        currentUser = nil
        isAuthenticated = false
        keychain.clearAuthToken()
        supabase.setAuthToken(nil)
    }

    // MARK: - Private Helpers

    private func handleAuthResponse(_ response: AuthResponse) async {
        keychain.setAuthToken(response.accessToken)
        supabase.setAuthToken(response.accessToken)

        // Fetch or create user profile
        do {
            let users: [User] = try await supabase.fetch(from: "users", limit: 1)

            if let user = users.first {
                currentUser = user
            } else {
                // Create new user profile
                let newUser = User(
                    id: UUID(uuidString: response.user.id) ?? UUID(),
                    email: response.user.email ?? "",
                    fullName: nil,
                    avatarUrl: nil,
                    subscriptionTier: .free,
                    subscriptionExpiresAt: nil,
                    readingProfile: ReadingProfile(),
                    settings: UserSettings(),
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastActiveAt: Date()
                )

                currentUser = try await supabase.insert(into: "users", values: newUser)
            }

            isAuthenticated = true
        } catch {
            self.error = error
        }
    }
}

// MARK: - Apple Sign In Delegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            return
        }

        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }

            do {
                // Exchange Apple token for Supabase session
                let body: [String: Any] = [
                    "provider": "apple",
                    "id_token": tokenString
                ]

                let bodyData = try JSONSerialization.data(withJSONObject: body)

                var request = URLRequest(url: URL(string: "\(Config.supabaseURL)/auth/v1/token?grant_type=id_token")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.httpBody = bodyData

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw AuthError.appleSignInFailed
                }

                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                await handleAuthResponse(authResponse)
            } catch {
                self.error = error
            }
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.error = error
        }
    }
}

// MARK: - Supporting Types

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Codable {
    let id: String
    let email: String?
}

enum AuthError: LocalizedError {
    case appleSignInFailed
    case sessionExpired
    case signUpFailed
    case signInFailed
    case invalidCredentials
    case userAlreadyExists
    case otpSendFailed
    case otpVerifyFailed
    case invalidOTP
    case otpExpired

    var errorDescription: String? {
        switch self {
        case .appleSignInFailed:
            return "Sign in with Apple failed. Please try again."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .signUpFailed:
            return "Failed to create account. Please try again."
        case .signInFailed:
            return "Failed to sign in. Please try again."
        case .invalidCredentials:
            return "Invalid email or password. Please try again."
        case .userAlreadyExists:
            return "An account with this email already exists. Please sign in instead."
        case .otpSendFailed:
            return "Failed to send verification code. Please try again."
        case .otpVerifyFailed:
            return "Failed to verify code. Please try again."
        case .invalidOTP:
            return "Invalid verification code. Please check and try again."
        case .otpExpired:
            return "Verification code has expired. Please request a new one."
        }
    }
}

// MARK: - Keychain Manager

class KeychainManager {
    static let shared = KeychainManager()

    private let service = Config.keychainService
    private let account = "auth_token"

    func setAuthToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemAdd(attributes as CFDictionary, nil)
    }

    func getAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    func clearAuthToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
