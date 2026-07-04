// AcademicNotificationScheduler.swift
// Feature: Core
// Purpose: Core module — SemesterSnapshot.
// Data: CollegePersistence / repositories when applicable.

//
//  AcademicNotificationScheduler.swift
//  College
//
//  Schedules proactive academic reminders using UNCalendarNotificationTrigger.
//  Notifications are re-scheduled after any semester or grade change.
//

import Foundation
import UserNotifications

/// Schedules proactive academic reminders using UNCalendarNotificationTrigger.
/// Notifications are re-scheduled after any semester or grade change.
final class AcademicNotificationScheduler: @unchecked Sendable {
    static let shared = AcademicNotificationScheduler()
    private init() {}

    private struct SemesterSnapshot: Sendable {
        let name: String?
        let year: Int
        let season: String?
        let seasonOrder: Int
    }

    private struct SAPSnapshot: Sendable {
        let attempted: Int
        let rate: Double
    }

    /// Call this after loading or changing academic data.
    /// Schedules/replaces all academic reminder notifications.
    func reschedule(using collegePersistence: CollegePersistence) {
        Task { @MainActor in
            await BackgroundServiceOnDemand.run(id: "academic_notification_reschedule") {
                AcademicNotificationScheduler.shared.performReschedule(using: collegePersistence)
            }
        }
    }

    @MainActor
    private func performReschedule(using collegePersistence: CollegePersistence) {
        let gpa = collegePersistence.primaryGPA()
        let semesters = collegePersistence.semesters.map {
            SemesterSnapshot(
                name: $0.name,
                year: Int($0.year),
                season: $0.season,
                seasonOrder: Int($0.seasonOrder)
            )
        }
        let sap = collegePersistence.sapStats()
        let sapSnapshot = SAPSnapshot(attempted: sap.attempted, rate: sap.rate)
        AcademicNotificationScheduler.shared.finishReschedule(
            gpa: gpa,
            semesters: semesters,
            sapSnapshot: sapSnapshot
        )
    }

    @MainActor
    private func finishReschedule(
        gpa: Double,
        semesters: [SemesterSnapshot],
        sapSnapshot: SAPSnapshot
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
                "academic.low_gpa",
                "academic.registration_reminder",
                "academic.sap_warning"
            ])
            Task { @MainActor in
                if gpa > 0 {
                    AcademicNotificationScheduler.shared.scheduleGPAWarningIfNeeded(gpa: gpa)
                }
                AcademicNotificationScheduler.shared.scheduleRegistrationReminder(semesters: semesters)
                AcademicNotificationScheduler.shared.scheduleSAPWarningIfNeeded(sap: sapSnapshot)
            }
        }
    }

    // MARK: - Low GPA Warning

    private func scheduleGPAWarningIfNeeded(gpa: Double) {
        guard gpa > 0 && gpa < 2.0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Academic Standing Alert"
        content.body = String(format: "Your GPA is %.2f — below the 2.0 minimum for good academic standing. Visit your advisor.", gpa)
        content.sound = .default

        var dc = DateComponents()
        dc.hour = 9
        dc.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        let request = UNNotificationRequest(identifier: "academic.low_gpa", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Registration Reminder

    private func scheduleRegistrationReminder(semesters: [SemesterSnapshot]) {
        let cal = Calendar.current
        let now = Date()

        let nextSemester = semesters
            .sorted { a, b in
                a.year < b.year ||
                (a.year == b.year && a.seasonOrder < b.seasonOrder)
            }
            .first { sem in
                let yr = sem.year
                let month: Int
                switch (sem.season ?? "").lowercased() {
                case "spring": month = 1
                case "summer": month = 5
                case "fall":   month = 8
                default:       month = 12
                }
                let start = cal.date(from: DateComponents(year: yr, month: month, day: 1)) ?? .distantPast
                return start > now
            }

        guard let next = nextSemester else { return }
        let yr = next.year
        let month: Int
        switch (next.season ?? "").lowercased() {
        case "spring": month = 1
        case "summer": month = 5
        case "fall":   month = 8
        default:       month = 12
        }
        guard let semStart = cal.date(from: DateComponents(year: yr, month: month, day: 1)),
              let reminderDate = cal.date(byAdding: .weekOfYear, value: -3, to: semStart),
              reminderDate > now else { return }

        let semName = next.name ?? "\(next.season ?? "") \(next.year)"
        let content = UNMutableNotificationContent()
        content.title = "Registration Opens Soon"
        content.body = "\(semName) registration opens in ~3 weeks. Review your degree audit and plan your courses."
        content.sound = .default

        let dc = cal.dateComponents([.year, .month, .day, .hour], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        let request = UNNotificationRequest(identifier: "academic.registration_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - SAP Warning

    private func scheduleSAPWarningIfNeeded(sap: SAPSnapshot) {
        guard sap.attempted > 0, sap.rate < 0.67 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Financial Aid Warning"
        content.body = String(format: "Your SAP completion rate is %.0f%% — below the 67%% required for financial aid. Complete more attempted courses.", sap.rate * 100)
        content.sound = .default

        var dc = DateComponents()
        dc.hour = 10
        dc.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        let request = UNNotificationRequest(identifier: "academic.sap_warning", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
