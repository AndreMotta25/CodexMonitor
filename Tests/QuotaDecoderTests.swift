import XCTest
@testable import CodexMonitorCore

final class QuotaDecoderTests: XCTestCase {
    func testRealWireShapeAndRemainingPercent() throws {
        let data = Data(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":1793400000},"secondary_window":{"used_percent":100,"limit_window_seconds":604800,"reset_at":1794000000}}}"#.utf8)
        let now = Date(timeIntervalSince1970: 1793390000)
        let snapshot = try QuotaDecoder.decode(data, at: now)
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [75, 0])
        XCTAssertEqual(snapshot.windows.first?.resetsAt?.timeIntervalSince1970, 1793400000)
        XCTAssertEqual(snapshot.windows.first?.durationLabel, "5 horas")
        XCTAssertEqual(snapshot.windows.last?.durationLabel, "7 dias")
        XCTAssertFalse(snapshot.isStale(at: now))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(1800)))
    }

    func testAdditionalBucketsAndSelection() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":0}},"additional_rate_limits":[{"limit_name":"extra","rate_limit":{"primary_window":{"used_percent":60,"limit_window_seconds":7200}}}]}"#.utf8)
        var snapshot = try QuotaDecoder.decode(data)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 100)
        snapshot.selectedWindowID = snapshot.windows.last?.id
        XCTAssertEqual(snapshot.selectedWindow?.remainingPercent, 40)
        snapshot.selectedWindowID = "removed-bucket"
        XCTAssertEqual(snapshot.selectedWindow?.id, snapshot.windows.first?.id)
    }

    func testMissingAndMalformedDataNeverBecomesZeroUsage() {
        for json in ["{}", #"{"rate_limit":{"primary_window":{}}}"#,
                     #"{"rate_limit":{"primary_window":{"used_percent":101}}}"#,
                     #"{"rate_limit":{"primary_window":{"used_percent":-1}}}"#,
                     #"{"rate_limit":{"primary_window":{"used_percent":20,"reset_at":-1}}}"#,
                     #"{"rate_limit":{"primary_window":{"used_percent":"25"}}}"#] {
            XCTAssertThrowsError(try QuotaDecoder.decode(Data(json.utf8)), json)
        }
    }

    func testPassingResetMarksStaleWithoutInventingRenewedQuota() throws {
        let now = Date(timeIntervalSince1970: 1793399990)
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1793400000}}}"#.utf8)
        let snapshot = try QuotaDecoder.decode(data, at: now)
        XCTAssertFalse(snapshot.isStale(at: now))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(11)))
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 0)
    }

    func testCacheRoundTripAndFailurePreserveTimestamp() throws {
        let data = Data(#"{"rate_limit":{"primary_window":{"used_percent":35}}}"#.utf8)
        var snapshot = try QuotaDecoder.decode(data)
        let fetchedAt = snapshot.fetchedAt
        snapshot.status = .offline
        let cached = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(cached.fetchedAt, fetchedAt)
        XCTAssertEqual(cached.windows.first?.remainingPercent, 65)
        XCTAssertTrue(cached.isStale(at: fetchedAt))
    }
}
