import XCTest
import StoreKit
import StoreKitTest
@testable import Commonplace

/// The "Sangrah Pro" products in iOS/Sangrah.storekit, bought through StoreKit
/// in the simulator: what the paywall shows and what verify-purchase receives
@MainActor
final class SubscriptionStoreKitTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sangrah.storekit")
        session = try SKTestSession(contentsOf: file)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session.clearTransactions()
    }

    /// Purchases need StoreKit's local (Xcode) environment. Where it isn't in
    /// effect they go to the real Sandbox, which on a simulator signed into an
    /// Apple ID waits on a sign-in alert, so these run only when asked for:
    /// set SANGRAH_STOREKIT_PURCHASE_TESTS=1 in the scheme's Test environment.
    private func requirePurchaseTests() throws {
        guard ProcessInfo.processInfo.environment["SANGRAH_STOREKIT_PURCHASE_TESTS"] == "1" else {
            throw XCTSkip("Set SANGRAH_STOREKIT_PURCHASE_TESTS=1 to run StoreKit purchases")
        }
    }

    private func products() async throws -> [String: Product] {
        let products = try await Product.products(for: SubscriptionProduct.ids)
        // StoreKit only serves a test configuration to an app installed for
        // development (signed, with get-task-allow). CI builds unsigned
        // (CODE_SIGNING_ALLOWED=NO), where these tests can't run.
        if products.isEmpty {
            throw XCTSkip("StoreKit testing needs a development-signed build; run without CODE_SIGNING_ALLOWED=NO")
        }
        return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    func testBothPlansAreInOneGroupWithAFreeMonth() async throws {
        let products = try await products()
        let monthly = try XCTUnwrap(products[SubscriptionProduct.monthly.rawValue])
        let yearly = try XCTUnwrap(products[SubscriptionProduct.yearly.rawValue])

        XCTAssertEqual(monthly.type, .autoRenewable)
        XCTAssertEqual(monthly.price, 299)
        XCTAssertEqual(yearly.price, 2499)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod, .monthly)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod, .yearly)
        XCTAssertEqual(monthly.subscription?.subscriptionGroupID, yearly.subscription?.subscriptionGroupID)

        for product in [monthly, yearly] {
            let offer = try XCTUnwrap(product.subscription?.introductoryOffer)
            XCTAssertEqual(offer.paymentMode, .freeTrial)
            XCTAssertEqual(offer.period, .monthly)
            let eligible = await product.subscription?.isEligibleForIntroOffer
            XCTAssertEqual(eligible, true)
        }
        XCTAssertEqual(SubscriptionProduct.yearlySavingsPercent(monthly: monthly.price, yearly: yearly.price), 30)
    }

    func testPurchaseStartsTheFreeMonthAndCarriesTheAccount() async throws {
        try requirePurchaseTests()
        let all = try await products()
        let monthly = try XCTUnwrap(all[SubscriptionProduct.monthly.rawValue])
        let account = UUID()

        let result = try await monthly.purchase(options: [.appAccountToken(account)])
        guard case .success(.verified(let transaction)) = result else {
            return XCTFail("Expected a verified purchase, got \(result)")
        }
        XCTAssertEqual(transaction.appAccountToken, account)
        if #available(iOS 17.2, *) {
            XCTAssertEqual(transaction.offer?.type, .introductory)
        }
        XCTAssertEqual(transaction.environment, .xcode)
        await transaction.finish()

        var entitled: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let current) = entitlement { entitled.append(current.productID) }
        }
        XCTAssertEqual(entitled, [SubscriptionProduct.monthly.rawValue])

        // A second free month isn't offered to the same Apple ID
        let eligible = await monthly.subscription?.isEligibleForIntroOffer
        XCTAssertEqual(eligible, false)
    }

    /// verify-purchase reads these JWS fields (TransactionInfo in
    /// _shared/appstore.ts) and refuses Xcode-signed purchases
    func testSignedTransactionHasTheFieldsTheServerReads() async throws {
        try requirePurchaseTests()
        let all = try await products()
        let yearly = try XCTUnwrap(all[SubscriptionProduct.yearly.rawValue])
        let account = UUID()
        guard case .success(let verification) = try await yearly.purchase(options: [.appAccountToken(account)]) else {
            return XCTFail("Purchase didn't succeed")
        }

        let parts = verification.jwsRepresentation.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(fields["productId"] as? String, "sangrah.pro.yearly")
        XCTAssertNotNil(fields["originalTransactionId"] as? String)
        XCTAssertEqual(fields["bundleId"] as? String, Bundle.main.bundleIdentifier)
        XCTAssertEqual((fields["appAccountToken"] as? String)?.lowercased(), account.uuidString.lowercased())
        XCTAssertEqual(fields["environment"] as? String, "Xcode")

        if case .verified(let transaction) = verification { await transaction.finish() }
    }
}
