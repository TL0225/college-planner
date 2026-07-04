// AcademicCalendarIdentityResolver.swift
// Feature: Calendar
// Purpose: Stable per-event identity matching for ICS and scraped sources.

import Foundation

enum AcademicCalendarIdentityResolver {
    static func makeScopeKey(term: String, year: Int, level: AcademicCalendarLevelScope, subCalendarURL: String?) -> String {
        let sub = (subCalendarURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(term.lowercased())|\(year)|\(level.rawValue)|\(sub)"
    }

    static func scrapedIdentityKey(schoolID: String, scopeKey: String, title: String, startDay: String) -> String {
        let seed = "\(schoolID)|\(scopeKey)|\(AcademicCalendarTitleNormalizer.normalizeTitle(title))|\(startDay)"
        return "scraped:\(stableHash(seed))"
    }

    static func icsIdentityKey(uid: String) -> String {
        "ics:\(uid.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    static func dayString(_ date: Date, timeZoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = AcademicCalendarTimezone.calendar(for: timeZoneID)
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    struct MatchResult: Sendable {
        var entry: AcademicCalendarLedgerEntry
        var matchedBySignature: Bool
    }

    static func matchIncoming(
        event: AcademicCalendarParsedEvent,
        ledger: [AcademicCalendarLedgerEntry],
        schoolID: String
    ) -> MatchResult? {
        if let exact = ledger.first(where: { $0.identityKey == event.identityKey }) {
            return MatchResult(entry: exact, matchedBySignature: false)
        }

        let signature = event.identitySignature
        if let sigMatch = ledger.first(where: { $0.identitySignature == signature }) {
            return MatchResult(entry: sigMatch, matchedBySignature: true)
        }

        let candidates = ledger.filter { $0.scopeKey == event.scopeKey }
        if let dateTitle = candidates.first(where: {
            dayString($0.importedSnapshot.startDate, timeZoneID: TimeZone.current.identifier) == dayString(event.startDate, timeZoneID: TimeZone.current.identifier)
                && AcademicCalendarTitleNormalizer.areNearDuplicates($0.importedSnapshot.title, event.title)
        }) {
            return MatchResult(entry: dateTitle, matchedBySignature: true)
        }

        if let nearby = candidates.first(where: {
            AcademicCalendarTitleNormalizer.normalizeTitle($0.importedSnapshot.title) == AcademicCalendarTitleNormalizer.normalizeTitle(event.title)
                && abs($0.importedSnapshot.startDate.timeIntervalSince(event.startDate)) <= 7 * 86_400
        }) {
            return MatchResult(entry: nearby, matchedBySignature: true)
        }

        return nil
    }

    static func detectCrossScopeMoves(
        removed: [AcademicCalendarLedgerEntry],
        added: [AcademicCalendarParsedEvent]
    ) -> [(removed: AcademicCalendarLedgerEntry, added: AcademicCalendarParsedEvent)] {
        var pairs: [(AcademicCalendarLedgerEntry, AcademicCalendarParsedEvent)] = []
        var usedAdded = Set<String>()
        for old in removed {
            if let match = added.first(where: { added in
                !usedAdded.contains(added.id)
                    && added.scopeKey != old.scopeKey
                    && added.identitySignature == old.identitySignature
            }) {
                pairs.append((old, match))
                usedAdded.insert(match.id)
            }
        }
        return pairs
    }
}
