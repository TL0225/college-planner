// VaultWeeklyDigest.swift
// Feature: Core
// Purpose: Core module — VaultWeeklyDigest.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import UserNotifications
import SwiftData

// MARK: - VaultWeeklyDigest

@MainActor final class VaultWeeklyDigest {

    static let shared = VaultWeeklyDigest()

    private let notificationIdentifier = "vault.weekly.digest"
    private let categoryIdentifier = "VAULT_DIGEST"

    private init() {}

    func scheduleWeeklyDigest() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            guard granted else {
                if let error { print("[VaultWeeklyDigest] Auth denied: \(error)") }
                return
            }
            Task { @MainActor in
                await self.registerAndSchedule()
            }
        }
    }

    func cancelSchedule() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    func generateDigestContent() async -> (title: String, body: String) {
        let docs = CollegePersistence.shared.vaultDocuments
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentCount = docs.filter { $0.addedAt >= sevenDaysAgo }.count

        let tasksDueSoonCount: Int = {
            let repo = CollegePersistence.shared.calendarRepository
            let now = Date()
            let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            let tasks = (try? repo.fetchTasks(dueFrom: now, dueBefore: endOfWeek)) ?? []
            return tasks.filter { !$0.isCompleted }.count
        }()

        let title = "Your Weekly Vault Digest"
        let body = "You added \(recentCount) file\(recentCount == 1 ? "" : "s") this week. \(tasksDueSoonCount) task\(tasksDueSoonCount == 1 ? " is" : "s are") due soon."
        return (title, body)
    }

    private func registerAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        let (title, body) = await generateDigestContent()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        var dateComponents = DateComponents()
        dateComponents.weekday = 1
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[VaultWeeklyDigest] Failed to schedule: \(error)")
        }
    }
}
