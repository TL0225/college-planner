// AIAssistantCatalogTools.swift
// Feature: Assistant
// Purpose: Semantic catalog search and department program listing tools (P15).

import Foundation

@MainActor
struct SemanticCatalogSearchTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let query: String?
        let limit: Int?
    }

    let descriptor = AssistantToolDescriptor(
        name: "semanticCatalogSearch",
        description: "Hybrid semantic + keyword search across indexed catalog chunks (courses, requirements, policies).",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"query\":\"data structures prerequisites\",\"limit?\":8}",
        outputSchemaDescription: "query, resultCount, hits[]",
        sourceLabel: "CatalogVectorStore.searchHybrid"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let query = (decoded.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AssistantToolExecutionError.missingCatalogQuery
        }
        let limit = max(1, min(decoded.limit ?? 8, 12))

        guard let university = context.collegePersistence.getActiveUniversity() else {
            let payload = SemanticCatalogSearchPayload(query: query, resultCount: 0, hits: [])
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: "No active catalog university is set.",
                errorMessage: nil
            )
        }

        let rows = try await CatalogVectorStore.shared.searchHybrid(
            query: query,
            universityId: university.id,
            ftsPrefetch: 32,
            limit: limit,
            queryVector: nil,
            semanticEnabled: false
        )
        let hits = rows.map {
            SemanticCatalogHitPayload(
                chunkId: $0.chunkId,
                sourceKind: $0.sourceKind,
                courseCode: $0.courseCode,
                programURL: $0.programURL,
                requirementCategory: $0.requirementCategory,
                excerpt: String($0.ftsBody.prefix(240))
            )
        }
        let payload = SemanticCatalogSearchPayload(query: query, resultCount: hits.count, hits: hits)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Found \(hits.count) semantic catalog hit(s) for \"\(query)\".",
            errorMessage: nil
        )
    }
}

@MainActor
struct ProgramsUnderDepartmentTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let department: String?
        let degreeLevel: String?
    }

    let descriptor = AssistantToolDescriptor(
        name: "listProgramsUnderDepartment",
        description: "List catalog majors/minors offered by a department at the active university.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"department\":\"Computer Science\",\"degreeLevel?\":\"Undergraduate\"}",
        outputSchemaDescription: "department, degreeLevel, programs[]",
        sourceLabel: "CatalogProgramReadBridge"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let department = (decoded.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !department.isEmpty else {
            throw AssistantToolExecutionError.missingCatalogQuery
        }
        let degreeLevel = (decoded.degreeLevel ?? "Undergraduate").trimmingCharacters(in: .whitespacesAndNewlines)
        let universityName = context.collegePersistence.getActiveUniversity()?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let programs = CatalogProgramReadBridge.fetchMajors(
            for: universityName,
            degreeLevel: degreeLevel,
            department: department,
            includeMinors: true,
            appDataStore: AppDataStore.shared
        )
        let payload = DepartmentProgramsPayload(
            department: department,
            degreeLevel: degreeLevel,
            programs: programs
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: programs.isEmpty
                ? "No programs found under \(department) for \(degreeLevel)."
                : "Found \(programs.count) program(s) under \(department).",
            errorMessage: nil
        )
    }
}

struct SemanticCatalogHitPayload: Codable {
    let chunkId: String
    let sourceKind: String
    let courseCode: String?
    let programURL: String?
    let requirementCategory: String?
    let excerpt: String
}

struct SemanticCatalogSearchPayload: Codable {
    let query: String
    let resultCount: Int
    let hits: [SemanticCatalogHitPayload]
}

struct DepartmentProgramsPayload: Codable {
    let department: String
    let degreeLevel: String
    let programs: [String]
}
