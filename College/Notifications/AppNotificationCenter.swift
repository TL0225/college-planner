import Foundation
import SwiftUI
import Combine
import UserNotifications

final class AppNotificationCenter: NSObject, ObservableObject {
    nonisolated(unsafe) static let shared = AppNotificationCenter()

    /// Lightweight descriptor used only to track in-flight progress operations
    /// so that `complete()` can deliver a final macOS system notification with
    /// the correct title and message.
    struct AppNotification: Identifiable, Equatable {
        enum Kind: Equatable {
            case info
            case success
            case warning
            case error
            case progress
        }

        let id: UUID
        var kind: Kind
        var title: String
        var message: String
        var progress: Double?
        var createdAt: Date
        var isDismissible: Bool
        var autoDismissAfter: TimeInterval?

        var showsProgress: Bool { progress != nil }
    }

    /// Tracks in-flight progress notifications so `complete()` can fire the
    /// final macOS notification with the right title/message. Never rendered
    /// in-app.
    private var progressTracking: [UUID: (title: String, message: String)] = [:]

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    /// Call once at app startup. Requests macOS notification authorisation.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[AppNotificationCenter] Permission request failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Public API

    @MainActor
    @discardableResult
    func post(
        kind: AppNotification.Kind,
        title: String,
        message: String,
        progress: Double? = nil,
        isDismissible: Bool = true,
        autoDismissAfter: TimeInterval? = nil
    ) -> UUID {
        let id = UUID()

        if kind == .progress {
            // Track progress operations so complete() can fire the final notification.
            progressTracking[id] = (title: title, message: message)
        } else {
            // Deliver all non-progress notifications immediately to macOS.
            deliverSystemNotification(id: id, kind: kind, title: title, message: message)
        }

        return id
    }

    @MainActor
    func update(
        id: UUID,
        title: String? = nil,
        message: String? = nil,
        kind: AppNotification.Kind? = nil,
        progress: Double? = nil,
        autoDismissAfter: TimeInterval? = nil
    ) {
        // Update the tracking entry if this is a progress notification so
        // complete() will use the latest title/message.
        if var entry = progressTracking[id] {
            if let title { entry.title = title }
            if let message { entry.message = message }
            progressTracking[id] = entry
        }
    }

    @MainActor
    func complete(
        id: UUID,
        kind: AppNotification.Kind = .success,
        title: String? = nil,
        message: String? = nil,
        autoDismissAfter: TimeInterval = 4
    ) {
        // Resolve the best title/message: prefer override params, fall back to
        // what was tracked at post() time.
        let tracked = progressTracking.removeValue(forKey: id)
        let finalTitle   = title   ?? tracked?.title   ?? ""
        let finalMessage = message ?? tracked?.message ?? ""

        deliverSystemNotification(id: id, kind: kind, title: finalTitle, message: finalMessage)
    }

    @MainActor
    func dismiss(id: UUID) {
        progressTracking.removeValue(forKey: id)
        withdrawSystemNotification(id: id)
    }

    @MainActor
    func dismissAll() {
        progressTracking.removeAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - System Notification Delivery

    private func deliverSystemNotification(
        id: UUID,
        kind: AppNotification.Kind,
        title: String,
        message: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = (kind == .error) ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: id.uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[AppNotificationCenter] Failed to deliver system notification: \(error.localizedDescription)")
            }
        }
    }

    private func withdrawSystemNotification(id: UUID) {
        let identifier = id.uuidString
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppNotificationCenter: UNUserNotificationCenterDelegate {
    /// Show the notification banner + play sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Handle a user tapping a delivered notification (bring app to front on macOS).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - AppNotification.Kind helpers

extension AppNotificationCenter.AppNotification.Kind {
    var accentColor: Color {
        switch self {
        case .info:     return DesignSystem.Colors.info
        case .success:  return DesignSystem.Colors.success
        case .warning:  return DesignSystem.Colors.warning
        case .error:    return DesignSystem.Colors.error
        case .progress: return DesignSystem.Colors.info
        }
    }

    var iconSystemName: String {
        switch self {
        case .info:     return "info.circle.fill"
        case .success:  return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .error:    return "xmark.octagon.fill"
        case .progress: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}
