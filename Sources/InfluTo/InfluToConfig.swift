import Foundation

/// Configuration for `InfluTo.initialize`.
public struct InfluToConfig: Sendable {
    /// Your InfluTo API key (from the dashboard).
    public let apiKey: String

    /// Enable debug logging.
    public var debug: Bool

    /// Base API URL. Defaults to `https://influ.to/api` (override for testing).
    public var apiURL: URL

    /// Your app's version string, reported on `/sdk/init` for telemetry.
    public var appVersion: String?

    /// Automatically capture + report StoreKit 2 purchases (store-direct apps only).
    /// Default `true`. When on, `initialize` starts observing `Transaction.updates` and
    /// back-syncs existing purchases — no manual `reportPurchase` needed. It activates only
    /// when the backend reports the app is store-direct (RevenueCat apps are unaffected).
    /// Set `false` to manage purchase reporting yourself.
    public var autoCapture: Bool

    /// OPTIONAL. If the host uses RevenueCat, wire this to
    /// `{ attrs in Purchases.shared.attribution.setAttributes(attrs) }`. The SDK calls it
    /// with `["influto_code": code, "influto_referral": "true"]` on attribution /
    /// setReferralCode. Keeps RevenueCat OUT of the SDK (binary-distribution safe).
    public var revenueCatAttributeSetter: (@Sendable ([String: String]) -> Void)?

    public init(
        apiKey: String,
        debug: Bool = false,
        apiURL: URL = URL(string: "https://influ.to/api")!,
        appVersion: String? = nil,
        autoCapture: Bool = true,
        revenueCatAttributeSetter: (@Sendable ([String: String]) -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.debug = debug
        self.apiURL = apiURL
        self.appVersion = appVersion
        self.autoCapture = autoCapture
        self.revenueCatAttributeSetter = revenueCatAttributeSetter
    }
}
