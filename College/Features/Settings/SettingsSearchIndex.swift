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
        /// Lowercased blob split into words, for prefix/stem-aware matching.
        let blobWords: [Substring]

        init(section: SettingsNavSection, suggestionTitle: String, suggestionSubtitle: String, searchBlob: String) {
            self.section = section
            self.suggestionTitle = suggestionTitle
            self.suggestionSubtitle = suggestionSubtitle
            // Fold the human-readable title into the blob so titles are always searchable.
            let blob = (searchBlob + " " + suggestionTitle).lowercased()
            self.searchBlob = blob
            self.blobWords = blob.split { $0.isWhitespace || $0 == "-" || $0 == "/" }
        }
    }

    private static let rows: [Row] = [
        // MARK: Profile
        Row(section: .profile, suggestionTitle: "Profile", suggestionSubtitle: "Profile", searchBlob: "profile account name email password student sign in avatar photo college school major minor graduation year gpa open profile tab"),
        Row(section: .profile, suggestionTitle: "Email & Account", suggestionSubtitle: "Profile", searchBlob: "email account student sign in credentials login"),

        // MARK: Academics (catalog)
        Row(section: .academics, suggestionTitle: "Academic Catalog", suggestionSubtitle: "Academics", searchBlob: "catalog sync academics courses programs import school skeleton scrape majors minors requirements degree audit trusted sources"),
        Row(section: .academics, suggestionTitle: "Catalog Sync", suggestionSubtitle: "Academics", searchBlob: "catalog sync background refresh update scrape rescrape programs courses"),
        Row(section: .academics, suggestionTitle: "Reset Scraped Catalog", suggestionSubtitle: "Academics", searchBlob: "reset scraped catalog clear delete requirements cache purge rescrape honors baseline"),
        Row(section: .academics, suggestionTitle: "Trusted Catalog Sources", suggestionSubtitle: "Academics", searchBlob: "trusted catalog sources bundle signing fingerprint verification"),
        Row(section: .academics, suggestionTitle: "Assignment Reminders", suggestionSubtitle: "Academics", searchBlob: "assignment due reminders deadlines grades notifications"),
        Row(section: .academics, suggestionTitle: "Grade Updates", suggestionSubtitle: "Academics", searchBlob: "grade updates changes notifications gpa"),

        // MARK: Calendar
        Row(section: .calendar, suggestionTitle: "Calendar", suggestionSubtitle: "Calendar", searchBlob: "calendar events google icloud outlook sync reminders duration work hours ics subscription privacy mirror"),
        Row(section: .calendar, suggestionTitle: "Connected Calendars", suggestionSubtitle: "Calendar", searchBlob: "connected calendars accounts integrations google icloud apple outlook microsoft caldav app password connect disconnect"),
        Row(section: .calendar, suggestionTitle: "Google Calendar", suggestionSubtitle: "Calendar", searchBlob: "google calendar connect oauth sync account"),
        Row(section: .calendar, suggestionTitle: "iCloud Calendar", suggestionSubtitle: "Calendar", searchBlob: "icloud apple id calendar caldav app specific password"),
        Row(section: .calendar, suggestionTitle: "Outlook Calendar", suggestionSubtitle: "Calendar", searchBlob: "outlook microsoft graph calendar office 365"),
        Row(section: .calendar, suggestionTitle: "General Calendar Options", suggestionSubtitle: "Calendar", searchBlob: "first day of week default event duration default reminder default calendar show week numbers"),
        Row(section: .calendar, suggestionTitle: "Default Calendar", suggestionSubtitle: "Calendar", searchBlob: "default calendar where new events are created"),
        Row(section: .calendar, suggestionTitle: "Event Popover", suggestionSubtitle: "Calendar", searchBlob: "event popover detail level leave by late risk eta estimated arrival meeting actions render markdown auto link urls provider metadata transport mode driving walking"),
        Row(section: .calendar, suggestionTitle: "Lateness Signals", suggestionSubtitle: "Calendar", searchBlob: "lateness late risk prep buffer grace period escalation lead time leave by"),
        Row(section: .calendar, suggestionTitle: "Work Hours", suggestionSubtitle: "Calendar", searchBlob: "work hours dim non work start end business hours"),
        Row(section: .calendar, suggestionTitle: "Weekends", suggestionSubtitle: "Calendar", searchBlob: "weekend visibility show dim hide saturday sunday"),
        Row(section: .calendar, suggestionTitle: "Sleep-Friendly Scheduling", suggestionSubtitle: "Calendar", searchBlob: "sleep friendly scheduling typical day starts ends bedtime warn late events"),
        Row(section: .calendar, suggestionTitle: "Academic Priorities", suggestionSubtitle: "Calendar", searchBlob: "grade weight badge threshold study block length study buffer scheduler"),
        Row(section: .calendar, suggestionTitle: "Calendar Feed Subscriptions", suggestionSubtitle: "Calendar", searchBlob: "subscribe subscribed subscription subscriptions ics webcal rss atom feed url add subscription import external google outlook calendar feed"),
        Row(section: .calendar, suggestionTitle: "University Term Dates", suggestionSubtitle: "Calendar", searchBlob: "university term dates academic calendar registrar semester quarter holidays breaks add drop deadlines finals scrape refresh school important dates import webpage"),
        Row(section: .calendar, suggestionTitle: "Notification Muting", suggestionSubtitle: "Calendar", searchBlob: "notification muting mute muted silence per calendar notifications bell slash disable alerts"),
        Row(section: .calendar, suggestionTitle: "Event Reminders", suggestionSubtitle: "Calendar", searchBlob: "event reminders notifications alerts default reminder"),
        Row(section: .calendar, suggestionTitle: "Time Zone", suggestionSubtitle: "Calendar", searchBlob: "time zone timezone region calendar"),

        // MARK: Career
        Row(section: .career, suggestionTitle: "Career Board", suggestionSubtitle: "Career", searchBlob: "career board kanban applications resumes analytics keyboard navigation quick add tracker"),
        Row(section: .career, suggestionTitle: "Job Boards", suggestionSubtitle: "Career", searchBlob: "job boards workday greenhouse lever oracle icims talemetry jobvite careers scrape openings refresh companies myworkdayjobs integration ats postings"),

        // MARK: Assistant
        Row(section: .assistant, suggestionTitle: "Assistant Model", suggestionSubtitle: "Assistant", searchBlob: "assistant ai model llm gemma mlx syllabus download install storage on device local"),
        Row(section: .assistant, suggestionTitle: "Web Search", suggestionSubtitle: "Assistant", searchBlob: "assistant web search searx startpage semantic memory streaming diagnostics response length"),
        Row(section: .assistant, suggestionTitle: "Planner Indexing", suggestionSubtitle: "Assistant", searchBlob: "planner indexing consent context personal data assistant"),
        Row(section: .assistant, suggestionTitle: "Runtime Diagnostics", suggestionSubtitle: "Assistant", searchBlob: "runtime diagnostics memory llm loaded idle release catalog store path resident"),

        // MARK: Documents
        Row(section: .documents, suggestionTitle: "Documents", suggestionSubtitle: "Documents", searchBlob: "documents vault files storage watchdog screenshots folder triage stale files organize"),

        // MARK: LMS
        Row(section: .lms, suggestionTitle: "Learning Management System", suggestionSubtitle: "LMS", searchBlob: "brightspace blackboard canvas moodle lms learning management system portal learn url session password cookies sign in sign out clear session"),

        // MARK: Shortcuts
        Row(section: .shortcuts, suggestionTitle: "Web Shortcuts", suggestionSubtitle: "Shortcuts", searchBlob: "web shortcuts links bookmark sidebar groups grouping favicon custom icon reorder drag drop"),
        Row(section: .shortcuts, suggestionTitle: "Shortcut Groups", suggestionSubtitle: "Shortcuts", searchBlob: "shortcut groups grouping organize folder collapse expand"),

        // MARK: App
        Row(section: .app, suggestionTitle: "Appearance", suggestionSubtitle: "App", searchBlob: "appearance theme dark light mode motion reduce glass background density font size accent color"),
        Row(section: .app, suggestionTitle: "App Updates", suggestionSubtitle: "App", searchBlob: "app updates update software version github download release check automatic"),
        Row(section: .app, suggestionTitle: "Time Zone & Region", suggestionSubtitle: "App", searchBlob: "time zone timezone automatic region scheduling language date format locale"),
        Row(section: .app, suggestionTitle: "Notifications", suggestionSubtitle: "App", searchBlob: "notifications desktop alerts email digest banners sounds"),

        // MARK: Privacy & Data
        Row(section: .privacyAndData, suggestionTitle: "Security", suggestionSubtitle: "Privacy & Data", searchBlob: "security encryption touch id face id password lock biometrics wipe erase student data privacy overview"),
        Row(section: .privacyAndData, suggestionTitle: "Backup & Restore", suggestionSubtitle: "Privacy & Data", searchBlob: "backup export import restore collegebackup save data migrate transfer"),
        Row(section: .privacyAndData, suggestionTitle: "Diagnostics", suggestionSubtitle: "Privacy & Data", searchBlob: "diagnostics telemetry logs debug performance unlock console health crash memory metrickit export support bundle diagnostics center"),
        Row(section: .privacyAndData, suggestionTitle: "Diagnostics Center", suggestionSubtitle: "Privacy & Data", searchBlob: "diagnostics center health crash logs export support bundle performance memory catalog assistant"),
        Row(section: .privacyAndData, suggestionTitle: "Export Diagnostics", suggestionSubtitle: "Privacy & Data", searchBlob: "export diagnostics support bundle zip logs crash health share"),
        Row(section: .privacyAndData, suggestionTitle: "Erase / Wipe Data", suggestionSubtitle: "Privacy & Data", searchBlob: "wipe erase delete all data reset factory remove account"),
    ]

    private static func queryTokens(_ raw: String) -> [Substring] {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { $0.isWhitespace || $0 == "-" || $0 == "/" }
            .filter { !$0.isEmpty }
    }

    /// A token matches a row when it is a substring of the blob, or it shares a stem with any
    /// blob word (prefix either direction). This makes "muting"↔"mute", "subscribed"↔"subscribe",
    /// and "notification"↔"notifications" all resolve without exhaustive keyword lists.
    private static func tokenMatches(_ token: Substring, row: Row) -> Bool {
        if row.searchBlob.contains(token) { return true }
        guard token.count >= 3 else { return false }
        for word in row.blobWords {
            if word.count < 3 { continue }
            if word.hasPrefix(token) || token.hasPrefix(word) { return true }
        }
        return false
    }

    /// Every query token must match the row (AND semantics across tokens).
    private static func matchesAllTokens(tokens: [Substring], row: Row) -> Bool {
        guard !tokens.isEmpty else { return true }
        for t in tokens where !tokenMatches(t, row: row) {
            return false
        }
        return true
    }

    private static func scoreRow(tokens: [Substring], fullQueryLower: String, row: Row) -> Int {
        guard matchesAllTokens(tokens: tokens, row: row) else { return 0 }
        var score = 10
        let titleLower = row.suggestionTitle.lowercased()
        if titleLower == fullQueryLower { score += 200 }
        else if titleLower.hasPrefix(fullQueryLower) { score += 120 }
        else if titleLower.contains(fullQueryLower) { score += 90 }
        // Reward each token that appears at the start of a title word (strong relevance signal).
        let titleWords = titleLower.split { $0.isWhitespace }
        for t in tokens where titleWords.contains(where: { $0.hasPrefix(t) }) {
            score += 25
        }
        if row.section.rawValue.lowercased().contains(fullQueryLower) { score += 40 }
        if fullQueryLower.count >= 3, row.searchBlob.contains(fullQueryLower) { score += 30 }
        return score
    }

    static func suggestionHits(matching query: String, limit: Int = 16) -> [Hit] {
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
        for row in rows where matchesAllTokens(tokens: tokens, row: row) {
            sections.insert(row.section)
        }
        if sections.isEmpty { return [] }
        return SettingsNavSection.allCases.filter { sections.contains($0) }
    }
}
