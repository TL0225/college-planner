import Foundation

/// Sendable event fields for visibility filtering without SwiftData coupling.
public struct CalendarVisibilityEventInput: Sendable {
    public let localID: String
    public let providerSource: String?
    public let courseCode: String?

    public init(localID: String, providerSource: String?, courseCode: String?) {
        self.localID = localID
        self.providerSource = providerSource
        self.courseCode = courseCode
    }
}

/// Snapshot of calendar visibility toggles for off-main cache rebuild (Phase 3 P0).
public struct CalendarVisibilityFilter: Sendable {
    public let enabledCalendarIDs: Set<String>
    public let disabledAcademicsIDs: Set<String>
    public let connectedCalendarIDs: Set<String>
    public let googleRemoteKeyByLocalIDLower: [String: String]
    public let appleExternalIDByLocalIDLower: [String: String]
    public let appleToggleIDByExternalID: [String: String]
    public let primaryGoogleCalendarRemoteID: String?

    public init(
        enabledCalendarIDs: Set<String>,
        disabledAcademicsIDs: Set<String>,
        connectedCalendarIDs: Set<String>,
        googleRemoteKeyByLocalIDLower: [String: String],
        appleExternalIDByLocalIDLower: [String: String],
        appleToggleIDByExternalID: [String: String],
        primaryGoogleCalendarRemoteID: String?
    ) {
        self.enabledCalendarIDs = enabledCalendarIDs
        self.disabledAcademicsIDs = disabledAcademicsIDs
        self.connectedCalendarIDs = connectedCalendarIDs
        self.googleRemoteKeyByLocalIDLower = googleRemoteKeyByLocalIDLower
        self.appleExternalIDByLocalIDLower = appleExternalIDByLocalIDLower
        self.appleToggleIDByExternalID = appleToggleIDByExternalID
        self.primaryGoogleCalendarRemoteID = primaryGoogleCalendarRemoteID
    }

    private static let googleRemoteKeySeparator = "||"

    public func shouldDisplay(_ event: CalendarVisibilityEventInput) -> Bool {
        let localID = event.localID
        let normalizedCourseCode = event.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if event.providerSource == "CollegeApp" {
            let appleID = academicsToggleID(courseCode: normalizedCourseCode)
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
            if !normalizedCourseCode.isEmpty {
                let academicsID = "Academics:\(normalizedCourseCode.uppercased())"
                if disabledAcademicsIDs.contains(academicsID) { return false }
            }
            return true
        }

        if let externalID = appleExternalIDByLocalIDLower[localID.lowercased()] {
            let toggleID = appleToggleIDByExternalID[externalID] ?? "AppleSystem:\(externalID)"
            if !connectedCalendarIDs.contains(toggleID) { return true }
            guard enabledCalendarIDs.contains(toggleID) else { return false }
            if !normalizedCourseCode.isEmpty {
                let academicsID = "Academics:\(normalizedCourseCode.uppercased())"
                if disabledAcademicsIDs.contains(academicsID) { return false }
            }
            return true
        }

        let appleID = academicsToggleID(courseCode: normalizedCourseCode)
        if appleID.hasPrefix("Academics:") {
            return !disabledAcademicsIDs.contains(appleID)
        }
        if connectedCalendarIDs.contains(appleID) {
            return enabledCalendarIDs.contains(appleID)
        }
        return true
    }

    private func academicsToggleID(courseCode: String) -> String {
        if !courseCode.isEmpty {
            return "Academics:\(courseCode.uppercased())"
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
