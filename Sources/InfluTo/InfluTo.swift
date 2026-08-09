import Foundation
import StoreKit

/// InfluTo iOS SDK — influencer attribution + store-direct purchase validation.
///
/// A static facade over the `InfluToActor` singleton, so call sites read like the
/// React Native SDK. Fail-soft: only `initialize` and `reportPurchase` throw.
///
/// ```swift
/// try await InfluTo.initialize(InfluToConfig(apiKey: "it_..."))
/// let attr = await InfluTo.checkAttribution()
/// ```
public enum InfluTo {
    /// The actor singleton.
    public static let shared = InfluToActor()

    public static func initialize(_ config: InfluToConfig) async throws {
        try await shared.initialize(config)
    }
    public static func checkAttribution() async -> AttributionResult {
        await shared.checkAttribution()
    }
    public static func identifyUser(_ appUserId: String, properties: [String: AnyCodable]? = nil) async {
        await shared.identifyUser(appUserId, properties: properties)
    }
    public static func trackEvent(_ options: TrackEventOptions) async {
        await shared.trackEvent(options)
    }
    public static func getActiveCampaigns() async -> [Campaign] {
        await shared.getActiveCampaigns()
    }
    public static func getReferralCode() async -> String? {
        await shared.getReferralCode()
    }
    public static func getPrefilledCode() async -> String? {
        await shared.getPrefilledCode()
    }
    public static func validateCode(_ code: String) async -> CodeValidationResult {
        await shared.validateCode(code)
    }
    public static func setReferralCode(_ code: String, appUserId: String? = nil) async -> SetCodeResult {
        await shared.setReferralCode(code, appUserId: appUserId)
    }
    public static func applyCode(_ code: String, appUserId: String? = nil) async -> CodeValidationResult {
        await shared.applyCode(code, appUserId: appUserId)
    }
    public static func clearAttribution() async {
        await shared.clearAttribution()
    }

    /// Server-authoritative premium-access check (platform-independent comp). Works for BOTH
    /// RevenueCat and store-direct apps. Gate premium on `rcEntitlement || checkAccess().hasAccess`.
    public static func checkAccess(appUserId: String? = nil) async -> AccessResult {
        await shared.checkAccess(appUserId: appUserId)
    }

    /// Store-direct purchase report from a StoreKit 2 verification result.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public static func reportPurchase(
        verification: VerificationResult<Transaction>, appUserId: String? = nil, referralCode: String? = nil
    ) async throws -> PurchaseResult {
        try await shared.reportPurchase(verification: verification, appUserId: appUserId, referralCode: referralCode)
    }

    /// Store-direct purchase report from a raw StoreKit 2 JWS string.
    public static func reportPurchase(jws: String, appUserId: String? = nil, referralCode: String? = nil) async throws -> PurchaseResult {
        try await shared.reportPurchase(jws: jws, appUserId: appUserId, referralCode: referralCode)
    }

    /// Deterministic `appAccountToken` to bind a purchase to a user. The HOST passes this
    /// to `product.purchase(options: [.appAccountToken(InfluTo.appAccountToken(forUserID:))])`.
    public static func appAccountToken(forUserID userID: String) -> UUID {
        Purchase.appAccountToken(forUserID: userID)
    }

    // ---- Opt-in automatic purchase capture + historical back-sync (StoreKit 2) -------

    /// OPT-IN: auto-report NEW purchases as they arrive on `Transaction.updates`. Call once
    /// after `initialize`. Deduped; safe to call repeatedly. Use only for store-direct apps
    /// that don't already report via RevenueCat or manual `reportPurchase`.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public static func startPurchaseObservation() async {
        await shared.startPurchaseObservation()
    }

    /// Stop the live observation started by `startPurchaseObservation()`.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public static func stopPurchaseObservation() async {
        await shared.stopPurchaseObservation()
    }

    /// One-shot back-sync of existing/unfinished transactions. Returns `{fetched, sent, failed}`.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    @discardableResult
    public static func syncExistingPurchases() async -> PurchaseSyncResult {
        await shared.syncExistingPurchases()
    }
}

