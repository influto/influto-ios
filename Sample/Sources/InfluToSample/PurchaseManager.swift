import Foundation
import StoreKit
import InfluTo

/// Minimal StoreKit 2 purchase manager — the best-practice reference an integrator
/// can copy. It buys a product, hands the StoreKit 2 verification straight to
/// `InfluTo.reportPurchase(verification:)` (which extracts the signed JWS), then
/// finishes the transaction. A `Transaction.updates` listener forwards renewals /
/// out-of-band purchases too. App deployment target is iOS 16, so no availability
/// gymnastics are needed.
@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published private(set) var lastResult: String = ""
    @Published private(set) var lastPurchaseResult: PurchaseResult?
    @Published private(set) var isWorking = false

    private var updatesTask: Task<Void, Never>?

    /// Start the lifetime transaction listener (call once, e.g. after init).
    func startListening(appUserID: @escaping @Sendable () -> String) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let txn) = update else { continue }
                // Forward renewals / purchases made on other devices. The backend
                // dedups on the transaction id, so a double-report is a no-op.
                _ = try? await InfluTo.reportPurchase(verification: update, appUserId: appUserID())
                await self?.markPurchased(txn.productID)
                await txn.finish()
            }
        }
    }

    func loadProducts(ids: [String]) async {
        do {
            products = try await Product.products(for: ids)
            if products.isEmpty { lastResult = "No products found for the given id(s)." }
        } catch {
            lastResult = "Failed to load products: \(error.localizedDescription)"
        }
    }

    /// Buy → capture the StoreKit 2 verification → `InfluTo.reportPurchase` → finish.
    @discardableResult
    func purchase(_ product: Product, appUserID: String, referralCode: String?) async -> PurchaseResult? {
        isWorking = true
        defer { isWorking = false }
        do {
            // Bind the purchase to the user (stable across renewals) — store-signed.
            let token = InfluTo.appAccountToken(forUserID: appUserID)
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                // Hand the signed transaction to InfluTo (it reads jwsRepresentation).
                let purchaseResult = try await InfluTo.reportPurchase(
                    verification: verification, appUserId: appUserID, referralCode: referralCode
                )
                lastPurchaseResult = purchaseResult
                if case .verified(let txn) = verification {
                    purchasedProductIDs.insert(txn.productID)
                    await txn.finish()   // deliver content / report BEFORE finishing
                }
                lastResult = purchaseResult.success
                    ? "✅ reported · validated=\(purchaseResult.validated ?? "-") env=\(purchaseResult.environment ?? "-")"
                    : "⚠️ reportPurchase returned success=false"
                return purchaseResult
            case .pending:
                lastResult = "⏳ Purchase pending (Ask to Buy / SCA). It'll arrive on the listener."
                return nil
            case .userCancelled:
                lastResult = "Cancelled."
                return nil
            @unknown default:
                lastResult = "Unknown purchase result."
                return nil
            }
        } catch {
            lastResult = "❌ \(error.localizedDescription)"
            return nil
        }
    }

    private func markPurchased(_ productID: String) {
        purchasedProductIDs.insert(productID)
    }

    deinit { updatesTask?.cancel() }
}
