import Foundation

final class CodexAppServerRateLimitsClient {
    enum ClientError: Error {
        case missingCodexExecutable
        case missingSocket
        case noRateLimitsResponse
        case invalidResponse
    }

    func fetchLatestSnapshot() throws -> CodexRateLimitsSnapshot {
        if let directSnapshot = try? fetchSnapshot(from: .direct) {
            return directSnapshot
        }

        if let socketSnapshot = try? fetchSnapshot(from: .socket(try controlSocketURL())) {
            return socketSnapshot
        }

        throw ClientError.invalidResponse
    }

    private enum Source {
        case direct
        case socket(URL)
    }

    private func fetchSnapshot(from source: Source) throws -> CodexRateLimitsSnapshot {
        let output: Data

        switch source {
        case .direct:
            output = try runAppServer()
        case .socket(let socketURL):
            guard FileManager.default.fileExists(atPath: socketURL.path) else {
                throw ClientError.missingSocket
            }
            output = try runProxy(socketPath: socketURL.path)
        }

        return try snapshot(fromJSONRPCOutput: output)
    }

    func snapshot(fromJSONRPCOutput output: Data) throws -> CodexRateLimitsSnapshot {
        let response = try parseRateLimitsResponse(from: output)

        if let codexSnapshot = response.rateLimitsByLimitId?["codex"] {
            let windows = [
                ("primary", codexSnapshot.primary ?? response.rateLimits.primary),
                ("secondary", codexSnapshot.secondary ?? response.rateLimits.secondary)
            ].compactMap { id, window in
                window.map {
                    CodexRateLimitsSnapshot.Window(
                        id: id,
                        usedPercent: $0.usedPercent,
                        windowMinutes: $0.windowDurationMins,
                        resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                    )
                }
            }

            guard !windows.isEmpty else {
                throw ClientError.noRateLimitsResponse
            }

            let snapshot = CodexRateLimitsSnapshot(
                windows: windows,
                credits: (codexSnapshot.credits ?? response.rateLimits.credits).map {
                    .init(balance: $0.balance, hasCredits: $0.hasCredits, unlimited: $0.unlimited)
                }
            )

            guard snapshot.hasValidUsage else {
                throw ClientError.invalidResponse
            }

            return snapshot
        }

        if let legacySnapshot = CodexRateLimitsSnapshot(response.rateLimits), legacySnapshot.hasValidUsage {
            return legacySnapshot
        }

        throw ClientError.noRateLimitsResponse
    }

    private func runAppServer() throws -> Data {
        let process = Process()
        let invocation = try codexInvocation()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments + ["app-server", "--listen", "stdio://"]

        return try runJSONRPC(process: process)
    }

    private func controlSocketURL() throws -> URL {
        let fileManager = FileManager.default
        let codexHome: URL

        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            codexHome = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            codexHome = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }

