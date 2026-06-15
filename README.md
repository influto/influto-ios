# InfluTo iOS SDK (Swift)

Influencer attribution + store-direct purchase validation for iOS. **Zero dependencies**
(URLSession + UserDefaults + StoreKit 2 + CryptoKit, all platform frameworks). Mirrors the
[InfluTo React Native SDK](https://github.com/influto/influto-react-native) and the [canonical contract](./CONTRACT.md).

- **iOS 16+** · Swift (compiles in Swift 5 or 6 mode) · async/await · actor singleton
- **SPM-first** (CocoaPods provided as a fallback; CocoaPods trunk goes read-only Dec 2026)

## Prerequisites

You need a free **InfluTo account** — sign up at [https://influ.to](https://influ.to), create your
app in the dashboard, and copy your API key (it starts with `it_`). For store-direct purchase
validation / auto-capture, also add your Apple store credentials to the app in the dashboard.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies →** `https://github.com/influto/influto-ios`, or:

```swift
// Package.swift
dependencies: [ .package(url: "https://github.com/influto/influto-ios.git", from: "1.0.0") ]
```

## Quick start

```swift
import InfluTo
import StoreKit

// 1. Initialize once at launch.
var config = InfluToConfig(apiKey: "it_live_...", debug: true)
// OPTIONAL: wire RevenueCat (no hard dependency on it):
config.revenueCatAttributeSetter = { attrs in Purchases.shared.attribution.setAttributes(attrs) }
try await InfluTo.initialize(config)

// 2. Resolve install attribution.
let attr = await InfluTo.checkAttribution()
if attr.attributed { print("Referred by \(attr.referralCode ?? "")") }

// 3. Identify + track.
await InfluTo.identifyUser("user_123")
await InfluTo.trackEvent(TrackEventOptions(eventType: "paywall_viewed", appUserId: "user_123"))

// 4. Manual promo-code entry.
let result = await InfluTo.applyCode("FITGURU30", appUserId: "user_123")

// 5. Store-direct purchase (only if NOT using RevenueCat). At purchase time, bind the
//    purchase to the user with appAccountToken, then report the verified transaction:
let token = InfluTo.appAccountToken(forUserID: "user_123")          // host sets it at purchase
let purchase = try await product.purchase(options: [.appAccountToken(token)])
if case .success(let verification) = purchase {
    let r = try await InfluTo.reportPurchase(verification: verification)
    print("validated=\(r.validated ?? "-") env=\(r.environment ?? "-")")
    if case .verified(let txn) = verification { await txn.finish() }
}
```

`reportPurchase` sends the StoreKit 2 **`jwsRepresentation`** (the backend re-verifies it) and
defaults `referralCode` to the stored `influto_code`. Throws on failure; catch
`InfluToError.retryable` (503 = FX momentarily unavailable) to retry.

## Premium access (`checkAccess`)

`checkAccess(appUserId:)` is a server-authoritative premium-access check that works for **both**
RevenueCat and store-direct apps. It powers platform-independent comp (e.g. a free-access code that
grants entitlement without a purchase). Gate premium on the OR of your store entitlement and this:

```swift
let access = await InfluTo.checkAccess(appUserId: "user_123")  // appUserId optional → uses identified user
let isPremium = rcEntitlement || access.hasAccess
// access also exposes: source, entitlement, expiresAt, code
```

Positive results are cached (in-memory **and** persisted across cold starts, ~5-min TTL), so calling
it on every launch is cheap.

## Automatic purchase capture (store-direct)

For store-direct apps (not RevenueCat), the SDK can capture purchases for you — no manual
`reportPurchase` needed. This is **on by default**: when `initialize` runs and the backend reports
the app is store-direct, the SDK starts observing StoreKit 2 `Transaction.updates` and back-syncs
existing purchases. RevenueCat apps are unaffected (it stays silent). Set
`config.autoCapture = false` to manage reporting yourself.

To drive it manually:

```swift
await InfluTo.startPurchaseObservation()        // observe Transaction.updates (deduped, idempotent)
let sync = await InfluTo.syncExistingPurchases() // one-shot back-sync → {fetched, sent, failed}
await InfluTo.stopPurchaseObservation()         // stop the live observation
```

> **Cross-SDK note:** the canonical contract names these auto-capture toggles
> `enableAutoPurchaseCapture` / `disableAutoPurchaseCapture`; on iOS they are
> `startPurchaseObservation()` / `stopPurchaseObservation()`.

## Build & test — **requires macOS + Xcode**

> ⚠️ Swift-for-iOS cannot be compiled on Windows/WSL2. Build on a **Mac** (or a cloud-Mac CI
> like GitHub Actions `macos-15`). The physical iPhones pair to a Mac running Xcode.

```bash
swift build                       # compile (macOS slice)
swift test                        # unit tests (pure helpers; networking via URLProtocol)

# Run unit tests on the iOS Simulator:
xcodebuild test -scheme InfluTo \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

### Minimal SwiftUI sample

```swift
import SwiftUI
import StoreKit
import InfluTo

struct ContentView: View {
    @State private var log = ""
    var body: some View {
        VStack {
            Button("Run InfluTo flow") { Task { await run() } }
            ScrollView { Text(log).font(.footnote.monospaced()) }
        }.padding()
    }
    func run() async {
        do {
            try await InfluTo.initialize(InfluToConfig(apiKey: "it_TEST_KEY", debug: true))
            let a = await InfluTo.checkAttribution(); add("attributed=\(a.attributed) code=\(a.referralCode ?? "-")")
            let v = await InfluTo.validateCode("FITGURU30"); add("valid=\(v.valid) \(v.campaign?.name ?? v.error ?? "")")
            await InfluTo.identifyUser("user_123")
            await InfluTo.trackEvent(TrackEventOptions(eventType: "paywall_viewed", appUserId: "user_123"))
            add("identify + trackEvent sent")
            // Purchase via a Products.storekit config in the scheme (Sandbox for end-to-end):
            let products = try await Product.products(for: ["com.kaloria.pro.monthly"])
            if let p = products.first {
                let token = InfluTo.appAccountToken(forUserID: "user_123")
                if case .success(let v) = try await p.purchase(options: [.appAccountToken(token)]) {
                    let r = try await InfluTo.reportPurchase(verification: v)
                    add("purchase validated=\(r.validated ?? "-") env=\(r.environment ?? "-")")
                    if case .verified(let t) = v { await t.finish() }
                }
            }
        } catch { add("ERR \(error)") }
    }
    func add(_ s: String) { log += s + "\n" }
}
```

### StoreKit testing (step 5)

- Add a **`Products.storekit`** configuration file (Xcode → File → New → StoreKit Configuration File),
  define a subscription matching a backend product id, and select it in the scheme
  (**Run ▸ Options ▸ StoreKit Configuration**) to exercise the SDK's capture/send path.
- For end-to-end against the real `/sdk/purchase`, use a **Sandbox** Apple ID on the device (the JWS
  then verifies against Apple's sandbox chain; backend returns `environment: "Sandbox"`). The app must
  have `ios_validation_provider = "apple"` + Apple `.p8` creds configured, else `/sdk/purchase` 400s.

## Privacy

Ships `PrivacyInfo.xcprivacy`: `NSPrivacyTracking=false`, no tracking domains, declares Device ID /
Product Interaction / Purchase History collection (all `Linked=false`, `Tracking=false`), and the
UserDefaults Required-Reason `CA92.1`. Uses `identifierForVendor` (not IDFA) → **no
AppTrackingTransparency prompt required.**

## Verify on the backend

`GET /api/apps/{id}/events/recent` → `sdk_events[]` shows each `trackEvent` once with the right
`referral_code`; `webhooks[]` shows the purchase with `"attributed": true`.
