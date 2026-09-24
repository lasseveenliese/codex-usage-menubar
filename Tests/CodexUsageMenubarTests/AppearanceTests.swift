import XCTest
import SwiftUI
@testable import CodexUsageMenubar

final class AppearanceTests: XCTestCase {
    @MainActor
    func testGlassDefaultsOffAndRemembersBothChoices() {
        let suiteName = "AppearanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = CodexStatusModel(defaults: defaults)
        XCTAssertFalse(model.liquidGlassEnabled)
        model.liquidGlassEnabled = true
        XCTAssertTrue(CodexStatusModel(defaults: defaults).liquidGlassEnabled)
        model.liquidGlassEnabled = false
        XCTAssertFalse(CodexStatusModel(defaults: defaults).liquidGlassEnabled)
    }
    @MainActor
    func testPopupLayoutInBothStyles() throws {
        let suiteName = "AppearanceLayoutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CodexStatusModel(defaults: defaults, appVersion: "1.6.0")
        var sizes: [NSSize] = []

        for enabled in [false, true] {
            model.liquidGlassEnabled = enabled
            let view = NSHostingView(rootView: MenuContent(model: model).background(Color(nsColor: .windowBackgroundColor)))
            view.appearance = NSAppearance(named: .aqua)
            let size = view.fittingSize
            XCTAssertEqual(size.width, 270, accuracy: 1)
            XCTAssertGreaterThan(size.height, 300)
            sizes.append(size)
            view.setFrameSize(size)
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if let directory = ProcessInfo.processInfo.environment["POPUP_SNAPSHOT_DIRECTORY"],
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(enabled ? "glass.png" : "normal.png"))
            }
        }
        XCTAssertEqual(sizes[0], sizes[1], "Switching styles must preserve popup layout")
    }

}
