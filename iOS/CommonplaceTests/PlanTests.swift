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
        used: Int = 0,
        limit: Int? = 20,
        trialEndsAt: Date? = nil,
        expiresAt: Date? = nil,
        autoRenews: Bool? = nil
    ) -> PlanSummary {
        PlanSummary(
            tier: tier, expiresAt: expiresAt, trialEndsAt: trialEndsAt, autoRenews: autoRenews,
            periodEnds: date("2026-11-01T00:00:00Z"),
            saves: .init(used: used, limit: limit),
            compose: .init(used: 3, limit: tier == .pro ? 10 : 0)
        )
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // MARK: - Decoding

    func testDecodesVerifyPurchaseResponseWithFractionalSeconds() throws {
        let json = """
        {"tier":"pro","expiresAt":"2026-11-29T10:15:00.000Z","trialEndsAt":"2026-11-29T10:15:00.000Z",
         "autoRenews":true,"periodEnds":"2026-11-01T00:00:00.000Z",
         "saves":{"used":42,"limit":null},"compose":{"used":2,"limit":10}}
        """
        let plan = try SupabaseService.flexibleDateDecoder().decode(PlanSummary.self, from: Data(json.utf8))
        XCTAssertTrue(plan.isPro)
        XCTAssertEqual(plan.trialEndsAt, date("2026-11-29T10:15:00Z"))
        XCTAssertNil(plan.saves.limit)
        XCTAssertNil(plan.savesRemaining)
        XCTAssertEqual(plan.composeRemaining, 8)
    }

    func testDecodesFreePlanWithNulls() throws {
        let json = """
        {"tier":"free","expiresAt":null,"trialEndsAt":null,"autoRenews":null,"periodEnds":"2026-11-01T00:00:00.000Z",
         "saves":{"used":3,"limit":20},"compose":{"used":0,"limit":0}}
        """
        let plan = try SupabaseService.flexibleDateDecoder().decode(PlanSummary.self, from: Data(json.utf8))
        XCTAssertFalse(plan.isPro)
        XCTAssertEqual(plan.savesRemaining, 17)
        XCTAssertEqual(plan.composeRemaining, 0)
    }

    // MARK: - Save counter

    func testSavesLeftText() {
        XCTAssertEqual(plan(used: 3).savesLeftText, "17 of 20 saves left this month")
        XCTAssertEqual(plan(used: 19).savesLeftText, "1 of 20 saves left this month")
        XCTAssertEqual(plan(used: 20).savesLeftText, "No AI saves left this month")
        XCTAssertEqual(plan(tier: .pro, used: 400, limit: nil).savesLeftText, "Unlimited AI saves")
    }

    func testRemainingNeverGoesNegative() {
        // A save that raced the limit, or a limit lowered mid-month
        XCTAssertEqual(plan(used: 23).savesRemaining, 0)
    }

    func testFootnoteOnlyWhenOutOfSaves() {
        XCTAssertNil(plan(used: 5).savesFootnote(calendar: utc))
        XCTAssertEqual(
            plan(used: 20).savesFootnote(calendar: utc),
            "New saves are kept and wait for a summary. More AI saves on 1 Nov."
        )
    }

    // MARK: - Plan status

    func testStatusText() {
        let end = date("2026-11-29T10:00:00Z")
        XCTAssertNil(plan().statusText(calendar: utc))
        XCTAssertEqual(plan(tier: .pro, limit: nil, trialEndsAt: end, expiresAt: end, autoRenews: true).statusText(calendar: utc),
                       "Free month ends 29 Nov")
        XCTAssertEqual(plan(tier: .pro, limit: nil, trialEndsAt: end, expiresAt: end, autoRenews: false).statusText(calendar: utc),
                       "Free month ends 29 Nov; won't renew")
        XCTAssertEqual(plan(tier: .pro, limit: nil, expiresAt: end, autoRenews: true).statusText(calendar: utc), "Renews 29 Nov")
        XCTAssertEqual(plan(tier: .pro, limit: nil, expiresAt: end, autoRenews: false).statusText(calendar: utc), "Ends 29 Nov")
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
        XCTAssertEqual(SupabaseError.rejected(code: "monthly_limit_reached", message: "x").refusalCode, "monthly_limit_reached")
        XCTAssertEqual(SupabaseError.rejected(code: "pro_required", message: "Compose is part of Sangrah Pro.").errorDescription,
                       "Compose is part of Sangrah Pro.")
        XCTAssertNil(SupabaseError.requestFailed.refusalCode)
    }
}
