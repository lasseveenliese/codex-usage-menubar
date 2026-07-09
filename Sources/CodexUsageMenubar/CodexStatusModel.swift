import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class CodexStatusModel: ObservableObject {
    private static let launchAtLoginPreferenceKey = "launchAtLoginEnabled"
    private static let menuBarDisplayModePreferenceKey = "menuBarDisplayMode"
    private static let lastUpdateCheckAtPreferenceKey = "lastUpdateCheckAt"
    private static let dismissedUpdateVersionPreferenceKey = "dismissedUpdateVersion"
    private static let updateCheckInterval: TimeInterval = 12 * 60 * 60

    @Published var statusText = "Codex -- | weekly --"
    @Published private(set) var snapshot: CodexRateLimitsSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var updateState: UpdateState = .idle {
        didSet {
            scheduleCurrentStatusDismissalIfNeeded()
        }
    }
    @Published private(set) var lastUpdateCheckAt: Date?
    @Published var launchAtLoginEnabled: Bool
    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            storeMenuBarDisplayMode(menuBarDisplayMode)
            onChange?()
        }
    }
    @Published private(set) var isUpdatingLaunchAtLogin = false
    var onChange: (() -> Void)?

    private let updateChecker = UpdateChecker()
    private let updateInstaller = UpdateInstaller()
    private var refreshLoopTask: Task<Void, Never>?
    private var transientUpdateStatusTask: Task<Void, Never>?

    init() {
        launchAtLoginEnabled = Self.readLaunchAtLoginPreference()
        menuBarDisplayMode = Self.readMenuBarDisplayMode()
        lastUpdateCheckAt = Self.readLastUpdateCheckAt()
    }

    deinit {
        refreshLoopTask?.cancel()
        transientUpdateStatusTask?.cancel()
    }

    func start() async {
        await refresh()
        await checkForUpdatesIfNeeded()

        guard refreshLoopTask == nil else { return }
        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        let nextSnapshot = await Task.detached(priority: .utility) {
            try? CodexRateLimitsProvider().fetchLatestSnapshot()
        }.value

        snapshot = nextSnapshot
        statusText = nextSnapshot.map(StatusText.format(snapshot:)) ?? "Codex -- | weekly --"
        lastUpdatedAt = Date()
        onChange?()
    }

    func checkForUpdatesIfNeeded() async {
        guard shouldCheckForUpdates else { return }
        await checkForUpdates(force: false)
    }

    func checkForUpdates(force: Bool = true) async {
        if case .checking = updateState {
            return
        }

        if case .installing = updateState {
            return
        }

        if !force, !shouldCheckForUpdates {
            return
        }

        updateState = .checking
        do {
            let result = try await updateChecker.check(currentVersion: appVersionText)
            let checkedAt = Date()
            lastUpdateCheckAt = checkedAt
            storeLastUpdateCheckAt(checkedAt)

            switch result {
            case .current:
                updateState = .current(showStatus: force)
            case .available(let update):
                updateState = isDismissed(update) ? .current(showStatus: false) : .available(update)
            }
        } catch {
            let checkedAt = Date()
            lastUpdateCheckAt = checkedAt
            storeLastUpdateCheckAt(checkedAt)
            updateState = .failed
        }
    }

    func dismissAvailableUpdate() {
        guard case .available(let update) = updateState else { return }
        UserDefaults.standard.set(update.version, forKey: Self.dismissedUpdateVersionPreferenceKey)
        updateState = .current(showStatus: false)
    }

    func clearTransientUpdateStatus() {
        guard case .current(showStatus: true) = updateState else { return }
        updateState = .current(showStatus: false)
    }

    func openAvailableUpdateDownload() {
        guard case .available(let update) = updateState else { return }
        NSWorkspace.shared.open(update.downloadUrl)
    }

    func installAvailableUpdate() async {
        guard case .available(let update) = updateState else { return }
        guard update.canInstallInApp else {
            NSWorkspace.shared.open(update.downloadUrl)
            return
        }

        updateState = .installing(update)
        do {
            try await updateInstaller.install(update: update)
            NSApplication.shared.terminate(nil)
        } catch {
            updateState = .available(update)
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) async {
        guard !isUpdatingLaunchAtLogin else { return }
        let previousValue = launchAtLoginEnabled
        launchAtLoginEnabled = enabled
        storeLaunchAtLoginPreference(enabled)
        isUpdatingLaunchAtLogin = true
        defer {
            isUpdatingLaunchAtLogin = false
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginEnabled = previousValue
            storeLaunchAtLoginPreference(previousValue)
        }
    }

    var primaryAvailablePercent: Int? {
        snapshot.map { StatusText.availablePercent(from: $0.primary.usedPercent) }
    }

    var secondaryAvailablePercent: Int? {
        snapshot.map { StatusText.availablePercent(from: $0.secondary.usedPercent) }
    }

    var primaryStatusText: String {
        statusSegmentText(title: "5h", availablePercent: primaryAvailablePercent)
    }

    var secondaryStatusText: String {
        statusSegmentText(title: "7d", availablePercent: secondaryAvailablePercent)
    }

    var primaryResetText: String {
        guard let snapshot else {
            return "resets --"
        }

        return StatusText.resetCountdownText(for: snapshot.primary)
    }

    var secondaryResetText: String {
        guard let snapshot else {
            return "resets --"
        }

        return StatusText.resetCountdownText(for: snapshot.secondary)
    }

    var creditsText: String {
        guard let credits = snapshot?.credits else {
            return "--"
        }

        if credits.unlimited {
            return "unlimited"
        }

        if let balance = credits.balance, !balance.isEmpty {
            return StatusText.formattedCreditsBalance(balance)
        }

        return credits.hasCredits ? "available" : "0"
    }

    var lastUpdatedText: String {
        StatusText.updatedAtText(lastUpdatedAt: lastUpdatedAt)
    }

    var appVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.3"
    }

    var updateStatusText: String? {
        switch updateState {
        case .checking:
            return "Checking for updates..."
        case .current(showStatus: true):
            return "Up to date"
        case .available(let update):
            return "Update \(update.version) available"
        case .installing:
            return "Installing update..."
        case .idle, .current(showStatus: false), .failed:
            return nil
        }
    }

    var primaryMenuBarTone: MenuBarTone {
        MenuBarTone.from(availablePercent: primaryAvailablePercent ?? 100)
    }

    var secondaryMenuBarTone: MenuBarTone {
        MenuBarTone.from(availablePercent: secondaryAvailablePercent ?? 100)
    }

    private static func readLaunchAtLoginPreference() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.launchAtLoginPreferenceKey) != nil {
            return defaults.bool(forKey: Self.launchAtLoginPreferenceKey)
        }

        return SMAppService.mainApp.status == .enabled
    }

    private func storeLaunchAtLoginPreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.launchAtLoginPreferenceKey)
    }

    private static func readMenuBarDisplayMode() -> MenuBarDisplayMode {
        guard let rawValue = UserDefaults.standard.string(forKey: Self.menuBarDisplayModePreferenceKey) else {
            return .classic
        }

        return MenuBarDisplayMode(rawValue: rawValue) ?? .classic
    }

    private func storeMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.menuBarDisplayModePreferenceKey)
    }

    private var shouldCheckForUpdates: Bool {
        guard let lastUpdateCheckAt else {
            return true
        }

        return Date().timeIntervalSince(lastUpdateCheckAt) >= Self.updateCheckInterval
    }

    private static func readLastUpdateCheckAt() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: Self.lastUpdateCheckAtPreferenceKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func storeLastUpdateCheckAt(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastUpdateCheckAtPreferenceKey)
    }

    private func isDismissed(_ update: AvailableUpdate) -> Bool {
        UserDefaults.standard.string(forKey: Self.dismissedUpdateVersionPreferenceKey) == update.version
    }

    private func scheduleCurrentStatusDismissalIfNeeded() {
        transientUpdateStatusTask?.cancel()
        guard case .current(showStatus: true) = updateState else { return }

        transientUpdateStatusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.clearTransientUpdateStatus()
        }
    }

    private func statusSegmentText(title: String, availablePercent: Int?) -> String {
        guard let availablePercent else {
            return "\(title) --%"
        }

        return "\(title) \(max(0, min(100, availablePercent)))%"
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case available(AvailableUpdate)
    case installing(AvailableUpdate)
    case current(showStatus: Bool)
    case failed
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case classic
    case stacked
    case rings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:
            return "Classic"
        case .stacked:
            return "Compact"
        case .rings:
            return "Rings"
        }
    }
}

enum MenuBarTone: Equatable {
    case normal
    case warning
    case critical

    static func from(availablePercent: Int) -> MenuBarTone {
        if availablePercent < 10 {
            return .critical
        }

        if availablePercent < 25 {
            return .warning
        }

        return .normal
    }

    var nsColor: NSColor {
        switch self {
        case .normal:
            return .labelColor
        case .warning:
            return .systemOrange
        case .critical:
            return .systemRed
        }
    }
}
