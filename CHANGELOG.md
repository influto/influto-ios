# Changelog

All notable changes to the InfluTo iOS SDK are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-10-09

### Fixed
- `setReferralCode` / `applyCode` fall back to the user stored by
  `identifyUser` when `appUserId` isn't passed. Without it the backend
  rejected free-access codes with `MISSING_USER_ID`.
- `setReferralCode` stores the code (and the `manual_entry` attribution record)
  and calls `revenueCatAttributeSetter` only after the backend answers
  `success == true`, using the canonical code it returns. A rejected code is
  no longer stored or tagged. Still fail-soft.
- `InfluToReferralCodeInput`: the field no longer drops `_` (codes allow
  `[A-Z0-9_-]`), and `onApplied` fires only when the code was actually applied
  (`applied == true`), not merely valid.
- Automatic purchase capture: `Transaction.updates` does not deliver purchases
  the app completes itself via `product.purchase()`, so those were only
  reported at the next launch's back-sync. While observation is running, the
  back-sync now also re-runs when the app becomes active (iOS/tvOS/visionOS;
  no-op on macOS/watchOS). Deduped locally; reports stay idempotent
  server-side.

### Changed
- CocoaPods podspec version brought in line with the SDK (`1.1.1`; it was
  still `1.0.0`).

## [1.1.0] - 2026-08-09

### Fixed
- `checkAttribution()` no longer re-fires `/sdk/track-install` on every cold
  start for organic users: the organic (non-attributed) result is now persisted
  like the attributed one (contract 1.6.0). A failed request still retries on
  the next launch.

### Added
- Persisted per-install UUID (`@influto/install_id`) sent as `device_id`, so
  the backend counts unique devices instead of launches. No permissions, no
  fingerprinting; resets on reinstall by design.
- Deterministic `eventId` for once-only monetization events (`trial_started`,
  `subscription_purchased`, `subscription_renewed`) derived from
  (event type, user, properties) — cross-launch re-fires collapse server-side.

## [1.0.0] - 2026-06-15

### Added
- Initial public release of the InfluTo iOS SDK (Swift, zero dependencies:
  URLSession + UserDefaults + StoreKit 2 + CryptoKit).
- Full influencer attribution API: `initialize`, `checkAttribution`,
  `identifyUser`, `trackEvent`, `getActiveCampaigns`, `validateCode`,
  `setReferralCode`, `applyCode`, `getReferralCode`, `getPrefilledCode`,
  `clearAttribution` — matching the canonical cross-platform contract (wire 1.0.0).
- Store-direct purchase validation: `reportPurchase(verification:)` sends the
  StoreKit 2 `jwsRepresentation` to `/sdk/purchase`; `appAccountToken(forUserID:)`
  helper to bind a purchase to a user. Throws `InfluToError.retryable` on a 503
  (FX rate momentarily unavailable) so callers can retry.
- `checkAccess(appUserId:)`: server-authoritative premium-access check enabling
  platform-independent comp (free-access codes that grant entitlement without a
  purchase) — works for both RevenueCat and store-direct apps. Positive results
  use a persisted cache (in-memory + UserDefaults, ~5-min TTL) so it survives cold
  starts.
- Default-on StoreKit 2 automatic purchase capture for store-direct apps:
  `initialize` starts observing `Transaction.updates` and back-syncs existing
  purchases when the backend reports the app is store-direct (RevenueCat apps
  unaffected; set `config.autoCapture = false` to opt out). Exposed directly via
  `startPurchaseObservation()` / `stopPurchaseObservation()` / `syncExistingPurchases()`
  (the iOS names for the contract's `enableAutoPurchaseCapture` /
  `disableAutoPurchaseCapture`).
- Optional RevenueCat integration via a caller-injected attribute-setter callback
  (`revenueCatAttributeSetter`) — no hard dependency on RevenueCat.
- `InfluToReferralCodeInput` SwiftUI component with live debounced validation.
  `showCampaignName` and `showReferrerName` both default to `false`, so the
  influencer's personal name is hidden unless explicitly opted in.
- `PrivacyInfo.xcprivacy` privacy manifest: `NSPrivacyTracking=false`, no tracking
  domains, declares Device ID / Product Interaction / Purchase History collection
  (all `Linked=false`, `Tracking=false`) and the UserDefaults Required-Reason
  `CA92.1`. Uses `identifierForVendor` (not IDFA) — no ATT prompt required.

[1.0.0]: https://github.com/influto/influto-ios/releases/tag/1.0.0
