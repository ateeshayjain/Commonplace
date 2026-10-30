import XCTest
@testable import Commonplace

/// Contact Support's email links
final class SupportContactTests: XCTestCase {
    func testMailLinkHasAddressSubjectAndVersion() throws {
        let url = try XCTUnwrap(SupportContact.mailURL)
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, SupportContact.email)
        XCTAssertEqual(components.queryItems?.first { $0.name == "subject" }?.value, "Sangrah support")
        XCTAssertTrue(components.queryItems?.first { $0.name == "body" }?.value?.contains(SupportContact.appVersion) == true)
    }

    func testGmailLinkKeepsTheBodyInOneParameter() throws {
        let url = try XCTUnwrap(SupportContact.gmailURL)
        XCTAssertEqual(url.scheme, "googlegmail")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.map(\.name), ["to", "subject", "body"])
    }

    func testVersionNamesSangrah() {
        XCTAssertTrue(SupportContact.appVersion.hasPrefix("Sangrah "))
    }
}
