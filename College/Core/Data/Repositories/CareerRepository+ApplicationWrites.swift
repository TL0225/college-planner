// CareerRepository+ApplicationWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerRepository+ApplicationWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

extension CareerRepository {
    private static let companyNotesKey = "companyNotes"
    private static let companyNotesNormalizedKey = "companyNotesNormalized"
    private static let networkingNotesKey = "networkingNotes"
    private static let interviewPipelineStageKey = "careerInterviewPipelineStage.v1"
    private static let offerBonusKey = "careerOfferBonus.v1"
    private static let offerSigningKey = "careerOfferSigning.v1"
    private static let offerEquityKey = "careerOfferEquity.v1"
    private static let careerPriorityKey = "careerPriority.v1"
    private static let careerPriorityDefaultKey = "career.priority.default"

    @discardableResult
    func addApplication(
        title: String,
        company: String,
        postingURLString: String,
        jobDescriptionText: String,
        interviewStatus: String,
        applicationDeadline: Date?,
        status: CareerApplicationStatus,
        source: String = "manual",
        sourceRequestId: UUID? = nil,
        extractedKeywordsJSON: String? = nil,
        locationText: String? = nil,
        baseSalaryText: String? = nil
    ) throws -> JobApplication {
        let application = JobApplication(
            id: UUID(),
            statusRaw: status.rawValue,
            sortOrder: try nextSortOrder(for: status)
        )
        application.createdAt = Date()
        application.updatedAt = Date()
        application.lastStatusChangeAt = Date()
        application.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        application.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        application.interviewStatus = interviewStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        application.applicationDeadline = applicationDeadline
        application.postingURLString = postingURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        application.jobDescriptionText = jobDescriptionText
        application.source = source
        application.sourceRequestId = sourceRequestId
        application.extractedKeywordsJSON = extractedKeywordsJSON
        application.locationText = locationText
        application.baseSalaryText = baseSalaryText
        if status == .applied {
            application.dateApplied = Date()
        }
        context.insert(application)
        try saveAndBump()
        return application
    }

    func moveApplication(id: UUID, to status: CareerApplicationStatus) throws {
        guard let application = try fetchApplication(id: id) else { return }
        let nextOrder = try nextSortOrder(for: status)
        guard application.statusRaw != status.rawValue || application.sortOrder != nextOrder else { return }
        application.statusRaw = status.rawValue
        application.sortOrder = nextOrder
        application.updatedAt = Date()
        application.lastStatusChangeAt = Date()
        if status == .applied, application.dateApplied == nil {
            application.dateApplied = Date()
        }
        try saveAndBump()
    }

    func deleteApplication(_ application: JobApplication) throws {
        if let posting = application.workdaySourcePosting {
            posting.trackedApplication = nil
        }
        context.delete(application)
        try cleanupJobBoardRelationshipOrphans()
        try saveAndBump()
    }

    func cleanupJobBoardRelationshipOrphans() throws {
        var postingDescriptor = FetchDescriptor<JobBoardPosting>()
        postingDescriptor.fetchLimit = 5000
        for posting in try context.fetch(postingDescriptor) {
            guard let app = posting.trackedApplication else { continue }
            if try fetchApplication(id: app.id) == nil {
                posting.trackedApplication = nil
            }
        }
    }

    func upsertApplication(from saveRequest: CareerSaveRequest) throws {
        let requestID = saveRequest.requestId
        var descriptor = FetchDescriptor<JobApplication>(
            predicate: #Predicate { $0.sourceRequestId == requestID }
        )
        descriptor.fetchLimit = 1
        let application: JobApplication
        if let existing = try context.fetch(descriptor).first {
            application = existing
        } else {
            application = JobApplication(
                id: UUID(),
                statusRaw: CareerApplicationStatus.interested.rawValue,
                sortOrder: try nextSortOrder(for: .interested)
            )
            application.createdAt = Date()
            application.source = "shareExtension"
            application.sourceRequestId = saveRequest.requestId
            context.insert(application)
        }
        application.updatedAt = Date()
        application.title = saveRequest.title
        application.company = saveRequest.company
        application.baseSalaryText = saveRequest.baseSalary
        application.locationText = saveRequest.location
        application.postingURLString = saveRequest.postingURL
        application.applicationDeadline = saveRequest.applicationDeadline
        application.jobDescriptionText = saveRequest.jobDescription
        application.extractedKeywordsJSON = (try? String(
            data: JSONEncoder().encode(saveRequest.keywords),
            encoding: .utf8
        )) ?? "[]"
        try saveAndBump()
    }

