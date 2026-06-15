import Foundation

/// Errors thrown by the throwing methods (`initialize`, `reportPurchase`).
public enum InfluToError: Error, Sendable {
    /// A method requiring initialization was called before `initialize`.
    case notInitialized
    /// The server returned a non-2xx status.
    case http(status: Int, body: String)
    /// A 503 (FX rate momentarily unavailable) — the caller should retry.
    case retryable(status: Int)
    /// A 400 — the app is not configured for store-direct validation on this platform.
    case notConfigured(String)
    /// The response body could not be decoded.
    case decoding(Error)
    /// A transport-level failure.
    case transport(Error)
}
