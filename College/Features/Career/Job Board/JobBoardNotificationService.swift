// JobBoardNotificationService.swift
// Feature: Career
// Purpose: Career module — JobBoardNotificationService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import UserNotifications

@MainActor
final class JobBoardNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = JobBoardNotificationService()

    private static let permissionKey = "jobBoard.notifications.requested"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermissionIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.permissionKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.permissionKey)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])
    }

    func notifyIfNeeded(company: JobBoardCompany) async {
        await requestPermissionIfNeeded()
        let lastViewed = UserDefaults.standard.object(forKey: "workday.lastOpeningsViewedAt") as? Date
        let unseen = CollegePersistence.shared.countNewOpeningsSince(lastViewed)
        guard unseen > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(unseen) new job\(unseen == 1 ? "" : "s")"
        content.body = "Latest from \(company.displayName)"
        content.userInfo = ["companySlug": company.normalizedSlug]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "jobboard.\(company.normalizedSlug).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let slug = response.notification.request.content.userInfo["companySlug"] as? String {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .jobBoardOpenCompany,
                    object: nil,
                    userInfo: ["companySlug": slug]
                )
            }
        }
    }
}

extension Notification.Name {
    static let jobBoardOpenCompany = Notification.Name("jobBoard.openCompany")
}
