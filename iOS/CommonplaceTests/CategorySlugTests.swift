import XCTest
@testable import Commonplace

/// Category names that differ only in case, spacing or punctuation are one category
final class CategorySlugTests: XCTestCase {
    func testLowercasesAndJoinsWords() {
        XCTAssertEqual(CategoryService.slug(for: "Design Trends"), "design-trends")
        XCTAssertEqual(CategoryService.slug(for: "  Design   trends! "), "design-trends")
    }

    func testDropsPunctuationOnlyNames() {
        XCTAssertEqual(CategoryService.slug(for: "!!!"), "")
    }

    func testKeepsDevanagariIntact() {
        // Viramas and vowel signs are marks, not punctuation
        XCTAssertEqual(CategoryService.slug(for: "संग्रह"), "संग्रह")
    }
}
