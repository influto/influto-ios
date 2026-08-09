import Foundation

/// Non-sensitive K/V persistence over a named UserDefaults suite. Keys mirror the
/// React Native SDK's `@influto/` prefix byte-for-byte. Actor-isolated (held by
/// InfluToActor), so it needs no Sendable conformance.
final class Storage {
    static let attribution = "@influto/attribution"
    static let influtoCode = "@influto/influto_code"
    static let appUserId = "@influto/app_user_id"
    static let initialized = "@influto/initialized"
    static let access = "@influto/access"
    /// Per-install UUID sent as device_id — backend counts devices, not launches.
    static let installId = "@influto/install_id"
    /// Set of store identifiers (Apple `originalTransactionId`) already auto-reported, so
    /// opt-in observation/back-sync never re-reports across launches. Stored as a JSON
    /// array of strings under one key. Additive — NOT part of the byte-identical 4-key set.
    static let sentPurchases = "@influto/sent_purchases"

    private let defaults: UserDefaults

    init() {
        self.defaults = UserDefaults(suiteName: "com.influto.sdk") ?? .standard
    }

    func string(_ key: String) -> String? { defaults.string(forKey: key) }
    func set(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
    func remove(_ keys: [String]) { keys.forEach { defaults.removeObject(forKey: $0) } }

    // -------------------------------------------------- sent-purchase dedup (opt-in)

    private var sentCache: Set<String>?

    private func loadSent() -> Set<String> {
        if let sentCache { return sentCache }
        let arr = (defaults.array(forKey: Self.sentPurchases) as? [String]) ?? []
        let set = Set(arr)
        sentCache = set
        return set
    }

    /// True if this store identifier was already auto-reported.
    func isPurchaseSent(_ id: String) -> Bool { loadSent().contains(id) }

    /// Record a store identifier as auto-reported (persisted + cached).
    func markPurchaseSent(_ id: String) {
        var set = loadSent()
        guard set.insert(id).inserted else { return }
        sentCache = set
        defaults.set(Array(set), forKey: Self.sentPurchases)
    }

    /// Forget a store identifier — used to roll back an optimistic mark when the report
    /// failed, so a genuine retry can resend it.
    func unmarkPurchaseSent(_ id: String) {
        var set = loadSent()
        guard set.remove(id) != nil else { return }
        sentCache = set
        defaults.set(Array(set), forKey: Self.sentPurchases)
    }
}
