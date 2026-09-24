import XCTest
import SwiftUI
@testable import CodexUsageMenubar

final class AppearanceTests: XCTestCase {
    @MainActor
    func testNativePopupLayoutIgnoresLegacyGlassPreference() {
        let suiteName = "AppearanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var sizes: [NSSize] = []

        for legacyGlassEnabled in [false, true] {
            defaults.set(legacyGlassEnabled, forKey: "liquidGlassEnabled")
            let model = CodexStatusModel(defaults: defaults, appVersion: "1.6.1")
            let view = NSHostingView(rootView: MenuContent(model: model))
            let size = view.fittingSize
            XCTAssertEqual(size.width, 270, accuracy: 1)
            XCTAssertGreaterThan(size.height, 300)
            sizes.append(size)
        }
        XCTAssertEqual(sizes[0], sizes[1])
    }
}
