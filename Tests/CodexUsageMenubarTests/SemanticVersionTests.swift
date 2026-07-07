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
