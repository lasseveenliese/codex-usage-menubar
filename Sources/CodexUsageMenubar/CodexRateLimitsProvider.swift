import Foundation

struct CodexRateLimitsSnapshot: Equatable {
    struct Credits: Equatable {
        let balance: String?
        let hasCredits: Bool
        let unlimited: Bool
    }

    struct Window: Equatable {
        let usedPercent: Int
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    let primary: Window
    let secondary: Window
    let credits: Credits?

    init(primary: Window, secondary: Window, credits: Credits? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
    }
}

enum StatusText {
    static func format(snapshot: CodexRateLimitsSnapshot) -> String {
        "5h \(availablePercent(from: snapshot.primary.usedPercent))% | 7d \(availablePercent(from: snapshot.secondary.usedPercent))%"
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

        if let liveSnapshot = try? appServerClient.fetchLatestSnapshot() {
            return liveSnapshot
        }

        return try scanLatestSnapshot()
    }

    private func scanLatestSnapshot() throws -> CodexRateLimitsSnapshot {
        let candidates = try candidateLogFiles()

        for url in candidates.prefix(12) {
            if let snapshot = try snapshotFromLogFile(url: url) {
                return snapshot
            }
        }

        throw CocoaError(.fileReadNoSuchFile)
    }

    private func candidateLogFiles() throws -> [URL] {
        let fileManager = FileManager.default
        let codexHome = codexHomeDirectory()
        let searchRoots = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions")
        ]

        var files: [(URL, Date)] = []

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                guard url.lastPathComponent.hasPrefix("rollout-") else { continue }

                let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                files.append((url, values.contentModificationDate ?? .distantPast))
            }
        }

        return files
            .sorted { lhs, rhs in
                lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private func snapshotFromLogFile(url: URL) throws -> CodexRateLimitsSnapshot? {
        let decoder = JSONDecoder()
        let contents = try String(contentsOf: url, encoding: .utf8)
        var latestSnapshot: CodexRateLimitsSnapshot?

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8) else { continue }
            guard let entry = try? decoder.decode(CodexLogEntry.self, from: data) else { continue }
            guard let rateLimits = entry.payload?.rateLimits else { continue }
            guard let primary = rateLimits.primary, let secondary = rateLimits.secondary else { continue }

            latestSnapshot = CodexRateLimitsSnapshot(
                primary: .init(
                    usedPercent: Int(primary.usedPercent.rounded()),
                    windowMinutes: primary.windowMinutes,
                    resetsAt: primary.resetsAt.map(Date.init(timeIntervalSince1970:))
                ),
                secondary: .init(
                    usedPercent: Int(secondary.usedPercent.rounded()),
                    windowMinutes: secondary.windowMinutes,
                    resetsAt: secondary.resetsAt.map(Date.init(timeIntervalSince1970:))
                ),
                credits: entry.payload?.rateLimits?.credits.map {
                    .init(balance: $0.balance, hasCredits: $0.hasCredits, unlimited: $0.unlimited)
                }
            )
        }

        return latestSnapshot
    }

    private func codexHomeDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
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
            primary: simulationWindow(
                displayPercent: primaryDisplayPercent,
                windowMinutes: 300,
                resetsAt: Calendar.current.date(byAdding: .hour, value: 5, to: now)
            ),
            secondary: simulationWindow(
                displayPercent: secondaryDisplayPercent,
                windowMinutes: 10_080,
                resetsAt: Calendar.current.date(byAdding: .day, value: 7, to: now)
            )
        )
    }

    private static func simulationWindow(
        displayPercent: Int,
        windowMinutes: Int,
        resetsAt: Date?
    ) -> CodexRateLimitsSnapshot.Window {
        let clampedDisplayPercent = max(0, min(100, displayPercent))
        return .init(
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

struct CodexLogEntry: Decodable {
    let payload: Payload?

    struct Payload: Decodable {
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
        }
    }
}

struct RateLimits: Decodable {
    let primary: Window?
    let secondary: Window?
    let credits: Credits?

    struct Window: Decodable {
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }
    }

    struct Credits: Decodable {
        let balance: String?
        let hasCredits: Bool
        let unlimited: Bool
    }
}
