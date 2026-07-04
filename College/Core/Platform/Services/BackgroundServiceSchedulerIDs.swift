// BackgroundServiceSchedulerIDs.swift
// Feature: Core/Platform
// Purpose: Stable NSBackgroundActivityScheduler identifiers (single source of truth).

import Foundation

enum BackgroundServiceSchedulerIDs {
    static let icsSubscriptionRefresh = "com.college.calendar.ics-refresh"
    static let academicCalendarRefresh = "com.college.calendar.academic-refresh"
    static let calendarGoogleProviderSync = "com.college.calendar.google-provider-sync"
    static let calendarOutlookProviderSync = "com.college.calendar.outlook-provider-sync"
    static let calendarICloudProviderSync = "com.college.calendar.icloud-provider-sync"
    static let jobBoardRefresh = "com.college.jobboard.refresh"
    /// Legacy alias kept during transition.
    static let jobBoardRefreshLegacy = "com.college.workday.refresh"
}
