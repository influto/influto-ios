import XCTest
import StoreKit
import StoreKitTest
@testable import InfluToSample
import InfluTo

/// Headless StoreKit-Testing purchase tests.
///
/// The `SKTestSession` is created IN CODE from the bundled `Products.storekit` (a
/// resource of this test target) — the reliable approach under `xcodebuild test`.
/// We drive purchases with `session.buyProduct(identifier:)` (fully programmatic)
/// rather than `product.purchase()` (whose confirmation flow can hang headlessly),
/// then read the signed transaction from `Transaction.currentEntitlements`.
@MainActor
final class PurchaseFlowTests: XCTestCase {
    private var session: SKTestSession!
    private let productID = "to.influ.sample.pro.monthly"

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The live E2E does real network round-trips to prod + polls the feedback
        // endpoint, so it can run well over the default per-test allowance.
        executionTimeAllowance = 600
        session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = true
        session.clearTransactions()
        session.resetToDefaultState()
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
        super.tearDown()
    }

    /// The most recent signed transaction's `VerificationResult` (carries the JWS).
    private func latestTransaction() async -> VerificationResult<Transaction>? {
        for await result in Transaction.currentEntitlements { return result }
        for await result in Transaction.all { return result }
        return nil
    }

    /// Layer 1 — ALWAYS runs (no secrets): a StoreKit-Testing purchase yields a signed
    /// StoreKit 2 transaction whose JWS is non-empty — the client plumbing that feeds
    /// `InfluTo.reportPurchase`.
    func testStoreKitPurchaseProducesSignedJWS() async throws {
        _ = try await Product.products(for: [productID]) // ensure the product resolves
        try await session.buyProduct(identifier: productID)

        let txn = await latestTransaction()
        let verification = try XCTUnwrap(txn, "no transaction after purchase")
        XCTAssertFalse(verification.jwsRepresentation.isEmpty, "empty signed JWS")
    }

    /// Layer 2 — E2E, runs ONLY when CI secrets are present: the StoreKit-Test JWS is
    /// POSTed to the LIVE InfluTo backend (a test app configured in XCODE mode) and a
    /// money-excluded conversion lands, attributed to the referral code.
    func testReportPurchaseLandsInInfluToE2E() async throws {
        // Values are compiled in from E2ESecrets (CI overwrites it from GitHub secrets);
        // fall back to the process env for local runs.
        let env = ProcessInfo.processInfo.environment
        func cfg(_ baked: String, _ key: String) -> String? {
            if !baked.isEmpty { return baked }
            let v = env[key]
            return (v?.isEmpty == false) ? v : nil
        }
        guard let apiKey = cfg(E2ESecrets.apiKey, "INFLUTO_TEST_API_KEY") else {
            throw XCTSkip("INFLUTO_TEST_API_KEY not set — skipping live E2E (Layer 1 still ran).")
        }
        let baseURLString = cfg(E2ESecrets.baseURL, "INFLUTO_TEST_BASE_URL") ?? "https://influ.to/api"
        let baseURL = try XCTUnwrap(URL(string: baseURLString))
        let referral = cfg(E2ESecrets.referralCode, "INFLUTO_TEST_REFERRAL_CODE")
        let pid = cfg(E2ESecrets.productID, "INFLUTO_TEST_PRODUCT_ID") ?? productID
        let appUserID = "ci-e2e-" + UUID().uuidString.prefix(12).lowercased()

        // autoCapture:false so this test drives the manual reportPurchase path deterministically
        // (the default-on observation would also report, deduped, but adds non-determinism here).
        try await InfluTo.initialize(InfluToConfig(apiKey: apiKey, debug: true, apiURL: baseURL, autoCapture: false))
        await InfluTo.identifyUser(appUserID)
        if let referral { _ = await InfluTo.applyCode(referral, appUserId: appUserID) }

        _ = try await Product.products(for: [pid])
        try await session.buyProduct(identifier: pid)
        let txn = await latestTransaction()
        let verification = try XCTUnwrap(txn, "no transaction after purchase")

        let purchaseResult = try await InfluTo.reportPurchase(
            verification: verification, appUserId: appUserID, referralCode: referral
        )
        XCTAssertTrue(purchaseResult.success, "reportPurchase success=false")
        XCTAssertEqual(purchaseResult.validated, "apple")
        // StoreKit-Test (XCODE) transactions are ALWAYS money-excluded -> SANDBOX.
        XCTAssertEqual(purchaseResult.environment, "SANDBOX")

        // Confirm it landed via the feedback endpoint, looked up by the SDK appUserId.
        // Poll briefly for consistency.
        var landed: [RecentConversions.Item] = []
        for _ in 0..<8 {
            landed = (try? await RecentConversions.fetch(
                apiURL: baseURL, apiKey: apiKey, appUserID: appUserID)) ?? []
            if !landed.isEmpty { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let latest = try XCTUnwrap(landed.first, "no conversion recorded for \(appUserID)")
        XCTAssertTrue(latest.isTest, "expected a money-excluded test conversion, got \(latest.environment)")
        if let referral {
            XCTAssertTrue(latest.attributed, "expected attribution to \(referral)")
            XCTAssertEqual(latest.referralCode, referral.uppercased())
        }
    }
}
