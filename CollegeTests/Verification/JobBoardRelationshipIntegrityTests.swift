// JobBoardRelationshipIntegrityTests.swift
// Snow Leopard DM-R3: WorkdayJobPosting ↔ JobApplication link integrity.

import SwiftData
import XCTest
@testable import College

@MainActor
final class JobBoardRelationshipIntegrityTests: PersistenceTestCase {
    func testWorkdayPostingApplicationRelationshipRoundTrip() throws {
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "JR-100")
        posting.title = "Engineer"
        let application = JobApplication(statusRaw: "interested")
        application.title = "Engineer"
        application.company = "Acme"
        application.workdaySourcePosting = posting
        posting.trackedApplication = application

        profileContext.insert(posting)
        profileContext.insert(application)
        try profileContext.save()

        let postingID = posting.id
        let fresh = ModelContext(AppDataStore.shared.profileContainer)
        var descriptor = FetchDescriptor<WorkdayJobPosting>(
            predicate: #Predicate { $0.id == postingID }
        )
        descriptor.fetchLimit = 1
        let reloaded = try XCTUnwrap(try fresh.fetch(descriptor).first)
        XCTAssertEqual(reloaded.trackedApplication?.id, application.id)
        XCTAssertEqual(reloaded.trackedApplication?.workdaySourcePosting?.id, postingID)
    }
}
