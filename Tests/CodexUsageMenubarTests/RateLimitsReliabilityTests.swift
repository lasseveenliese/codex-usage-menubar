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

        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [22, 3])
    }

    func testSinglePrimaryWindowResponseIsAcceptedAndUsesItsReportedDuration() throws {
        let output = jsonRPCOutput(result: """
        {
          "rateLimits": {},
          "rateLimitsByLimitId": {
            "codex": {
              "primary": {"usedPercent": 3, "windowDurationMins": 43200, "resetsAt": 1784238284}
            }
          }
        }
        """)

        let snapshot = try CodexAppServerRateLimitsClient().snapshot(fromJSONRPCOutput: output)

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 3)
        XCTAssertEqual(StatusText.windowTitle(snapshot.windows[0]), "30d")
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
            windows: [
                .init(id: "primary", usedPercent: -1, windowMinutes: 300, resetsAt: nil),
                .init(id: "secondary", usedPercent: 101, windowMinutes: 10_080, resetsAt: nil)
            ]
        )

        XCTAssertFalse(snapshot.hasValidUsage)
    }

    func testSnapshotWithoutResetTimesIsRejected() {
        let snapshot = CodexRateLimitsSnapshot(
            windows: [
                .init(id: "primary", usedPercent: 22, windowMinutes: 300, resetsAt: nil),
                .init(id: "secondary", usedPercent: 3, windowMinutes: 10_080, resetsAt: nil)
            ]
        )

        XCTAssertFalse(snapshot.hasValidUsage)
    }

    func testNearFullAvailabilityBeforeResetIsRejected() {
        let now = Date(timeIntervalSince1970: 2_000)
        let previous = CodexRateLimitsSnapshot(
            windows: [
                .init(id: "primary", usedPercent: 80, windowMinutes: 300, resetsAt: now.addingTimeInterval(1_000)),
                .init(id: "secondary", usedPercent: 60, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(1_000))
            ]
        )
        let next = CodexRateLimitsSnapshot(
            windows: [
                .init(id: "primary", usedPercent: 0, windowMinutes: 300, resetsAt: now.addingTimeInterval(900)),
                .init(id: "secondary", usedPercent: 10, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(900))
            ]
        )

        XCTAssertFalse(CodexStatusModel.isReliableTransition(from: previous, to: next, now: now))
    }

    private func jsonRPCOutput(result: String) -> Data {
        let resultObject = try! JSONSerialization.jsonObject(with: Data(result.utf8))
        return try! JSONSerialization.data(withJSONObject: ["id": 2, "result": resultObject])
    }
}