/// The actor that owns all SDK state. Actor isolation serializes access to the config,
/// HTTP client, and storage (the modern replacement for a module-level singleton).
public actor InfluToActor {
    private let sdkVersion = "1.1.0"

    private var config: InfluToConfig?
    private var api: APIClient?
    private var storage: Storage?
    private var initialized = false
    /// Retained `Transaction.updates` observation task (opt-in auto-capture). `nil` unless
    /// `startPurchaseObservation()` is active. Actor-isolated so start/stop are serialized.
    private var observationTask: Task<Void, Never>?
    /// In-memory positive cache for `checkAccess` (uid, result, fetched-at). ~5 min TTL.
    private var accessCache: (uid: String, result: AccessResult, at: Date)?

    // Plain (camelCase) coders for the locally-stored attribution blob (matches the RN
    // persistence shape). The API decoder uses convertFromSnakeCase; these do NOT.
    private let storedEncoder = JSONEncoder()
    private let storedDecoder = JSONDecoder()

    public init() {}

    private var debug: Bool { config?.debug ?? false }
    private func log(_ s: String) { if debug { print("[InfluTo] \(s)") } }

    // ------------------------------------------------------------------ initialize

    public func initialize(_ config: InfluToConfig) async throws {
        self.config = config
        self.storage = Storage()
        self.api = APIClient(baseURL: config.apiURL, apiKey: config.apiKey, debug: config.debug)
        do {
            let body: [String: Any] = [
                "app_version": config.appVersion ?? "unknown",
                "sdk_version": sdkVersion,
                "platform": "ios",
            ]
            let resp: InitResponse = try await api!.post("/sdk/init", body: body)
            if resp.initialized == true {
                initialized = true
                storage?.set("true", Storage.initialized)
                log("SDK initialized")

                // Auto-capture purchases by default for store-direct apps (one-line
                // integration). RevenueCat apps report store_direct=false → stays silent.
                if config.autoCapture, resp.storeDirect == true {
                    if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                        startPurchaseObservation()
                        Task { _ = await syncExistingPurchases() }
                    }
                }
            }
        } catch {
            log("Initialization failed: \(error)")
            throw error
        }
    }

    // ------------------------------------------------------------- checkAttribution

    public func checkAttribution() async -> AttributionResult {
        guard initialized, let api, let storage else {
            return AttributionResult(attributed: false, message: "SDK not initialized")
        }
        do {
            if let stored = storage.string(Storage.attribution),
               let data = stored.data(using: .utf8),
               let attribution = try? storedDecoder.decode(AttributionResult.self, from: data) {
                return attribution
            }
            var device = await DeviceInfo.trackInstallBody()
            device["device_id"] = installId(storage)
            let resp: AttributionResult = try await api.post(
                "/sdk/track-install", body: device.mapValues { $0 as Any }
            )
            if resp.attributed, let code = resp.referralCode {
                if let data = try? storedEncoder.encode(resp),
                   let json = String(data: data, encoding: .utf8) {
                    storage.set(json, Storage.attribution)
                }
                storage.set(code, Storage.influtoCode)
                setRevenueCatAttributes(code)
                return resp
            }
            // Persist the ORGANIC result too (contract 1.6.0): persisting only
            // attributed results made every organic user re-POST track-install
            // on every cold start. A thrown request (catch) persists nothing,
            // so a failed attempt retries on the next launch.
            let organic = AttributionResult(attributed: false, message: resp.message ?? "No attribution found")
            if let data = try? storedEncoder.encode(organic),
               let json = String(data: data, encoding: .utf8) {
                storage.set(json, Storage.attribution)
            }
            return organic
        } catch {
            log("checkAttribution error: \(error)")
            return AttributionResult(attributed: false, message: "Error checking attribution")
        }
    }

    /// Per-install UUID, generated once and persisted (UserDefaults suite).
    private func installId(_ storage: Storage) -> String {
        if let existing = storage.string(Storage.installId) { return existing }
        let fresh = UUID().uuidString.lowercased()
        storage.set(fresh, Storage.installId)
        return fresh
    }

    /// Once-only monetization events get a DETERMINISTIC id from
    /// (type, user, sorted properties) so cross-launch re-fires collapse
    /// server-side; other events get a random uuid.
    static func defaultEventId(
        eventType: String, appUserId: String, properties: [String: Any]?
    ) -> String {
        let onceOnly = ["trial_started", "subscription_purchased", "subscription_renewed"]
        guard onceOnly.contains(eventType) else { return UUID().uuidString.lowercased() }
        let canonical = (properties ?? [:])
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "&")
        var h: UInt32 = 0x811c9dc5
        for byte in canonical.utf8 {
            h ^= UInt32(byte)
            h = h &* 0x01000193
        }
        let hex = String(format: "%08x", h)
        return "det:\(eventType):\(appUserId):\(hex)"
    }

    // ----------------------------------------------------------------- identifyUser

    public func identifyUser(_ appUserId: String, properties: [String: AnyCodable]? = nil) async {
        guard initialized, let api, let storage else { log("not initialized"); return }
        storage.set(appUserId, Storage.appUserId)
        var body: [String: Any] = ["app_user_id": appUserId]
        body["properties"] = properties.map { anyCodableMapToJSON($0) } ?? [:]
        do {
            let _: EmptyResponse = try await api.post("/sdk/identify", body: body)
        } catch {
            log("identify error: \(error)")
        }
    }

    // ------------------------------------------------------------------- trackEvent

    public func trackEvent(_ options: TrackEventOptions) async {
        guard initialized, let api else { log("not initialized"); return }
        var body: [String: Any] = [
            "eventType": options.eventType,
            "appUserId": options.appUserId,
            "eventId": options.eventId ?? Self.defaultEventId(
                eventType: options.eventType,
                appUserId: options.appUserId,
                properties: options.properties
            ),
        ]
        if let props = options.properties { body["properties"] = anyCodableMapToJSON(props) }
        if let code = options.referralCode { body["referralCode"] = code }
        do {
            let _: EmptyResponse = try await api.post("/sdk/event", body: body)
        } catch {
            log("trackEvent error: \(error)")
        }
    }

    // ------------------------------------------------------------ getActiveCampaigns

    public func getActiveCampaigns() async -> [Campaign] {
        guard initialized, let api else { return [] }
        do {
            return try await api.get("/sdk/campaigns")
        } catch {
            log("campaigns error: \(error)")
            return []
        }
    }

    // ----------------------------------------------------------- local read helpers

    public func getReferralCode() -> String? { storage?.string(Storage.influtoCode) }

    public func getPrefilledCode() -> String? {
        guard let stored = storage?.string(Storage.attribution),
              let data = stored.data(using: .utf8),
              let a = try? storedDecoder.decode(AttributionResult.self, from: data) else {
            return nil
        }
        return a.attributed ? a.referralCode : nil
    }

    public func clearAttribution() {
        storage?.remove([Storage.attribution, Storage.influtoCode, Storage.appUserId])
    }

    // ------------------------------------------------------------------- checkAccess

    public func checkAccess(appUserId: String? = nil) async -> AccessResult {
        guard initialized, let api, let storage else { return AccessResult(hasAccess: false) }
        guard let uid = appUserId ?? storage.string(Storage.appUserId) else {
            return AccessResult(hasAccess: false)
        }
        if let c = accessCache, c.uid == uid, c.result.hasAccess,
           Date().timeIntervalSince(c.at) < 300 {
            return c.result
        }
        // Persisted positive cache survives cold starts (same 5-min TTL as the in-memory one).
        if let p = loadPersistedAccess(uid: uid) { return p }
        do {
            let escaped = uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uid
            let resp: AccessResult = try await api.get("/sdk/access?app_user_id=\(escaped)")
            if resp.hasAccess { persistAccess(uid: uid, result: resp) }
            return resp
        } catch {
            log("checkAccess error: \(error)")
            return AccessResult(hasAccess: false)
        }
    }

    /// Envelope for the persisted positive access result (uid + fetched-at + the result).
    private struct PersistedAccess: Codable {
        let uid: String
        let at: Double  // timeIntervalSince1970
        let result: AccessResult
    }

    /// Cache a positive access result in memory + persist it under `Storage.access`.
    private func persistAccess(uid: String, result: AccessResult) {
        let now = Date()
        accessCache = (uid, result, now)
        guard let storage else { return }
        if let data = try? storedEncoder.encode(
            PersistedAccess(uid: uid, at: now.timeIntervalSince1970, result: result)),
           let json = String(data: data, encoding: .utf8) {
            storage.set(json, Storage.access)
        }
    }

    /// Read a still-valid (~5 min) persisted positive access result for `uid`, else nil.
    private func loadPersistedAccess(uid: String) -> AccessResult? {
        guard let storage, let json = storage.string(Storage.access),
              let data = json.data(using: .utf8),
              let p = try? storedDecoder.decode(PersistedAccess.self, from: data),
              p.uid == uid, p.result.hasAccess,
              Date().timeIntervalSince1970 - p.at < 300 else { return nil }
        accessCache = (uid, p.result, Date(timeIntervalSince1970: p.at))
        return p.result
    }

    // ----------------------------------------------------------------- validateCode

    public func validateCode(_ code: String) async -> CodeValidationResult {
        guard initialized, let api else {
            return CodeValidationResult(valid: false, error: "SDK not initialized", errorCode: "NETWORK_ERROR")
        }
        do {
            let body = ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
            return try await api.post("/sdk/validate-code", body: body)
        } catch {
            log("validateCode error: \(error)")
            return CodeValidationResult(valid: false, error: "Network error or invalid response", errorCode: "NETWORK_ERROR")
        }
    }

    // --------------------------------------------------------------- setReferralCode

    public func setReferralCode(_ code: String, appUserId: String? = nil) async -> SetCodeResult {
        guard initialized, let api, let storage else {
            return SetCodeResult(success: false, code: nil, message: "SDK not initialized", campaign: nil)
        }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            storage.set(normalized, Storage.influtoCode)
            let attribution = AttributionResult(
                attributed: true, referralCode: normalized, attributionMethod: "manual_entry",
                clickedAt: iso8601Now(), message: "Manually entered code"
            )
            if let data = try? storedEncoder.encode(attribution),
               let json = String(data: data, encoding: .utf8) {
                storage.set(json, Storage.attribution)
            }
            setRevenueCatAttributes(normalized)

            var body: [String: Any] = ["code": normalized]
            if let appUserId {
                body["app_user_id"] = appUserId
                storage.set(appUserId, Storage.appUserId)
            }
            return try await api.post("/sdk/set-referral-code", body: body)
        } catch {
            log("setReferralCode error: \(error)")
            return SetCodeResult(success: false, code: nil, message: "Failed to set code", campaign: nil)
        }
    }

    // ------------------------------------------------------------------- applyCode

    public func applyCode(_ code: String, appUserId: String? = nil) async -> CodeValidationResult {
        var validation = await validateCode(code)
        if !validation.valid {
            validation.applied = false
            return validation
        }
        let set = await setReferralCode(code, appUserId: appUserId)
        validation.applied = set.success
        return validation
    }

    // --------------------------------------------------------------- reportPurchase

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public func reportPurchase(
        verification: VerificationResult<Transaction>, appUserId: String? = nil, referralCode: String? = nil
    ) async throws -> PurchaseResult {
        try await reportPurchase(jws: Purchase.jws(from: verification), appUserId: appUserId, referralCode: referralCode)
    }

    public func reportPurchase(jws: String, appUserId: String? = nil, referralCode: String? = nil) async throws -> PurchaseResult {
        guard initialized, let api, let storage else { throw InfluToError.notInitialized }
        let code = referralCode ?? storage.string(Storage.influtoCode)
        let user = appUserId ?? storage.string(Storage.appUserId)
        var body: [String: Any] = ["platform": "ios", "signedTransaction": jws]
        if let code { body["referralCode"] = code }
        if let user { body["appUserId"] = user }
        let resp: PurchaseResult = try await api.post("/sdk/purchase", body: body)
        log("purchase reported: \(resp.validated ?? "-")")
        return resp
    }

    // ---- Opt-in automatic purchase capture + back-sync (StoreKit 2) ----
    // Runs only when the host calls these, so it never double-reports against the
    // RevenueCat or manual-reportPurchase paths. Deduped on Transaction.originalID, persisted.

    /// Auto-report new transactions from `Transaction.updates` (deduped). Idempotent.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public func startPurchaseObservation() {
        guard initialized else { log("startPurchaseObservation: not initialized"); return }
        guard observationTask == nil else { log("already observing"); return }
        observationTask = Task.detached { [weak self] in
            // `Transaction.updates` yields new + renewed transactions for the app's lifetime.
            for await verification in Transaction.updates {
                await self?.handleObservedTransaction(verification)
            }
        }
        log("purchase observation started")
    }

    /// Stop observing the live stream. Safe to call when not observing.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    public func stopPurchaseObservation() {
        observationTask?.cancel()
        observationTask = nil
        log("purchase observation stopped")
    }

    /// One-shot back-sync of existing/unfinished transactions, reporting each not-yet-sent
    /// one. Returns `{fetched, sent, failed}`. Does not finish() transactions (host's job).
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    @discardableResult
    public func syncExistingPurchases() async -> PurchaseSyncResult {
        guard initialized, let storage else {
            log("syncExistingPurchases: not initialized")
            return PurchaseSyncResult(fetched: 0, sent: 0, failed: 0, success: false)
        }
        var fetched = 0, sent = 0, failed = 0
        var seen = Set<String>()

        // Nested helper captures the counters by reference; all actor-isolated + serial.
        func handle(_ v: VerificationResult<Transaction>) async {
            fetched += 1
            let originalID = Self.originalID(of: v)
            if seen.contains(originalID) || storage.isPurchaseSent(originalID) { return }
            seen.insert(originalID)
            // Mark BEFORE the await: the actor yields during reportPurchase, so a concurrent live
            // observation of the same transaction could otherwise pass the isPurchaseSent check and
            // double-report. Roll back on failure so a genuine retry can resend.
            storage.markPurchaseSent(originalID)
            do {
                _ = try await reportPurchase(verification: v)
                sent += 1
            } catch {
                storage.unmarkPurchaseSent(originalID)
                log("auto reportPurchase failed for \(originalID): \(error)")
                failed += 1
            }
        }

        for await v in Transaction.currentEntitlements { await handle(v) }
        for await v in Transaction.unfinished { await handle(v) }

        log("syncExistingPurchases fetched=\(fetched) sent=\(sent) failed=\(failed)")
        return PurchaseSyncResult(fetched: fetched, sent: sent, failed: failed, success: failed == 0)
    }

    /// Live-stream handler: report a brand-new transaction (deduped). We do NOT finish() it —
    /// the host owns transaction lifecycle.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    private func handleObservedTransaction(_ v: VerificationResult<Transaction>) async {
        guard let storage else { return }
        let originalID = Self.originalID(of: v)
        if storage.isPurchaseSent(originalID) { return }
        // Mark before the await (see syncExistingPurchases) so the back-sync can't also report
        // this same transaction during the network call. Roll back on failure to allow a retry.
        storage.markPurchaseSent(originalID)
        do {
            _ = try await reportPurchase(verification: v)
        } catch {
            storage.unmarkPurchaseSent(originalID)
            log("auto reportPurchase failed for \(originalID): \(error)")
        }
    }

    /// `originalID` is readable on BOTH `.verified` and `.unverified` (the payload is present
    /// either way; verification only attests the signature).
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    private static func originalID(of v: VerificationResult<Transaction>) -> String {
        switch v {
        case .verified(let t): return String(t.originalID)
        case .unverified(let t, _): return String(t.originalID)
        }
    }

    // ------------------------------------------------------------------- internals

    private func setRevenueCatAttributes(_ code: String) {
        config?.revenueCatAttributeSetter?(["influto_code": code, "influto_referral": "true"])
    }

    private func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private func anyCodableMapToJSON(_ m: [String: AnyCodable]) -> [String: Any] {
        m.mapValues { anyCodableToJSON($0) }
    }

    private func anyCodableToJSON(_ v: AnyCodable) -> Any {
        switch v.value {
        case nil: return NSNull()
        case let b as Bool: return b
        case let i as Int: return i
        case let d as Double: return d
        case let s as String: return s
        case let a as [AnyCodable]: return a.map { anyCodableToJSON($0) }
        case let m as [String: AnyCodable]: return m.mapValues { anyCodableToJSON($0) }
        default: return NSNull()
        }
    }
}

/// Internal: an ignored response for fire-and-forget endpoints.
struct EmptyResponse: Codable, Sendable {}
