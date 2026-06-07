// CatalogEntityLLMValidator.swift
// Feature: Catalog
// Purpose: Optional LLM validation for a single low-confidence catalog entity node (dev/review).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogEntityLLMValidator {
    struct ValidationRequest: Sendable {
        let entityType: CatalogEntityType
        let displayKey: String
        let sourceURL: String
        let excerpt: String
        let layoutProfileID: String
        let confidence: Double
    }

    struct ValidationResult: Sendable, Codable, Equatable {
        let passed: Bool
        let suggestedDisplayKey: String?
        let suggestedCorrections: [String]
        let confidence: Double?
        let rawJSON: String?
    }

    static var isEnabled: Bool {
        CatalogPlatformFlags.entityLLMEnabled
    }

    static func scheduleAutoValidation(
        schoolID: String,
        reason: String,
        severity: CatalogReviewSeverity,
        confidence: Double?,
        snapshot: CatalogReviewSnapshot
    ) {
        guard isEnabled, severity != .informational else { return }
        let resolvedConfidence = confidence
            ?? snapshot.metrics?.averageEntityConfidence
            ?? snapshot.metrics?.averageOwnershipConfidence
            ?? 0.45
        guard resolvedConfidence < 0.55 else { return }

        let snapshotID = snapshot.id
        Task(priority: .utility) {
            let request = ValidationRequest(
                entityType: .program,
                displayKey: reason,
                sourceURL: snapshot.sourceURL ?? "",
                excerpt: snapshot.excerpt ?? reason,
                layoutProfileID: snapshot.layoutProfileID ?? "unknown",
                confidence: resolvedConfidence
            )
            guard let result = await validate(request) else { return }
            CatalogEntityLLMValidationStore.save(
                CatalogEntityLLMValidationRecord(
                    snapshotID: snapshotID,
                    schoolID: schoolID,
                    result: result
                )
            )
        }
    }

    static func validate(_ request: ValidationRequest) async -> ValidationResult? {
        guard isEnabled else { return nil }
        guard request.confidence < 0.55 else { return nil }
        guard AppleSiliconPlatform.isSupported else { return nil }

        let spec = ModelSpec.jsonWorker
        guard let modelPath = try? await ModelManager.shared.ensureModelInstalled(spec, progress: { _ in }) else {
            return nil
        }

        let prompt = """
/no_think
Validate this catalog \(request.entityType.rawValue) extraction. Return ONLY JSON:
{"passed":true,"suggestedDisplayKey":null,"suggestedCorrections":[],"confidence":0.0}

layoutProfile: \(request.layoutProfileID)
sourceURL: \(request.sourceURL)
displayKey: \(request.displayKey)
confidence: \(String(format: "%.2f", request.confidence))
excerpt: \(String(request.excerpt.prefix(800)))
"""
        do {
            let raw = try await LocalLLMRunner.shared.generateJSON(prompt: prompt, modelPath: modelPath, maxTokens: 160)
            return parseResponse(raw)
        } catch {
            return nil
        }
    }

    private static func parseResponse(_ raw: String) -> ValidationResult? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let passed = (json["passed"] as? Bool) ?? false
        let suggestedDisplayKey = json["suggestedDisplayKey"] as? String
        let corrections = (json["suggestedCorrections"] as? [String]) ?? []
        let confidence = (json["confidence"] as? Double) ?? (json["confidence"] as? NSNumber)?.doubleValue
        return ValidationResult(
            passed: passed,
            suggestedDisplayKey: suggestedDisplayKey,
            suggestedCorrections: corrections,
            confidence: confidence,
            rawJSON: raw
        )
    }
}
