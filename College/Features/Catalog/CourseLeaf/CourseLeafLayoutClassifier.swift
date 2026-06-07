// CourseLeafLayoutClassifier.swift
// Feature: Catalog
// Purpose: Deterministic CourseLeaf layout profile scoring from DOM feature vectors.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CourseLeafLayoutClassifier {
    /// Scores layout profiles from DOM structure only (no schoolID routing).
    static func classify(domFeatures: CatalogDOMFeatures) -> (profileID: String, confidence: Double) {
        let scoreA = profileAScore(domFeatures)
        let scoreB = profileBScore(domFeatures)
        let scoreC = profileCScore(domFeatures)
        let scoreDefault = profileDefaultScore(domFeatures)

        let candidates: [(CourseLeafLayoutProfileID, Double)] = [
            (.profileA, scoreA),
            (.profileB, scoreB),
            (.profileC, scoreC),
            (.profileDefault, scoreDefault)
        ]

        let best = candidates.max(by: { $0.1 < $1.1 }) ?? (.profileDefault, scoreDefault)
        let total = candidates.map(\.1).reduce(0, +)
        let rawConfidence: Double
        if total > 0 {
            rawConfidence = best.1 / total
        } else {
            rawConfidence = 0.25
        }
        let confidence = min(max(rawConfidence, 0.15), 1.0)
        return (best.0.rawValue, confidence)
    }

    private static func profileAScore(_ f: CatalogDOMFeatures) -> Double {
        Double(f.detailCodeCount) * 4.0
            + Double(f.detailTitleCount) * 1.5
            + Double(f.divCourseblockCount) * 1.0
            - Double(f.courseblocktitleCount) * 2.0
            - Double(f.dlCourseblockCount) * 3.0
    }

    private static func profileBScore(_ f: CatalogDOMFeatures) -> Double {
        Double(f.courseblocktitleCount) * 4.0
            + Double(f.divCourseblockCount) * 1.0
            + Double(f.courseblockextraCount) * 0.5
            - Double(f.detailCodeCount) * 3.0
            - Double(f.dlCourseblockCount) * 2.0
    }

    private static func profileCScore(_ f: CatalogDOMFeatures) -> Double {
        Double(f.dlCourseblockCount) * 6.0
            - Double(f.detailCodeCount) * 2.0
            - Double(f.courseblocktitleCount) * 1.0
    }

    private static func profileDefaultScore(_ f: CatalogDOMFeatures) -> Double {
        let structural = Double(f.divCourseblockCount + f.dlCourseblockCount + f.scCourselistCount)
        if structural == 0 {
            return 0.5
        }
        return 1.0 + structural * 0.05
    }
}
