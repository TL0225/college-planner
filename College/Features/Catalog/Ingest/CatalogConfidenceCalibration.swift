// CatalogConfidenceCalibration.swift
// Feature: Catalog
// Purpose: Predicted confidence vs actual accuracy buckets against gold data (P23).

import Foundation

struct CatalogCalibrationBucket: Codable, Sendable, Equatable {
    let label: String
    let predictedMin: Double
    let predictedMax: Double
    let sampleCount: Int
    let actualAccuracy: Double
}

struct CatalogCalibrationReport: Codable, Sendable, Equatable {
    let schoolID: String
    let buckets: [CatalogCalibrationBucket]
    let meanAbsoluteError: Double
    let recordedAt: Date
}

enum CatalogConfidenceCalibration {
    private static let defaultBuckets: [(String, ClosedRange<Double>)] = [
        ("0.0-0.5", 0.0...0.5),
        ("0.5-0.7", 0.5...0.7),
        ("0.7-0.85", 0.7...0.85),
        ("0.85-1.0", 0.85...1.0),
    ]

    static func evaluate(
        schoolID: String,
        samples: [(predicted: Double, actualMatch: Bool)]
    ) -> CatalogCalibrationReport {
        var buckets: [CatalogCalibrationBucket] = []
        var totalError = 0.0
        for (label, range) in defaultBuckets {
            let bucketSamples = samples.filter { range.contains($0.predicted) }
            guard !bucketSamples.isEmpty else {
                buckets.append(CatalogCalibrationBucket(
                    label: label,
                    predictedMin: range.lowerBound,
                    predictedMax: range.upperBound,
                    sampleCount: 0,
                    actualAccuracy: 0
                ))
                continue
            }
            let accuracy = Double(bucketSamples.filter(\.actualMatch).count) / Double(bucketSamples.count)
            let meanPredicted = bucketSamples.map(\.predicted).reduce(0, +) / Double(bucketSamples.count)
            totalError += abs(meanPredicted - accuracy) * Double(bucketSamples.count)
            buckets.append(CatalogCalibrationBucket(
                label: label,
                predictedMin: range.lowerBound,
                predictedMax: range.upperBound,
                sampleCount: bucketSamples.count,
                actualAccuracy: accuracy
            ))
        }
        let mae = samples.isEmpty ? 0 : totalError / Double(samples.count)
        return CatalogCalibrationReport(schoolID: schoolID, buckets: buckets, meanAbsoluteError: mae, recordedAt: .now)
    }

    static func calibrationScore(from report: CatalogCalibrationReport) -> Double {
        max(0, 1 - report.meanAbsoluteError)
    }
}
