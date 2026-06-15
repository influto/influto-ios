# InfluTo iOS Sample App

A runnable SwiftUI reference app showing the **best-practice InfluTo integration**
end-to-end, so you can verify the whole flow against your own InfluTo app + SKU
**before** wiring the SDK into production:

**1 configure → 2 attribution → 3 referral-code input → 4 paywall (StoreKit 2
purchase) → 5 confirm it landed in InfluTo.**

Nothing is hardcoded: you paste your API key + product id in the app (stored only
on-device). Copy the patterns in `Sources/InfluToSample/` into your real app.

## Run it

The project is generated with [XcodeGen](https://github.com/yonatankra/xcodegen)
(so there's no committed `.xcodeproj`):

```bash
brew install xcodegen
cd Sample
xcodegen generate
open InfluToSample.xcodeproj
```

Then in the app:

1. Paste your **InfluTo API key** (dashboard → your app → API key) and your
   **product id** (a real App Store Connect SKU, or the bundled StoreKit-Test id
   `to.influ.sample.pro.monthly`).
2. Tap **Initialize SDK**.
3. (Optional) enter a **referral code** to test attribution.
4. Tap a product in the **paywall** to purchase.
5. Tap **"Did it land in InfluTo?"** to confirm the conversion was recorded
   (and attributed) via the SDK-key-authed `/sdk/recent-conversions` endpoint.

### Local StoreKit Testing (no Apple account, simulator)

The app ships `Products.storekit`. In Xcode, select the scheme → **Edit Scheme →
Run → Options → StoreKit Configuration → Products.storekit** to buy locally on the
simulator. For these purchases to validate end-to-end, your InfluTo app must be in
**`apple_environment = "xcode"`** test mode (money-excluded). For real sandbox,
use a Sandbox Apple ID on a device and leave the scheme's StoreKit config as None.

## What the CI does (`.github/workflows/ci.yml`, job `sample`)

- **Layer 1 (always):** generates the project, builds the app, and runs an
  `SKTestSession` test that buys a product headlessly and asserts a non-empty
  signed JWS — proving the client plumbing. No secrets, no signing.
- **Layer 2 (live E2E):** when the repo secrets `INFLUTO_TEST_API_KEY`,
  `INFLUTO_TEST_REFERRAL_CODE`, `INFLUTO_TEST_PRODUCT_ID` (and optional
  `INFLUTO_TEST_BASE_URL`) are set, it POSTs the StoreKit-Test JWS to the live
  InfluTo backend and asserts a **money-excluded** conversion lands, attributed to
  the referral code. Without the secrets it `XCTSkip`s.

## Files

- `Sources/InfluToSample/PurchaseManager.swift` — StoreKit 2 purchase + `reportPurchase`
- `Sources/InfluToSample/ReferralCodeField.swift` — best-practice referral input
- `Sources/InfluToSample/SampleViewModel.swift` — init / attribution / "did it land"
- `Sources/InfluToSample/RecentConversions.swift` — `/sdk/recent-conversions` client
- `Tests/InfluToSampleTests/PurchaseFlowTests.swift` — the SKTestSession E2E
