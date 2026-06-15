import Foundation
import CryptoKit
import StoreKit

/// StoreKit 2 helpers for the store-direct `reportPurchase` path.
enum Purchase {

    /// Extract the SIGNED JWS from a verification result. We send the JWS even when the
    /// device couldn't verify it (`.unverified`) — the BACKEND is the trust anchor and
    /// re-verifies the x5c chain / signature; local verification can fail for benign
    /// reasons (clock skew, Xcode test certs). NEVER send `jsonRepresentation` (unsigned).
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    static func jws(from verification: VerificationResult<Transaction>) -> String {
        // `jwsRepresentation` is a property of `VerificationResult` (NOT `Transaction`) and
        // is populated for both `.verified` and `.unverified` — so we always hand the backend
        // the signed envelope regardless of local verification, and the backend re-verifies
        // the x5c chain itself.
        return verification.jwsRepresentation
    }

    /// A DETERMINISTIC appAccountToken derived from a user id (UUIDv5-style: SHA-256 of the
    /// id, folded to 16 bytes with the v5 version/variant bits). The host passes this to
    /// `product.purchase(options: [.appAccountToken(token)])` so the purchase binds to the
    /// user server-side (stable across renewals). CryptoKit is part of the platform.
    static func appAccountToken(forUserID userID: String) -> UUID {
        let digest = SHA256.hash(data: Data(userID.utf8))
        var b = Array(digest.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50 // version 5
        b[8] = (b[8] & 0x3F) | 0x80 // variant 10xx
        let t: uuid_t = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                         b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
        return UUID(uuid: t)
    }
}
