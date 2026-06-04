// CalendarVisibilityFilter.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarVisibilityFilter.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Snapshot of calendar visibility toggles for off-main cache rebuild (Phase 3 P0).
struct CalendarVisibilityFilter: Sendable {
    let enabledCalendarIDs: Set<String>
    let disabledAcademicsIDs: Set<String>
    let connectedCalendarIDs: Set<String>
    let googleRemoteKeyByLocalIDLower: [String: String]
    let appleExternalIDByLocalIDLower: [String: String]
    let appleToggleIDByExternalID: [String: String]
    let primaryGoogleCalendarRemoteID: String?

    private static let googleRemoteKeySeparator = "||"

    func shouldDisplay(_ event: CalendarEvent) -> Bool {
        let localID = event.id.uuidString

        if event.providerSource == "CollegeApp" {
            let appleID = academicsToggleID(for: event)
            if appleID.hasPrefix("Academics:") {
                return !disabledAcademicsIDs.contains(appleID)
            }
            if connectedCalendarIDs.contains(appleID) {
                return enabledCalendarIDs.contains(appleID)
            }
            return true
        }

        if let remoteKey = googleRemoteKeyByLocalIDLower[localID.lowercased()] {
            let parsed = Self.parseGoogleRemoteKey(remoteKey)
            let toggleID = googleToggleID(forCalendarID: parsed.calendarID)
            if !connectedCalendarIDs.contains(toggleID) { return true }
            guard enabledCalendarIDs.contains(toggleID) else { return false }
            let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !code.isEmpty {
                let academicsID = "Academics:\(code.uppercased())"
                if disabledAcademicsIDs.contains(academicsID) { return false }
            }
            return true
        }

        if let externalID = appleExternalIDByLocalIDLower[localID.lowercased()] {
            let toggleID = appleToggleIDByExternalID[externalID] ?? "AppleSystem:\(externalID)"
            if !connectedCalendarIDs.contains(toggleID) { return true }
            guard enabledCalendarIDs.contains(toggleID) else { return false }
            if let course = event.course {
                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    let academicsID = "Academics:\(code.uppercased())"
                    if disabledAcademicsIDs.contains(academicsID) { return false }
                }
            }
            return true
        }

        let appleID = academicsToggleID(for: event)
        if appleID.hasPrefix("Academics:") {
            return !disabledAcademicsIDs.contains(appleID)
        }
        if connectedCalendarIDs.contains(appleID) {
            return enabledCalendarIDs.contains(appleID)
        }
        return true
    }

    private func academicsToggleID(for event: CalendarEvent) -> String {
        let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !code.isEmpty {
            return "Academics:\(code.uppercased())"
        }
        return "Apple:Home"
    }

    private func googleToggleID(forCalendarID calendarID: String) -> String {
        if calendarID == "primary", let primaryGoogleCalendarRemoteID {
            return "Google:\(primaryGoogleCalendarRemoteID)"
        }
        return "Google:\(calendarID)"
    }

    private static func parseGoogleRemoteKey(_ key: String) -> (calendarID: String, eventID: String) {
        let parts = key.components(separatedBy: googleRemoteKeySeparator)
        if parts.count >= 2 {
            let calendarID = parts[0]
            let eventID = parts[1...].joined(separator: googleRemoteKeySeparator)
            return (calendarID, eventID)
        }
        return ("primary", key)
    }
}

/// Background-safe calendar fetches for cache rebuild.
enum CalendarFetchQuery {
    static func hasMirroredCalendarRows(context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<CalendarEvent>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    static func hasMirroredPlannerTaskRows(context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<PlannerTask>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    static func fetchEventsOverlapping(
        start: Date,
        end: Date,
        limit: Int,
        context: ModelContext
    ) throws -> [CalendarEvent] {
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.startDate < end && event.endDate > start
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    static func fetchTasks(
        dueFrom start: Date,
        dueBefore end: Date,
        limit: Int,
        context: ModelContext
    ) throws -> [PlannerTask] {
        let pageLimit = min(max(limit, 1), 400)
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { task in
                task.isCompleted == false
            },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = pageLimit * 2
        return Array(
            try context.fetch(descriptor)
                .filter { task in
                    guard let due = task.dueDate else { return false }
                    return due >= start && due < end
                }
                .prefix(pageLimit)
        )
    }
}
