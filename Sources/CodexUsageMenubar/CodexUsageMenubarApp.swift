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
            button.attributedTitle = statusItemTitle()
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
            button.attributedTitle = statusItemTitle()
        case .stacked:
            let image = MenuBarImageRenderer.stacked(
                primaryPercent: model.primaryAvailablePercent,
                secondaryPercent: model.secondaryAvailablePercent,
                primaryTone: model.primaryMenuBarTone,
                secondaryTone: model.secondaryMenuBarTone
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        case .rings:
            let image = MenuBarImageRenderer.rings(
                primaryPercent: model.primaryAvailablePercent,
                secondaryPercent: model.secondaryAvailablePercent,
                primaryTone: model.primaryMenuBarTone,
                secondaryTone: model.secondaryMenuBarTone
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.imagePosition = .imageOnly
            statusItem.length = image.size.width
        }

        button.toolTip = model.usageLoadFailed
            ? "Codex usage unavailable; availability is hidden until a verified refresh succeeds"
            : "Codex usage: \(model.primaryStatusText) | \(model.secondaryStatusText)"
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

    private func statusItemTitle() -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: model.primaryStatusText,
            attributes: [
                .font: MenuBarStyle.largeFont,
                .foregroundColor: model.primaryMenuBarTone.nsColor
            ]
        ))

        result.append(NSAttributedString(
            string: " | ",
            attributes: [
                .font: MenuBarStyle.largeFont,
                .foregroundColor: MenuBarStyle.hardTextColor
            ]
        ))

        result.append(NSAttributedString(
            string: model.secondaryStatusText,
            attributes: [
                .font: MenuBarStyle.largeFont,
                .foregroundColor: model.secondaryMenuBarTone.nsColor
            ]
        ))

        return result
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

    static func stacked(
        primaryPercent: Int?,
        secondaryPercent: Int?,
        primaryTone: MenuBarTone,
        secondaryTone: MenuBarTone
    ) -> NSImage {
        let columns = [
            MenuBarDisplayColumn(title: "5h", percent: primaryPercent, tone: primaryTone),
            MenuBarDisplayColumn(title: "7d", percent: secondaryPercent, tone: secondaryTone)
        ]
        let image = NSImage(size: NSSize(width: 60, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * 30
            drawCentered(
                column.title,
                in: NSRect(x: x, y: 12, width: 30, height: 9),
                font: MenuBarStyle.smallFont,
                color: MenuBarStyle.softTextColor
            )
            drawCentered(
                percentText(column.percent),
                in: NSRect(x: x, y: 0, width: 30, height: 13),
                font: MenuBarStyle.mediumFont,
                color: column.tone.nsColor
            )
        }

        image.isTemplate = primaryTone == .normal && secondaryTone == .normal
        return image
    }

    static func rings(
        primaryPercent: Int?,
        secondaryPercent: Int?,
        primaryTone: MenuBarTone,
        secondaryTone: MenuBarTone
    ) -> NSImage {
        let columns = [
            MenuBarDisplayColumn(title: "5h", percent: primaryPercent, tone: primaryTone),
            MenuBarDisplayColumn(title: "7d", percent: secondaryPercent, tone: secondaryTone)
        ]
        let image = NSImage(size: NSSize(width: 48, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * 24
            drawRing(
                percent: column.percent,
                tone: column.tone,
                center: NSPoint(x: x + 12, y: 11),
                radius: 8.5
            )
            drawCentered(
                column.title,
                in: NSRect(x: x + 2, y: 7, width: 20, height: 9),
                font: MenuBarStyle.smallFont,
                color: MenuBarStyle.hardTextColor
            )
        }

        image.isTemplate = primaryTone == .normal && secondaryTone == .normal
        return image
    }

    private static func drawRing(
        percent: Int?,
        tone: MenuBarTone,
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
        tone.nsColor.setStroke()
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

                AvailabilityBar(
                    title: "5h",
                    availablePercent: model.primaryAvailablePercent,
                    resetText: model.primaryResetText
                )

                AvailabilityBar(
                    title: "7d",
                    availablePercent: model.secondaryAvailablePercent,
                    resetText: model.secondaryResetText
                )
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
                        Button("Install Update") {
                            Task {
                                await model.installAvailableUpdate()
                            }
                        }

                        Button("Download") {
                            model.openAvailableUpdateDownload()
                        }
                    }

                    Button("Later") {
                        model.dismissAvailableUpdate()
                    }
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
