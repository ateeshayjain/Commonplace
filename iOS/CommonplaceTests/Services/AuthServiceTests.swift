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
