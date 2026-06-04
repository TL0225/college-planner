// CareerSceneMaintenanceCoordinator.swift
// Feature: Career
// Purpose: Career module — CareerSceneMaintenanceCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Coalesces scene-active Career maintenance (ingest, reconcile, Workday refresh)
/// so `onAppear` and scene-phase transitions do not duplicate work.
@MainActor
final class CareerSceneMaintenanceCoordinator {
    static let shared = CareerSceneMaintenanceCoordinator()

    private var scheduledTask: Task<Void, Never>?
    private var coalesceToken = UUID()
    private var lastRunAt: Date?

    /// Minimum gap between full maintenance passes (ingest + reconcile + refresh).
    private static let maintenanceCooldown: TimeInterval = 30
    private static let coalesceDelayNanoseconds: UInt64 = 400_000_000

    private init() {}

    func schedule(bootstrapWorkdayBoard: Bool) {
        coalesceToken = UUID()
        let token = coalesceToken
        scheduledTask?.cancel()
        scheduledTask = Task {
            try? await Task.sleep(nanoseconds: Self.coalesceDelayNanoseconds)
            guard !Task.isCancelled, token == coalesceToken else { return }
            await runIfNeeded(bootstrapWorkdayBoard: bootstrapWorkdayBoard, token: token)
        }
    }

    private func runIfNeeded(bootstrapWorkdayBoard: Bool, token: UUID) async {
        guard !Task.isCancelled, token == coalesceToken else { return }

        if AppActivityCoordinator.shared.isResourceThrottled {
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, token == coalesceToken else { return }
                if !AppActivityCoordinator.shared.isResourceThrottled { break }
            }
            guard !AppActivityCoordinator.shared.isResourceThrottled else { return }
        }

        if let lastRunAt,
           Date().timeIntervalSince(lastRunAt) < Self.maintenanceCooldown {
            if bootstrapWorkdayBoard {
                WorkdayJobBoardSyncCoordinator.shared.start()
            }
            return
        }

        lastRunAt = Date()

        if bootstrapWorkdayBoard {
            WorkdayJobBoardSyncCoordinator.shared.start()
        }
        await CareerIngestCoordinator.shared.processPendingIngestIfNeeded()
        await CareerIngestCoordinator.shared.processPendingSaveRequests()
        CareerFollowUpScheduler.shared.reconcile(using: CollegePersistence.shared)
        await WorkdayRefreshScheduler.shared.refreshOverdueCompaniesIfNeeded()
    }
}
