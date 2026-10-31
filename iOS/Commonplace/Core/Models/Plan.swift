import Foundation

/// The reader's plan and this month's AI usage, as `verify-purchase` reports it.
/// The server decides every limit (supabase/functions/_shared/tiers.ts); the
/// app only shows them.
struct PlanSummary: Codable, Equatable {
    enum Tier: String, Codable {
        case free
        case pro
    }

    struct Usage: Codable, Equatable {
        let used: Int
        /// nil = unlimited
        let limit: Int?
    }

    let tier: Tier
    /// End of paid access (renewal date while subscribed)
    let expiresAt: Date?
    /// Set while the free month runs
    let trialEndsAt: Date?
    let autoRenews: Bool?
    /// When this month's credits renew (1st of next month, UTC)
    let periodEnds: Date
    let saves: Usage
    let compose: Usage

    var isPro: Bool { tier == .pro }

    /// AI saves left this month; nil when unlimited
    var savesRemaining: Int? {
        guard let limit = saves.limit else { return nil }
        return max(0, limit - saves.used)
    }

    var composeRemaining: Int {
        max(0, (compose.limit ?? 0) - compose.used)
    }

    /// Profile's usage row
    var savesLeftText: String {
        guard let limit = saves.limit, let remaining = savesRemaining else {
            return "Unlimited AI saves"
        }
        if remaining == 0 {
            return "No AI saves left this month"
        }
        return "\(remaining) of \(limit) saves left this month"
    }

    /// Under the usage row: what happens next
    func savesFootnote(calendar: Calendar = .current) -> String? {
        guard savesRemaining == 0 else { return nil }
        return "New saves are kept and wait for a summary. More AI saves on \(Self.dayMonth(periodEnds, calendar: calendar))."
    }

    /// Profile's plan row, e.g. "Free month ends 29 Nov" or "Renews 30 Nov"
    func statusText(calendar: Calendar = .current) -> String? {
        guard isPro else { return nil }
        if let trialEndsAt {
            return autoRenews == false
                ? "Free month ends \(Self.dayMonth(trialEndsAt, calendar: calendar)); won't renew"
                : "Free month ends \(Self.dayMonth(trialEndsAt, calendar: calendar))"
        }
        guard let expiresAt else { return nil }
        return autoRenews == false
            ? "Ends \(Self.dayMonth(expiresAt, calendar: calendar))"
            : "Renews \(Self.dayMonth(expiresAt, calendar: calendar))"
    }

    static func dayMonth(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    /// The demo account (no server) is Pro. Debug builds launched with
    /// `-SangrahDemoFreePlan` show it on a used-up free plan instead, to try
    /// the paywall and waiting saves without a server account.
    static func demo(now: Date = Date()) -> PlanSummary {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SangrahDemoFreePlan") {
            return PlanSummary(
                tier: .free, expiresAt: nil, trialEndsAt: nil, autoRenews: nil,
                periodEnds: Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now,
                saves: Usage(used: 20, limit: 20),
                compose: Usage(used: 0, limit: 0)
            )
        }
        #endif
        return PlanSummary(
            tier: .pro, expiresAt: nil, trialEndsAt: nil, autoRenews: nil,
            periodEnds: Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now,
            saves: Usage(used: 0, limit: nil),
            compose: Usage(used: 0, limit: 10)
        )
    }
}

/// The "Sangrah Pro" auto-renewable subscription group in App Store Connect.
/// Product ids are kept in step with `PRO_PRODUCT_IDS` in _shared/tiers.ts and
/// with iOS/Sangrah.storekit.
enum SubscriptionProduct: String, CaseIterable {
    case yearly = "sangrah.pro.yearly"
    case monthly = "sangrah.pro.monthly"

    static var ids: [String] { allCases.map(\.rawValue) }

    var title: String {
        switch self {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        }
    }

    /// Whole percent the yearly plan saves against twelve monthly payments,
    /// rounded down (₹2,499 vs 12 × ₹299 → 30). nil when it saves nothing.
    static func yearlySavingsPercent(monthly: Decimal, yearly: Decimal) -> Int? {
        guard monthly > 0 else { return nil }
        let fraction = 1 - (yearly / (monthly * 12))
        var percent = fraction * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &percent, 0, .down)
        let value = NSDecimalNumber(decimal: rounded).intValue
        return value > 0 ? value : nil
    }
}

/// The reminder before the first charge after the free month
enum TrialReminder {
    static let daysBefore = 2
    static let identifier = "sangrah.trial-reminder"

    /// When to remind: `daysBefore` days before the trial ends, or nil when
    /// that moment has already passed
    static func date(trialEnds: Date, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let date = calendar.date(byAdding: .day, value: -daysBefore, to: trialEnds), date > now else {
            return nil
        }
        return date
    }

    static func body(trialEnds: Date, price: String, calendar: Calendar = .current) -> String {
        "Your free month of Sangrah Pro ends on \(PlanSummary.dayMonth(trialEnds, calendar: calendar)). "
            + "You'll be charged \(price) then unless you cancel in Settings > Apple ID > Subscriptions."
    }
}
