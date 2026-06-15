import XCTest
@testable import InfluTo

final class InfluToTests: XCTestCase {

    func testAppAccountTokenIsDeterministic() {
        let a = InfluTo.appAccountToken(forUserID: "user_123")
        let b = InfluTo.appAccountToken(forUserID: "user_123")
        let c = InfluTo.appAccountToken(forUserID: "user_456")
        XCTAssertEqual(a, b, "same user id must yield the same token across calls/launches")
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.uuid.6 & 0xF0, 0x50, "version-5 nibble")
        XCTAssertEqual(a.uuid.8 & 0xC0, 0x80, "RFC4122 variant")
    }

    func testAnyCodableRoundTrip() throws {
        let json = #"{"a":1,"b":"x","c":true,"d":[1,2],"e":{"f":null}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json)
        XCTAssertEqual(decoded["a"]?.value as? Int, 1)
        XCTAssertEqual(decoded["b"]?.value as? String, "x")
        XCTAssertEqual(decoded["c"]?.value as? Bool, true)
        // re-encode then re-decode is stable
        let reencoded = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode([String: AnyCodable].self, from: reencoded)
        XCTAssertEqual(again["b"]?.value as? String, "x")
    }

    func testCodeValidationResultDecodesSnakeCase() throws {
        let json = #"{"valid":false,"error":"Code not found or inactive","error_code":"CODE_NOT_FOUND"}"#
            .data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let r = try dec.decode(CodeValidationResult.self, from: json)
        XCTAssertFalse(r.valid)
        XCTAssertEqual(r.errorCode, "CODE_NOT_FOUND")
    }

    func testStorageKeysMatchContract() {
        XCTAssertEqual(Storage.attribution, "@influto/attribution")
        XCTAssertEqual(Storage.influtoCode, "@influto/influto_code")
        XCTAssertEqual(Storage.appUserId, "@influto/app_user_id")
        XCTAssertEqual(Storage.initialized, "@influto/initialized")
    }

    func testSentPurchaseDedupPersists() {
        let s = Storage()
        s.remove([Storage.sentPurchases])
        XCTAssertFalse(s.isPurchaseSent("1000000123"))
        s.markPurchaseSent("1000000123")
        XCTAssertTrue(s.isPurchaseSent("1000000123"))
        // a fresh Storage over the same suite sees it (cross-launch persistence)
        XCTAssertTrue(Storage().isPurchaseSent("1000000123"))
        XCTAssertFalse(Storage().isPurchaseSent("9999999999"))
        s.remove([Storage.sentPurchases])
    }

    func testPurchaseSyncResultShape() {
        let r = PurchaseSyncResult(fetched: 3, sent: 2, failed: 1, success: false)
        XCTAssertEqual(r.fetched, 3)
        XCTAssertEqual(r.sent, 2)
        XCTAssertFalse(r.success)
    }
}
