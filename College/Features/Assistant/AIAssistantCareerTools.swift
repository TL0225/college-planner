// AIAssistantCareerTools.swift
// Feature: Assistant
// Purpose: Assistant module — JobApplicationSummaryPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CollegeCareer

struct JobApplicationSummaryPayload: Codable {
    let id: String
    let company: String
    let title: String
    let status: String
    let location: String?
}

struct JobApplicationListPayload: Codable {
    let applications: [JobApplicationSummaryPayload]
}

struct CareerResumeSummaryPayload: Codable {
    let id: String
    let displayName: String
    let parserCompliance: String?
    let detectedDomains: [String]
}

struct CareerResumeListPayload: Codable {
    let resumes: [CareerResumeSummaryPayload]
}

struct JobResumeMatchPayload: Codable {
    let applicationId: String?
    let companySlug: String?
    let externalPath: String?
    let recommendedResumeName: String?
    let overallScore: Int?
    let missingKeywords: [String]
    let tip: String?
}

struct JobApplicationDetailPayload: Codable {
    let id: String
    let company: String
    let title: String
    let status: String
    let location: String?
    let jobDescriptionSnippet: String?
    let matchScore: Int?
    let recommendedResumeName: String?
    let missingKeywords: [String]?
}

@MainActor
struct ListJobApplicationsTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "listJobApplications",
        description: "List job applications in the career tracker.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"status?\":\"applied|interviewing|offer\"}",
        outputSchemaDescription: "applications[]",
        sourceLabel: "JobApplication"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let statusFilter = arguments["status"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let apps = (try? context.collegePersistence.careerRepository.fetchApplications(limit: 100)) ?? []
        let filtered = apps.filter { app in
            guard let statusFilter, !statusFilter.isEmpty else { return true }
            let raw = app.statusRaw.lowercased()
            return raw == statusFilter || raw.contains(statusFilter)
        }
        let summaries = filtered.prefix(25).map { app in
            JobApplicationSummaryPayload(
                id: app.id.uuidString,
                company: app.company ?? "",
                title: app.title ?? "",
                status: app.statusRaw,
                location: app.locationText
            )
        }
        let payload = JobApplicationListPayload(applications: Array(summaries))
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Listed \(summaries.count) application(s).",
            errorMessage: nil
        )
    }
}

@MainActor
struct UpdateJobApplicationStatusTool: AIAssistantTool {
    private struct Arguments: Codable {
        let applicationId: String?
        let company: String?
        let title: String?
        let status: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "updateJobApplicationStatus",
        description: "Prepare a career application status change for confirmation.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .inline,
        inputSchemaDescription: "{\"applicationId?\":\"uuid\",\"company?\":\"Acme\",\"title?\":\"Engineer\",\"status\":\"interviewing\"}",
        outputSchemaDescription: "applicationId, status",
        sourceLabel: "JobApplication"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let status = decoded.status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("status required")
        }
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(decoded),
            source: descriptor.sourceLabel,
            summary: "Prepared status update to \(status).",
            errorMessage: nil
        )
    }
}

