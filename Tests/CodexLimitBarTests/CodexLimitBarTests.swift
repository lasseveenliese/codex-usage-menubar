import Testing
import Foundation
@testable import CodexLimitBar

@Test
func formatsCurrentUsageText() {
    let snapshot = CodexRateLimitsSnapshot(
        primary: .init(usedPercent: 7, windowMinutes: 300, resetsAt: nil),
        secondary: .init(usedPercent: 12, windowMinutes: 10_080, resetsAt: nil)
    )

    #expect(StatusText.format(snapshot: snapshot) == "5h 93% | 7d 88%")
}

@Test
func clampsAvailableUsageAtZero() {
    let snapshot = CodexRateLimitsSnapshot(
        primary: .init(usedPercent: 120, windowMinutes: 300, resetsAt: nil),
        secondary: .init(usedPercent: 100, windowMinutes: 10_080, resetsAt: nil)
    )

    #expect(StatusText.format(snapshot: snapshot) == "5h 0% | 7d 0%")
}

@Test
func formatsResetCountdownText() {
    let now = Date(timeIntervalSince1970: 0)
    let resetsAt = Date(timeIntervalSince1970: 11_520)
    let window = CodexRateLimitsSnapshot.Window(usedPercent: 7, windowMinutes: 300, resetsAt: resetsAt)

    #expect(
        StatusText.resetCountdownText(
            for: window,
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "resets at 03:12 (in 3h 12m)"
    )
}

@Test
func formatsResetCountdownTextWithWeekdayWhenNotToday() {
    let now = Date(timeIntervalSince1970: 0)
    let resetsAt = Date(timeIntervalSince1970: 97_920)
    let window = CodexRateLimitsSnapshot.Window(usedPercent: 7, windowMinutes: 300, resetsAt: resetsAt)
    let text = StatusText.resetCountdownText(
        for: window,
        now: now,
        timeZone: TimeZone(secondsFromGMT: 0)!
    )

    #expect(text.hasPrefix("resets on "))
    #expect(text.contains(" (in "))
    #expect(text.contains("03:12"))
}

@Test
func formatsUpdatedAtText() {
    let lastUpdatedAt = Date(timeIntervalSince1970: 5_400)

    #expect(
        StatusText.updatedAtText(
            lastUpdatedAt: lastUpdatedAt,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "Updated 01.01.1970, 01:30"
    )
}

@Test
func choosesMenuBarToneByRemainingPercent() {
    #expect(MenuBarTone.from(availablePercent: 100) == .normal)
    #expect(MenuBarTone.from(availablePercent: 25) == .normal)
    #expect(MenuBarTone.from(availablePercent: 24) == .warning)
    #expect(MenuBarTone.from(availablePercent: 10) == .warning)
    #expect(MenuBarTone.from(availablePercent: 9) == .critical)
}

@Test
func parsesLogLineWithRateLimits() throws {
    let json = """
    {"timestamp":"2026-05-15T18:51:22.493Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1756305,"cached_input_tokens":1517568,"output_tokens":20365,"reasoning_output_tokens":15171,"total_tokens":1776670},"last_token_usage":{"input_tokens":99953,"cached_input_tokens":99200,"output_tokens":403,"reasoning_output_tokens":179,"total_tokens":100356},"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":7.0,"window_minutes":300,"resets_at":1778888701},"secondary":{"used_percent":12.0,"window_minutes":10080,"resets_at":1779202245},"credits":null,"plan_type":"plus","rate_limit_reached_type":null}}}
    """

    let decoder = JSONDecoder()
    let entry = try decoder.decode(CodexLogEntry.self, from: Data(json.utf8))
    let rateLimits = try #require(entry.payload?.rateLimits)
    let primary = try #require(rateLimits.primary)
    let secondary = try #require(rateLimits.secondary)

    #expect(Int(primary.usedPercent.rounded()) == 7)
    #expect(primary.windowMinutes == 300)
    #expect(Int(secondary.usedPercent.rounded()) == 12)
    #expect(secondary.windowMinutes == 10_080)
}

@Test
func parsesSimulationSnapshotFromEnvironment() {
    let environment = [
        "CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT": "18",
        "CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT": "9",
        "CODEX_LIMITBAR_SIMULATE_PRIMARY_RESETS_AT": "11520",
        "CODEX_LIMITBAR_SIMULATE_SECONDARY_RESETS_AT": "97920"
    ]

    let snapshot = try #require(CodexRateLimitsProvider.simulationSnapshot(environment: environment, now: Date(timeIntervalSince1970: 0)))

    #expect(snapshot.primary.usedPercent == 82)
    #expect(snapshot.secondary.usedPercent == 91)
    #expect(StatusText.format(snapshot: snapshot) == "5h 18% | 7d 9%")
    #expect(
        StatusText.resetCountdownText(
            for: snapshot.primary,
            now: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "resets at 03:12 (in 3h 12m)"
    )
    #expect(
        StatusText.resetCountdownText(
            for: snapshot.secondary,
            now: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        ).hasPrefix("resets on ")
    )
}

@Test
func parsesWarningCriticalPreset() {
    let environment = [
        "CODEX_LIMITBAR_SIMULATE_PRESET": "warning-critical"
    ]

    let snapshot = try #require(CodexRateLimitsProvider.simulationSnapshot(environment: environment, now: Date(timeIntervalSince1970: 0)))

    #expect(StatusText.format(snapshot: snapshot) == "5h 19% | 7d 7%")
}

@Test
func parsesSimulationSnapshotFromArguments() {
    let arguments = [
        "CodexLimitBar",
        "--simulate-primary-used-percent",
        "18",
        "--simulate-secondary-used-percent",
        "9"
    ]

    let snapshot = try #require(CodexRateLimitsProvider.simulationSnapshot(arguments: arguments, environment: [:], now: Date(timeIntervalSince1970: 0)))

    #expect(StatusText.format(snapshot: snapshot) == "5h 18% | 7d 9%")
}
