// AIAssistantDocumentTools.swift
// Feature: Assistant
// Purpose: Assistant module — DocumentSearchHitPayload.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct DocumentSearchHitPayload: Codable {
    let documentId: String
    let filename: String
    let excerpt: String
    let score: Double
}

struct DocumentSearchPayload: Codable {
    let keywords: [String]
    let hits: [DocumentSearchHitPayload]
}

@MainActor
struct SearchDocumentsTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let keywords: [String]?
        let query: String?
        let limit: Int?
    }

    let descriptor = AssistantToolDescriptor(
        name: "searchDocuments",
        description: "Search vault documents by keywords using the on-device planner index.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"keywords\":[\"financial aid\"],\"limit?\":8}",
        outputSchemaDescription: "keywords, hits[]",
        sourceLabel: "PlannerVectorStore vault_document"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        var terms: [String] = decoded?.keywords ?? []
        if terms.isEmpty, let q = decoded?.query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            terms = [q]
        }
        if terms.isEmpty, let single = arguments["keywords"]?.stringValue {
            terms = [single]
        }
        guard !terms.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("keywords or query required")
        }
        let limit = max(1, min(decoded?.limit ?? 8, 20))
        let query = terms.joined(separator: " ")
        let params = PlannerVectorSearchConfig.searchParams(lengthPreset: nil)
        let rows = try await PlannerVectorStore.shared.searchHybrid(
            query: query,
            ftsPrefetch: params.ftsPrefetch,
            limit: limit,
            queryVector: nil,
            semanticEnabled: false
        )
        let vaultRows = rows.filter { $0.row.sourceType == "vault_document" }
        let hits = vaultRows.map { row -> DocumentSearchHitPayload in
            let meta = row.row.metadataJSON
            let filename = extractJSONField(meta, key: "filename") ?? row.row.sourceId
            return DocumentSearchHitPayload(
                documentId: row.row.sourceId,
                filename: filename,
                excerpt: String(row.row.ftsBody.prefix(280)),
                score: Double(row.finalScore)
            )
        }
        let payload = DocumentSearchPayload(keywords: terms, hits: hits)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: hits.isEmpty ? "No documents matched." : "Found \(hits.count) document(s).",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetDocumentExcerptTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getDocumentExcerpt",
        description: "Return the top matching excerpt for a vault document id.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"documentId\":\"uuid\",\"query?\":\"string\"}",
        outputSchemaDescription: "documentId, excerpt, filename",
        sourceLabel: "PlannerVectorStore"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let docId = arguments["documentId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !docId.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("documentId required")
        }
        let query = arguments["query"]?.stringValue ?? docId
        let rows = try await PlannerVectorStore.shared.searchHybrid(
            query: query,
            ftsPrefetch: 12,
            limit: 6,
            queryVector: nil,
            semanticEnabled: false
        )
        let vaultRows = rows.filter { $0.row.sourceType == "vault_document" }
        let match = vaultRows.first { $0.row.sourceId == docId } ?? vaultRows.first
        guard let match else {
            throw AssistantToolExecutionError.invalidArguments("No excerpt found for that document.")
        }
        let filename = extractJSONField(match.row.metadataJSON, key: "filename") ?? docId
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: [
                "documentId": .string(docId),
                "filename": .string(filename),
                "excerpt": .string(String(match.row.ftsBody.prefix(600))),
            ],
            source: descriptor.sourceLabel,
            summary: "Excerpt from \(filename).",
            errorMessage: nil
        )
    }
}

@MainActor
struct OpenDocumentTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "openDocument",
        description: "Navigate to Documents and highlight a vault document.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"documentId\":\"uuid\"}",
        outputSchemaDescription: "documentId, navigated",
        sourceLabel: "Documents tab"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let raw = arguments["documentId"]?.stringValue,
              let id = UUID(uuidString: raw) else {
            throw AssistantToolExecutionError.invalidArguments("documentId uuid required")
        }
        _ = context.navigate?(.documents)
        context.highlightVaultDocument?(id)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: ["documentId": .string(id.uuidString), "navigated": .bool(true)],
            source: descriptor.sourceLabel,
            summary: "Opened Documents.",
            errorMessage: nil
        )
    }
}

private func extractJSONField(_ json: String, key: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let value = obj[key] as? String else { return nil }
    return value
}
