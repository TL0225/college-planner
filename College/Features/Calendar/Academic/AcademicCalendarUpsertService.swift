// AcademicCalendarUpsertService.swift
// Feature: Calendar
// Purpose: Reconciling upsert for scraped academic calendar events.

import CollegeCalendar
import Foundation
import SwiftData

@MainActor
enum AcademicCalendarUpsertService {
    private static let removalDropThreshold = 0.5

    /// Tombstone removals only when the incoming snapshot looks complete (not an outage/partial parse).
    static func shouldAllowRemovals(priorCount: Int, incomingCount: Int, threshold: Double = removalDropThreshold) -> Bool {
        guard incomingCount > 0 else { return false }
        guard priorCount > 0 else { return true }
        return Double(incomingCount) >= Double(priorCount) * (1.0 - threshold)
    }

    static func reconcile(
        config: AcademicCalendarConfig,
        incoming: [AcademicCalendarParsedEvent],
        scrapeID: UUID,
        activeScopeKeys: Set<String>
    ) async -> AcademicCalendarSyncResult {
        var ledger = AcademicCalendarStore.loadLedger(configID: config.configID)
        let deletedKeys = AcademicCalendarStore.loadDeletedKeys(configID: config.configID)
        let repo = AppDataStore.shared.calendarRepository

        var changes: [AcademicCalendarSyncChange] = []
        var added = 0
        var changed = 0
        var removed = 0
        var skipped = 0
        var moved = 0

        let scopedIncoming = incoming.filter { activeScopeKeys.contains($0.scopeKey) }
        let priorScopedCount = ledger.filter { activeScopeKeys.contains($0.scopeKey) }.count
        let allowRemovals = shouldAllowRemovals(priorCount: priorScopedCount, incomingCount: scopedIncoming.count)

        var resolved: [(event: AcademicCalendarParsedEvent, entry: AcademicCalendarLedgerEntry?)] = []
        for event in scopedIncoming {
            if deletedKeys.contains(event.identityKey) {
                skipped += 1
                changes.append(AcademicCalendarSyncChange(
                    id: event.id,
                    kind: .suppressed,
                    title: event.title,
                    detail: "Previously removed",
                    event: event,
                    fromScope: nil,
                    toScope: nil
                ))
                continue
            }
            if event.status == .cancelled {
                skipped += 1
                continue
            }
            let match = AcademicCalendarIdentityResolver.matchIncoming(event: event, ledger: ledger, schoolID: config.schoolID)
            resolved.append((event, match?.entry))
        }

        let unmatchedIncoming = resolved.filter { $0.entry == nil }.map(\.event)
        let scopedLedger = ledger.filter { activeScopeKeys.contains($0.scopeKey) }
        let unmatchedLedger = scopedLedger.filter { old in
            !resolved.contains(where: { $0.entry?.identityKey == old.identityKey })
        }
        let movePairs = AcademicCalendarIdentityResolver.detectCrossScopeMoves(removed: unmatchedLedger, added: unmatchedIncoming)

        for (old, newEvent) in movePairs {
            moved += 1
            if let idx = ledger.firstIndex(where: { $0.identityKey == old.identityKey }) {
                ledger[idx].scopeKey = newEvent.scopeKey
                ledger[idx].importedSnapshot = snapshot(from: newEvent)
                ledger[idx].lastSeenScrapeID = scrapeID
            }
            _ = try? repo.upsertCalendarEvent(
                id: old.localID,
                title: newEvent.title,
                startDate: newEvent.startDate,
                endDate: newEvent.endDate,
                allDay: newEvent.allDay,
                notes: newEvent.notes,
                providerSource: config.providerSource,
                providerEventId: newEvent.providerEventId
            )
            changes.append(AcademicCalendarSyncChange(
                id: old.identityKey,
                kind: .moved,
                title: newEvent.title,
                detail: "Moved \(old.scopeKey) -> \(newEvent.scopeKey)",
                event: newEvent,
                fromScope: old.scopeKey,
                toScope: newEvent.scopeKey
            ))
        }

        for pair in resolved {
            let event = pair.event
            if movePairs.contains(where: { $0.added.id == event.id }) { continue }

            if let entry = pair.entry {
                let newSnapshot = snapshot(from: event)
                if entry.importedSnapshot != newSnapshot {
                    if entry.promptVersion != AcademicCalendarPrompt.version {
                        updateLedgerEntry(&ledger, entryID: entry.identityKey, event: event, scrapeID: scrapeID)
                        continue
                    }
                    if entry.userModified || userModifiedLive(entry: entry) {
                        skipped += 1
                        changes.append(AcademicCalendarSyncChange(
                            id: entry.identityKey,
                            kind: .userModifiedConflict,
                            title: event.title,
                            detail: "Upstream changed; kept your edit",
                            event: event,
                            fromScope: entry.scopeKey,
                            toScope: nil
                        ))
                        continue
                    }
                    if shouldSkipHolidayDuplicate(event, config: config) {
                        skipped += 1
                        continue
                    }
                    _ = try? repo.upsertCalendarEvent(
                        id: entry.localID,
                        title: event.title,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        allDay: event.allDay,
                        notes: event.notes,
                        providerSource: config.providerSource,
                        providerEventId: event.providerEventId
                    )
                    updateLedgerEntry(&ledger, entryID: entry.identityKey, event: event, scrapeID: scrapeID)
                    changed += 1
                    changes.append(AcademicCalendarSyncChange(id: entry.identityKey, kind: .changed, title: event.title, detail: nil, event: event, fromScope: entry.scopeKey, toScope: nil))
                } else {
                    updateLedgerEntry(&ledger, entryID: entry.identityKey, event: event, scrapeID: scrapeID)
                }
            } else {
                if shouldSkipHolidayDuplicate(event, config: config) {
                    skipped += 1
                    continue
                }
                let localID = UUID()
                _ = try? repo.upsertCalendarEvent(
                    id: localID,
                    title: event.title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    allDay: event.allDay,
                    notes: event.notes,
                    providerSource: config.providerSource,
                    providerEventId: event.providerEventId
                )
                let entry = AcademicCalendarLedgerEntry(
                    localID: localID,
                    identityKey: event.identityKey,
                    identitySignature: event.identitySignature,
                    scopeKey: event.scopeKey,
                    importedSnapshot: snapshot(from: event),
                    status: event.status,
                    confidence: event.confidence,
                    promptVersion: AcademicCalendarPrompt.version,
                    userModified: false,
                    lastSeenScrapeID: scrapeID
                )
                ledger.append(entry)
                added += 1
                changes.append(AcademicCalendarSyncChange(id: event.id, kind: .added, title: event.title, detail: nil, event: event, fromScope: nil, toScope: event.scopeKey))
            }
        }

        if allowRemovals {
            let incomingKeys = Set(resolved.compactMap { $0.entry?.identityKey } + resolved.filter { $0.entry == nil }.map { $0.event.identityKey })
            for old in scopedLedger where !incomingKeys.contains(old.identityKey) {
                if movePairs.contains(where: { $0.removed.identityKey == old.identityKey }) { continue }
                if old.userModified {
                    skipped += 1
                    continue
                }
                try? repo.deleteCalendarEvent(id: old.localID)
                ledger.removeAll { $0.identityKey == old.identityKey }
                removed += 1
                changes.append(AcademicCalendarSyncChange(id: old.identityKey, kind: .removed, title: old.importedSnapshot.title, detail: nil, event: nil, fromScope: old.scopeKey, toScope: nil))
            }
        }

        for idx in ledger.indices {
            if userModifiedLive(entry: ledger[idx]) {
                ledger[idx].userModified = true
            }
        }

        AcademicCalendarStore.saveLedger(configID: config.configID, entries: ledger)
        AcademicCalendarStore.saveDeletedKeys(configID: config.configID, keys: deletedKeys)
        _ = try? AppDataStore.shared.profileSave()
        CollegePersistence.shared.notifyCalendarDidChange()

        return AcademicCalendarSyncResult(
            scrapeID: scrapeID,
            added: added,
            changed: changed,
            removed: removed,
            skipped: skipped,
            moved: moved,
            changes: changes,
            parsedEvents: scopedIncoming,
            path: .scrape,
            error: allowRemovals ? nil : "Skipped removals: low-confidence snapshot"
        )
    }

