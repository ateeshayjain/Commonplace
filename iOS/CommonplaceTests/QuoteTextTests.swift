import XCTest
@testable import Commonplace

/// How quotes read on cards, in captions and in credits
final class QuoteTextTests: XCTestCase {

    // MARK: - Sentence case

    func testCapitalisesTheStartAndAfterSentenceEnds() {
        XCTAssertEqual(ShareableQuote.sentenceCased("the cat sat. it was happy."), "The cat sat. It was happy.")
        XCTAssertEqual(ShareableQuote.sentenceCased("why? because! fine."), "Why? Because! Fine.")
    }

    func testLeavesAbbreviationsAndDecimalsAlone() {
        XCTAssertEqual(ShareableQuote.sentenceCased("use tools, e.g. hammers."), "Use tools, e.g. hammers.")
        XCTAssertEqual(ShareableQuote.sentenceCased("pi is 3.14 today"), "Pi is 3.14 today")
    }

    func testCapitalisesAStandaloneI() {
        XCTAssertEqual(ShareableQuote.sentenceCased("i think i'm right, and i know it"), "I think I'm right, and I know it")
        XCTAssertEqual(ShareableQuote.sentenceCased("skiing is fun"), "Skiing is fun")
    }

    func testKeepsTheAuthorsCapitals() {
        XCTAssertEqual(ShareableQuote.sentenceCased("Ship it on iOS"), "Ship it on iOS")
    }

    // MARK: - Credits and captions

    private var article: Document {
        DocumentService.shared.fetchDemoDocuments().first { $0.sourceType == .article }!
    }

    func testCreditUsesTitleAuthorAndSiteForArticles() {
        let credit = ShareableQuote.credit(for: article)
        XCTAssertEqual(credit.title, article.title)
        XCTAssertEqual(credit.author, "John Doe")
        XCTAssertEqual(credit.source, "example.com")
    }

    func testCreditNamesThePlatformForPosts() {
        let post = DocumentService.shared.fetchDemoDocuments().first { $0.sourceType == .youtube }!
        XCTAssertEqual(ShareableQuote.credit(for: post).source, SourceType.youtube.displayName)
    }

    func testCaptionCarriesQuoteCreditAndLink() {
        let quote = ShareableQuote(text: "the future belongs to builders.", isVerbatim: true)
        let lines = quote.caption(for: article).components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "\u{201C}The future belongs to builders.\u{201D}")
        XCTAssertTrue(lines.contains("\u{2014} \(article.title)"))
        XCTAssertTrue(lines.contains("By John Doe"))
        XCTAssertTrue(lines.contains("On example.com"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("Read it: ") })
        XCTAssertEqual(lines.last, "Saved with Sangrah")
    }

    func testKeyIdeaCaptionSaysFrom() {
        let idea = ShareableQuote(text: "presence is rebellion", isVerbatim: false)
        let caption = idea.caption(for: article)
        XCTAssertTrue(caption.hasPrefix("Presence is rebellion\n"))
        XCTAssertTrue(caption.contains("From \(article.title)"))
    }
}
