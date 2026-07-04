// AIAssistantLearningProfileTools.swift
// Feature: Assistant
// Purpose: getStudentLearningProfile tool (Ship A).

import Foundation

struct GetStudentLearningProfileToolResult: Codable, Sendable {
    let courses: [AssistantLearningProfileCourse]
    let coverage: AssistantLearningProfileCoverage
    let summary: String
}

@MainActor
struct GetStudentLearningProfileTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getStudentLearningProfile",
        description: "Return the student's planned/completed courses (Tier 1 learning profile) with major-relevance flags and whether personalization is eligible (≥2 major-relevant courses).",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "courses[], coverage, summary",
        sourceLabel: "AssistantLearningProfileBuilder"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = arguments
        let majors = context.snapshot.majors
        let programURL = context.programIdentity?.programURL
            ?? context.collegePersistence.resolveSelectedMajorProgramURL()
        let profile = AssistantLearningProfileBuilder.build(
            persistence: context.collegePersistence,
            majorNames: majors,
            programURL: programURL
        )
        let payload = GetStudentLearningProfileToolResult(
            courses: profile.courses,
            coverage: profile.coverage,
            summary: profile.compressedSummary
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Learning profile: \(profile.coverage.tier1CourseCount) courses, personalizationEligible=\(profile.coverage.personalizationEligible).",
            errorMessage: nil
        )
    }
}
