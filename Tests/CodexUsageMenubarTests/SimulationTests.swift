import XCTest
@testable import CodexUsageMenubar

final class SimulationTests: XCTestCase {
    func testNewAndLegacyArgumentsRepresentAvailablePercent() {
        for suffix in ["available-percent", "used-percent"] {
            let snapshot = CodexRateLimitsProvider.simulationSnapshot(
                arguments: ["app", "--simulate-primary-\(suffix)", "75", "--simulate-secondary-\(suffix)", "20"],
                environment: [:]
            )
            XCTAssertEqual(snapshot?.windows.map(\.usedPercent), [25, 80])
        }
    }

    func testNewEnvironmentNamesTakePrecedenceOverLegacyNames() {
        let snapshot = CodexRateLimitsProvider.simulationSnapshot(arguments: [], environment: [
            "CODEX_USAGE_MENUBAR_SIMULATE_PRIMARY_AVAILABLE_PERCENT": "75",
            "CODEX_USAGE_MENUBAR_SIMULATE_SECONDARY_AVAILABLE_PERCENT": "20",
            "CODEX_USAGE_MENUBAR_SIMULATE_PRIMARY_USED_PERCENT": "1",
            "CODEX_USAGE_MENUBAR_SIMULATE_SECONDARY_USED_PERCENT": "2"
        ])
        XCTAssertEqual(snapshot?.windows.map(\.usedPercent), [25, 80])
    }

    func testLegacyEnvironmentNamesRemainSupported() {
        for prefix in ["CODEX_USAGE_MENUBAR", "CODEX_LIMITBAR"] {
            let snapshot = CodexRateLimitsProvider.simulationSnapshot(arguments: [], environment: [
                "\(prefix)_SIMULATE_PRIMARY_USED_PERCENT": "75",
                "\(prefix)_SIMULATE_SECONDARY_USED_PERCENT": "20"
            ])
            XCTAssertEqual(snapshot?.windows.map(\.usedPercent), [25, 80])
        }
    }

    func testWarningThresholds() {
        XCTAssertEqual(MenuBarTone.from(availablePercent: 9), .critical)
        XCTAssertEqual(MenuBarTone.from(availablePercent: 10), .warning)
        XCTAssertEqual(MenuBarTone.from(availablePercent: 24), .warning)
        XCTAssertEqual(MenuBarTone.from(availablePercent: 25), .normal)
    }
}
