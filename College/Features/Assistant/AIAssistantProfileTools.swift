// AIAssistantProfileTools.swift
// Feature: Assistant
// Purpose: Assistant module — ProfileToolPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ProfileToolPayload: Codable {
    let name: String
    let major: String
    let minor: String
    let gpa: Double
    let classStanding: String
    let expectedGraduation: String
    let collegeName: String
    let department: String
}

@MainActor
struct GetProfileTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getProfile",
        description: "Return editable profile fields (name, programs, GPA, graduation).",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "name, major, minor, gpa, classStanding, expectedGraduation, collegeName, department",
        sourceLabel: "ProfileEntity"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let profile = context.collegePersistence.profile else {
            throw AssistantToolExecutionError.missingProfile
        }
        let core = context.collegePersistence
        let payload = ProfileToolPayload(
            name: profile.name ?? "",
            major: core.primaryMajorDisplay() ?? "",
            minor: core.primaryMinorDisplay() ?? "",
            gpa: core.primaryGPA(),
            classStanding: core.primaryClassStanding() ?? "",
            expectedGraduation: core.primaryExpectedGraduation() ?? "",
            collegeName: profile.collegeName ?? "",
            department: core.primaryDepartment() ?? ""
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Loaded profile for \(payload.name).",
            errorMessage: nil
        )
    }
}

@MainActor
struct UpdateProfileTool: AIAssistantTool {
    private struct Arguments: Codable {
        let name: String?
        let major: String?
        let minor: String?
        let gpa: Double?
        let classStanding: String?
        let expectedGraduation: String?
        let collegeName: String?
        let department: String?
    }

    let descriptor = AssistantToolDescriptor(
        name: "updateProfile",
        description: "Prepare profile field updates for confirmation.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .inline,
        inputSchemaDescription: "{\"name?\":\"string\",\"major?\":\"string\",\"minor?\":\"string\",\"gpa?\":3.5,\"classStanding?\":\"string\",\"expectedGraduation?\":\"string\",\"collegeName?\":\"string\",\"department?\":\"string\"}",
        outputSchemaDescription: "fields to apply after confirm",
        sourceLabel: "ProfileEntity via CollegePersistence.updateProfile"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard context.collegePersistence.profile != nil else {
            throw AssistantToolExecutionError.missingProfile
        }
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(decoded),
            source: descriptor.sourceLabel,
            summary: "Prepared profile update for confirmation.",
            errorMessage: nil
        )
    }
}
