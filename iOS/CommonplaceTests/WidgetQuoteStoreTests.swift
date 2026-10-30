import XCTest
@testable import Commonplace

/// The widget's daily pick and shuffle (Shared/WidgetQuote.swift)
final class WidgetQuoteStoreTests: XCTestCase {
    private let calendar = Calendar.current
    private var savedPool: [WidgetQuote] = []

    override func setUp() {
        super.setUp()
        savedPool = WidgetQuoteStore.loadPool()
    }

    override func tearDown() {
        WidgetQuoteStore.savePool(savedPool)
        super.tearDown()
    }

    private func pool(_ count: Int) -> [WidgetQuote] {
        (0..<count).map { n in
            let idea = n.isMultiple(of: 2)
            return WidgetQuote(
                id: (idea ? "idea:" : "bookmark:") + UUID().uuidString,
                text: "Quote \(n)", isVerbatim: !idea, isKeyIdea: idea,
                title: "Title \(n)", author: nil, source: nil, documentId: UUID()
            )
        }
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date())!
    }

    func testEmptyPoolShowsNothing() {
        WidgetQuoteStore.savePool([])
        XCTAssertNil(WidgetQuoteStore.quote())
        XCTAssertNil(WidgetQuoteStore.shuffle())
    }

    func testSameQuoteAllDay() {
        WidgetQuoteStore.savePool(pool(5))
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day(40))!
        let night = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day(40))!
        XCTAssertEqual(WidgetQuoteStore.quote(on: morning)?.id, WidgetQuoteStore.quote(on: night)?.id)
    }

    func testEveryQuoteHasATurnBeforeAnyRepeats() {
        let quotes = pool(6)
        WidgetQuoteStore.savePool(quotes)
        let shown = (100..<106).compactMap { WidgetQuoteStore.quote(on: day($0))?.id }
        XCTAssertEqual(Set(shown), Set(quotes.map(\.id)))
    }

    func testShufflePicksADifferentQuoteThatStaysForTheDay() {
        WidgetQuoteStore.savePool(pool(4))
        let now = Date()
        let before = WidgetQuoteStore.quote(on: now)
        let shuffled = WidgetQuoteStore.shuffle(now: now)
        XCTAssertNotNil(shuffled)
        XCTAssertNotEqual(shuffled?.id, before?.id)
        XCTAssertEqual(WidgetQuoteStore.quote(on: now)?.id, shuffled?.id)
    }

    func testShuffleWithOneQuoteKeepsIt() {
        let only = pool(1)
        WidgetQuoteStore.savePool(only)
        XCTAssertEqual(WidgetQuoteStore.shuffle()?.id, only[0].id)
    }

    func testChangesAtMidnight() {
        let now = Date()
        XCTAssertEqual(
            WidgetQuoteStore.nextChange(after: now),
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        )
    }
}
