import XCTest
@testable import TiboDog

final class CodexUsageTests: XCTestCase {
    func testPrefersCodexBucketAndDecodesResetSeconds() throws {
        let result = try CodexUsageAPI.decode([
            "rateLimits": ["primary": ["usedPercent": 99]],
            "rateLimitsByLimitId": [
                "codex": ["planType": "plus", "primary": ["usedPercent": 63, "windowDurationMins": 300, "resetsAt": 1789194640],
                          "secondary": ["usedPercent": 16, "windowDurationMins": 10080]],
                "other": ["primary": ["usedPercent": 100]]
            ]
        ])
        XCTAssertEqual(result.usage.fiveHour?.utilization, 63)
        XCTAssertEqual(result.usage.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1789194640))
        XCTAssertEqual(result.usage.fiveHour?.durationLabel, "5H")
        XCTAssertEqual(result.usage.sevenDay?.durationLabel, "7D")
        XCTAssertEqual(result.plan, "plus")
        XCTAssertNil(result.usage.sevenDayOpus)
        XCTAssertNil(result.resetCredits)
    }

    func testDecodesResetCredits() throws {
        let result = try CodexUsageAPI.decode([
            "rateLimits": ["primary": ["usedPercent": 1, "windowDurationMins": 300]],
            "rateLimitResetCredits": ["availableCount": 2]
        ])
        XCTAssertEqual(result.resetCredits, 2)
    }

    func testLegacySingleWindowAndNonStandardDuration() throws {
        let result = try CodexUsageAPI.decode(["rateLimits": ["primary": ["usedPercent": 0, "windowDurationMins": 15]]])
        XCTAssertEqual(result.usage.fiveHour?.percentText, "0%")
        XCTAssertEqual(result.usage.fiveHour?.durationLabel, "15M")
        XCTAssertNil(result.usage.sevenDay)
        XCTAssertNil(result.usage.fiveHour?.resetsAt)
    }

    func testMissingUsageIsNotZeroAndOtherBucketIsNotCodex() {
        XCTAssertThrowsError(try CodexUsageAPI.decode(["rateLimits": NSNull()]))
        XCTAssertThrowsError(try CodexUsageAPI.decode(["rateLimits": ["primary": ["resetsAt": 123]]]))
        XCTAssertThrowsError(try CodexUsageAPI.decode(["rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 12]]]]))
    }

    func testInvalidPercentageAndClamping() throws {
        XCTAssertThrowsError(try CodexUsageAPI.decode(["rateLimits": ["primary": ["usedPercent": Double.nan]]]))
        let result = try CodexUsageAPI.decode(["rateLimits": ["primary": ["usedPercent": 110]]])
        XCTAssertEqual(result.usage.fiveHour?.fraction, 1)
    }

    func testClaudeDecoderStillWorks() throws {
        let data = Data(#"{"five_hour":{"utilization":42,"resets_at":"2026-09-12T12:00:00Z"},"seven_day":{"utilization":71},"seven_day_opus":{"utilization":18}}"#.utf8)
        let usage = try Usage(json: data)
        XCTAssertEqual(usage.fiveHour?.utilization, 42)
        XCTAssertNotNil(usage.fiveHour?.resetsAt)
        XCTAssertEqual(usage.sevenDayOpus?.utilization, 18)
    }

    func testLiveCodexReadWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["TIBODOG_TEST_LIVE_CODEX"] == "1" else {
            throw XCTSkip("Set TIBODOG_TEST_LIVE_CODEX=1 to check the installed Codex login.")
        }
        let result = try CodexUsageAPI.fetch()
        XCTAssertTrue(result.usage.fiveHour != nil || result.usage.sevenDay != nil)
    }
}