    @discardableResult
    func quickAddInterested(companyName: String) throws -> JobApplication {
        try addApplication(
            title: "New Role",
            company: companyName,
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .interested
        )
    }

    func fetchApplicationsForFollowUp() throws -> [JobApplication] {
        try fetchApplications(limit: 250)
    }

    func networkingKPIs() throws -> CareerNetworkingKPIs {
        let contacts = try context.fetch(FetchDescriptor<RecruiterContact>()).count
        let appliedRaw = CareerApplicationStatus.applied.rawValue
        let interviewingRaw = CareerApplicationStatus.interviewing.rawValue
        let followUps = try fetchApplications(limit: 250).filter {
            $0.statusRaw == appliedRaw || $0.statusRaw == interviewingRaw
        }.count
        let coffee = try context.fetch(FetchDescriptor<CareerEvent>()).filter {
            ($0.kindRaw ?? "") == "coffee"
        }.count
        return CareerNetworkingKPIs(
            contacts: contacts,
            followUpsQueued: followUps,
            coffeeEvents: coffee
        )
    }

    func priority(for application: JobApplication) -> CareerKanbanTheme.Priority {
        let payload = decodeJSONDictionary(application.provenanceJSON)
        let stored = (payload[Self.careerPriorityKey] ?? "").lowercased()
        if let parsed = CareerKanbanTheme.Priority(rawValue: stored) {
            return parsed
        }
        return defaultPriority()
    }

    func setPriority(_ priority: CareerKanbanTheme.Priority, for application: JobApplication) throws {
        var payload = decodeJSONDictionary(application.provenanceJSON)
        payload[Self.careerPriorityKey] = priority.rawValue
        application.provenanceJSON = encodeJSONDictionary(payload)
        application.updatedAt = Date()
        try saveAndBump()
    }

    func defaultPriority() -> CareerKanbanTheme.Priority {
        let raw = (UserDefaults.standard.string(forKey: Self.careerPriorityDefaultKey) ?? "").lowercased()
        return CareerKanbanTheme.Priority(rawValue: raw) ?? .low
    }

    func networkingNotes(for application: JobApplication) -> String {
        decodeJSONDictionary(application.provenanceJSON)[Self.networkingNotesKey] ?? ""
    }

    func setNetworkingNotes(_ notes: String, for application: JobApplication) throws {
        var payload = decodeJSONDictionary(application.provenanceJSON)
        payload[Self.networkingNotesKey] = notes
        application.provenanceJSON = encodeJSONDictionary(payload)
        application.updatedAt = Date()
        try saveAndBump()
    }

    func offerCompensationPackage(for application: JobApplication) -> CareerOfferCompensationPackage {
        let payload = decodeJSONDictionary(application.provenanceJSON)
        return CareerOfferCompensationPackage(
            bonusText: payload[Self.offerBonusKey] ?? "",
            signingText: payload[Self.offerSigningKey] ?? "",
            equityText: payload[Self.offerEquityKey] ?? ""
        )
    }

    func setOfferCompensationPackage(
        _ package: CareerOfferCompensationPackage,
        for application: JobApplication
    ) throws {
        var payload = decodeJSONDictionary(application.provenanceJSON)
        payload[Self.offerBonusKey] = package.bonusText
        payload[Self.offerSigningKey] = package.signingText
        payload[Self.offerEquityKey] = package.equityText
        application.provenanceJSON = encodeJSONDictionary(payload)
        application.updatedAt = Date()
        try saveAndBump()
    }

    func markFollowUpComplete(for application: JobApplication) throws {
        let event = CareerEvent(id: UUID(), completed: true)
        event.kindRaw = "followupComplete"
        event.title = "Follow-up completed"
        event.date = Date()
        event.application = application
        context.insert(event)
        application.lastStatusChangeAt = Date()
        application.updatedAt = Date()
        try saveAndBump()
    }

    func snoozeFollowUp(for application: JobApplication, days: Int = 3) throws {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let event = CareerEvent(id: UUID(), completed: false)
        event.kindRaw = "followupSnooze"
        event.title = "Snoozed follow-up"
        event.date = date
        event.application = application
        context.insert(event)
        application.lastStatusChangeAt = Date()
        application.updatedAt = Date()
        try saveAndBump()
    }

