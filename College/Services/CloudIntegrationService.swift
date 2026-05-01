import Foundation
import CoreData
import Combine

@MainActor
final class CloudIntegrationService: ObservableObject {
    static let shared = CloudIntegrationService()

    struct AuthorizedRoot: Identifiable, Hashable {
        let id: String
        let providerID: String
        let providerName: String
        let path: String

        var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    }

    struct Provider: Identifiable, Hashable {
        enum Kind: String {
            case iCloudDrive
            case googleDrive
            case oneDrive
            case boxDrive
            case dropbox
            case generic

            var title: String {
                switch self {
                case .iCloudDrive: return "iCloud Drive"
                case .googleDrive: return "Google Drive"
                case .oneDrive: return "OneDrive"
                case .boxDrive: return "Box Drive"
                case .dropbox: return "Dropbox"
                case .generic: return "Cloud Folder"
                }
            }
        }

        let id: String
        let kind: Kind
        let displayName: String
        let rootPath: String
        let isDetected: Bool
        let authorizedPaths: [String]
        let needsRegrant: Bool

        var isAuthorized: Bool { !authorizedPaths.isEmpty }

        var statusText: String {
            if needsRegrant { return "Needs Regrant" }
            if isAuthorized { return "Authorized" }
            if isDetected { return "Detected" }
            return "Not Found"
        }
    }

    struct ScanSummary: Hashable {
        let scannedAt: Date
        let fileCount: Int
        let latestFileName: String?
    }

    @Published private(set) var providers: [Provider] = []
    @Published private(set) var lastScanAt: Date? = nil
    @Published private(set) var scanSummaries: [String: ScanSummary] = [:]
    @Published private(set) var lastImportByProvider: [String: Date] = [:]

    private var autoRescanTask: Task<Void, Never>?
    private let autoRescanIntervalNanos: UInt64 = 15 * 60 * 1_000_000_000
    private static let importsDefaultsKey = "cloudIntegration.lastImportByProvider"

    private init() {
        if let raw = UserDefaults.standard.dictionary(forKey: Self.importsDefaultsKey) as? [String: TimeInterval] {
            lastImportByProvider = raw.reduce(into: [:]) { partial, entry in
                partial[entry.key] = Date(timeIntervalSince1970: entry.value)
            }
        }
        refreshDetectedProviders()
        activateStoredSecurityBookmarks()
        scanAuthorizedRootsNow()
        startAutoRescanLoop()
    }

    deinit {
        autoRescanTask?.cancel()
    }

