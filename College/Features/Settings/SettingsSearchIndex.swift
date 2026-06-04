// SettingsSearchIndex.swift
// Feature: Settings
// Purpose: Settings module — Hit.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// When adding a new searchable settings row, add an entry here so sidebar search and suggestions stay accurate.
/// Deep keyword → settings pane routing (System Settings–style search).
enum SettingsSearchIndex {
    struct Hit: Identifiable, Hashable {
        /// Stable across launches for SwiftUI lists.
        var id: String { "\(section.rawValue)|\(title)" }
        let section: SettingsNavSection
        let title: String
        let subtitle: String
    }

    /// One logical search row: section to open, suggestion labels, and flattened lowercase text for token matching.
    private struct Row {
        let section: SettingsNavSection
        let suggestionTitle: String
        let suggestionSubtitle: String
        /// Space-joined keywords / title fragments, lowercase (for token AND matching).
        let searchBlob: String
    }

    private static let rows: [Row] = [
        Row(section: .profile, suggestionTitle: "Profile", suggestionSubtitle: "Profile", searchBlob: "profile account name email password student sign in open profile tab"),
        Row(section: .profile, suggestionTitle: "Email", suggestionSubtitle: "Profile", searchBlob: "email account student sign in"),
        Row(section: .academics, suggestionTitle: "Academic Catalog", suggestionSubtitle: "Academics", searchBlob: "catalog sync academics courses programs import school skeleton scrape majors requirements trusted sources"),
        Row(section: .academics, suggestionTitle: "Reset scraped catalog", suggestionSubtitle: "Academics", searchBlob: "reset scraped catalog clear nyu delete requirements cache purge rescrape honors baseline"),
        Row(section: .academics, suggestionTitle: "Trusted catalog sources", suggestionSubtitle: "Academics", searchBlob: "trusted catalog sources bundle signing fingerprint"),
        Row(section: .academics, suggestionTitle: "Assignment reminders", suggestionSubtitle: "Academics", searchBlob: "assignment due reminders grades notifications academics"),
        Row(section: .academics, suggestionTitle: "Grade updates", suggestionSubtitle: "Academics", searchBlob: "grade updates notifications academics"),
        Row(section: .calendar, suggestionTitle: "Calendar", suggestionSubtitle: "Calendar", searchBlob: "calendar events google icloud outlook sync reminders duration work hours ics subscription privacy mirror mute notifications"),
        Row(section: .calendar, suggestionTitle: "Connected calendars", suggestionSubtitle: "Calendar", searchBlob: "connected calendars integrations google icloud outlook caldav app password connect disconnect"),
        Row(section: .calendar, suggestionTitle: "Google Calendar", suggestionSubtitle: "Calendar", searchBlob: "google calendar connect oauth sync"),
        Row(section: .calendar, suggestionTitle: "iCloud Calendar", suggestionSubtitle: "Calendar", searchBlob: "icloud apple id calendar caldav app-specific password"),
        Row(section: .calendar, suggestionTitle: "Outlook Calendar", suggestionSubtitle: "Calendar", searchBlob: "outlook microsoft graph calendar"),
        Row(section: .calendar, suggestionTitle: "Event reminders", suggestionSubtitle: "Calendar", searchBlob: "event reminders notifications calendar"),
        Row(section: .career, suggestionTitle: "Career board", suggestionSubtitle: "Career", searchBlob: "career board kanban resumes analytics keyboard navigation quick add"),
        Row(section: .career, suggestionTitle: "Job boards", suggestionSubtitle: "Career", searchBlob: "job boards workday greenhouse lever oracle icims talemetry jobvite careers scrape openings refresh companies myworkdayjobs integration ats"),
        Row(section: .assistant, suggestionTitle: "Assistant model", suggestionSubtitle: "Assistant", searchBlob: "assistant ai model llm gemma syllabus download install storage"),
        Row(section: .assistant, suggestionTitle: "Web search", suggestionSubtitle: "Assistant", searchBlob: "assistant web search searx startpage semantic memory streaming diagnostics response length"),
        Row(section: .assistant, suggestionTitle: "Runtime diagnostics", suggestionSubtitle: "Assistant", searchBlob: "runtime diagnostics memory llm loaded idle release catalog store path resident"),
        Row(section: .documents, suggestionTitle: "Documents", suggestionSubtitle: "Documents", searchBlob: "documents vault files storage watchdog screenshots folder triage stale files"),
        Row(section: .brightspace, suggestionTitle: "Brightspace", suggestionSubtitle: "Brightspace", searchBlob: "brightspace lms portal learn url session password cookies ublearns buffalo"),
        Row(section: .shortcuts, suggestionTitle: "Web Shortcuts", suggestionSubtitle: "Shortcuts", searchBlob: "web shortcuts links bookmark sidebar"),
        Row(section: .app, suggestionTitle: "Appearance", suggestionSubtitle: "App", searchBlob: "appearance theme dark light mode motion reduce glass background density font"),
        Row(section: .app, suggestionTitle: "App Updates", suggestionSubtitle: "App", searchBlob: "app updates update software version github download release check college"),
        Row(section: .app, suggestionTitle: "Time Zone", suggestionSubtitle: "App", searchBlob: "time zone timezone automatic region scheduling language date format"),
        Row(section: .app, suggestionTitle: "Notifications", suggestionSubtitle: "App", searchBlob: "notifications desktop alerts email digest"),
        Row(section: .privacyAndData, suggestionTitle: "Security", suggestionSubtitle: "Privacy & Data", searchBlob: "security encryption touch id password lock wipe student data privacy overview"),
        Row(section: .privacyAndData, suggestionTitle: "Backup", suggestionSubtitle: "Privacy & Data", searchBlob: "backup export import restore collegebackup"),
        Row(section: .privacyAndData, suggestionTitle: "Diagnostics", suggestionSubtitle: "Privacy & Data", searchBlob: "diagnostics telemetry logs debug performance unlock console"),
    ]

