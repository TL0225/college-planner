// CatalogSchoolScrapePurgeNotifier.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogSchoolScrapePurgeNotifier.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension Notification.Name {
    static let collegeCatalogScrapePurgeProgress = Notification.Name("College.catalogScrapePurgeProgress")
    static let collegeCatalogScrapePurgeFinished = Notification.Name("College.catalogScrapePurgeFinished")
}

enum CatalogSchoolScrapePurgeNotifier {
    static func postInProgress(
        fraction: Double,
        title: String,
        indeterminate: Bool = false,
        completedCount: Int? = nil,
        totalCount: Int? = nil,
        stage: String? = nil
    ) {
        var userInfo: [String: Any] = [
            "fraction": fraction,
            "title": title,
            "finished": false,
            "indeterminate": indeterminate,
        ]
        if let completedCount { userInfo["completedCount"] = completedCount }
        if let totalCount { userInfo["totalCount"] = totalCount }
        if let stage { userInfo["stage"] = stage }
        NotificationCenter.default.post(
            name: .collegeCatalogScrapePurgeProgress,
            object: nil,
            userInfo: userInfo
        )
    }

    static func postFinished(summary: String, failed: Bool = false, message: String? = nil) {
        var userInfo: [String: Any] = [
            "finished": true,
            "summary": summary,
            "failed": failed,
        ]
        if let message { userInfo["message"] = message }
        NotificationCenter.default.post(
            name: .collegeCatalogScrapePurgeProgress,
            object: nil,
            userInfo: userInfo
        )
        NotificationCenter.default.post(
            name: .collegeCatalogScrapePurgeFinished,
            object: nil,
            userInfo: userInfo
        )
    }
}
