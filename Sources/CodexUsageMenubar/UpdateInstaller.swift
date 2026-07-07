import CryptoKit
import Foundation

enum UpdateInstallerError: Error {
    case missingPackage
    case checksumMismatch
    case missingAppBundle
    case missingExecutable
}

struct UpdateInstaller {
    private static let appBundleName = "Codex Usage Menubar.app"

    func install(update: AvailableUpdate, currentAppURL: URL = Bundle.main.bundleURL) async throws {
        guard let zipURL = update.zipUrl, let expectedSHA256 = update.sha256 else {
            throw UpdateInstallerError.missingPackage
        }

        let tempDirectory = try createTempDirectory()
        let archiveURL = tempDirectory.appendingPathComponent("CodexUsageMenubar.app.zip")
        let extractDirectory = tempDirectory.appendingPathComponent("extracted", isDirectory: true)

        do {
            let (downloadedURL, response) = try await URLSession.shared.download(from: zipURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw UpdateCheckError.invalidHTTPStatus(httpResponse.statusCode)
            }

            try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
            guard try sha256Hex(for: archiveURL).caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                throw UpdateInstallerError.checksumMismatch
            }

            try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
            try runProcess(executablePath: "/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, extractDirectory.path])

            let newAppURL = extractDirectory.appendingPathComponent(Self.appBundleName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: newAppURL.path) else {
                throw UpdateInstallerError.missingAppBundle
            }

            try launchInstallerScript(newAppURL: newAppURL, currentAppURL: currentAppURL, tempDirectory: tempDirectory)
        } catch {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }
    }

    private func createTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-usage-menubar-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func launchInstallerScript(newAppURL: URL, currentAppURL: URL, tempDirectory: URL) throws {
        guard let executableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              !executableName.isEmpty else {
            throw UpdateInstallerError.missingExecutable
        }

        let scriptURL = tempDirectory.appendingPathComponent("install-update.zsh")
        let backupURL = URL(fileURLWithPath: currentAppURL.path + ".previous-update", isDirectory: true)
        let script = """
        #!/bin/zsh
        set -euo pipefail

        NEW_APP="$1"
        CURRENT_APP="$2"
        BACKUP_APP="$3"
        TEMP_DIR="$4"
        EXECUTABLE_NAME="$5"

        for _ in {1..100}; do
          if ! pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done

        rm -rf "$BACKUP_APP"
        if [[ -d "$CURRENT_APP" ]]; then
          if ! mv "$CURRENT_APP" "$BACKUP_APP"; then
            /usr/bin/open -n "$CURRENT_APP" || true
            rm -rf "$TEMP_DIR"
            exit 1
          fi
        fi

        if /usr/bin/ditto --norsrc --noextattr "$NEW_APP" "$CURRENT_APP"; then
          rm -rf "$BACKUP_APP"
          /usr/bin/open -n "$CURRENT_APP"
          rm -rf "$TEMP_DIR"
        else
          rm -rf "$CURRENT_APP"
          if [[ -d "$BACKUP_APP" ]]; then
            mv "$BACKUP_APP" "$CURRENT_APP"
            /usr/bin/open -n "$CURRENT_APP"
          fi
          exit 1
        fi
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            newAppURL.path,
            currentAppURL.path,
            backupURL.path,
            tempDirectory.path,
            executableName
        ]
        try process.run()
    }

    private func runProcess(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CocoaError(.executableLoad)
        }
    }
}
