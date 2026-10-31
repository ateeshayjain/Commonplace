import Foundation
import StoreKit
import UserNotifications

/// Sangrah Pro through StoreKit 2. Purchases carry the reader's account id
/// (appAccountToken) and are confirmed by `verify-purchase`, which asks Apple
/// for the subscription's status and sets the tier on the server. The plan
/// shown in the app is always the server's answer, never StoreKit's alone.
@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    /// Yearly first, then monthly; empty until App Store Connect (or the
    /// StoreKit test file) provides them
    @Published private(set) var products: [Product] = []
    @Published private(set) var plan: PlanSummary?
    /// Whether the free month is still on offer to this Apple ID
    @Published private(set) var isTrialEligible = true
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var error: Error?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    private var isDemo: Bool {
        AuthService.shared.currentUser?.email == "demo@commonplace.app"
    }

    // MARK: - Lifecycle

    /// Called once the reader is signed in: listens for renewals and purchases
    /// finished outside the app (Ask to Buy, a purchase on another device),
    /// then brings the plan up to date
    func start() {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    await self?.handle(update)
                }
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    /// Signed out: forget the last account's plan
    func reset() {
        plan = nil
        error = nil
        PlanTierCache.clear()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: SubscriptionProduct.ids)
            products = SubscriptionProduct.allCases.compactMap { kind in loaded.first { $0.id == kind.rawValue } }
            if let subscription = products.first?.subscription {
                isTrialEligible = await subscription.isEligibleForIntroOffer
            }
        } catch {
            print("Loading subscriptions failed:", error)
        }
    }

    func product(_ kind: SubscriptionProduct) -> Product? {
        products.first { $0.id == kind.rawValue }
    }

    // MARK: - Plan

    /// Sends the current App Store entitlement (if any) to the server and
    /// shows the plan it returns. Run at launch and after Restore Purchases.
    func refresh() async {
        guard AuthService.shared.currentUser != nil else { return }
        if isDemo {
            let demo = PlanSummary.demo()
            plan = demo
            PlanTierCache.store(isPro: demo.isPro)
            AuthService.shared.currentUser?.subscriptionTier = demo.isPro ? .pro : .free
            return
        }
        guard let entitlement = await currentEntitlement() else {
            return await refreshUsage()
        }
        do {
            try await verify(entitlement)
        } catch {
            print("Refreshing the plan failed:", error)
            await refreshUsage()
        }
    }

    /// The plan and this month's usage from the server alone, without asking
    /// the App Store (after a save or a Summarise)
    func refreshUsage() async {
        guard AuthService.shared.currentUser != nil, !isDemo else { return }
        do {
            apply(try await SupabaseService.shared.invokeFunction(name: "verify-purchase"))
        } catch {
            print("Refreshing usage failed:", error)
        }
    }

    /// The newest verified Sangrah Pro transaction this Apple ID is entitled to
    private func currentEntitlement() async -> VerificationResult<Transaction>? {
        var newest: VerificationResult<Transaction>?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SubscriptionProduct.ids.contains(transaction.productID) else { continue }
            if case .verified(let current) = newest, current.purchaseDate >= transaction.purchaseDate { continue }
            newest = result
        }
        return newest
    }

    private func verify(_ result: VerificationResult<Transaction>) async throws {
        let plan: PlanSummary = try await SupabaseService.shared.invokeFunction(
            name: "verify-purchase",
            body: ["signedTransaction": result.jwsRepresentation]
        )
        apply(plan)
    }

    private func apply(_ plan: PlanSummary) {
        let wasPro = self.plan?.isPro ?? false
        self.plan = plan
        // The Share Extension reads screenshots on the device unless the reader is on Pro
        PlanTierCache.store(isPro: plan.isPro)
        // The profile badge reads the user row, which the server just changed
        AuthService.shared.currentUser?.subscriptionTier = plan.isPro ? .pro : .free
        AuthService.shared.currentUser?.subscriptionExpiresAt = plan.expiresAt
        if plan.isPro && !wasPro {
            // The newest saves made on the free plan get their smart summary now
            Task { try? await DocumentService.shared.summariseWaitingSaves() }
        }
    }

    // MARK: - Purchase

    /// Buys a plan. Returns true once the server has confirmed Pro.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard let userId = AuthService.shared.currentUser?.id else { return false }
        isPurchasing = true
        error = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase(options: [.appAccountToken(userId)]) {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    throw SubscriptionError.unverified
                }
                let confirmed = await confirm(result, transaction: transaction)
                if confirmed, let trialEnds = plan?.trialEndsAt {
                    await scheduleTrialReminder(trialEnds: trialEnds, price: product.displayPrice)
                }
                return confirmed
            case .pending:
                // Ask to Buy or a bank check: Transaction.updates delivers it later
                error = SubscriptionError.pending
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = error
            return false
        }
    }

    /// Restore Purchases: asks the App Store to sync (it may ask for the
    /// Apple ID password), then confirms whatever this Apple ID owns
    func restore() async {
        isRestoring = true
        error = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            guard let entitlement = await currentEntitlement() else {
                throw SubscriptionError.nothingToRestore
            }
            try await verify(entitlement)
        } catch {
            self.error = error
        }
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        _ = await confirm(update, transaction: transaction)
    }

    /// Confirms a transaction with the server and finishes it. A transaction
    /// that couldn't reach the server stays unfinished, so StoreKit offers it
    /// again on the next launch.
    private func confirm(_ result: VerificationResult<Transaction>, transaction: Transaction) async -> Bool {
        do {
            try await verify(result)
            await transaction.finish()
            return plan?.isPro ?? false
        } catch let failure as SupabaseError where failure.refusalCode != nil {
            // A definite answer (another account's purchase, a test-file
            // purchase): retrying won't change it
            await transaction.finish()
            error = failure
            return false
        } catch {
            self.error = SubscriptionError.notConfirmed
            return false
        }
    }

    // MARK: - Trial reminder

    /// A local notification two days before the free month turns into the
    /// first charge, on top of the dates shown in the paywall and Profile
    private func scheduleTrialReminder(trialEnds: Date, price: String) async {
        guard let fireDate = TrialReminder.date(trialEnds: trialEnds) else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your free month ends soon"
        content.body = TrialReminder.body(trialEnds: trialEnds, price: price)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: TrialReminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }
}

enum SubscriptionError: LocalizedError {
    case unverified
    case pending
    case nothingToRestore
    case notConfirmed

    var errorDescription: String? {
        switch self {
        case .unverified:
            return "The App Store couldn't verify this purchase."
        case .pending:
            return "Your purchase is waiting for approval. Pro starts as soon as it goes through."
        case .nothingToRestore:
            return "This Apple ID has no Sangrah Pro subscription to restore."
        case .notConfirmed:
            return "Your purchase went through, but we couldn't confirm it yet. Pro will switch on the next time you open Sangrah, or tap Restore Purchases."
        }
    }
}