        return codexHome
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock")
    }

    private func runProxy(socketPath: String) throws -> Data {
        let process = Process()
        let invocation = try codexInvocation()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments + ["app-server", "proxy", "--sock", socketPath]

        return try runJSONRPC(process: process)
    }

    private struct Invocation {
        let executableURL: URL
        let arguments: [String]
    }

    private func codexInvocation() throws -> Invocation {
        let fileManager = FileManager.default
        var candidateDirectories: [String] = []

        if let path = ProcessInfo.processInfo.environment["PATH"], !path.isEmpty {
            candidateDirectories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        candidateDirectories.append(contentsOf: [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin").path,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ])

        var seen = Set<String>()
        for directory in candidateDirectories where seen.insert(directory).inserted {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("codex")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                if let invocation = nodeInvocation(for: candidate) {
                    return invocation
                }

                return Invocation(executableURL: candidate, arguments: [])
            }
        }

        throw ClientError.missingCodexExecutable
    }

    private func nodeInvocation(for codexURL: URL) -> Invocation? {
        let resolvedCodexURL = codexURL.resolvingSymlinksInPath()
        guard ["js", "mjs", "cjs"].contains(resolvedCodexURL.pathExtension.lowercased()) else {
            return nil
        }

        guard let nodeURL = nodeExecutableURL() else {
            return nil
        }

        return Invocation(executableURL: nodeURL, arguments: [resolvedCodexURL.path])
    }

    private func nodeExecutableURL() -> URL? {
        let fileManager = FileManager.default
        var candidateDirectories: [String] = []

        if let path = ProcessInfo.processInfo.environment["PATH"], !path.isEmpty {
            candidateDirectories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        candidateDirectories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ])

        var seen = Set<String>()
        for directory in candidateDirectories where seen.insert(directory).inserted {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("node")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func runJSONRPC(process: Process) throws -> Data {

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let requestLines = [
            Self.jsonLine([
                "id": 1,
                "method": "initialize",
                "params": [
                    "capabilities": [:],
                    "clientInfo": [
                        "name": "Codex Usage Menubar",
                        "version": Self.appVersion,
                        "title": "Codex Usage Menubar"
                    ]
                ]
            ]),
            Self.jsonLine([
                "method": "initialized"
            ]),
            Self.jsonLine([
                "id": 2,
                "method": "account/rateLimits/read",
                "params": NSNull()
            ])
        ]

        let inputHandle = inputPipe.fileHandleForWriting
        defer {
            inputHandle.closeFile()
        }

        for line in requestLines {
            guard let data = line.data(using: .utf8) else { continue }
            inputHandle.write(data)
            inputHandle.write(Data([0x0A]))
        }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        let stdout = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if stdout.isEmpty, !stderr.isEmpty {
            throw ClientError.invalidResponse
        }

        return stdout
    }

    private func parseRateLimitsResponse(from output: Data) throws -> AppServerRateLimitsResponse {
        let text = String(decoding: output, as: UTF8.self)
        var rateLimitsResponse: AppServerRateLimitsResponse?

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8) else { continue }
            guard
                let object = try? JSONSerialization.jsonObject(with: data),
                let dictionary = object as? [String: Any]
            else {
                continue
            }

            guard Self.messageId(dictionary) == 2 else { continue }
            guard let resultObject = dictionary["result"] else { continue }
            let resultData = try JSONSerialization.data(withJSONObject: resultObject)
            rateLimitsResponse = try JSONDecoder().decode(AppServerRateLimitsResponse.self, from: resultData)
        }

        if let rateLimitsResponse {
            return rateLimitsResponse
        }

        throw ClientError.invalidResponse
    }

    private static func messageId(_ dictionary: [String: Any]) -> Int? {
        if let id = dictionary["id"] as? Int {
            return id
        }

        if let id = dictionary["id"] as? NSNumber {
            return id.intValue
        }

        if let id = dictionary["id"] as? String {
            return Int(id)
        }

        return nil
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: object, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

private struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: AppServerRateLimitSnapshot
    let rateLimitsByLimitId: [String: AppServerRateLimitSnapshot]?
}

private struct AppServerRateLimitSnapshot: Decodable {
    let primary: AppServerRateLimitWindow?
    let secondary: AppServerRateLimitWindow?
    let credits: AppServerCreditsSnapshot?
}

private struct AppServerCreditsSnapshot: Decodable {
    let balance: String?
    let hasCredits: Bool
    let unlimited: Bool
}

private struct AppServerRateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

extension CodexRateLimitsSnapshot {
    fileprivate init?(_ snapshot: AppServerRateLimitSnapshot) {
        let windows = [("primary", snapshot.primary), ("secondary", snapshot.secondary)].compactMap { id, window in
            window.map {
                Window(
                    id: id,
                    usedPercent: $0.usedPercent,
                    windowMinutes: $0.windowDurationMins,
                    resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }
        }
        guard !windows.isEmpty else {
            return nil
        }

        self.init(
            windows: windows,
            credits: snapshot.credits.map {
                .init(balance: $0.balance, hasCredits: $0.hasCredits, unlimited: $0.unlimited)
            }
        )
    }
}
