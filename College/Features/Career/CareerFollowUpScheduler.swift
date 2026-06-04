// CareerFollowUpScheduler.swift
// Feature: Career
// Purpose: Career module — CareerFollowUpScheduler.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import UserNotifications

@MainActor
final class CareerFollowUpScheduler {
    static let shared = CareerFollowUpScheduler()

    private var lastReconcileAt: Date?

    func reconcile(using persistence: CollegePersistence = .shared) {
        if let lastReconcileAt, Date().timeIntervalSince(lastReconcileAt) < 60 {
            return
        }
        lastReconcileAt = Date()
        performReconcile(using: persistence)
    }

    private func performReconcile(using persistence: CollegePersistence) {
        let apps = (try? persistence.careerRepository.fetchApplicationsForFollowUp()) ?? []
        for app in apps {
            reconcileNotification(for: app)
        }
    }

    private func reconcileNotification(for app: JobApplication) {
        let identifier = "career.followup.applied14d.\(app.id.uuidString)"
        if app.statusRaw == CareerApplicationStatus.applied.rawValue {
            let anchor = app.dateApplied ?? app.lastStatusChangeAt ?? app.updatedAt ?? Date()
            let triggerDate = Calendar.current.date(byAdding: .day, value: 14, to: anchor) ?? anchor

            let content = UNMutableNotificationContent()
            content.title = "\(app.company ?? "Application") follow-up"
            content.body = "\(app.company ?? "Company") (Applied 14 days ago): It's been 2 weeks. Time to send a polite follow-up email."
            content.sound = .default
            content.userInfo = [
                "jobApplicationId": app.id.uuidString,
                "targetSubView": "networking",
                "ruleId": "applied14d",
            ]

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }
}
