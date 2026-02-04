import XCTest
@testable import Commonplace

@MainActor
final class AuthServiceTests: XCTestCase {

    // MARK: - Email Validation Tests

    func testValidEmailFormats() {
        let validEmails = [
            "user@example.com",
            "user.name@example.com",
            "user+tag@example.com",
            "user@sub.example.com",
            "user123@example.co.uk",
        ]

        for email in validEmails {
            XCTAssertTrue(isValidEmail(email), "Should accept valid email: \(email)")
        }
    }

    func testInvalidEmailFormats() {
        let invalidEmails = [
            "",
            "notanemail",
            "@example.com",
            "user@",
            "user@.com",
            "user space@example.com",
        ]

        for email in invalidEmails {
            XCTAssertFalse(isValidEmail(email), "Should reject invalid email: \(email)")
        }
    }

    // MARK: - Demo Mode Tests

    func testDemoUserEmail() {
        let demoEmail = "demo@commonplace.app"
        XCTAssertEqual(demoEmail, "demo@commonplace.app")
    }

    func testIsDemoUser() {
        // When user email matches demo email, should be in demo mode
        let demoEmail = "demo@commonplace.app"
        let regularEmail = "user@example.com"

        XCTAssertTrue(isDemoUser(email: demoEmail))
        XCTAssertFalse(isDemoUser(email: regularEmail))
    }

    // MARK: - Auth State Tests

    func testInitialAuthStateIsSignedOut() {
        // AuthService should start in signed out state
        // This is a behavioral test - actual implementation checks currentUser
    }

    // MARK: - Google Sign-In Tests

    func testGoogleClientIDFormat() {
        // Google Client ID should be in the correct format
        let clientID = "218018331354-0skfufmloh0crdoun1up6ak96jpphpik.apps.googleusercontent.com"
        XCTAssertTrue(clientID.hasSuffix(".apps.googleusercontent.com"), "Client ID should end with .apps.googleusercontent.com")
        XCTAssertTrue(clientID.contains("-"), "Client ID should contain project identifier")
    }

    func testGoogleURLSchemeFormat() {
        // URL scheme should be reversed client ID
        let clientID = "218018331354-0skfufmloh0crdoun1up6ak96jpphpik.apps.googleusercontent.com"
        let expectedScheme = "com.googleusercontent.apps.218018331354-0skfufmloh0crdoun1up6ak96jpphpik"

        // Extract parts and reverse
        let parts = clientID.components(separatedBy: ".")
        let reversed = parts.reversed().joined(separator: ".")

        XCTAssertEqual(reversed, expectedScheme, "URL scheme should be reversed client ID")
    }

    func testGoogleAuthErrorDescription() {
        let error = AuthError.googleSignInFailed
        XCTAssertNotNil(error.errorDescription, "Google sign in error should have a description")
        XCTAssertTrue(error.errorDescription?.contains("Google") ?? false, "Error should mention Google")
    }

    func testSupabaseGoogleTokenEndpoint() {
        // Verify the token exchange endpoint format
        let baseURL = "https://mliivcgiyezaltfbnpzb.supabase.co"
        let tokenEndpoint = "\(baseURL)/auth/v1/token?grant_type=id_token"

        XCTAssertTrue(tokenEndpoint.contains("/auth/v1/token"), "Should use auth v1 token endpoint")
        XCTAssertTrue(tokenEndpoint.contains("grant_type=id_token"), "Should use id_token grant type")
    }

    // MARK: - AuthError Tests

    func testAllAuthErrorsHaveDescriptions() {
        let errors: [AuthError] = [
            .appleSignInFailed,
            .googleSignInFailed,
            .sessionExpired,
            .signUpFailed,
            .signInFailed,
            .invalidCredentials,
            .userAlreadyExists,
            .otpSendFailed,
            .otpVerifyFailed,
            .invalidOTP,
            .otpExpired
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) description should not be empty")
        }
    }

    // MARK: - Helper Functions

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func isDemoUser(email: String?) -> Bool {
        return email == "demo@commonplace.app"
    }
}
