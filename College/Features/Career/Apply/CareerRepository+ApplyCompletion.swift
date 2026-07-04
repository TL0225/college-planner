// CareerRepository+ApplyCompletion.swift
// Feature: Core/Data
// Purpose: Wire apply session completion into Board Applied + resume lineage.

import Foundation
import SwiftData
import CollegeCareer

extension CareerRepository {
    func recordApplyCompletion(
        applicationID: UUID,
        session: CareerApplySession,
        appliedAt: Date,
        fillReport: CareerApplyVerificationReport
    ) throws {
        try moveApplication(id: applicationID, to: .applied)
        guard let application = try fetchApplication(id: applicationID) else { return }
        application.dateApplied = appliedAt
        try finalizeSubmittedResume(application: application, resumeDocumentID: session.resumeDocumentID, session: session)
        application.provenanceJSON = mergeApplyProvenance(
            existing: application.provenanceJSON,
            session: session,
            fillReport: fillReport
        )
        let event = CareerEvent(id: UUID(), completed: true)
        event.title = "Applied via College"
        event.notes = "Completed apply session for \(session.jobTitle)"
        event.date = appliedAt
        event.application = application
        context.insert(event)
        try context.save()
        CareerSpotlightIndexer.index(application: application)
    }

    private func finalizeSubmittedResume(
        application: JobApplication,
        resumeDocumentID: UUID,
        session: CareerApplySession
    ) throws {
        guard let resume = try VaultRepository(context: context).fetchDocument(id: resumeDocumentID) else { return }
        application.submittedResume = resume
        application.resumeDisplayName = resume.customDisplayName ?? resume.fileName
        let meta = careerResumeMetadata(for: resume)
        application.submittedResumeContentHash = meta.parsedTextHash
        if let posting = application.workdaySourcePosting,
           let path = posting.externalPath,
           let match = try? fetchResumeJobMatch(
               companySlug: posting.companySlug,
               externalPath: path,
               resumeDocumentID: resumeDocumentID
           ) {
            application.matchScoreAtSubmission = match.overallScore
            application.matchResultJSONAtSubmission = match.resultJSON
        }
        _ = session
    }

    private func mergeApplyProvenance(
        existing: String?,
        session: CareerApplySession,
        fillReport: CareerApplyVerificationReport
    ) -> String {
        struct ApplyProvenanceEntry: Codable {
            var applySessionID: UUID
            var platform: String
            var completedAt: Date
            var mapVersion: String?
            var manualOnly: Bool
            var wrongValueCount: Int
            var writeAttemptCount: Int
        }
        var entries: [ApplyProvenanceEntry] = []
        if let existing,
           let data = existing.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ApplyProvenanceEntry].self, from: data) {
            entries = decoded
        }
        entries.append(
            ApplyProvenanceEntry(
                applySessionID: session.id,
                platform: session.platform.rawValue,
                completedAt: Date(),
                mapVersion: fillReport.mapVersion ?? session.mapVersion,
                manualOnly: session.status == .manualOnly,
                wrongValueCount: fillReport.wrongValueCount,
                writeAttemptCount: fillReport.writeAttemptCount
            )
        )
        return (try? JSONEncoder().encode(entries)).flatMap { String(data: $0, encoding: .utf8) } ?? existing ?? ""
    }
}
