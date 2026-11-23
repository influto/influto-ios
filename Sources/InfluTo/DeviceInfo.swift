import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Builds the `/sdk/track-install` device-signals body. All values are Strings (so the
/// dictionary is Sendable and can cross the actor boundary). Uses `identifierForVendor`
/// (NOT IDFA) so no AppTrackingTransparency prompt is required.
///
/// `platform` is "ios" on every Apple platform (native macOS included): it is the wire
/// key of the Apple store (App Store validation, store-direct config), not the OS name.
enum DeviceInfo {
    @MainActor
    static func trackInstallBody() -> [String: String] {
        var body: [String: String] = ["platform": "ios", "device_brand": "Apple"]
        #if canImport(UIKit) && !os(watchOS)
        body["os_version"] = UIDevice.current.systemVersion
        body["device_model"] = UIDevice.current.model
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = idfv
        }
        let b = UIScreen.main.nativeBounds
        body["screen_resolution"] = "\(Int(b.width))x\(Int(b.height))"
        #else
        // Native macOS / watchOS: no UIDevice. The OS version comes from ProcessInfo; the
        // device id is the SDK's per-install UUID (set by the caller for every platform).
        body["os_version"] = osVersionString()
        #if os(macOS)
        body["device_model"] = "Mac"
        #endif
        #endif
        body["timezone"] = TimeZone.current.identifier
        if let lang = Locale.current.language.languageCode?.identifier {
            body["language"] = lang
        }
        return body
    }

    /// "15.1" / "15.1.2" from `ProcessInfo` (works on every Apple platform).
    static func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
    }
}
