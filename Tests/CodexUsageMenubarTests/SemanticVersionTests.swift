import XCTest
@testable import CodexUsageMenubar

final class SemanticVersionTests: XCTestCase {
    func testNewerPatchVersionComparesGreater() {
        XCTAssertGreaterThan(SemanticVersion("1.2.0")!, SemanticVersion("1.1.3")!)
    }

    func testSameVersionDoesNotCompareGreater() {
        XCTAssertFalse(SemanticVersion("1.1.3")! > SemanticVersion("1.1.3")!)
    }

    func testOlderPatchVersionDoesNotCompareGreater() {
        XCTAssertFalse(SemanticVersion("1.1.2")! > SemanticVersion("1.1.3")!)
    }

    func testInvalidVersionIsRejected() {
        XCTAssertNil(SemanticVersion("1.2"))
        XCTAssertNil(SemanticVersion("1.2.beta"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
    }

    func testUpdateCheckerReturnsAvailableUpdateFromManifest() async throws {
        let manifestURL = try writeManifest(version: "1.2.0")
        let result = try await UpdateChecker(manifestURL: manifestURL).check(currentVersion: "1.1.3")

        guard case .available(let update) = result else {
            return XCTFail("Expected available update")
        }

        XCTAssertEqual(update.version, "1.2.0")
        XCTAssertEqual(update.downloadUrl.absoluteString, "https://example.com/CodexUsageMenubar.dmg")
        XCTAssertEqual(update.zipUrl?.absoluteString, "https://example.com/CodexUsageMenubar.app.zip")
        XCTAssertEqual(update.sha256, "abc123")
    }

    func testUpdateCheckerReturnsCurrentForSameVersion() async throws {
        let manifestURL = try writeManifest(version: "1.1.3")
        let result = try await UpdateChecker(manifestURL: manifestURL).check(currentVersion: "1.1.3")

        XCTAssertEqual(result, .current)
    }

    func testUpdateCheckerRejectsInvalidRemoteVersion() async throws {
        let manifestURL = try writeManifest(version: "latest")

        do {
            _ = try await UpdateChecker(manifestURL: manifestURL).check(currentVersion: "1.1.3")
            XCTFail("Expected invalid remote version error")
        } catch UpdateCheckError.invalidRemoteVersion {
        }
    }

    func testMinimumMacOSCompatibility() {
        let current = OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 1)
        for (minimum, expected) in [("14", true), ("14.2", true), ("14.2.1", true),
                                    ("14.2.2", false), ("15.0", false), ("invalid", false),
                                    ("14..0", false), ("14.0.0.0", false)] {
            let update = AvailableUpdate(
                version: "2.0.0", downloadUrl: URL(string: "https://example.com/app.dmg")!,
                zipUrl: nil, sha256: nil, releaseUrl: URL(string: "https://example.com/release")!,
                minimumMacOS: minimum
            )
            XCTAssertEqual(update.supports(current), expected, minimum)
        }
    }

    @MainActor
    func testManualCheckShowsDismissedUpdateAgain() async throws {
        let manifestURL = try writeManifest(version: "99.0.0")
        defer { try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent()) }
        let suiteName = "UpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CodexStatusModel(updateChecker: UpdateChecker(manifestURL: manifestURL), defaults: defaults, appVersion: "1.5.3")
        await model.checkForUpdates()
        model.dismissAvailableUpdate()
        XCTAssertEqual(model.updateState, .current(showStatus: false))

        let automaticModel = CodexStatusModel(updateChecker: UpdateChecker(manifestURL: manifestURL), defaults: defaults, appVersion: "1.5.3")
        defaults.removeObject(forKey: "lastUpdateCheckAt")
        let dueModel = CodexStatusModel(updateChecker: UpdateChecker(manifestURL: manifestURL), defaults: defaults, appVersion: "1.5.3")
        await dueModel.checkForUpdatesIfNeeded()
        XCTAssertEqual(dueModel.updateState, .current(showStatus: false))
        await automaticModel.checkForUpdates()
        guard case .available(let update) = automaticModel.updateState else {
            return XCTFail("Manual checks must show dismissed updates")
        }
        XCTAssertEqual(update.version, "99.0.0")
    }

    @MainActor
    func testAutomaticCheckWaitsTwelveHours() async throws {
        let manifestURL = try writeManifest(version: "99.0.0")
        defer { try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent()) }
        let suiteName = "UpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheckAt")
        let recentModel = CodexStatusModel(updateChecker: UpdateChecker(manifestURL: manifestURL), defaults: defaults, appVersion: "1.5.3")
        await recentModel.checkForUpdatesIfNeeded()
        XCTAssertEqual(recentModel.updateState, .idle)

        defaults.set(Date().addingTimeInterval(-13 * 60 * 60).timeIntervalSince1970, forKey: "lastUpdateCheckAt")
        let dueModel = CodexStatusModel(updateChecker: UpdateChecker(manifestURL: manifestURL), defaults: defaults, appVersion: "1.5.3")
        await dueModel.checkForUpdatesIfNeeded()
        guard case .available = dueModel.updateState else { return XCTFail("Expected overdue check") }
    }

    @MainActor
    func testFailedCheckShowsErrorAndCanRetry() async throws {
        let manifestURL = try writeManifest(version: "invalid")
        defer { try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent()) }
        let suiteName = "UpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CodexStatusModel(updateChecker: UpdateChecker(manifestURL: manifestURL), defaults: defaults, appVersion: "1.5.3")
        await model.checkForUpdates()
        XCTAssertEqual(model.updateState, .failed)
        XCTAssertNotNil(model.updateErrorText)
        let contents = try String(contentsOf: manifestURL, encoding: .utf8)
        try contents.replacingOccurrences(of: "invalid", with: "99.0.0").write(to: manifestURL, atomically: true, encoding: .utf8)
        await model.checkForUpdates()
        XCTAssertNil(model.updateErrorText)
        guard case .available = model.updateState else { return XCTFail("Expected successful retry") }
    }

    private func writeManifest(version: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("update.json")
        let json = """
        {
          "version": "\(version)",
          "downloadUrl": "https://example.com/CodexUsageMenubar.dmg",
          "zipUrl": "https://example.com/CodexUsageMenubar.app.zip",
          "sha256": "abc123",
          "releaseUrl": "https://example.com/releases/latest",
          "minimumMacOS": "14.0"
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
