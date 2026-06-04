// LLMSamplingProfile.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — LLMSamplingProfile.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import MLXLMCommon

/// Sampling presets at the `LocalLLMRunner` boundary so assistant chat never picks up cold JSON parameters (and vice versa).
enum LLMSamplingProfile: Sendable {
    /// Syllabus, classifiers, prerequisite LLM, vault summary, ModernCampus sidebar JSON, etc.
    case structuredJSON
    /// Student-facing academic advisor path only (`AIAssistantService.runModel`).
    case assistantPlanner

    func generateParameters(maxTokens: Int) -> GenerateParameters {
        switch self {
        case .structuredJSON:
            return GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0.2,
                topP: 0.95,
                repetitionPenalty: 1.05,
                repetitionContextSize: 64
            )
        case .assistantPlanner:
            // MLXLMCommon `GenerateParameters` in this pin has no `topK`; keep temperature/topP guardrails per plan §5b.
            return GenerateParameters(
                maxTokens: maxTokens,
                kvBits: 8,
                temperature: 1.0,
                topP: 0.95,
                repetitionPenalty: 1.05,
                repetitionContextSize: 64
            )
        }
    }
}
