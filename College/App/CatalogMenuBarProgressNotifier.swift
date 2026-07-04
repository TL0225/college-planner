// CatalogMenuBarProgressNotifier.swift
// Feature: App
// Purpose: App module — CatalogMenuBarProgressNotifier.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Single entry point for posting catalog import progress to the menu bar controller.
enum CatalogMenuBarProgressNotifier {
    private static let defaultActivityID = "catalog.import"

    static func postInProgress(
        fraction: Double,
        title: String,
        indeterminate: Bool = false,
        activityID: String = defaultActivityID
    ) {
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "fraction": fraction,
                "title": title,
                "finished": false,
                "indeterminate": indeterminate,
                "activityID": activityID,
            ]
        )
    }

    static func postFinished(activityID: String = defaultActivityID) {
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "finished": true,
                "activityID": activityID,
            ]
        )
    }

    /// Fraction-first progress for student-facing copy (e.g. "Courses 1240 / 3800").
    static func postCountProgress(
        completed: Int,
        total: Int,
        title: String,
        stage: String,
        activityID: String = defaultActivityID
    ) {
        let safeTotal = max(0, total)
        let safeCompleted = max(0, min(completed, safeTotal == 0 ? completed : safeTotal))
        let frac: Double = safeTotal > 0 ? Double(safeCompleted) / Double(safeTotal) : 0
        let statusTitle: String
        if safeTotal > 0 {
            statusTitle = "\(stage) \(safeCompleted) / \(safeTotal) — \(title)"
        } else {
            statusTitle = "\(stage) \(safeCompleted) — \(title)"
        }
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "fraction": frac,
                "title": statusTitle,
                "finished": false,
                "indeterminate": false,
                "completedCount": safeCompleted,
                "totalCount": safeTotal,
                "stage": stage,
                "activityID": activityID,
            ]
        )
    }

    static func postSucceeded(
        title: String = "Catalog sync complete",
        summary: String? = nil,
        activityID: String = defaultActivityID
    ) {
        postInProgress(fraction: 1, title: title, indeterminate: false, activityID: activityID)
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "finished": true,
                "title": title,
                "summary": summary ?? title,
                "activityID": activityID,
            ]
        )
    }

    static func postSkipped(
        message: String,
        activityID: String = defaultActivityID
    ) {
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "finished": true,
                "title": message,
                "summary": message,
                "skipped": true,
                "activityID": activityID,
            ]
        )
    }

    static func postFailed(
        message: String,
        activityID: String = defaultActivityID
    ) {
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: [
                "finished": true,
                "title": message,
                "message": message,
                "failed": true,
                "activityID": activityID,
            ]
        )
    }
}
