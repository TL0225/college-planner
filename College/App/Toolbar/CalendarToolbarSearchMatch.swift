// CalendarToolbarSearchMatch.swift
// Feature: App / Toolbar
// Purpose: Calendar toolbar search result row model.

import Foundation

struct CalendarToolbarSearchMatch: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
}