    private static func snapshot(from event: AcademicCalendarParsedEvent) -> AcademicCalendarImportedSnapshot {
        AcademicCalendarImportedSnapshot(
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            allDay: event.allDay,
            notes: event.notes,
            status: event.status
        )
    }

    private static func updateLedgerEntry(
        _ ledger: inout [AcademicCalendarLedgerEntry],
        entryID: String,
        event: AcademicCalendarParsedEvent,
        scrapeID: UUID
    ) {
        guard let idx = ledger.firstIndex(where: { $0.identityKey == entryID }) else { return }
        ledger[idx].importedSnapshot = snapshot(from: event)
        ledger[idx].identitySignature = event.identitySignature
        ledger[idx].scopeKey = event.scopeKey
        ledger[idx].status = event.status
        ledger[idx].confidence = event.confidence
        ledger[idx].promptVersion = AcademicCalendarPrompt.version
        ledger[idx].lastSeenScrapeID = scrapeID
    }

    private static func userModifiedLive(entry: AcademicCalendarLedgerEntry) -> Bool {
        guard let live = try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: entry.localID) else {
            return false
        }
        let snap = entry.importedSnapshot
        return live.title != snap.title
            || live.startDate != snap.startDate
            || live.endDate != snap.endDate
            || (live.notes ?? "") != (snap.notes ?? "")
    }

    private static func shouldSkipHolidayDuplicate(_ event: AcademicCalendarParsedEvent, config: AcademicCalendarConfig) -> Bool {
        let overlapping = (try? AppDataStore.shared.calendarRepository.fetchEventsOverlapping(
            start: event.startDate,
            end: event.endDate,
            limit: 20
        )) ?? []
        return overlapping.contains { other in
            other.providerSource != config.providerSource
                && AcademicCalendarTitleNormalizer.areNearDuplicates(other.title, event.title)
        }
    }
}
