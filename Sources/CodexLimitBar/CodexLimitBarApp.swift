import AppKit
import SwiftUI

@main
struct CodexLimitBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }
}

@MainActor
final class StatusItemController {
    private let model = CodexStatusModel()
    private let statusItem: NSStatusItem
    private let popover: NSPopover

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

        Task {
            await model.start()
            updateStatusItem()
        }
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.attributedTitle = statusItemTitle()
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
                .foregroundColor: NSColor.black
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
            Text(model.statusText)
                .font(.headline)
                .monospacedDigit()

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
