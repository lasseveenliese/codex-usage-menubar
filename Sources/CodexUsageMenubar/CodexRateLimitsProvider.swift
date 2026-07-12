import Foundation

struct CodexRateLimitsSnapshot: Equatable {
    struct Credits: Equatable {
        let balance: String?
        let hasCredits: Bool
        let unlimited: Bool
    }

    struct Window: Equatable {
        let id: String
        let usedPercent: Int
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    let windows: [Window]
    let credits: Credits?

    init(windows: [Window], credits: Credits? = nil) {
        self.windows = windows
        self.credits = credits
    }

    var hasValidUsage: Bool {
        !windows.isEmpty && windows.allSatisfy { window in
            (0...100).contains(window.usedPercent)
                && window.windowMinutes.map { $0 > 0 } == true
                && window.resetsAt.map { $0.timeIntervalSince1970.isFinite } == true
        }
    }
}

enum StatusText {
    static func format(snapshot: CodexRateLimitsSnapshot) -> String {
        snapshot.windows.map { "\(windowTitle($0)) \(availablePercent(from: $0.usedPercent))%" }.joined(separator: " | ")
    }

    static func windowTitle(_ window: CodexRateLimitsSnapshot.Window) -> String {
        guard let minutes = window.windowMinutes else { return window.id }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    static func availablePercent(from usedPercent: Int) -> Int {
        max(0, 100 - usedPercent)
    }

    static func resetCountdownText(
        for window: CodexRateLimitsSnapshot.Window,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        guard let resetsAt = window.resetsAt else {
            return "resets --"
        }

        return "resets \(resetMomentString(for: resetsAt, now: now, timeZone: timeZone)) (in \(durationString(from: now, to: resetsAt)))"
    }

    static func updatedAtText(lastUpdatedAt: Date?, timeZone: TimeZone = .current) -> String {
        guard let lastUpdatedAt else {
            return "Updated --"
        }

        return "Updated \(dateTimeString(for: lastUpdatedAt, timeZone: timeZone))"
    }

    static func formattedCreditsBalance(_ balance: String) -> String {
        guard let value = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")) else {
            return balance
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0

        return formatter.string(from: value as NSDecimalNumber) ?? balance
    }

    static func shortClockString(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }

    static func dateTimeString(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter.string(from: date)
    }

    private static func resetMomentString(for date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if calendar.isDate(date, inSameDayAs: now) {
            return "at \(shortClockString(for: date, timeZone: timeZone))"
        }

        return "on \(shortWeekdayString(for: date, timeZone: timeZone)) \(shortClockString(for: date, timeZone: timeZone))"
    }

    private static func shortWeekdayString(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        return calendar.shortWeekdaySymbols[weekdayIndex]
    }

    private static func durationString(from now: Date, to future: Date) -> String {
        let remainingSeconds = max(0, Int(future.timeIntervalSince(now)))
        let hours = remainingSeconds / 3_600
        let minutes = (remainingSeconds % 3_600) / 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(max(0, minutes))m"
    }
}

final class CodexRateLimitsProvider {
    private let appServerClient = CodexAppServerRateLimitsClient()

    func fetchLatestSnapshot() throws -> CodexRateLimitsSnapshot {
        if let simulatedSnapshot = Self.simulationSnapshot(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        ) {
            return simulatedSnapshot
        }

        // Session logs can contain partial or stale rate-limit events. Showing
        // those as current availability is worse than reporting a refresh error.
        return try appServerClient.fetchLatestSnapshot()
    }

    static func simulationSnapshot(
        arguments: [String],
        environment: [String: String]
    ) -> CodexRateLimitsSnapshot? {
        guard
            let primaryDisplayPercent = launchInt(
                flag: "--simulate-primary-used-percent",
                environmentKeys: [
                    "CODEX_USAGE_MENUBAR_SIMULATE_PRIMARY_USED_PERCENT",
                    "CODEX_LIMITBAR_SIMULATE_PRIMARY_USED_PERCENT"
                ],
                arguments: arguments,
                environment: environment
            ),
            let secondaryDisplayPercent = launchInt(
                flag: "--simulate-secondary-used-percent",
                environmentKeys: [
                    "CODEX_USAGE_MENUBAR_SIMULATE_SECONDARY_USED_PERCENT",
                    "CODEX_LIMITBAR_SIMULATE_SECONDARY_USED_PERCENT"
                ],
                arguments: arguments,
                environment: environment
            )
        else {
            return nil
        }

        let now = Date()
        return CodexRateLimitsSnapshot(
            windows: [simulationWindow(
                id: "primary",
                displayPercent: primaryDisplayPercent,
                windowMinutes: 300,
                resetsAt: Calendar.current.date(byAdding: .hour, value: 5, to: now)
            ), simulationWindow(
                id: "secondary",
                displayPercent: secondaryDisplayPercent,
                windowMinutes: 10_080,
                resetsAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )]
        )
    }

    private static func simulationWindow(
        id: String,
        displayPercent: Int,
        windowMinutes: Int,
        resetsAt: Date?
    ) -> CodexRateLimitsSnapshot.Window {
        let clampedDisplayPercent = max(0, min(100, displayPercent))
        return .init(
            id: id,
            usedPercent: max(0, min(100, 100 - clampedDisplayPercent)),
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    private static func launchInt(
        flag: String,
        environmentKeys: [String],
        arguments: [String],
        environment: [String: String]
    ) -> Int? {
        guard let value = launchValue(flag: flag, environmentKeys: environmentKeys, arguments: arguments, environment: environment) else {
            return nil
        }

        return Int(value)
    }

    private static func launchValue(
        flag: String,
        environmentKeys: [String],
        arguments: [String],
        environment: [String: String]
    ) -> String? {
        if let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }

        for key in environmentKeys {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
