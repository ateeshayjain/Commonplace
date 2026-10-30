import XCTest
@testable import Commonplace

/// What Listen reads, in which voice, and how fast (SpeechService)
final class SpeechTextTests: XCTestCase {

    // MARK: - Text

    func testReadsTitleThenAuthorThenArticle() {
        let article = DocumentService.shared.fetchDemoDocuments().first { $0.sourceType == .article }!
        let parts = SpeechService.paragraphs(for: article)
        XCTAssertEqual(parts.first, article.title)
        XCTAssertEqual(parts[1], "By John Doe.")
        XCTAssertGreaterThan(parts.count, 2)
    }

    func testLinksBulletsAndSpacingAreNotRead() {
        let body = "First paragraph with a link https://example.com/page here.\n\n• A bullet point\n• Another   one\n\n---\n\n42"
        XCTAssertEqual(SpeechService.speakableParagraphs(body), [
            "First paragraph with a link here.",
            "A bullet point Another one",
        ])
    }

    // MARK: - Voice

    private let karen = SpeechService.VoiceOption(id: "karen", name: "Karen", language: "en-AU", quality: 1)
    private let leeEnhanced = SpeechService.VoiceOption(id: "lee-e", name: "Lee", language: "en-AU", quality: 2)
    private let leePremium = SpeechService.VoiceOption(id: "lee-p", name: "Lee", language: "en-AU", quality: 3)
    private let ava = SpeechService.VoiceOption(id: "ava", name: "Ava", language: "en-US", quality: 3)
    private let daniel = SpeechService.VoiceOption(id: "daniel", name: "Daniel", language: "en-GB", quality: 1)
    private let lekha = SpeechService.VoiceOption(id: "lekha", name: "Lekha", language: "hi-IN", quality: 2)

    func testDefaultsToLeePremium() {
        let all = [karen, leeEnhanced, leePremium, ava, lekha]
        XCTAssertEqual(SpeechService.preferredVoice(language: "en", among: all, saved: nil), leePremium)
    }

    func testFallsBackToBestAustralianThenBestEnglish() {
        XCTAssertEqual(SpeechService.preferredVoice(language: "en", among: [karen, ava], saved: nil), karen)
        XCTAssertEqual(SpeechService.preferredVoice(language: "en", among: [daniel, ava], saved: nil), ava)
    }

    func testReadersPickWinsWhenItSuitsTheLanguage() {
        let all = [leePremium, ava, lekha]
        XCTAssertEqual(SpeechService.preferredVoice(language: "en", among: all, saved: "ava"), ava)
        // An English pick doesn't read a Hindi article
        XCTAssertEqual(SpeechService.preferredVoice(language: "hi", among: all, saved: "ava"), lekha)
    }

    func testHindiTextIsDetected() {
        XCTAssertEqual(SpeechService.language(ofText: "संग्रह में आपके पढ़ने के लिए सहेजे गए लेख, विचार और उद्धरण एक ही जगह रहते हैं।"), "hi")
        XCTAssertEqual(SpeechService.language(ofText: "The quiet life is the most underrated path to success."), "en")
    }

    // MARK: - Speed

    func testSpeedMapsOntoSpeechRate() {
        XCTAssertEqual(SpeechService.utteranceRate(for: 1.0), 0.5, accuracy: 0.001)
        XCTAssertEqual(SpeechService.utteranceRate(for: 0.8), 0.4, accuracy: 0.001)
        XCTAssertEqual(SpeechService.utteranceRate(for: 2.0), 1.0, accuracy: 0.001)
    }
}
