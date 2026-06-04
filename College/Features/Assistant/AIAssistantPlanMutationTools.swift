// AIAssistantPlanMutationTools.swift
// Feature: Assistant
// Purpose: Assistant module — PlanMutationPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct PlanMutationPayload: Codable {
    let semesterName: String?
    let year: Int?
    let season: String?
    let courseCode: String?
    let courseName: String?
    let credits: Int?
}

@MainActor
struct AddSemesterTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let name: String
        let year: Int
        let season: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "addSemester",
        description: "Prepare adding a semester to the active degree plan for confirmation.",
        allowedPersonas: [.academicAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .inline,
        inputSchemaDescription: "{\"name\":\"Fall 2026\",\"year\":2026,\"season\":\"Fall\"}",
        outputSchemaDescription: "name, year, season",
        sourceLabel: "CollegePersistence.addSemester"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = try activePlanOrThrow(context.collegePersistence)
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PlanMutationPayload(
            semesterName: decoded.name,
            year: decoded.year,
            season: decoded.season,
            courseCode: nil,
            courseName: nil,
            credits: nil
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared semester \(decoded.name) for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct AddCourseToPlanTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let semesterName: String
        let courseCode: String
        let courseName: String?
        let credits: Int?
    }

    let descriptor = AssistantToolDescriptor(
        name: "addCourseToPlan",
        description: "Prepare adding a course to a plan semester for confirmation.",
        allowedPersonas: [.academicAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .inline,
        inputSchemaDescription: "{\"semesterName\":\"Fall 2026\",\"courseCode\":\"CSC 316\",\"courseName?\":\"string\",\"credits?\":3}",
        outputSchemaDescription: "semesterName, courseCode, courseName, credits",
        sourceLabel: "CollegePersistence.addCourse"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = try activePlanOrThrow(context.collegePersistence)
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PlanMutationPayload(
            semesterName: decoded.semesterName,
            year: nil,
            season: nil,
            courseCode: decoded.courseCode,
            courseName: decoded.courseName,
            credits: decoded.credits ?? 3
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared \(decoded.courseCode) in \(decoded.semesterName) for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct RemoveCourseFromPlanTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let semesterName: String
        let courseCode: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "removeCourseFromPlan",
        description: "Prepare removing a course from the plan for confirmation (destructive).",
        allowedPersonas: [.academicAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .alertDestructive,
        inputSchemaDescription: "{\"semesterName\":\"Fall 2026\",\"courseCode\":\"CSC 316\"}",
        outputSchemaDescription: "semesterName, courseCode",
        sourceLabel: "CollegePersistence.deleteCourse"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = try activePlanOrThrow(context.collegePersistence)
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PlanMutationPayload(
            semesterName: decoded.semesterName,
            year: nil,
            season: nil,
            courseCode: decoded.courseCode,
            courseName: nil,
            credits: nil
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared removal of \(decoded.courseCode) from \(decoded.semesterName).",
            errorMessage: nil
        )
    }
}

@MainActor
func findSemester(named name: String, in plan: PlanEntity) -> SemesterEntity? {
    let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return plan.semestersArray.first {
        $0.name.lowercased() == target
            || "\($0.season) \($0.year)".lowercased() == target
    }
}
