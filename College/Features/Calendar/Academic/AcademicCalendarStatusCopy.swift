// AcademicCalendarStatusCopy.swift
// Feature: Calendar
// Purpose: User-visible status strings for academic calendar import flows.

import Foundation

enum AcademicCalendarStatusCopy {
  static func bannerTitle(for status: AcademicCalendarImportStatus?) -> String {
    switch status {
    case .discovering:
      return String(localized: "calendar.banner.discovering_title", defaultValue: "Finding your school's calendar…")
    case .resolving:
      return String(localized: "calendar.banner.resolving_title", defaultValue: "Matching your program's calendar…")
    case .needsChoice:
      return String(localized: "calendar.banner.needs_choice_title", defaultValue: "Choose your term calendar")
    case .previewReady:
      return String(localized: "calendar.banner.preview_title", defaultValue: "Review term dates before importing")
    case .needsAttention:
      return String(localized: "calendar.banner.needs_attention_title", defaultValue: "Term calendar needs attention")
    case .needsHelp:
      return String(localized: "calendar.banner.needs_help_title", defaultValue: "We need your help with term dates")
    case .imported, .notStarted, .none:
      return String(localized: "calendar.banner.import_title", defaultValue: "Import university term dates")
    }
  }

  static func bannerSubtitle(
    status: AcademicCalendarImportStatus?,
    departmentName: String?,
    isDegraded: Bool
  ) -> String {
    if isDegraded {
      return String(
        localized: "calendar.banner.degraded_subtitle",
        defaultValue: "Using your program name to find the right calendar. College details will refine matching after catalog sync."
      )
    }
    if let departmentName, !departmentName.isEmpty {
      return String(
        format: String(
          localized: "calendar.banner.department_subtitle",
          defaultValue: "Importing dates for %@."
        ),
        departmentName
      )
    }
    switch status {
    case .needsHelp:
      return String(
        localized: "calendar.banner.needs_help_subtitle",
        defaultValue: "Paste your registrar's academic calendar link in Settings, or pick from suggested calendars."
      )
    case .needsAttention:
      return String(
        localized: "calendar.banner.needs_attention_subtitle",
        defaultValue: "Your school's calendar page may have changed. Open Settings to update or re-import."
      )
    default:
      return String(
        localized: "calendar.banner.default_subtitle",
        defaultValue: "Registration deadlines, breaks, and finals from your school's official calendar."
      )
    }
  }

  static func honestyFooter() -> String {
    String(
      localized: "calendar.banner.honesty_footer",
      defaultValue: "We match calendars using your program and school catalog when available. Some schools still need a quick manual pick."
    )
  }

  static func failureMessage(for error: String?) -> String {
    guard let error, !error.isEmpty else {
      return String(
        localized: "calendar.failure.generic",
        defaultValue: "Couldn't import term dates. Try a more specific calendar URL."
      )
    }
    return error
  }
}
