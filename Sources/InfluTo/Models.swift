import Foundation

/// A type-erased JSON value (for `properties` / `customData` / `result`). ~Codable + Sendable.
public struct AnyCodable: Codable, Sendable {
    public let value: (any Sendable)?

    public init(_ value: (any Sendable)?) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = nil
        } else if let b = try? c.decode(Bool.self) {
            value = b
        } else if let i = try? c.decode(Int.self) {
            value = i
        } else if let d = try? c.decode(Double.self) {
            value = d
        } else if let s = try? c.decode(String.self) {
            value = s
        } else if let a = try? c.decode([AnyCodable].self) {
            value = a
        } else if let m = try? c.decode([String: AnyCodable].self) {
            value = m
        } else {
            value = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case nil: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [AnyCodable]: try c.encode(a)
        case let m as [String: AnyCodable]: try c.encode(m)
        default: try c.encodeNil()
        }
    }
}

/// Result of `checkAttribution`.
public struct AttributionResult: Codable, Sendable {
    public let attributed: Bool
    public let referralCode: String?
    public let attributionMethod: String?
    public let clickedAt: String?
    public let confidence: Double?
    public let message: String?

    public init(
        attributed: Bool, referralCode: String? = nil, attributionMethod: String? = nil,
        clickedAt: String? = nil, confidence: Double? = nil, message: String? = nil
    ) {
        self.attributed = attributed
        self.referralCode = referralCode
        self.attributionMethod = attributionMethod
        self.clickedAt = clickedAt
        self.confidence = confidence
        self.message = message
    }
}

/// A campaign from `/sdk/campaigns`.
public struct Campaign: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let commissionPercentage: Double?
}

/// Campaign details nested in validate/set results.
public struct CampaignInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let commissionPercentage: Double?
    public let campaignType: String?
}

/// Influencer details, when available.
public struct Influencer: Codable, Sendable {
    public let name: String
    public let socialHandle: String?
    public let followerCount: Int?
}

/// Options for `trackEvent`.
public struct TrackEventOptions: Sendable {
    public let eventType: String
    public let appUserId: String
    public var properties: [String: AnyCodable]?
    public var referralCode: String?
    public var eventId: String?

    public init(
        eventType: String, appUserId: String, properties: [String: AnyCodable]? = nil,
        referralCode: String? = nil, eventId: String? = nil
    ) {
        self.eventType = eventType
        self.appUserId = appUserId
        self.properties = properties
        self.referralCode = referralCode
        self.eventId = eventId
    }
}

/// Result of `validateCode` / `applyCode`.
public struct CodeValidationResult: Codable, Sendable {
    public let valid: Bool
    public let code: String?
    public let campaign: CampaignInfo?
    public let influencer: Influencer?
    public let customData: [String: AnyCodable]?
    public let message: String?
    public let error: String?
    /// INVALID_FORMAT | CODE_NOT_FOUND | CODE_EXPIRED | NETWORK_ERROR.
    public let errorCode: String?
    /// Populated by `applyCode`.
    public var applied: Bool?

    public init(
        valid: Bool, code: String? = nil, campaign: CampaignInfo? = nil,
        influencer: Influencer? = nil, customData: [String: AnyCodable]? = nil,
        message: String? = nil, error: String? = nil, errorCode: String? = nil, applied: Bool? = nil
    ) {
        self.valid = valid; self.code = code; self.campaign = campaign
        self.influencer = influencer; self.customData = customData; self.message = message
        self.error = error; self.errorCode = errorCode; self.applied = applied
    }
}

/// Result of `setReferralCode`.
public struct SetCodeResult: Codable, Sendable {
    public let success: Bool
    public let code: String?
    public let message: String?
    public let campaign: ShortCampaign?
    /// True when this code is a developer free-access (comp) code.
    public let freeAccess: Bool?
    /// True when the backend granted native premium access for this redemption.
    public let grantsAccess: Bool?
    /// Granted entitlement id/lookup-key, if any.
    public let entitlement: String?
    /// ISO-8601 expiry, or nil for open-ended.
    public let expiresAt: String?
    public struct ShortCampaign: Codable, Sendable {
        public let id: String
        public let name: String
    }
    // Explicit init with defaults so the existing fallback call sites keep compiling; Codable
    // synthesizes its own init(from:) which decodes the comp fields (convertFromSnakeCase).
    public init(
        success: Bool, code: String? = nil, message: String? = nil, campaign: ShortCampaign? = nil,
        freeAccess: Bool? = nil, grantsAccess: Bool? = nil, entitlement: String? = nil, expiresAt: String? = nil
    ) {
        self.success = success; self.code = code; self.message = message; self.campaign = campaign
        self.freeAccess = freeAccess; self.grantsAccess = grantsAccess
        self.entitlement = entitlement; self.expiresAt = expiresAt
    }
}

/// Result of `checkAccess` — server-authoritative premium access (platform-independent comp).
public struct AccessResult: Codable, Sendable {
    public let hasAccess: Bool
    public let source: String?
    public let entitlement: String?
    public let expiresAt: String?
    public let code: String?
    public init(
        hasAccess: Bool, source: String? = nil, entitlement: String? = nil,
        expiresAt: String? = nil, code: String? = nil
    ) {
        self.hasAccess = hasAccess; self.source = source; self.entitlement = entitlement
        self.expiresAt = expiresAt; self.code = code
    }
}

/// Result of `reportPurchase` (store-direct).
public struct PurchaseResult: Codable, Sendable {
    public let success: Bool
    /// The provider that validated the purchase: "apple" | "google" (a STRING).
    public let validated: String?
    public let environment: String?
    public let eventType: String?
    public let result: [String: AnyCodable]?
}

/// Counters returned by `syncExistingPurchases()`. `fetched` = transactions seen;
/// `sent` = newly reported; `failed` = reports that threw (deduped ones count as neither).
public struct PurchaseSyncResult: Sendable, Equatable {
    public let fetched: Int
    public let sent: Int
    public let failed: Int
    public let success: Bool

    public init(fetched: Int, sent: Int, failed: Int, success: Bool) {
        self.fetched = fetched
        self.sent = sent
        self.failed = failed
        self.success = success
    }
}

/// Internal: shape of the `/sdk/init` response.
struct InitResponse: Codable, Sendable {
    let appId: String?
    let appName: String?
    let attributionWindowHours: Int?
    /// True when this platform is configured for store-direct validation (drives default
    /// auto-capture; absent/false for RevenueCat apps).
    let storeDirect: Bool?
    let initialized: Bool?
}
