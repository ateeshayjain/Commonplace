import XCTest
@testable import Commonplace

/// The plan as verify-purchase reports it, and what Profile, the paywall and
/// the trial reminder make of it
final class PlanTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func plan(
        tier: PlanSummary.Tier = .free,
        savesToday: Int = 0,
        smartUsed: Int = 0,
        trialEndsAt: Date? = nil,
        expiresAt: Date? = nil,
        autoRenews: Bool? = nil
    ) -> PlanSummary {
        let isPro = tier == .pro
        return PlanSummary(
            tier: tier, expiresAt: expiresAt, trialEndsAt: trialEndsAt, autoRenews: autoRenews,
            saves: .init(used: savesToday, limit: isPro ? nil : 5, resetsAt: date("2026-10-31T00:00:00Z")),
            smartSummaries: .init(used: smartUsed, limit: isPro ? 300 : 0, resetsAt: date("2026-11-01T00:00:00Z")),
            compose: .init(used: 3, limit: isPro ? 10 : 0, resetsAt: date("2026-11-01T00:00:00Z"))
        )
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: - Decoding

    func testDecodesAProPlanWithFractionalSeconds() throws {
        let json = """
        {"tier":"pro","expiresAt":"2026-11-29T10:15:00.000Z","trialEndsAt":"2026-11-29T10:15:00.000Z","autoRenews":true,
         "saves":{"used":12,"limit":null,"resetsAt":"2026-10-31T00:00:00.000Z"},
         "smartSummaries":{"used":42,"limit":300,"resetsAt":"2026-11-01T00:00:00.000Z"},
         "compose":{"used":2,"limit":10,"resetsAt":"2026-11-01T00:00:00.000Z"}}
        """
        let plan = try SupabaseService.flexibleDateDecoder().decode(PlanSummary.self, from: Data(json.utf8))
        XCTAssertTrue(plan.isPro)
        XCTAssertEqual(plan.trialEndsAt, date("2026-11-29T10:15:00Z"))
        XCTAssertNil(plan.saves.remaining)
        XCTAssertEqual(plan.smartSummaries.remaining, 258)
        XCTAssertEqual(plan.composeRemaining, 8)
    }

    func testDecodesAFreePlanWithNulls() throws {
        let json = """
        {"tier":"free","expiresAt":null,"trialEndsAt":null,"autoRenews":null,
         "saves":{"used":2,"limit":5,"resetsAt":"2026-10-31T00:00:00.000Z"},
         "smartSummaries":{"used":0,"limit":0,"resetsAt":"2026-11-01T00:00:00.000Z"},
         "compose":{"used":0,"limit":0,"resetsAt":"2026-11-01T00:00:00.000Z"}}
        """
        let plan = try SupabaseService.flexibleDateDecoder().decode(PlanSummary.self, from: Data(json.utf8))
        XCTAssertFalse(plan.isPro)
        XCTAssertEqual(plan.saves.remaining, 3)
        XCTAssertEqual(plan.composeRemaining, 0)
    }

    // MARK: - Plan card

    func testFreePlanCardCountsTodaysSaves() {
        XCTAssertEqual(plan(savesToday: 2).planCardText, "Free: 3 of 5 saves left today")
        XCTAssertEqual(plan(savesToday: 4).planCardText, "Free: 1 of 5 saves left today")
        XCTAssertEqual(plan(savesToday: 5).planCardText, "Free: no saves left today")
        // A save that raced the limit never shows a negative count
        XCTAssertEqual(plan(savesToday: 7).saves.remaining, 0)
        XCTAssertEqual(plan(tier: .pro).planCardText, "Sangrah Pro: unlimited saves with smart summaries")
    }

    func testFootnoteWhenTheDayOrMonthIsUsedUp() {
        XCTAssertNil(plan(savesToday: 3).usageFootnote(calendar: utc))
        XCTAssertEqual(
            plan(savesToday: 5).usageFootnote(calendar: utc),
            "You can save again from 12:00 am tomorrow, or go Pro for unlimited saves."
        )
        XCTAssertNil(plan(tier: .pro, smartUsed: 120).usageFootnote(calendar: utc))
        XCTAssertEqual(
            plan(tier: .pro, smartUsed: 300).usageFootnote(calendar: utc),
            "New saves are kept and get their smart summary from 1 Nov."
        )
    }

    func testProShowsTheMonthsSmartSummaries() {
        XCTAssertEqual(plan(tier: .pro, smartUsed: 120).smartSummariesText, "120 of 300 smart summaries this month")
        XCTAssertNil(plan().smartSummariesText)
    }

    func testWhyItCostsNamesClaudeAndWhatStaysFree() {
        XCTAssertEqual(ProCopy.whyItCostsQuestion, "Why does Sangrah cost money?")
        XCTAssertTrue(ProCopy.whyItCosts.contains("Claude, an AI from Anthropic"))
        XCTAssertTrue(ProCopy.whyItCosts.contains("Saving, reading and listening stay free"))
    }

    // MARK: - Plan status

    func testStatusText() {
        let end = date("2026-11-29T10:00:00Z")
        XCTAssertNil(plan().statusText(calendar: utc))
        XCTAssertEqual(plan(tier: .pro, trialEndsAt: end, expiresAt: end, autoRenews: true).statusText(calendar: utc),
                       "Free month ends 29 Nov")
        XCTAssertEqual(plan(tier: .pro, trialEndsAt: end, expiresAt: end, autoRenews: false).statusText(calendar: utc),
                       "Free month ends 29 Nov; won't renew")
        XCTAssertEqual(plan(tier: .pro, expiresAt: end, autoRenews: true).statusText(calendar: utc), "Renews 29 Nov")
        XCTAssertEqual(plan(tier: .pro, expiresAt: end, autoRenews: false).statusText(calendar: utc), "Ends 29 Nov")
    }

    // MARK: - Products

    func testProductIdsMatchTheServer() {
        // PRO_PRODUCT_IDS in supabase/functions/_shared/tiers.ts
        XCTAssertEqual(Set(SubscriptionProduct.ids), ["sangrah.pro.monthly", "sangrah.pro.yearly"])
        XCTAssertEqual(SubscriptionProduct.allCases.first, .yearly)
    }

    func testYearlySavings() {
        // India: ₹2,499 a year against 12 × ₹299
        XCTAssertEqual(SubscriptionProduct.yearlySavingsPercent(monthly: 299, yearly: 2499), 30)
        // US: $49.99 against 12 × $5.99
        XCTAssertEqual(SubscriptionProduct.yearlySavingsPercent(monthly: Decimal(string: "5.99")!, yearly: Decimal(string: "49.99")!), 30)
        XCTAssertNil(SubscriptionProduct.yearlySavingsPercent(monthly: 100, yearly: 1200))
        XCTAssertNil(SubscriptionProduct.yearlySavingsPercent(monthly: 0, yearly: 10))
    }

    // MARK: - Trial reminder

    func testTrialReminderTwoDaysBeforeTheFirstCharge() {
        let now = date("2026-10-30T09:00:00Z")
        let trialEnds = date("2026-11-29T09:00:00Z")
        XCTAssertEqual(TrialReminder.date(trialEnds: trialEnds, now: now, calendar: utc), date("2026-11-27T09:00:00Z"))
    }

    func testNoTrialReminderWhenItWouldBeInThePast() {
        let now = date("2026-11-28T09:00:00Z")
        XCTAssertNil(TrialReminder.date(trialEnds: date("2026-11-29T09:00:00Z"), now: now, calendar: utc))
    }

    func testTrialReminderNamesTheDateAndPrice() {
        XCTAssertEqual(
            TrialReminder.body(trialEnds: date("2026-11-29T09:00:00Z"), price: "₹299.00", calendar: utc),
            "Your free month of Sangrah Pro ends on 29 Nov. You'll be charged ₹299.00 then unless you cancel in Settings > Apple ID > Subscriptions."
        )
    }

    // MARK: - Waiting saves

    func testWaitingForSummary() {
        var document = Document.preview
        XCTAssertFalse(document.isWaitingForSummary)
        document.aiWaiting = true
        XCTAssertTrue(document.isWaitingForSummary)
        document.aiWaiting = false
        XCTAssertFalse(document.isWaitingForSummary)
    }

    func testRefusalCodeFromFunctionErrors() {
        XCTAssertEqual(SupabaseError.rejected(code: "daily_limit_reached", message: "x").refusalCode, "daily_limit_reached")
        XCTAssertEqual(SupabaseError.rejected(code: "pro_required", message: "Compose is part of Sangrah Pro.").errorDescription,
                       "Compose is part of Sangrah Pro.")
        XCTAssertNil(SupabaseError.requestFailed.refusalCode)
    }
}
