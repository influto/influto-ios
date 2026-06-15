import Foundation

/// Tiny client for the SDK-key-authed `GET /sdk/recent-conversions` feedback
/// endpoint, so the sample can confirm in-app that a purchase actually landed in
/// InfluTo (and whether it attributed to a referral code) — before wiring the SDK
/// into a production app. Scoped to the caller's app + the given `appUserID`.
enum RecentConversions {
    struct Item: Decodable, Identifiable {
        let eventType: String
        let productId: String?
        let store: String?
        let environment: String
        let isTest: Bool
        let attributed: Bool
        let referralCode: String?
        let status: String?
        let eventTimestamp: String?

        var id: String { (eventTimestamp ?? "") + eventType + (productId ?? "") }

        enum CodingKeys: String, CodingKey {
            case eventType = "event_type"
            case productId = "product_id"
            case store
            case environment
            case isTest = "is_test"
            case attributed
            case referralCode = "referral_code"
            case status
            case eventTimestamp = "event_timestamp"
        }
    }

    private struct Response: Decodable {
        let count: Int
        let attributedCount: Int
        let conversions: [Item]
        enum CodingKeys: String, CodingKey {
            case count
            case attributedCount = "attributed_count"
            case conversions
        }
    }

    enum FetchError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(let code): return "Backend returned HTTP \(code)"
            }
        }
    }

    static func fetch(apiURL: URL, apiKey: String, appUserID: String, limit: Int = 10) async throws -> [Item] {
        var comps = URLComponents(
            url: apiURL.appendingPathComponent("sdk/recent-conversions"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "app_user_id", value: appUserID),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data).conversions
    }
}