    private static func queryTokens(_ raw: String) -> [Substring] {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { $0.isWhitespace || $0 == "-" }
            .filter { !$0.isEmpty }
    }

    /// Every query token must appear somewhere in the row’s search blob (AND semantics).
    private static func matchesAllTokens(tokens: [Substring], blob: String) -> Bool {
        guard !tokens.isEmpty else { return true }
        for t in tokens {
            if !blob.contains(t) { return false }
        }
        return true
    }

    private static func scoreRow(tokens: [Substring], fullQueryLower: String, row: Row) -> Int {
        guard matchesAllTokens(tokens: tokens, blob: row.searchBlob) else { return 0 }
        var score = 10
        let titleLower = row.suggestionTitle.lowercased()
        if titleLower == fullQueryLower { score += 200 }
        else if titleLower.hasPrefix(fullQueryLower) { score += 120 }
        else if titleLower.contains(fullQueryLower) { score += 90 }
        if row.section.rawValue.lowercased().contains(fullQueryLower) { score += 40 }
        if fullQueryLower.count >= 3, row.searchBlob.contains(fullQueryLower) { score += 30 }
        return score
    }

    static func suggestionHits(matching query: String, limit: Int = 12) -> [Hit] {
        let full = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokens = queryTokens(query)
        guard !full.isEmpty || !tokens.isEmpty else { return [] }

        var scored: [(Int, Hit)] = []
        for row in rows {
            let s = scoreRow(tokens: tokens.isEmpty ? [Substring(full)] : tokens, fullQueryLower: full, row: row)
            guard s > 0 else { continue }
            let hit = Hit(section: row.section, title: row.suggestionTitle, subtitle: row.suggestionSubtitle)
            scored.append((s, hit))
        }
        scored.sort { $0.0 > $1.0 }
        var seen = Set<String>()
        var out: [Hit] = []
        for (_, hit) in scored {
            let key = hit.id
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(hit)
            if out.count >= limit { break }
        }
        return out
    }

    static func visibleSections(forSearchText text: String) -> [SettingsNavSection] {
        let tokens = queryTokens(text)
        guard !tokens.isEmpty else { return SettingsNavSection.allCases }
        var sections = Set<SettingsNavSection>()
        for row in rows where matchesAllTokens(tokens: tokens, blob: row.searchBlob) {
            sections.insert(row.section)
        }
        if sections.isEmpty { return [] }
        return SettingsNavSection.allCases.filter { sections.contains($0) }
    }
}
