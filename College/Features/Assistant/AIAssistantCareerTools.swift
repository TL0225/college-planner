// AIAssistantCareerTools.swift
// Feature: Assistant
// Purpose: Assistant module — JobApplicationSummaryPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation

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
