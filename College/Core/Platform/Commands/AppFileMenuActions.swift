// AppFileMenuActions.swift
// Feature: Core / Platform
// Purpose: Shared File-menu import/export flows (Settings + menu bar).

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum AppFileMenuActions {
    private static func formattedBackupDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.nameFieldStringValue = "CollegeBackup-\(formattedBackupDate()).collegebackup"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await BackgroundServiceOnDemand.run(id: "app_backup_export") {
                do {
                    try await AppBackupManager.exportBackup(to: url)
                    ProductAnalytics.track(.backupExported)
                    AppNotificationCenter.shared.post(
                        kind: .success,
                        title: "Backup Exported",
                        message: "Your data was saved successfully."
                    )
                } catch {
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Export Failed",
                        message: userFacingBackupError(error)
                    )
                }
            }
        }
    }

    static func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "Import Backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "collegebackup") ?? .data,
            UTType(filenameExtension: "portal") ?? .data
        ]

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        importBackup(from: url)
    }

    static func importBackup(from url: URL) {
        Task {
            await BackgroundServiceOnDemand.run(id: "app_backup_import") {
                do {
                    try await AppBackupManager.importBackup(from: url)
                    ProductAnalytics.track(.backupImported)
                    AppNotificationCenter.shared.post(
                        kind: .success,
                        title: "Backup Imported",
                        message: "Your data was restored successfully."
                    )
                } catch {
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Import Failed",
                        message: userFacingBackupError(error)
                    )
                }
            }
        }
    }

    static func importCatalogBundle() {
        let panel = NSOpenPanel()
        panel.title = "Import Catalog Bundle"
        panel.allowedContentTypes = [
            UTType(filenameExtension: CatalogBundle.fileExtension) ?? .json,
            UTType(filenameExtension: "sqlite") ?? .data
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppTypedNavigationRouter.importCatalogBundle(at: url)
    }

    static func importTransferCommunityJSON() {
        AppTypedNavigationRouter.openPage(.transferDatabase)
        NotificationCenter.default.post(name: .transferImportCommunityJSON, object: nil)
    }

    private static func userFacingBackupError(_ error: Error) -> String {
        if let backupError = error as? AppBackupManager.BackupError {
            switch backupError {
            case .appLocked:
                return "Unlock College before importing or exporting a backup."
            case .invalidBackupFile:
                return "The selected file is not a valid College backup."
            case .missingBundleIdentifier:
                return "College could not determine its application identity. Try reinstalling the app."
            }
        }
        return error.localizedDescription
    }
}
