import Foundation

struct AppUpdateInfo: Equatable, Sendable {
    let currentVersion: String
    let latestVersion: String
    let releasePageURL: URL
    let downloadURL: URL
    let releaseName: String?

    var isUpdateAvailable: Bool {
        AppUpdateCheckService.isVersion(latestVersion, newerThan: currentVersion)
    }
}

actor AppUpdateCheckService {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let name: String?
        let html_url: URL
        let assets: [Asset]
    }

    static let shared = AppUpdateCheckService()
    static let repositoryURL = URL(string: "https://github.com/TL0225/college-planner")!

    private let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/TL0225/college-planner/releases/latest")!
    private let timeoutSeconds: TimeInterval = 8

    func checkForUpdates(currentVersion: String = AppUpdateCheckService.currentAppVersion()) async throws -> AppUpdateInfo {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CollegeAppUpdateCheck/1.0", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds + 2
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = sanitizedVersion(release.tag_name)
        guard !latestVersion.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releasePageURL: release.html_url,
            downloadURL: preferredDownloadURL(from: release),
            releaseName: release.name
        )
    }

    static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }

        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        sanitizedVersion(version)
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }

    private static func sanitizedVersion(_ version: String) -> String {
        var sanitized = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.lowercased().hasPrefix("v") {
            sanitized.removeFirst()
        }
        return sanitized
    }

    private func sanitizedVersion(_ version: String) -> String {
        Self.sanitizedVersion(version)
    }

    private func preferredDownloadURL(from release: GitHubRelease) -> URL {
        release.assets.first { asset in
            let lowercased = asset.name.lowercased()
            return lowercased.hasSuffix(".dmg") ||
                lowercased.hasSuffix(".pkg") ||
                lowercased.hasSuffix(".zip")
        }?.browser_download_url ?? release.html_url
    }
}
