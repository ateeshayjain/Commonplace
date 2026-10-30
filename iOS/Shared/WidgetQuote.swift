import Foundation

/// One quote the home-screen widget can show: a bookmarked quote or a save's
/// Key Idea. Compiled into the app and the widget. The app writes the pool to
/// the App Group whenever bookmarks or saves change; the widget only reads it,
/// plus the day's shuffle.
struct WidgetQuote: Codable, Hashable, Identifiable {
    /// "bookmark:<saved quote id>" or "idea:<document id>"
    let id: String
    /// Ready to show: sentence-cased, no surrounding quote marks
    let text: String
    let isVerbatim: Bool
    let isKeyIdea: Bool
    let title: String
    let author: String?
    let source: String?
    let documentId: UUID
}

enum WidgetQuoteStore {
    static let appGroup = "group.app.commonplace"
    static let widgetKind = "DailyQuote"

    private static let poolKey = "widgetQuotePool"
    private static let pickKey = "widgetQuotePick"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// A shuffle made today, kept until midnight
    private struct Pick: Codable {
        let day: Int
        let quoteId: String
    }

    // MARK: - Pool

    static func loadPool() -> [WidgetQuote] {
        guard let data = defaults?.data(forKey: poolKey),
              let pool = try? JSONDecoder().decode([WidgetQuote].self, from: data) else { return [] }
        return pool
    }

    static func savePool(_ pool: [WidgetQuote]) {
        guard let data = try? JSONEncoder().encode(pool) else { return }
        defaults?.set(data, forKey: poolKey)
    }

    // MARK: - Choosing

    /// Today's quote: the one shuffled to today if there is one, otherwise the
    /// day's own. Days walk through the pool in a fixed order, so nothing
    /// repeats until every quote has had a turn.
    static func quote(on date: Date = Date()) -> WidgetQuote? {
        let pool = ordered(loadPool())
        guard !pool.isEmpty else { return nil }
        let day = dayNumber(date)
        if let pick = currentPick(), pick.day == day,
           let picked = pool.first(where: { $0.id == pick.quoteId }) {
            return picked
        }
        return pool[day % pool.count]
    }

    /// Swaps today's quote for a different one at random; it stays until midnight
    @discardableResult
    static func shuffle(now: Date = Date()) -> WidgetQuote? {
        let pool = loadPool()
        let current = quote(on: now)
        let others = pool.filter { $0.id != current?.id }
        guard let next = others.randomElement() ?? current else { return nil }
        if let data = try? JSONEncoder().encode(Pick(day: dayNumber(now), quoteId: next.id)) {
            defaults?.set(data, forKey: pickKey)
        }
        return next
    }

    /// Midnight tonight, when the daily quote changes
    static func nextChange(after date: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }

    private static func currentPick() -> Pick? {
        guard let data = defaults?.data(forKey: pickKey) else { return nil }
        return try? JSONDecoder().decode(Pick.self, from: data)
    }

    /// Sorted by the random UUID after the prefix: a stable shuffle that mixes
    /// bookmarks and Key Ideas instead of running through one kind first
    private static func ordered(_ pool: [WidgetQuote]) -> [WidgetQuote] {
        func key(_ quote: WidgetQuote) -> Substring { quote.id.split(separator: ":").last ?? Substring(quote.id) }
        return pool.sorted { key($0) < key($1) }
    }

    /// Days since 2001 in the local calendar
    private static func dayNumber(_ date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
    }
}
