// CareerNLSemanticEmbedding.swift
// Feature: Career
// Purpose: On-device semantic embeddings via NLContextualEmbedding (Neural Engine, no Metal).

import Foundation
import NaturalLanguage

enum CareerNLSemanticEmbedding {
    static func embed(_ text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> [Float]? in
            guard let embedding = NLContextualEmbedding(language: .english) else { return nil }
            if !embedding.hasAvailableAssets {
                _ = try? await embedding.requestAssets()
            }
            guard embedding.hasAvailableAssets else { return nil }

            guard let result = try? embedding.embeddingResult(for: trimmed, language: .english) else {
                return nil
            }

            var vectors: [[Double]] = []
            result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
                vectors.append(vector)
                return true
            }
            guard !vectors.isEmpty else { return nil }
            let dimension = vectors[0].count
            var mean = [Double](repeating: 0, count: dimension)
            for vector in vectors {
                for i in 0..<dimension {
                    mean[i] += vector[i]
                }
            }
            let count = Double(vectors.count)
            return mean.map { Float($0 / count) }
        }.value
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 1e-6 else { return 0 }
        return dot / denom
    }

    static func embedExperienceWeighted(profile: CareerResumeStructuredProfile?, fullText: String) async -> [Float]? {
        var chunks: [String] = []
        if let summary = profile?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            chunks.append(summary)
        }
        let experienceText = (profile?.experience ?? [])
            .prefix(2)
            .map { entry in
                (entry.headingLines + entry.bullets).joined(separator: "\n")
            }
            .joined(separator: "\n\n")
        if !experienceText.isEmpty {
            chunks.append(experienceText)
            chunks.append(experienceText)
        }
        let combined = chunks.isEmpty ? fullText : chunks.joined(separator: "\n\n")
        return await embed(String(combined.prefix(6_000)))
    }
}
