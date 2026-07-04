// CalendarSyncExportBridge.swift
// Feature: Calendar
// Purpose: Tier 2 on-demand bridge for calendar provider export after local writes.

import CollegeCalendar
import Foundation

@MainActor
enum CalendarSyncExportBridge {
    static func exportAfterWriteAndReport(
        eventID: UUID,
        options: CalendarEventWriteOptions = .init()
    ) async -> CalendarExportAfterWriteResult {
        return await BackgroundServiceOnDemand.runReturning(id: "calendar_sync_export") {
            await CalendarEventWritePipeline.shared.exportAfterWriteAndReport(
                eventID: eventID,
                options: options
            )
        }
    }
}
