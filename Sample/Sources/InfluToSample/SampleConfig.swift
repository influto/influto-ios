import Foundation

/// Runtime-configurable sample settings.
///
/// NOTHING is hardcoded or committed: the API key + product id are entered in the
/// app at runtime and persisted in `UserDefaults`, so a real key never lands in
/// source control. The XCTest reads the same values from the environment (CI
/// secrets) instead — see `PurchaseFlowTests`.
@MainActor
final class SampleConfig: ObservableObject {
    @Published var apiKey: String { didSet { defaults.set(apiKey, forKey: K.apiKey) } }
    @Published var productID: String { didSet { defaults.set(productID, forKey: K.productID) } }
    @Published var appUserID: String { didSet { defaults.set(appUserID, forKey: K.appUserID) } }
    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: K.baseURL) } }

    private let defaults = UserDefaults.standard
    private enum K {
        static let apiKey = "influto.sample.apiKey"
        static let productID = "influto.sample.productID"
        static let appUserID = "influto.sample.appUserID"
        static let baseURL = "influto.sample.baseURL"
    }

    /// Matches the product id in `Products.storekit`.
    static let defaultProductID = "to.influ.sample.pro.monthly"
    static let defaultBaseURL = "https://influ.to/api"

    init() {
        apiKey = defaults.string(forKey: K.apiKey) ?? ""
        productID = defaults.string(forKey: K.productID) ?? Self.defaultProductID
        appUserID = defaults.string(forKey: K.appUserID)
            ?? "sample-" + UUID().uuidString.prefix(8).lowercased()
        apiBaseURL = defaults.string(forKey: K.baseURL) ?? Self.defaultBaseURL
    }

    var apiURL: URL { URL(string: apiBaseURL) ?? URL(string: Self.defaultBaseURL)! }

    /// Minimal sanity: an InfluTo key is `it_...` and well over 10 chars.
    var isConfigured: Bool { apiKey.trimmingCharacters(in: .whitespaces).count >= 10 }
}
