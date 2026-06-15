import Foundation
import InfluTo

/// Orchestrates the InfluTo SDK calls + the "did it land in InfluTo?" check.
@MainActor
final class SampleViewModel: ObservableObject {
    @Published var initialized = false
    @Published var statusLine = "Not initialized"
    @Published var attribution = "—"
    @Published var appliedCode: String?
    @Published var landedSummary = ""
    @Published var checking = false
    @Published var syncSummary = ""

    func initialize(config: SampleConfig) async {
        guard config.isConfigured else { statusLine = "Enter your InfluTo API key first"; return }
        do {
            try await InfluTo.initialize(InfluToConfig(
                apiKey: config.apiKey,
                debug: true,
                apiURL: config.apiURL,
                appVersion: "sample-1.0.0"
            ))
            initialized = true
            statusLine = "✅ Initialized as \(config.appUserID)"
            await InfluTo.identifyUser(config.appUserID)
            let attr = await InfluTo.checkAttribution()
            attribution = attr.attributed
                ? "Attributed → \(attr.referralCode ?? "?")"
                : "Organic (no attribution link)"
            appliedCode = await InfluTo.getReferralCode()
        } catch {
            initialized = false
            statusLine = "❌ Init failed: \(error.localizedDescription)"
        }
    }

    /// Confirms the purchase reached InfluTo (and whether it attributed) via the
    /// SDK-key-authed `/sdk/recent-conversions` endpoint.
    func checkLanded(config: SampleConfig) async {
        checking = true
        defer { checking = false }
        do {
            let items = try await RecentConversions.fetch(
                apiURL: config.apiURL, apiKey: config.apiKey, appUserID: config.appUserID
            )
            if items.isEmpty {
                landedSummary = "No purchase recorded yet for this user. Buy a product above, then re-check."
            } else {
                let attributed = items.filter { $0.attributed }.count
                let latest = items[0]
                landedSummary = """
                ✅ \(items.count) event(s) recorded · \(attributed) attributed.
                Latest: \(latest.eventType) · \(latest.environment) · code=\(latest.referralCode ?? "—")
                """
            }
        } catch {
            landedSummary = "Couldn't check: \(error.localizedDescription)"
        }
    }

    /// Opt-in auto-capture: back-sync existing/unfinished StoreKit 2 transactions, reporting
    /// each not-yet-sent one. `InfluTo.startPurchaseObservation()` is the live equivalent.
    func backSync() async {
        let r = await InfluTo.syncExistingPurchases()
        syncSummary = "fetched=\(r.fetched) · sent=\(r.sent) · failed=\(r.failed)"
    }
}
