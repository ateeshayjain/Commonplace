import Foundation

/// The reader's plan, today's saves and this month's Pro usage, as
/// `verify-purchase` reports it. The server decides every limit
/// (supabase/functions/_shared/tiers.ts); the app only shows them.
struct PlanSummary: Codable, Equatable {
    enum Tier: String, Codable {
        case free
        case pro
    }

    struct Usage: Codable, Equatable {
        let used: Int
        /// nil = unlimited, 0 = not part of the plan
        let limit: Int?
        /// When the day's or month's allowance renews
        let resetsAt: Date

        var remaining: Int? { limit.map { max(0, $0 - used) } }
    }

    let tier: Tier
    /// End of paid access (renewal date while subscribed)
    let expiresAt: Date?
    /// Set while the free month runs
    let trialEndsAt: Date?
    let autoRenews: Bool?
    /// Saves today (free: 5 a day; Pro: unlimited)
    let saves: Usage
    /// Smart summaries this month (Pro fair use; 0 on free)
    let smartSummaries: Usage
    /// Compose runs this month (Pro only)
    let compose: Usage

    var isPro: Bool { tier == .pro }

    /// Profile's plan card, e.g. "Free: 3 of 5 saves left today"
    var planCardText: String {
        guard !isPro else { return "Sangrah Pro: unlimited saves with smart summaries" }
        guard let limit = saves.limit, let remaining = saves.remaining else { return "Free" }
        if remaining == 0 { return "Free: no saves left today" }
        return "Free: \(remaining) of \(limit) saves left today"
    }

    /// Under the plan card when today's saves or the month's summaries are used up
    func usageFootnote(calendar: Calendar = .current) -> String? {
        if !isPro, saves.remaining == 0 {
            return "You can save again from \(Self.time(saves.resetsAt, calendar: calendar)) tomorrow, or go Pro for unlimited saves."
        }
        if isPro, smartSummaries.remaining == 0 {
            return "New saves are kept and get their smart summary from \(Self.dayMonth(smartSummaries.resetsAt, calendar: calendar))."
        }
        return nil
    }

    /// Pro's fair-use row, e.g. "120 of 300 smart summaries this month"
    var smartSummariesText: String? {
        guard isPro, let limit = smartSummaries.limit else { return nil }
        return "\(smartSummaries.used) of \(limit) smart summaries this month"
    }

    var composeRemaining: Int { compose.remaining ?? 0 }

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
        formatter("d MMM", calendar: calendar).string(from: date)
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        // The formatter puts a narrow no-break space before "am"
        formatter("h:mm a", calendar: calendar).string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .lowercased()
    }

    private static func formatter(_ template: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// The demo account (no server) is Pro. Debug builds launched with
    /// `-SangrahDemoFreePlan` show it on the free plan with today's saves used
    /// up, to try the paywall and the Smart summary card without a server account.
    static func demo(now: Date = Date()) -> PlanSummary {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SangrahDemoFreePlan") {
            return PlanSummary(
                tier: .free, expiresAt: nil, trialEndsAt: nil, autoRenews: nil,
                saves: Usage(used: 5, limit: 5, resetsAt: tomorrow),
                smartSummaries: Usage(used: 0, limit: 0, resetsAt: nextMonth),
                compose: Usage(used: 0, limit: 0, resetsAt: nextMonth)
            )
        }
        #endif
        return PlanSummary(
            tier: .pro, expiresAt: nil, trialEndsAt: nil, autoRenews: nil,
            saves: Usage(used: 0, limit: nil, resetsAt: tomorrow),
            smartSummaries: Usage(used: 0, limit: 300, resetsAt: nextMonth),
            compose: Usage(used: 0, limit: 10, resetsAt: nextMonth)
        )
    }
}

/// Plain-words copy about Pro, shared by the paywall, the FAQ and the Smart
/// summary card
enum ProCopy {
    static let whyItCostsQuestion = "Why does Sangrah cost money?"
    static let whyItCosts = "Every smart summary is written by Claude, an AI from Anthropic. Sending an article to Claude's API costs real money each time, so smart summaries are part of Pro. Saving, reading and listening stay free."
    static let smartSummary = "With Pro, Claude reads each save and writes a Key Idea, a short summary, key points and quotes you can share as cards, and files it under the right category."
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
