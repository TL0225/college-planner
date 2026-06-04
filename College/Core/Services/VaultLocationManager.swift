// VaultLocationManager.swift
// Feature: Core
// Purpose: Core module — VaultLocationManager.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine
import SwiftUI
import AppKit

// MARK: - VaultLocationError

enum VaultLocationError: LocalizedError {
    case notConfigured
    case bookmarkResolveFailed
    case securityScopeDenied

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Choose a Vault folder in Settings (Documents → File Watchdog)."
        case .bookmarkResolveFailed:
            return "Saved Vault access is no longer valid. Choose the Vault folder again."
        case .securityScopeDenied:
            return "Could not access the Vault folder (sandbox). Try choosing it again in Settings."
        }
    }
}

// MARK: - VaultLocationManager

/// Resolves the user-chosen Vault directory via a security-scoped app bookmark (sandbox-safe).
@MainActor
final class VaultLocationManager: ObservableObject {

    static let shared = VaultLocationManager()

    private static let vaultBookmarkKey = "vault.location.root.bookmarkData"
    private static let desktopBookmarkKey = "vault.location.desktop.bookmarkData"

    /// True once a vault root bookmark is stored and resolves.
    @Published private(set) var hasConfiguredVault: Bool = false

    @Published private(set) var resolvedVaultRootURL: URL?

    /// Optional Desktop folder for screenshot triage (separate user grant).
    @Published private(set) var resolvedDesktopURL: URL?

    private var startedVaultScope = false
    private var startedDesktopScope = false

    private init() {
        restoreBookmarksOnLaunch()
    }

    // MARK: - Lifecycle

    /// Call early on startup; resolves bookmarks and starts security-scoped access for the session.
    func restoreBookmarksOnLaunch() {
        resolveVaultFromStoredBookmark()
        resolveDesktopFromStoredBookmark()
    }

    private func resolveVaultFromStoredBookmark() {
        if startedVaultScope, let prev = resolvedVaultRootURL {
            prev.stopAccessingSecurityScopedResource()
            startedVaultScope = false
        }
        resolvedVaultRootURL = nil
        hasConfiguredVault = false

        guard let data = UserDefaults.standard.data(forKey: Self.vaultBookmarkKey), !data.isEmpty else {
            return
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return
        }

        if stale {
            // Keep trying; user may need to re-pick. Don't delete bookmark automatically.
            print("[VaultLocationManager] Vault bookmark is stale — ask user to re-select vault.")
        }

        guard url.startAccessingSecurityScopedResource() else {
            print("[VaultLocationManager] startAccessingSecurityScopedResource failed for vault.")
            return
        }

        startedVaultScope = true
        resolvedVaultRootURL = url.standardizedFileURL
        hasConfiguredVault = true
    }

    private func resolveDesktopFromStoredBookmark() {
        if startedDesktopScope, let prev = resolvedDesktopURL {
            prev.stopAccessingSecurityScopedResource()
            startedDesktopScope = false
        }
        resolvedDesktopURL = nil

        guard let data = UserDefaults.standard.data(forKey: Self.desktopBookmarkKey), !data.isEmpty else {
            return
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            return
        }

        startedDesktopScope = true
        resolvedDesktopURL = url.standardizedFileURL
    }

    // MARK: - Mutations

    /// Call with the URL from `NSOpenPanel` while security scope is still valid (we start/stop around bookmark creation).
    func commitVaultRootBookmark(fromOpenPanelURL url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultLocationError.securityScopeDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: Self.vaultBookmarkKey)

        if startedVaultScope, let prev = resolvedVaultRootURL {
            prev.stopAccessingSecurityScopedResource()
            startedVaultScope = false
        }

        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        guard resolved.startAccessingSecurityScopedResource() else {
            throw VaultLocationError.securityScopeDenied
        }

        startedVaultScope = true
        let std = resolved.standardizedFileURL
        resolvedVaultRootURL = std
        hasConfiguredVault = true

        let path = std.path
        if !FSWatchdogService.shared.watchedPaths.contains(path) {
            FSWatchdogService.shared.addWatchedPath(path)
        }
        FSWatchdogService.shared.storeSecurityBookmark(for: std)
    }

    func commitDesktopScanBookmark(fromOpenPanelURL url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultLocationError.securityScopeDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: Self.desktopBookmarkKey)

        if startedDesktopScope, let prev = resolvedDesktopURL {
            prev.stopAccessingSecurityScopedResource()
            startedDesktopScope = false
        }

        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )

        guard resolved.startAccessingSecurityScopedResource() else {
            throw VaultLocationError.securityScopeDenied
        }

        startedDesktopScope = true
        resolvedDesktopURL = resolved.standardizedFileURL
    }

    func clearDesktopScanFolder() {
        UserDefaults.standard.removeObject(forKey: Self.desktopBookmarkKey)
        if startedDesktopScope, let prev = resolvedDesktopURL {
            prev.stopAccessingSecurityScopedResource()
        }
        startedDesktopScope = false
        resolvedDesktopURL = nil
    }

    // MARK: - Path Helpers

    func requireVaultRoot() throws -> URL {
        guard let u = resolvedVaultRootURL else {
            throw VaultLocationError.notConfigured
        }
        return u
    }

    /// Path prefix for stale-file detection; empty if vault not configured (`isInVault` treats as never inside vault).
    var standardizedVaultPathForStaleMonitor: String {
        resolvedVaultRootURL?.standardizedFileURL.path ?? ""
    }

    func revealVaultInFinder() {
        guard let url = resolvedVaultRootURL else { return }
        NSWorkspace.shared.open(url)
    }

    func presentChooseVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault Folder"
        panel.message = "Select the folder where College should store your documents (for example Documents/College)."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try VaultLocationManager.shared.commitVaultRootBookmark(fromOpenPanelURL: url)
                } catch {
                    print("[VaultLocationManager] commitVaultRootBookmark failed: \(error)")
                }
            }
        }
    }

    func presentChooseDesktopForScreenshotsPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Desktop Access"
        panel.message = "Choose your Desktop folder so College can find screenshots to triage."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try VaultLocationManager.shared.commitDesktopScanBookmark(fromOpenPanelURL: url)
                } catch {
                    print("[VaultLocationManager] commitDesktopScanBookmark failed: \(error)")
                }
            }
        }
    }
}
