import Foundation

struct UpdateManifest: Decodable {
    let version: String
    let downloadUrl: URL
    let zipUrl: URL?
    let sha256: String?
    let releaseUrl: URL
    let minimumMacOS: String
}

struct AvailableUpdate: Equatable {
    let version: String
    let downloadUrl: URL
    let zipUrl: URL?
    let sha256: String?
    let releaseUrl: URL
    let minimumMacOS: String

    var canInstallInApp: Bool {
        zipUrl != nil && sha256?.isEmpty == false
    }
}

enum UpdateCheckResult: Equatable {
    case current
    case available(AvailableUpdate)
}

enum UpdateCheckError: Error {
    case invalidCurrentVersion
    case invalidRemoteVersion
    case invalidHTTPStatus(Int)
}

struct UpdateChecker {
    static let defaultManifestURL = URL(
        string: "https://github.com/lasseveenliese/codex-usage-menubar/releases/download/latest/update.json"
    )!

    let manifestURL: URL
    let session: URLSession

    init(manifestURL: URL = Self.defaultManifestURL, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.session = session
    }

    func check(currentVersion: String) async throws -> UpdateCheckResult {
        guard let current = SemanticVersion(currentVersion) else {
            throw UpdateCheckError.invalidCurrentVersion
        }

        let (data, response) = try await session.data(from: manifestURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw UpdateCheckError.invalidHTTPStatus(httpResponse.statusCode)
        }

        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        guard let remote = SemanticVersion(manifest.version) else {
            throw UpdateCheckError.invalidRemoteVersion
        }

        guard remote > current else {
            return .current
        }

        return .available(AvailableUpdate(
            version: manifest.version,
            downloadUrl: manifest.downloadUrl,
            zipUrl: manifest.zipUrl,
            sha256: manifest.sha256,
            releaseUrl: manifest.releaseUrl,
            minimumMacOS: manifest.minimumMacOS
        ))
    }
}

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0,
              minor >= 0,
              patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }

        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }

        return lhs.patch < rhs.patch
    }
}
