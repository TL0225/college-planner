// CalendarSyncIngestIntegrationTests.swift
// Ingest dedup and attachment linking integration tests.

import CollegeCalendar
import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarSyncIngestIntegrationTests: PersistenceTestCase {
    func testICloudIngestReusesLocalUUIDFromICalTag() async throws {
        let eventID = UUID()
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        let end = start.addingTimeInterval(3600)
        let repo = CalendarRepository(context: profileContext)
        _ = try repo.upsertCalendarEvent(
            id: eventID,
            title: "Existing",
            startDate: start,
            endDate: end,
            allDay: false,
            providerSource: "CollegeApp"
        )
        ModelMergeCoalescer.flushNow()

        let snap = CalendarSyncIngestService.ICloudEventSnapshot(
            mapKey: "https://caldav.example/cal||uid-1",
            providerEventId: "uid-1",
            title: "Renamed on iCloud",
            start: start.addingTimeInterval(3_600),
            end: end.addingTimeInterval(3_600),
            isAllDay: false,
            location: "Room 101",
            notes: nil,
            localUUIDFromICal: eventID
        )

        let updates = try await CalendarSyncIngestService.ingestICloudSnapshots(
            snapshots: [snap],
            currentMap: [:],
            store: .shared
        )

        XCTAssertEqual(updates[snap.mapKey], eventID.uuidString)
        let events = try profileContext.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, eventID)
        XCTAssertEqual(events.first?.title, "Renamed on iCloud")
    }

    func testLinkedAttachmentsReloadAfterVaultLink() throws {
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        let repo = CalendarRepository(context: profileContext)
        let event = try repo.createCalendarEvent(
            title: "With Files",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            allDay: false
        )
        ModelMergeCoalescer.flushNow()

        let document = VaultDocument(
            id: UUID(),
            fileName: "Syllabus.pdf",
            category: VaultDocumentCategory.other.rawValue,
            fileSizeBytes: 128,
            localRelativePath: "test-doc.colenc"
        )
        profileContext.insert(document)
        try profileContext.save()

        let vault = AppDataStore.shared.vaultRepository
        try vault.linkVaultDocumentToCalendarEvent(id: document.id, eventID: event.id)
        ModelMergeCoalescer.flushNow()

        let linked = try vault.fetchDocuments(linkedCalendarEventID: event.id)
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked.first?.id, document.id)
    }

    func testGoogleIngestReusesExistingProviderEventId() async throws {
        let eventID = UUID()
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        let end = start.addingTimeInterval(3600)
        let repo = CalendarRepository(context: profileContext)
        _ = try repo.upsertCalendarEvent(
            id: eventID,
            title: "Lecture",
            startDate: start,
            endDate: end,
            allDay: false,
            providerSource: "CollegeApp",
            providerEventId: "google-event-123"
        )
        ModelMergeCoalescer.flushNow()

        let movedStart = start.addingTimeInterval(86_400)
        let snap = CalendarSyncIngestService.GoogleEventSnapshot(
            remoteKey: "primary||google-event-123",
            legacyKey: "google-event-123",
            providerEventId: "google-event-123",
            title: "Lecture",
            start: movedStart,
            end: movedStart.addingTimeInterval(3600),
            isAllDay: false,
            location: nil,
            notes: nil,
            status: nil,
            customColorHex: nil,
            recurrenceRule: nil,
            attendeesJSON: nil,
            isCancelled: false
        )

        let result = try await CalendarSyncIngestService.ingestGoogleSnapshots(
            snapshots: [snap],
            calendarID: "primary",
            currentMap: [:],
            mappedLocalIDsLower: [],
            deletedTombstones: [],
            store: .shared
        )

        XCTAssertEqual(result.newCount, 0)
        let events = try profileContext.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, eventID)
        XCTAssertEqual(events.first?.startDate, movedStart)
        XCTAssertEqual(result.mapUpdates[snap.remoteKey], eventID.uuidString)
    }

    func testGoogleIngestPreservesCollegeOwnedCoreFields() async throws {
        let eventID = UUID()
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        let end = start.addingTimeInterval(3600)
        let repo = CalendarRepository(context: profileContext)
        _ = try repo.upsertCalendarEvent(
            id: eventID,
            title: "Local Title",
            startDate: start,
            endDate: end,
            allDay: false,
            notes: "Local notes",
            location: "Room A",
            providerSource: "CollegeApp",
            providerEventId: "google-owned-1"
        )
        ModelMergeCoalescer.flushNow()

        let snap = CalendarSyncIngestService.GoogleEventSnapshot(
            remoteKey: "primary||google-owned-1",
            legacyKey: "google-owned-1",
            providerEventId: "google-owned-1",
            title: "Remote Title",
            start: start.addingTimeInterval(3_600),
            end: end.addingTimeInterval(3_600),
            isAllDay: false,
            location: "Room B",
            notes: "Remote notes",
            status: nil,
            customColorHex: "ff887c",
            recurrenceRule: nil,
            attendeesJSON: nil,
            isCancelled: false
        )

        _ = try await CalendarSyncIngestService.ingestGoogleSnapshots(
            snapshots: [snap],
            calendarID: "primary",
            currentMap: [snap.remoteKey: eventID.uuidString],
            mappedLocalIDsLower: [eventID.uuidString.lowercased()],
            deletedTombstones: [],
            store: .shared
        )

        let event = try XCTUnwrap(try repo.fetchCalendarEvent(id: eventID))
        XCTAssertEqual(event.title, "Local Title")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.location, "Room A")
        XCTAssertEqual(event.notes, "Local notes")
        XCTAssertEqual(event.providerEventId, "google-owned-1")
    }
}
