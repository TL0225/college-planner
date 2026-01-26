import Foundation
import SwiftUI
import Combine

final class AppNotificationCenter: ObservableObject {
    static let shared = AppNotificationCenter()

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

    @Published private(set) var notifications: [AppNotification] = []

    private init() {}

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
        let clamped = progress.map { min(max($0, 0), 1) }
        let id = UUID()
        let item = AppNotification(
            id: id,
            kind: kind,
            title: title,
            message: message,
            progress: clamped,
            createdAt: Date(),
            isDismissible: isDismissible,
            autoDismissAfter: autoDismissAfter
        )

        notifications.insert(item, at: 0)
        scheduleAutoDismissIfNeeded(id: id)
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
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }

        if let title { notifications[idx].title = title }
        if let message { notifications[idx].message = message }
        if let kind { notifications[idx].kind = kind }
        if let progress { notifications[idx].progress = min(max(progress, 0), 1) }
        if let autoDismissAfter { notifications[idx].autoDismissAfter = autoDismissAfter }

        scheduleAutoDismissIfNeeded(id: id)
    }

    @MainActor
    func complete(
        id: UUID,
        kind: AppNotification.Kind = .success,
        title: String? = nil,
        message: String? = nil,
        autoDismissAfter: TimeInterval = 4
    ) {
        update(
            id: id,
            title: title,
            message: message,
            kind: kind,
            progress: 1,
            autoDismissAfter: autoDismissAfter
        )
    }

    @MainActor
    func dismiss(id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    @MainActor
    func dismissAll() {
        notifications.removeAll()
    }

    @MainActor
    private func scheduleAutoDismissIfNeeded(id: UUID) {
        guard let item = notifications.first(where: { $0.id == id }) else { return }
        guard let delay = item.autoDismissAfter else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            // Only dismiss if it still exists.
            if self.notifications.contains(where: { $0.id == id }) {
                self.dismiss(id: id)
            }
        }
    }
}

extension AppNotificationCenter.AppNotification.Kind {
    var accentColor: Color {
        switch self {
        case .info:
            return DesignSystem.Colors.info
        case .success:
            return DesignSystem.Colors.success
        case .warning:
            return DesignSystem.Colors.warning
        case .error:
            return DesignSystem.Colors.error
        case .progress:
            return DesignSystem.Colors.info
        }
    }

    var iconSystemName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .progress:
            return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}
