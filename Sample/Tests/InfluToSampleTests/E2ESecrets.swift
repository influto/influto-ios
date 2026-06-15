// E2E test secrets.
//
// Default values are EMPTY → the live E2E test (`testReportPurchaseLandsInInfluToE2E`)
// SKIPS locally and on PRs without secrets. CI overwrites THIS file with the
// `INFLUTO_TEST_*` GitHub secrets before building (the filled version is never
// committed — it exists only on the runner). xcodebuild test won't reliably forward
// CI env vars into the simulator's XCTest process, so the values are compiled in.
enum E2ESecrets {
    static let apiKey = ""
    static let referralCode = ""
    static let productID = ""
    static let baseURL = ""
}
