// CalendarInspectorAccessibility.swift
// Feature: Calendar
// Purpose: Shared accessibility labels and hints for the event inspector.

import SwiftUI

public enum CalendarInspectorAccessibility {
    public static let closeInspectorHint = "Closes the event inspector without deleting the event."
    public static let saveAndSyncHint = "Saves changes locally and syncs to connected calendars."
    public static let createEventHint = "Creates this event and syncs to connected calendars."
    public static let timeCardHint = "Set start and end dates, times, all-day, and recurrence."
    public static let locationCardHint = "Enter an address or pick a place on the map."
    public static let courseCardHint = "Link this event to a planner course."
    public static let descriptionCardHint = "Notes sync to connected calendars when you save."
    public static let eventDetailsHint = "Calendar destinations, color, alerts, travel, guests, and files."
    public static let deleteEventHint = "Permanently removes this event from College and connected calendars."
    public static let resendInvitesHint = "Retries sending guest invites through connected calendars."
}

public extension View {
    func inspectorAccessibility(label: String, hint: String) -> some View {
        accessibilityLabel(label)
            .accessibilityHint(hint)
    }
}
