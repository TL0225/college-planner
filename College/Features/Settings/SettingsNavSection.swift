// SettingsNavSection.swift
// Feature: Settings
// Purpose: Settings module — SettingsNavSection.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Settings sidebar destinations aligned with main app tabs (+ global App / Privacy & Data).
enum SettingsNavSection: String, CaseIterable, Hashable {
    case profile = "Profile"
    case academics = "Academics"
    case calendar = "Calendar"
    case career = "Career"
    case assistant = "Assistant"
    case documents = "Documents"
    case lms = "LMS"
    case shortcuts = "Shortcuts"
    case app = "App"
    case privacyAndData = "Privacy & Data"

    /// User-facing sidebar / detail title (localized).
    var displayName: String {
        switch self {
        case .profile:
            return String(localized: "settings.section.profile", defaultValue: "Profile")
        case .academics:
            return String(localized: "settings.section.academics", defaultValue: "Academics")
        case .calendar:
            return String(localized: "settings.section.calendar", defaultValue: "Calendar")
        case .career:
            return String(localized: "settings.section.career", defaultValue: "Career")
        case .assistant:
            return String(localized: "settings.section.assistant", defaultValue: "Assistant")
        case .documents:
            return String(localized: "settings.section.documents", defaultValue: "Documents")
        case .lms:
            return LMSPortalConfiguration.lmsDisplayName
        case .shortcuts:
            return String(localized: "settings.section.shortcuts", defaultValue: "Shortcuts")
        case .app:
            return String(localized: "settings.section.app", defaultValue: "App")
        case .privacyAndData:
            return String(localized: "settings.section.privacy", defaultValue: "Privacy & Data")
        }
    }

    var icon: String {
        switch self {
        case .profile: return "person.circle"
        case .academics: return "graduationcap"
        case .calendar: return "calendar"
        case .career: return "briefcase"
        case .assistant: return "sparkles"
        case .documents: return "folder"
        case .lms: return "globe"
        case .shortcuts: return "link.circle"
        case .app: return "slider.horizontal.3"
        case .privacyAndData: return "lock.shield"
        }
    }

    var accessibilityIdentifier: String {
        "settings.section.\(rawValue.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "&", with: "and"))"
    }

    /// Maps legacy sidebar / notification raw values to the current section.
    static func resolved(fromRaw raw: String) -> SettingsNavSection? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = SettingsNavSection(rawValue: trimmed) {
            return match
        }
        switch trimmed {
        case "Brightspace":
            return .lms
        case "General", "Appearance", "Notifications":
            return .app
        case "Account":
            return .profile
        case "Connected Apps":
            return .calendar
        case "Web Shortcuts":
            return .shortcuts
        case "Privacy":
            return .privacyAndData
        case "Job Boards":
            return .career
        default:
            return nil
        }
    }
}

extension SettingsNavSection {
    static func fromAssistantToken(_ raw: String) -> SettingsNavSection? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "profile", "account":
            return .profile
        case "academics", "catalog", "school":
            return .academics
        case "calendar", "schedule":
            return .calendar
        case "career", "jobs", "job_boards", "jobboards":
            return .career
        case "assistant", "ai", "copilot":
            return .assistant
        case "documents", "vault":
            return .documents
        case "brightspace", "lms":
            return .lms
        case "shortcuts", "web_shortcuts", "web shortcuts":
            return .shortcuts
        case "app", "general", "appearance", "theme", "notifications":
            return .app
        case "privacy", "privacy_and_data", "security", "backup":
            return .privacyAndData
        default:
            return SettingsNavSection(rawValue: raw)
        }
    }
}
