import Foundation
import CoreData
import UserNotifications

// MARK: - VaultWeeklyDigest

@MainActor final class VaultWeeklyDigest {

    static let shared = VaultWeeklyDigest()

    // MARK: - Constants

    private let notificationIdentifier = "vault.weekly.digest"
    private let categoryIdentifier = "VAULT_DIGEST"

    // MARK: - Init

    private init() {}

    // MARK: - Scheduling

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

    // MARK: - Digest Content

    func generateDigestContent() async -> (title: String, body: String) {
        let docs = CoreDataManager.shared.vaultDocuments
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentCount = docs.filter { doc in
            guard let addedAt = doc.addedAt else { return false }
            return addedAt >= sevenDaysAgo
        }.count

        let context = CoreDataManager.shared.viewContext
        let tasksDueSoonCount: Int = {
            let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
            let now = Date()
            let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            request.predicate = NSPredicate(
                format: "isCompleted == NO AND dueDate >= %@ AND dueDate <= %@",
                now as CVarArg,
                endOfWeek as CVarArg
            )
            return (try? context.fetch(request))?.count ?? 0
        }()

        let title = "Your Weekly Vault Digest"
        let body = "You added \(recentCount) file\(recentCount == 1 ? "" : "s") this week. \(tasksDueSoonCount) task\(tasksDueSoonCount == 1 ? " is" : "s are") due soon."
        return (title, body)
    }

    // MARK: - Private Helpers

    private func registerAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        let (title, body) = await generateDigestContent()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        // Sunday = weekday 1
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
