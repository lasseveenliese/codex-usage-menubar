import AppKit
import Combine
import Foundation

@MainActor
final class CodexStatusModel: ObservableObject {
    @Published var statusText = "Codex -- | weekly --"
    @Published private(set) var snapshot: CodexRateLimitsSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    var onChange: (() -> Void)?

    private let provider = CodexRateLimitsProvider()
    private var refreshLoopTask: Task<Void, Never>?

    deinit {
        refreshLoopTask?.cancel()
    }

    func start() async {
        await refresh()

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
        let nextSnapshot = await Task.detached(priority: .utility) { [provider] in
            try? provider.fetchLatestSnapshot()
        }.value

        snapshot = nextSnapshot
        statusText = nextSnapshot.map(StatusText.format(snapshot:)) ?? "Codex -- | weekly --"
        lastUpdatedAt = Date()
        onChange?()
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

    var lastUpdatedText: String {
        StatusText.updatedAtText(lastUpdatedAt: lastUpdatedAt)
    }

    var primaryMenuBarTone: MenuBarTone {
        MenuBarTone.from(availablePercent: primaryAvailablePercent ?? 100)
    }

    var secondaryMenuBarTone: MenuBarTone {
        MenuBarTone.from(availablePercent: secondaryAvailablePercent ?? 100)
    }

    private func statusSegmentText(title: String, availablePercent: Int?) -> String {
        guard let availablePercent else {
            return "\(title) --%"
        }

        return "\(title) \(max(0, min(100, availablePercent)))%"
    }
}

enum MenuBarTone {
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
