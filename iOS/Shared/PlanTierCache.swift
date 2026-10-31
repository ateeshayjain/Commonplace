import Foundation

/// Whether the reader was on Pro when the app last heard from the server,
/// shared with the Share Extension through the App Group. The extension uses
/// it to choose how to read screenshots: by Claude on the server (Pro) or on
/// the device (free). Only a hint: the server checks the tier on every save,
/// and a stale Pro answer is refused with pro_required, after which the
/// extension reads the screenshots on the device.
enum PlanTierCache {
    private static let key = "planIsPro"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.app.commonplace") }

    static var isPro: Bool { defaults?.bool(forKey: key) ?? false }

    static func store(isPro: Bool) {
        defaults?.set(isPro, forKey: key)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
