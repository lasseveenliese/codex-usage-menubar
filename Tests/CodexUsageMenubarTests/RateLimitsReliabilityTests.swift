import XCTest
@testable import CodexUsageMenubar

final class RateLimitsReliabilityTests: XCTestCase {
    func testIncompleteCodexResponseIsRejectedInsteadOfBecomingFullyAvailable() throws {
        let output = jsonRPCOutput(result: """
        {
          "rateLimits": {},
          "rateLimitsByLimitId": {
            "codex": {}
          }
        }
        """)

        XCTAssertThrowsError(try CodexAppServerRateLimitsClient().snapshot(fromJSONRPCOutput: output))
    }

    func testCompleteCodexResponseIsAccepted() throws {
        let output = jsonRPCOutput(result: """
        {
          "rateLimits": {},
          "rateLimitsByLimitId": {
            "codex": {
              "primary": {"usedPercent": 22, "windowDurationMins": 300, "resetsAt": 1783651484},
              "secondary": {"usedPercent": 3, "windowDurationMins": 10080, "resetsAt": 1784238284}
            }
          }
        }
        """)

        let snapshot = try CodexAppServerRateLimitsClient().snapshot(fromJSONRPCOutput: output)

        XCTAssertEqual(snapshot.primary.usedPercent, 22)
        XCTAssertEqual(snapshot.secondary.usedPercent, 3)
    }

    func testRateLimitNotificationCannotFillIncompleteResponse() {
        let notification = """
        {"method":"account/rateLimits/updated","params":{"rateLimits":{"primary":{"usedPercent":22,"windowDurationMins":300},"secondary":{"usedPercent":3,"windowDurationMins":10080}}}}
        """
        let response = jsonRPCOutput(result: """
        {
          "rateLimits": {},
          "rateLimitsByLimitId": {
            "codex": {}
          }
        }
        """)
        let output = Data(notification.utf8) + Data([0x0A]) + response

        XCTAssertThrowsError(try CodexAppServerRateLimitsClient().snapshot(fromJSONRPCOutput: output))
    }

    func testOutOfRangeUsageIsRejected() {
        let snapshot = CodexRateLimitsSnapshot(
            primary: .init(usedPercent: -1, windowMinutes: 300, resetsAt: nil),
            secondary: .init(usedPercent: 101, windowMinutes: 10_080, resetsAt: nil)
        )

        XCTAssertFalse(snapshot.hasValidUsage)
    }

    func testSnapshotWithoutResetTimesIsRejected() {
        let snapshot = CodexRateLimitsSnapshot(
            primary: .init(usedPercent: 22, windowMinutes: 300, resetsAt: nil),
            secondary: .init(usedPercent: 3, windowMinutes: 10_080, resetsAt: nil)
        )

        XCTAssertFalse(snapshot.hasValidUsage)
    }

    func testNearFullAvailabilityBeforeResetIsRejected() {
        let now = Date(timeIntervalSince1970: 2_000)
        let previous = CodexRateLimitsSnapshot(
            primary: .init(usedPercent: 80, windowMinutes: 300, resetsAt: now.addingTimeInterval(1_000)),
            secondary: .init(usedPercent: 60, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(1_000))
        )
        let next = CodexRateLimitsSnapshot(
            primary: .init(usedPercent: 0, windowMinutes: 300, resetsAt: now.addingTimeInterval(900)),
            secondary: .init(usedPercent: 10, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(900))
        )

        XCTAssertFalse(CodexStatusModel.isReliableTransition(from: previous, to: next, now: now))
    }

    private func jsonRPCOutput(result: String) -> Data {
        let resultObject = try! JSONSerialization.jsonObject(with: Data(result.utf8))
        return try! JSONSerialization.data(withJSONObject: ["id": 2, "result": resultObject])
    }
}