    func fetchNetworkingQueueApplications() throws -> [JobApplication] {
        let appliedRaw = CareerApplicationStatus.applied.rawValue
        let interviewingRaw = CareerApplicationStatus.interviewing.rawValue
        return try fetchApplications(limit: 250)
            .filter { $0.statusRaw == appliedRaw || $0.statusRaw == interviewingRaw }
            .sorted { lhs, rhs in
                let lk = urgencyKey(lhs)
                let rk = urgencyKey(rhs)
                if lk != rk { return lk < rk }
                let la = lhs.lastStatusChangeAt ?? lhs.updatedAt ?? lhs.createdAt ?? .distantPast
                let lb = rhs.lastStatusChangeAt ?? rhs.updatedAt ?? rhs.createdAt ?? .distantPast
                return la < lb
            }
    }

    @discardableResult
    func createOrphanRecruiterContact(
        fullName: String,
        roleTitle: String?,
        companyName: String,
        contactKindRaw: String,
        lastInteractionChannelRaw: String?,
        lastInteractionSummary: String?,
        followUpDate: Date?
    ) throws -> RecruiterContact {
        let contact = RecruiterContact(id: UUID(), isFavorite: false)
        contact.fullName = fullName
        contact.roleTitle = roleTitle
        contact.companyName = companyName
        contact.contactKindRaw = contactKindRaw
        contact.lastInteractionChannelRaw = lastInteractionChannelRaw
        contact.lastInteractionSummary = lastInteractionSummary
        contact.lastInteractionDetailedAt = Date()
        contact.lastContactedAt = Date()
        context.insert(contact)
        if let followUpDate {
            let event = CareerEvent(id: UUID(), completed: false)
            event.kindRaw = "followup"
            event.title = "Follow up"
            event.date = followUpDate
            event.recruiterContact = contact
            context.insert(event)
        }
        try saveAndBump()
        return contact
    }

    func logInteraction(
        for contact: RecruiterContact,
        kindRaw: String,
        date: Date,
        notes: String
    ) throws {
        let event = CareerEvent(id: UUID(), completed: false)
        event.kindRaw = kindRaw
        event.title = selectedInteractionTitle(kindRaw: kindRaw)
        event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        event.date = date
        event.recruiterContact = contact
        contact.lastInteractionDetailedAt = date
        contact.lastContactedAt = date
        context.insert(event)
        try saveAndBump()
    }

    private func selectedInteractionTitle(kindRaw: String) -> String {
        switch kindRaw {
        case "coffee": return "Coffee Chat"
        case "email": return "Email"
        case "linkedin": return "LinkedIn"
        case "phone": return "Phone Call"
        case "inperson": return "In Person"
        case "referral": return "Referral"
        default: return "Interaction"
        }
    }

    func deleteRecruiterContact(_ contact: RecruiterContact) throws {
        context.delete(contact)
        try saveAndBump()
    }

    func fetchOrphanRecruiterContacts() throws -> [RecruiterContact] {
        try context.fetch(FetchDescriptor<RecruiterContact>())
            .filter { $0.application == nil }
            .sorted { lhs, rhs in
                let da = lhs.lastInteractionDetailedAt ?? lhs.lastContactedAt ?? .distantPast
                let db = rhs.lastInteractionDetailedAt ?? rhs.lastContactedAt ?? .distantPast
                if da != db { return da > db }
                return (lhs.fullName ?? "") < (rhs.fullName ?? "")
            }
    }

    private func urgencyKey(_ app: JobApplication) -> Date {
        var soonest = Date.distantFuture
        if let deadline = app.applicationDeadline {
            soonest = min(soonest, deadline)
        }
        if let events = app.events {
            let threshold = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            for event in events where !event.completed {
                guard let date = event.date, date >= threshold else { continue }
                soonest = min(soonest, date)
            }
        }
        if soonest != .distantFuture { return soonest }
        return app.lastStatusChangeAt ?? app.updatedAt ?? app.createdAt ?? .distantFuture
    }

    private func nextSortOrder(for status: CareerApplicationStatus) throws -> Int32 {
        let statusRaw = status.rawValue
        let apps = try fetchApplications(limit: 250).filter { $0.statusRaw == statusRaw }
        let maxOrder = apps.map(\.sortOrder).max() ?? 0
        return maxOrder + 1
    }

    private func saveAndBump() throws {
        ModelMergeCoalescer.scheduleSave(context)
        ModelMergeCoalescer.flushNow()
        CollegePersistence.shared.bumpCareerRevision()
    }

    private func decodeJSONDictionary(_ json: String?) -> [String: String] {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func encodeJSONDictionary(_ dict: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}