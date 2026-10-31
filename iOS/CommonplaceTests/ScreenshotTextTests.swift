import XCTest
@testable import Commonplace

/// Screenshots read on the device (free accounts) joined into one article
final class ScreenshotTextTests: XCTestCase {
    /// Lines laid out like a screenshot: each 0.02 tall, 0.005 apart, with a
    /// bigger gap wherever a line starts with "¶" (a new paragraph)
    private func page(_ texts: [String], startingAt start: Double = 0.1) -> [OCRLine] {
        var top = start
        return texts.map { raw in
            let newParagraph = raw.hasPrefix("¶")
            if newParagraph { top += 0.03 }
            let line = OCRLine(text: newParagraph ? String(raw.dropFirst()) : raw, top: top, bottom: top + 0.02)
            top += 0.025
            return line
        }
    }

    // MARK: - Chrome

    func testDropsStatusBarAndTabBar() {
        let lines = [
            OCRLine(text: "9:41", top: 0.01, bottom: 0.03),
            OCRLine(text: "87%", top: 0.01, bottom: 0.03),
            OCRLine(text: "The opening line of the article", top: 0.12, bottom: 0.14),
            OCRLine(text: "Home  Search  Profile", top: 0.96, bottom: 0.98),
        ]
        XCTAssertEqual(ScreenshotText.lines(from: lines).map(\.text), ["The opening line of the article"])
    }

    func testKeepsLongTextNearTheTopOfACroppedScreenshot() {
        let line = OCRLine(text: "A cropped screenshot can start with real text at the very top", top: 0.01, bottom: 0.03)
        XCTAssertFalse(ScreenshotText.isChrome(line))
        XCTAssertTrue(ScreenshotText.isChrome(OCRLine(text: "10:05 PM", top: 0.5, bottom: 0.52)))
        XCTAssertTrue(ScreenshotText.isChrome(OCRLine(text: "x", top: 0.5, bottom: 0.52)))
    }

    // MARK: - Paragraphs

    func testWrappedLinesJoinAndGapsStartParagraphs() {
        let article = ScreenshotText.article(from: [page([
            "Why we read slowly",
            "¶Reading slowly lets an idea settle before",
            "the next one arrives.",
            "¶Speed reading promises more pages but",
            "less memory.",
        ])])
        XCTAssertEqual(article.title, "Why we read slowly")
        XCTAssertEqual(article.body, """
        Why we read slowly

        Reading slowly lets an idea settle before the next one arrives.

        Speed reading promises more pages but less memory.
        """)
    }

    func testRejoinsAWordHyphenatedAcrossLines() {
        let paragraphs = ScreenshotText.paragraphs(from: [
            .init(text: "a long and care-", startsParagraph: nil),
            .init(text: "ful argument", startsParagraph: false),
        ])
        XCTAssertEqual(paragraphs, ["a long and careful argument"])
    }

    // MARK: - Overlap

    func testOverlappingLinesAreWrittenOnce() {
        let first = page([
            "Title of the piece",
            "¶First paragraph line one of the article",
            "first paragraph line two of the article",
            "¶Second paragraph begins here and runs on",
        ])
        let second = page([
            "first paragraph line two of the article",
            "¶Second paragraph begins here and runs on",
            "to a second line on the next screenshot.",
            "¶Third paragraph, only on the second one.",
        ])
        let article = ScreenshotText.article(from: [first, second])
        XCTAssertEqual(article.body, """
        Title of the piece

        First paragraph line one of the article first paragraph line two of the article

        Second paragraph begins here and runs on to a second line on the next screenshot.

        Third paragraph, only on the second one.
        """)
    }

    func testOverlapIgnoresOCRPunctuationAndCaseDifferences() {
        let earlier: [ScreenshotText.Line] = [
            .init(text: "Something before", startsParagraph: nil),
            .init(text: "The shared line, read once.", startsParagraph: false),
            .init(text: "And another shared line here", startsParagraph: false),
        ]
        let next: [ScreenshotText.Line] = [
            .init(text: "the shared line read once", startsParagraph: nil),
            .init(text: "And another shared line here.", startsParagraph: false),
            .init(text: "New text", startsParagraph: false),
        ]
        XCTAssertEqual(ScreenshotText.overlap(earlier, next), .init(dropLast: 0, dropFirst: 2))
    }

    func testCutOffLinesAtTheEdgesAreDropped() {
        // The bottom of the first screenshot cuts a line in half, and so does the top of the second
        let earlier: [ScreenshotText.Line] = [
            .init(text: "Line one of the overlap region", startsParagraph: nil),
            .init(text: "Line two of the overlap region", startsParagraph: false),
            .init(text: "Lne thr", startsParagraph: false),
        ]
        let next: [ScreenshotText.Line] = [
            .init(text: "ne tw f th ovrlap", startsParagraph: nil),
            .init(text: "Line one of the overlap region", startsParagraph: false),
            .init(text: "Line two of the overlap region", startsParagraph: false),
            .init(text: "Line three, whole this time", startsParagraph: false),
        ]
        let shared = ScreenshotText.overlap(earlier, next)
        XCTAssertEqual(shared, .init(dropLast: 1, dropFirst: 3))
        XCTAssertEqual(ScreenshotText.merge([earlier, next]).map(\.text), [
            "Line one of the overlap region",
            "Line two of the overlap region",
            "Line three, whole this time",
        ])
    }

    func testOneShortRepeatedLineIsNotAnOverlap() {
        // "Reply" at the end of one and the start of the next is a coincidence, not an overlap
        let earlier: [ScreenshotText.Line] = [.init(text: "Some text", startsParagraph: nil), .init(text: "Reply", startsParagraph: false)]
        let next: [ScreenshotText.Line] = [.init(text: "Reply", startsParagraph: nil), .init(text: "More", startsParagraph: false)]
        XCTAssertEqual(ScreenshotText.overlap(earlier, next), .init())
    }

    func testWithoutOverlapASentenceCarriesOnAcrossScreenshots() {
        let merged = ScreenshotText.merge([
            [.init(text: "The sentence keeps going and", startsParagraph: nil)],
            [.init(text: "ends on the next screenshot.", startsParagraph: nil),
             .init(text: "A new paragraph.", startsParagraph: true)],
        ])
        XCTAssertEqual(ScreenshotText.paragraphs(from: merged), [
            "The sentence keeps going and ends on the next screenshot.",
            "A new paragraph.",
        ])
        XCTAssertFalse(ScreenshotText.continues("It ended.", with: "next"))
        XCTAssertFalse(ScreenshotText.continues("No full stop", with: "Capitalised"))
        XCTAssertTrue(ScreenshotText.continues("hyphen-", with: "Ated"))
    }

    func testTheSameScreenshotTwiceAddsNothing() {
        let shot = page(["A headline", "¶Body text that is long enough to count"])
        XCTAssertEqual(ScreenshotText.article(from: [shot, shot]), ScreenshotText.article(from: [shot]))
    }

    // MARK: - Title

    func testTitleFallsBackWhenTheFirstParagraphIsBodyText() {
        let long = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(ScreenshotText.article(from: [page([long])]).title, ScreenshotText.defaultTitle)
        XCTAssertEqual(ScreenshotText.article(from: []), .init(title: ScreenshotText.defaultTitle, body: ""))
    }

    func testDevanagariKeepsItsMarksWhenComparing() {
        XCTAssertEqual(ScreenshotText.key("संग्रह, ज्ञान!"), "संग्रहज्ञान")
        XCTAssertNotEqual(ScreenshotText.key("कि"), ScreenshotText.key("क"))
    }
}
