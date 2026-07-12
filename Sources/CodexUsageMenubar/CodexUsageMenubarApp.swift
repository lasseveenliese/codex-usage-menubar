import AppKit
import SwiftUI

@main
struct CodexUsageMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LaunchWindowView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }

    func applicationDidResignActive(_ notification: Notification) {
        statusItemController?.closePopover()
    }
}

@MainActor
private enum MenuBarStyle {
    static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
    static let mediumFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    static let largeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let hardTextColor = NSColor.labelColor
    static let softTextColor = NSColor.labelColor.withAlphaComponent(0.48)
}

private struct LaunchWindowView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex Usage Menubar added")
                .font(.headline)

            Text("The menu bar item is now running. You can close this window and use the icon at the top of the screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("Close Window") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let model = CodexStatusModel()
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var refreshAnimationTimer: Timer?
    private var refreshAnimationStartedAt: Date?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 270, height: 410)
        popover.contentViewController = NSHostingController(rootView: MenuContent(model: model))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Codex usage"
        }

        model.onChange = { [weak self] in
            self?.updateStatusItem()
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfNeeded(for: event)
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }

        Task {
            await model.start()
            updateStatusItem()
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.imagePosition = .noImage
        statusItem.length = NSStatusItem.variableLength

        switch model.menuBarDisplayMode {
        case .classic:
            let image = MenuBarImageRenderer.classic(
                columns: menuBarColumns,
                loadingProgress: refreshAnimationProgress,
                usesLightMenuBarText: usesLightMenuBarText
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        case .stacked:
            let image = MenuBarImageRenderer.stacked(
                columns: menuBarColumns,
                loadingProgress: refreshAnimationProgress,
                usesLightMenuBarText: usesLightMenuBarText
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        case .rings:
            let image = MenuBarImageRenderer.rings(
                columns: menuBarColumns,
                loadingProgress: refreshAnimationProgress,
                usesLightMenuBarText: usesLightMenuBarText
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        }

        button.toolTip = model.usageLoadFailed
            ? "Codex usage unavailable; availability is hidden until a verified refresh succeeds"
            : "Codex usage: \(model.statusText)"

        updateRefreshAnimationTimer()
    }

    private var refreshAnimationProgress: CGFloat? {
        guard model.isRefreshingUsage, let refreshAnimationStartedAt else { return nil }

        let elapsed = Date().timeIntervalSince(refreshAnimationStartedAt)
        return CGFloat((sin((elapsed / 0.42 * .pi) - (.pi / 2)) + 1) / 2)
    }

    private var menuBarColumns: [MenuBarDisplayColumn] {
        model.usageWindows.map { .init(title: $0.title, percent: $0.availablePercent, tone: $0.tone) }
    }

    private var usesLightMenuBarText: Bool {
        statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func updateRefreshAnimationTimer() {
        guard model.isRefreshingUsage else {
            refreshAnimationTimer?.invalidate()
            refreshAnimationTimer = nil
            refreshAnimationStartedAt = nil
            return
        }

        guard refreshAnimationTimer == nil else { return }
        refreshAnimationStartedAt = Date()
        refreshAnimationTimer = Timer.scheduledTimer(
            timeInterval: 1 / 30,
            target: self,
            selector: #selector(refreshAnimationTick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func refreshAnimationTick(_ timer: Timer) {
        updateStatusItem()
    }

    private func closePopoverIfNeeded(for event: NSEvent) {
        guard popover.isShown else { return }
        guard let popoverWindow = popover.contentViewController?.view.window else {
            closePopover()
            return
        }

        if event.window === popoverWindow || event.window === statusItem.button?.window {
            return
        }

        closePopover()
    }

}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        model.clearTransientUpdateStatus()
    }
}

@MainActor
private enum MenuBarImageRenderer {
    private static let height: CGFloat = 22

    static func classic(
        columns: [MenuBarDisplayColumn],
        loadingProgress: CGFloat?,
        usesLightMenuBarText: Bool
    ) -> NSImage {
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: MenuBarStyle.largeFont,
            .foregroundColor: menuBarTextColor(usesLightMenuBarText: usesLightMenuBarText)
        ]
        let separator = " | "
        let separatorWidth = (separator as NSString).size(withAttributes: separatorAttributes).width
        let entries = columns.map { column in
            let text = isPlaceholder(columns) ? "%" : "\(column.title) \(percentText(column.percent))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: MenuBarStyle.largeFont,
                .foregroundColor: displayColor(for: column.tone, usesLightMenuBarText: usesLightMenuBarText)
            ]
            return (text, attributes, (text as NSString).size(withAttributes: attributes).width)
        }
        let image = NSImage(size: NSSize(width: ceil(entries.reduce(0) { $0 + $1.2 } + CGFloat(max(0, entries.count - 1)) * separatorWidth), height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        let baselineY: CGFloat = 6
        var x: CGFloat = 0
        for (index, entry) in entries.enumerated() {
            (entry.0 as NSString).draw(at: NSPoint(x: x, y: baselineY), withAttributes: entry.1)
            x += entry.2
            if index < entries.count - 1 {
                (separator as NSString).draw(at: NSPoint(x: x, y: baselineY), withAttributes: separatorAttributes)
                x += separatorWidth
            }
        }
        drawLoadingBall(progress: loadingProgress, width: image.size.width, color: loadingColor(for: columns))

        image.isTemplate = columns.allSatisfy { $0.tone == .normal }
        return image
    }

    static func stacked(
        columns: [MenuBarDisplayColumn],
        loadingProgress: CGFloat?,
        usesLightMenuBarText: Bool
    ) -> NSImage {
        if isPlaceholder(columns) {
            return classic(columns: columns, loadingProgress: loadingProgress, usesLightMenuBarText: usesLightMenuBarText)
        }
        let image = NSImage(size: NSSize(width: CGFloat(columns.count) * 30, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * 30
            drawCentered(
                column.title,
                in: NSRect(x: x, y: 13, width: 30, height: 8),
                font: MenuBarStyle.smallFont,
                color: menuBarTextColor(usesLightMenuBarText: usesLightMenuBarText).withAlphaComponent(0.48)
            )
            drawCentered(
                percentText(column.percent),
                in: NSRect(x: x, y: 3, width: 30, height: 11),
                font: MenuBarStyle.mediumFont,
                color: displayColor(for: column.tone, usesLightMenuBarText: usesLightMenuBarText)
            )
        }

        drawLoadingBall(progress: loadingProgress, width: image.size.width, color: loadingColor(for: columns))

        image.isTemplate = columns.allSatisfy { $0.tone == .normal }
        return image
    }

    static func rings(
        columns: [MenuBarDisplayColumn],
        loadingProgress: CGFloat?,
        usesLightMenuBarText: Bool
    ) -> NSImage {
        if isPlaceholder(columns) {
            return classic(columns: columns, loadingProgress: loadingProgress, usesLightMenuBarText: usesLightMenuBarText)
        }
        let image = NSImage(size: NSSize(width: CGFloat(columns.count) * 24, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * 24
            drawRing(
                percent: column.percent,
                color: displayColor(for: column.tone, usesLightMenuBarText: usesLightMenuBarText),
                center: NSPoint(x: x + 12, y: 11),
                radius: 8.5
            )
            drawCentered(
                column.title,
                in: NSRect(x: x + 2, y: 7, width: 20, height: 9),
                font: MenuBarStyle.smallFont,
                color: menuBarTextColor(usesLightMenuBarText: usesLightMenuBarText)
            )
        }

        drawLoadingBall(progress: loadingProgress, width: image.size.width, color: loadingColor(for: columns))

        image.isTemplate = columns.allSatisfy { $0.tone == .normal }
        return image
    }

    private static func drawLoadingBall(progress: CGFloat?, width: CGFloat, color: NSColor) {
        guard let progress else { return }

        let radius: CGFloat = 1.75
        let horizontalInset: CGFloat = 3.5
        let minimumX = horizontalInset
        let maximumX = max(minimumX, width - horizontalInset)
        let center = NSPoint(x: minimumX + ((maximumX - minimumX) * progress), y: radius)
        let stretch = sin(.pi * progress)
        let ballWidth = (radius * 2) + (7 * stretch)

        let ball = NSBezierPath(
            roundedRect: NSRect(
                x: center.x - (ballWidth / 2),
                y: center.y - radius,
                width: ballWidth,
                height: radius * 2
            ),
            xRadius: radius,
            yRadius: radius
        )
        color.withAlphaComponent(0.86).setFill()
        ball.fill()
    }

    private static func loadingColor(for columns: [MenuBarDisplayColumn]) -> NSColor {
        columns.first(where: { $0.tone != .normal })?.tone.nsColor ?? .systemBlue
    }

    private static func displayColor(for tone: MenuBarTone, usesLightMenuBarText: Bool) -> NSColor {
        tone == .normal ? menuBarTextColor(usesLightMenuBarText: usesLightMenuBarText) : tone.nsColor
    }

    private static func menuBarTextColor(usesLightMenuBarText: Bool) -> NSColor {
        usesLightMenuBarText ? .white : MenuBarStyle.hardTextColor
    }

    private static func drawRing(
        percent: Int?,
        color: NSColor,
        center: NSPoint,
        radius: CGFloat
    ) {
        let progress = CGFloat(clampedPercent(percent) ?? 0) / 100
        guard progress > 0 else { return }

        let foregroundPath = NSBezierPath()
        foregroundPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - (360 * progress),
            clockwise: true
        )
        foregroundPath.lineWidth = 2.0
        foregroundPath.lineCapStyle = .round
        color.setStroke()
        foregroundPath.stroke()
    }

    private static func drawCentered(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )
        attributedString.draw(in: rect)
    }

    private static func percentText(_ percent: Int?) -> String {
        guard let percent = clampedPercent(percent) else { return "--%" }
        return "\(percent)%"
    }

    private static func isPlaceholder(_ columns: [MenuBarDisplayColumn]) -> Bool {
        columns.count == 1 && columns[0].title == "Usage" && columns[0].percent == nil
    }

    private static func clampedPercent(_ percent: Int?) -> Int? {
        percent.map { max(0, min(100, $0)) }
    }
}

private struct MenuBarDisplayColumn {
    let title: String
    let percent: Int?
    let tone: MenuBarTone
}

private struct MenuContent: View {
    @ObservedObject var model: CodexStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusText)
                    .font(.headline)
                    .monospacedDigit()

                Text("Version \(model.appVersionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let updateStatusText = model.updateStatusText {
                UpdateStatusView(model: model, text: updateStatusText)
            }

            if model.usageLoadFailed {
                Text("Live refresh failed. Availability is hidden until a verified refresh succeeds.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Menu Bar View")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("Menu Bar View", selection: $model.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Availability")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(model.usageWindows) { window in
                    AvailabilityBar(
                        title: window.title,
                        availablePercent: window.availablePercent,
                        resetText: window.resetText
                    )
                }
            }

            HStack {
                Text("Credits")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(model.creditsText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { newValue in
                    Task {
                        await model.setLaunchAtLoginEnabled(newValue)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .disabled(model.isUpdatingLaunchAtLogin)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        Task {
                            await model.refresh()
                        }
                    } label: {
                        Text(model.isRefreshingUsage ? "Refreshing..." : "Refresh Now")
                    }
                    .disabled(model.isRefreshingUsage)

                    Button {
                        Task {
                            await model.checkForUpdates()
                        }
                    } label: {
                        Text("Check for Updates")
                    }
                    .disabled(model.updateState.isBusy)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }

            HStack {
                Spacer()
                Text(model.lastUpdatedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 270)
    }
}

private struct UpdateStatusView: View {
    @ObservedObject var model: CodexStatusModel
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .available = model.updateState {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button("Install") {
                            Task {
                                await model.installAvailableUpdate()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Later") {
                            model.dismissAvailableUpdate()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Download untrusted DMG") {
                        model.openAvailableUpdateDownload()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension UpdateState {
    var isBusy: Bool {
        switch self {
        case .checking, .installing:
            return true
        case .idle, .available, .current, .failed:
            return false
        }
    }
}

private struct AvailabilityBar: View {
    let title: String
    let availablePercent: Int?
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(availableLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let fillWidth = proxy.size.width * CGFloat(max(0, min(100, availablePercent ?? 0))) / 100.0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.18))

                    Capsule()
                        .fill(barColor)
                        .frame(width: fillWidth)
                        .animation(.easeInOut(duration: 0.2), value: availablePercent)

                    markerLayer(width: proxy.size.width)
                }
            }
            .frame(height: 8)

            Text(resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var availableLabel: String {
        guard let availablePercent else { return "--%" }
        return "\(max(0, min(100, availablePercent)))%"
    }

    private var barColor: Color {
        guard let availablePercent else { return Color(nsColor: .secondarySystemFill) }

        switch availablePercent {
        case 25...100:
            return Color(nsColor: .systemGreen)
        case 10..<25:
            return Color(nsColor: .systemOrange)
        default:
            return Color(nsColor: .systemRed)
        }
    }

    @ViewBuilder
    private func markerLayer(width: CGFloat) -> some View {
        ForEach([10, 25, 50, 75], id: \.self) { mark in
            let x = width * CGFloat(mark) / 100.0

            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1, height: 10)
                .position(x: x, y: 4)
        }
    }
}
