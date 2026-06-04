// PlannerVectorSearchConfig.swift
// Feature: Assistant
// Purpose: Assistant module — SearchParams.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Calibrated retrieval constants for planner hybrid search (single source — do not scatter literals).
enum PlannerVectorSearchConfig: Sendable {
    static let lexicalSimilarityFloor: Float = 0.38
    static let neuralSimilarityFloor: Float = 0.50

    static let bm25Weight: Float = 0.30
    static let cosineWeight: Float = 0.45
    static let recencyWeight: Float = 0.25

    static let usefulnessChunkFloor: Int = 50

    static let embeddingVersion = "planner-lexical-v1"

    struct SearchParams: Sendable, Equatable {
        let ftsPrefetch: Int
        let topK: Int
    }

    static func searchParams(lengthPreset: String?) -> SearchParams {
        switch lengthPreset ?? "balanced" {
        case "short":
            return SearchParams(ftsPrefetch: 16, topK: 4)
        case "detailed":
            return SearchParams(ftsPrefetch: 32, topK: 8)
        default:
            return SearchParams(ftsPrefetch: 24, topK: 6)
        }
    }

    static func similarityFloor(semanticEnabled: Bool, usesNeuralEmbedding: Bool) -> Float {
        guard semanticEnabled else { return 0 }
        return usesNeuralEmbedding ? neuralSimilarityFloor : lexicalSimilarityFloor
    }
}
