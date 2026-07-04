// CareerFoundationModelsJSONService.swift
// Feature: Career
// Purpose: Foundation Models JSON generation for career AI without MLX.

import Foundation
import FoundationModels

enum CareerFoundationModelsJSONService {
    static func isAvailable() -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    @MainActor
    static func generateJSON(prompt: String) async -> String? {
        guard #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable else {
            return nil
        }

        do {
            let session = LanguageModelSession(
                instructions: "Return only valid JSON. Do not include markdown fences, prose, or commentary."
            )
            let response = try await session.respond(to: prompt)
            return JSONSanitizer.extractJSONPayload(from: response.content)
                ?? extractJSONObject(from: response.content)
        } catch {
            return nil
        }
    }

    private static func extractJSONObject(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(trimmed[start...end])
    }
}