@MainActor
struct ListCareerResumesTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "listCareerResumes",
        description: "List career resumes with parser health and detected domains.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "resumes[]",
        sourceLabel: "VaultDocument"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = arguments
        let docs = CareerReadBridge.careerResumeDocuments(collegePersistence: context.collegePersistence)
        let resumes = docs.map { doc -> CareerResumeSummaryPayload in
            let meta = context.collegePersistence.careerResumeMetadata(for: doc)
            let domains: [String] = {
                guard let json = meta.detectedDomainsJSON,
                      let data = json.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
                return decoded
            }()
            return CareerResumeSummaryPayload(
                id: doc.id.uuidString,
                displayName: doc.customDisplayName ?? doc.fileName,
                parserCompliance: meta.parserComplianceRaw,
                detectedDomains: domains
            )
        }
        let payload = CareerResumeListPayload(resumes: resumes)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Listed \(resumes.count) resume(s).",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetJobResumeMatchTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getJobResumeMatch",
        description: "Get cached resume match for a job posting or board application.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"applicationId?\":\"uuid\",\"companySlug?\":\"acme\",\"externalPath?\":\"/job/1\"}",
        outputSchemaDescription: "recommendedResumeName, overallScore, missingKeywords, tip",
        sourceLabel: "CareerResumeJobMatch"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let repo = context.collegePersistence.careerRepository
        let applicationId = arguments["applicationId"]?.stringValue
        let companySlug = arguments["companySlug"]?.stringValue
        let externalPath = arguments["externalPath"]?.stringValue

        let match: CareerResumeJobMatch?
        if let applicationId,
           let uuid = UUID(uuidString: applicationId),
           let app = context.collegePersistence.jobApplication(id: uuid) {
            let slug = CareerRepository.CareerResumeJobMatchKey.companySlug(for: app)
            let path = CareerRepository.CareerResumeJobMatchKey.manualApplicationExternalPath(uuid)
            match = try? repo.recommendedMatch(companySlug: slug, externalPath: path)
        } else if let companySlug, let externalPath {
            match = try? repo.recommendedMatch(companySlug: companySlug, externalPath: externalPath)
        } else {
            throw AssistantToolExecutionError.invalidArguments("applicationId or companySlug+externalPath required")
        }

        let missing: [String] = {
            guard let json = match?.missingKeywordsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return decoded
        }()
        let tip: String? = {
            guard let json = match?.resultJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data) else { return nil }
            return decoded.tip
        }()
        let resumeName: String? = {
            guard let id = match?.resumeDocumentID,
                  let doc = try? context.collegePersistence.vaultRepository.fetchDocument(id: id) else { return nil }
            return doc.customDisplayName ?? doc.fileName
        }()

        let payload = JobResumeMatchPayload(
            applicationId: applicationId,
            companySlug: companySlug,
            externalPath: externalPath,
            recommendedResumeName: resumeName,
            overallScore: match?.overallScore,
            missingKeywords: missing,
            tip: tip
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: payload.overallScore.map { "Match score \($0)%." } ?? "No cached match yet.",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetJobApplicationDetailTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getJobApplicationDetail",
        description: "Get job application detail including JD snippet and resume match summary.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"applicationId\":\"uuid\"}",
        outputSchemaDescription: "application detail with matchScore and missingKeywords",
        sourceLabel: "JobApplication"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let rawID = arguments["applicationId"]?.stringValue,
              let uuid = UUID(uuidString: rawID),
              let app = context.collegePersistence.jobApplication(id: uuid) else {
            throw AssistantToolExecutionError.invalidArguments("applicationId required")
        }

        let slug = CareerRepository.CareerResumeJobMatchKey.companySlug(for: app)
        let path = CareerRepository.CareerResumeJobMatchKey.manualApplicationExternalPath(uuid)
        let match = try? context.collegePersistence.careerRepository.recommendedMatch(
            companySlug: slug,
            externalPath: path
        )
        if match == nil,
           let posting = app.workdaySourcePosting,
           let externalPath = posting.externalPath {
            let postingMatch = try? context.collegePersistence.careerRepository.recommendedMatch(
                companySlug: posting.companySlug,
                externalPath: externalPath
            )
            if let postingMatch {
                return try await detailPayload(
                    app: app,
                    match: postingMatch,
                    context: context
                )
            }
        }

        return try await detailPayload(app: app, match: match, context: context)
    }

    private func detailPayload(
        app: JobApplication,
        match: CareerResumeJobMatch?,
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let jd = (app.jobDescriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = jd.isEmpty ? nil : String(jd.prefix(500))
        let missing: [String]? = {
            guard let json = match?.missingKeywordsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else { return nil }
            return decoded
        }()
        let resumeName: String? = {
            if let resume = app.submittedResume {
                return resume.customDisplayName ?? resume.fileName
            }
            guard let id = match?.resumeDocumentID,
                  let doc = try? context.collegePersistence.vaultRepository.fetchDocument(id: id) else { return nil }
            return doc.customDisplayName ?? doc.fileName
        }()

        let payload = JobApplicationDetailPayload(
            id: app.id.uuidString,
            company: app.company ?? "",
            title: app.title ?? "",
            status: app.statusRaw,
            location: app.locationText,
            jobDescriptionSnippet: snippet,
            matchScore: match?.overallScore,
            recommendedResumeName: resumeName,
            missingKeywords: missing
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Loaded application detail for \(payload.title).",
            errorMessage: nil
        )
    }
}

struct OpenResumeBuilderPayload: Codable {
    let primaryResumeDocumentID: String?
    let primaryResumeName: String?
    let navigationHint: String
}

@MainActor
struct OpenResumeBuilderTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "openResumeBuilder",
        description: "Find the primary career resume and explain how to open the Resume Builder.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "primaryResumeDocumentID, primaryResumeName, navigationHint",
        sourceLabel: "ResumeBuilder"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = arguments
        let docs = CareerReadBridge.careerResumeDocuments(collegePersistence: context.collegePersistence)
        let primary = docs.first(where: \.isFavorite) ?? docs.first
        let payload = OpenResumeBuilderPayload(
            primaryResumeDocumentID: primary?.id.uuidString,
            primaryResumeName: primary.map { $0.customDisplayName ?? $0.fileName },
            navigationHint: "Open Career → Resumes, then choose Build Resume or open an existing resume in the builder."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: primary == nil
                ? "No resumes in library — import or build one from Career → Resumes."
                : "Primary resume: \(payload.primaryResumeName ?? "Resume").",
            errorMessage: nil
        )
    }
}
