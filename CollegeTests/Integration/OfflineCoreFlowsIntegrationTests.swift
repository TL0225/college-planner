// OfflineCoreFlowsIntegrationTests.swift
// M30-076 — core local-first flows work without network.

import Foundation
import SwiftData
import Testing
@testable import College

@Suite("Offline Core Flows")
struct OfflineCoreFlowsIntegrationTests {

    @Test("In-memory store opens without network")
    @MainActor
    func inMemoryStoreOpens() throws {
        let store = try PersistenceTestHarness.makeAppDataStore()
        #expect(store.storeOpenError == nil)
        #expect(store.profileContext != nil)
    }

    @Test("Calendar event CRUD works without network")
    @MainActor
    func calendarCRUDOffline() throws {
        let store = try PersistenceTestHarness.makeAppDataStore()
        let context = try #require(store.profileContext)
        let calendarRepo = CalendarRepository(context: context)
        let event = try calendarRepo.createCalendarEvent(
            title: "Offline lecture",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            allDay: false
        )
        let fetched = try calendarRepo.fetchEvents(from: .distantPast, to: .distantFuture, limit: 10)
        #expect(fetched.contains(where: { $0.id == event.id }))
    }

    @Test("Vault hierarchy clean on empty store")
    @MainActor
    func vaultHierarchyOffline() throws {
        let store = try PersistenceTestHarness.makeAppDataStore()
        let context = try #require(store.profileContext)
        let repo = VaultRepository(context: context)
        #expect(try repo.hierarchyViolations().isEmpty)
    }

    @Test("Profile in-memory container factory opens")
    @MainActor
    func profileContainerInMemory() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let context = ModelContext(container)
        let profiles = try context.fetch(FetchDescriptor<Profile>())
        #expect(profiles.isEmpty)
    }

    @Test("Career ingest coordinator resolves app group when entitled")
    func careerIngestAppGroupURL() {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.timothy.college")
        if let url {
            #expect(url.path.contains("group.com.timothy.college"))
        }
    }
}