    func refreshDetectedProviders() {
        let fm = FileManager.default
        let watched = CoreDataManager.shared.fetchWatchedFolders().filter { $0.isEnabled }

        var bookmarkValidityByPath: [String: Bool] = [:]
        for entry in watched {
            guard let path = entry.path else { continue }
            let canonical = (path as NSString).standardizingPath
            bookmarkValidityByPath[canonical] = isBookmarkValid(for: entry)
        }

        var discovered: [Provider] = []
        var seenIDs: Set<String> = []

        func addProvider(kind: Provider.Kind, displayName: String, rootPath: String, isDetected: Bool) {
            let canonical = (rootPath as NSString).standardizingPath
            let id = "\(kind.rawValue)::\(canonical.lowercased())"
            guard !seenIDs.contains(id) else { return }
            seenIDs.insert(id)

            let allWatchedPaths = watched
                .compactMap { $0.path }
                .map { ($0 as NSString).standardizingPath }
                .filter { watchedPath in
                    watchedPath == canonical
                        || watchedPath.hasPrefix(canonical + "/")
                        || canonical.hasPrefix(watchedPath + "/")
                }

            let authorizedPaths = allWatchedPaths.filter {
                bookmarkValidityByPath[$0] ?? false
            }

            let needsRegrant = allWatchedPaths.contains {
                !(bookmarkValidityByPath[$0] ?? false)
            }

            discovered.append(
                Provider(
                    id: id,
                    kind: kind,
                    displayName: displayName,
                    rootPath: canonical,
                    isDetected: isDetected,
                    authorizedPaths: Array(Set(authorizedPaths)).sorted(),
                    needsRegrant: needsRegrant
                )
            )
        }

        let cloudStorageRoot = ("~/Library/CloudStorage" as NSString).expandingTildeInPath
        if let entries = try? fm.contentsOfDirectory(atPath: cloudStorageRoot) {
            for entry in entries {
                let path = (cloudStorageRoot as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let kind = kindForFolderName(entry)
                let displayName = displayNameFor(kind: kind, fallback: entry)
                addProvider(kind: kind, displayName: displayName, rootPath: path, isDetected: true)
            }
        }

        // iCloud Drive root path (outside CloudStorage list in many setups)
        let iCloudRoot = ("~/Library/Mobile Documents/com~apple~CloudDocs" as NSString).expandingTildeInPath
        let iCloudDetected = fm.fileExists(atPath: iCloudRoot)
        addProvider(kind: .iCloudDrive, displayName: Provider.Kind.iCloudDrive.title, rootPath: iCloudRoot, isDetected: iCloudDetected)

        // Fallback: show user-configured watched folders as integrations even when
        // platform-specific root detection misses their parent provider path.
        let knownRoots = discovered.map { ($0.rootPath as NSString).standardizingPath }
        for entry in watched {
            guard let rawPath = entry.path else { continue }
            let watchedPath = (rawPath as NSString).standardizingPath

            let coveredByKnownRoot = knownRoots.contains { root in
                watchedPath == root
                    || watchedPath.hasPrefix(root + "/")
                    || root.hasPrefix(watchedPath + "/")
            }
            guard !coveredByKnownRoot else { continue }

            let leafName = URL(fileURLWithPath: watchedPath, isDirectory: true)
                .lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = leafName.isEmpty ? "Cloud Folder" : leafName

            addProvider(
                kind: .generic,
                displayName: displayName,
                rootPath: watchedPath,
                isDetected: true
            )
        }

        providers = discovered.sorted { lhs, rhs in
            if lhs.kind == .iCloudDrive && rhs.kind != .iCloudDrive { return true }
            if rhs.kind == .iCloudDrive && lhs.kind != .iCloudDrive { return false }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        lastScanAt = Date()
    }

    func scanAuthorizedRootsNow() {
        let providersSnapshot = providers
        Task.detached(priority: .utility) {
            var computed: [String: ScanSummary] = [:]

            for provider in providersSnapshot {
                let summary = Self.computeScanSummary(paths: provider.authorizedPaths)
                if let summary {
                    computed[provider.id] = summary
                }
            }

            await MainActor.run {
                self.scanSummaries = computed
            }
        }
    }

    /// Launch preload hook: refreshes provider detection and blocks until authorized scans complete.
    func preloadForLaunch(
        progress: ((Double) -> Void)? = nil,
        detail: ((String) -> Void)? = nil
    ) async {
        detail?("Refreshing integration providers")
        progress?(0.05)
        refreshDetectedProviders()
        progress?(0.20)

        let providersSnapshot = providers
        guard !providersSnapshot.isEmpty else {
            detail?("No integrations to scan")
            scanSummaries = [:]
            progress?(1)
            return
        }

        var computed: [String: ScanSummary] = [:]
        let total = providersSnapshot.count
        for (index, provider) in providersSnapshot.enumerated() {
            detail?("Scanning \(provider.displayName) (\(index + 1)/\(total))")

            let summary = await Task.detached(priority: .utility) {
                Self.computeScanSummary(paths: provider.authorizedPaths)
            }.value

            if let summary {
                computed[provider.id] = summary
            }

            let ratio = Double(index + 1) / Double(total)
            progress?(0.20 + 0.80 * ratio)
        }

        scanSummaries = computed
        detail?("Integration scan complete")
        progress?(1)
    }

    func scanSummary(for provider: Provider) -> ScanSummary? {
        scanSummaries[provider.id]
    }

    func lastImportDate(for provider: Provider) -> Date? {
        lastImportByProvider[provider.id]
    }

    func recordImport(providerID: String) {
        let now = Date()
        lastImportByProvider[providerID] = now
        let persisted = lastImportByProvider.reduce(into: [String: TimeInterval]()) { partial, entry in
            partial[entry.key] = entry.value.timeIntervalSince1970
        }
        UserDefaults.standard.set(persisted, forKey: Self.importsDefaultsKey)
    }

    func suggestedDirectoryURL(for provider: Provider?) -> URL {
        if let provider {
            return URL(fileURLWithPath: provider.rootPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    func authorizedPaths(for provider: Provider) -> [String] {
        provider.authorizedPaths
    }

    func authorizedRoots() -> [AuthorizedRoot] {
        providers.flatMap { provider in
            provider.authorizedPaths.map { path in
                let canonical = (path as NSString).standardizingPath
                return AuthorizedRoot(
                    id: "\(provider.id)::\(canonical.lowercased())",
                    providerID: provider.id,
                    providerName: provider.displayName,
                    path: canonical
                )
            }
        }
    }

    func revokeAuthorization(for provider: Provider) {
        let watched = CoreDataManager.shared.fetchWatchedFolders()
        for entry in watched {
            guard let path = entry.path else { continue }
            let canonical = (path as NSString).standardizingPath
            if provider.authorizedPaths.contains(canonical) {
                if let id = entry.id {
                    CoreDataManager.shared.removeWatchedFolder(id: id)
                }
                FSWatchdogService.shared.removeWatchedPath(canonical)
            }
        }
        refreshDetectedProviders()
    }

    private func startAutoRescanLoop() {
        autoRescanTask?.cancel()
        autoRescanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: autoRescanIntervalNanos)
                guard !Task.isCancelled else { return }
                self.refreshDetectedProviders()
                self.scanAuthorizedRootsNow()
            }
        }
    }

    private func activateStoredSecurityBookmarks() {
        let watched = CoreDataManager.shared.fetchWatchedFolders().filter { $0.isEnabled }
        for entry in watched {
            guard let bookmarkData = entry.bookmarkData else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            _ = url.startAccessingSecurityScopedResource()

            if isStale,
               let refreshed = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
               ),
               let path = entry.path {
                _ = CoreDataManager.shared.addWatchedFolder(path: path, bookmarkData: refreshed)
            }
        }
    }

    private func isBookmarkValid(for entry: WatchedFolderEntity) -> Bool {
        guard let bookmarkData = entry.bookmarkData else { return false }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return false
        }

        if isStale { return false }
        return url.startAccessingSecurityScopedResource()
    }

    nonisolated private static func computeScanSummary(paths: [String]) -> ScanSummary? {
        guard !paths.isEmpty else { return nil }
        let fm = FileManager.default
        var count = 0
        var latestDate: Date?
        var latestName: String?

        for path in paths {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }

                count += 1

                if let modified = values?.contentModificationDate {
                    if latestDate == nil || modified > latestDate! {
                        latestDate = modified
                        latestName = fileURL.lastPathComponent
                    }
                }
            }
        }

        return ScanSummary(scannedAt: Date(), fileCount: count, latestFileName: latestName)
    }

    private func kindForFolderName(_ folderName: String) -> Provider.Kind {
        let lower = folderName.lowercased()
        if lower.contains("google") && lower.contains("drive") { return .googleDrive }
        if lower.contains("onedrive") { return .oneDrive }
        if lower.contains("box") { return .boxDrive }
        if lower.contains("dropbox") { return .dropbox }
        return .generic
    }

    private func displayNameFor(kind: Provider.Kind, fallback: String) -> String {
        switch kind {
        case .generic:
            return fallback
        default:
            return kind.title
        }
    }
}
