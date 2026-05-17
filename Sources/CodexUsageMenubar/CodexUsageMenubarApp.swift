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
final class StatusItemController {
    private let model = CodexStatusModel()
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 270, height: 320)
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
        button.attributedTitle = statusItemTitle()
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: model.primaryStatusText,
            attributes: [
                .font: font,
                .foregroundColor: model.primaryMenuBarTone.nsColor
            ]
        ))

        result.append(NSAttributedString(
            string: " | ",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        ))

        result.append(NSAttributedString(
            string: model.secondaryStatusText,
            attributes: [
                .font: font,
                .foregroundColor: model.secondaryMenuBarTone.nsColor
            ]
        ))

        return result
    }
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

            HStack(alignment: .top, spacing: 10) {
                Button {
                    Task {
                        await model.refresh()
                    }
                } label: {
                    Text("Refresh Now")
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
