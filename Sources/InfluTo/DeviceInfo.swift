import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Builds the `/sdk/track-install` device-signals body. All values are Strings (so the
/// dictionary is Sendable and can cross the actor boundary). Uses `identifierForVendor`
/// (NOT IDFA) so no AppTrackingTransparency prompt is required.
enum DeviceInfo {
    @MainActor
    static func trackInstallBody() -> [String: String] {
        var body: [String: String] = ["platform": "ios", "device_brand": "Apple"]
        #if canImport(UIKit)
        body["os_version"] = UIDevice.current.systemVersion
        body["device_model"] = UIDevice.current.model
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            body["device_id"] = idfv
        }
        let b = UIScreen.main.nativeBounds
        body["screen_resolution"] = "\(Int(b.width))x\(Int(b.height))"
        #endif
        body["timezone"] = TimeZone.current.identifier
        if let lang = Locale.current.language.languageCode?.identifier {
            body["language"] = lang
        }
        return body
    }
}
