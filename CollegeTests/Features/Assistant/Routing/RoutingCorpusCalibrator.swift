// RoutingCorpusCalibrator.swift
// Regenerates routing fixture expectations from the live intent classifier.

import Foundation
@testable import College

enum RoutingCorpusCalibrator {
    static func calibratedCase(from routingCase: RoutingCase) -> RoutingCase {
        let frame = AssistantIntentSemantics.intentFrame(
            message: routingCase.prompt,
            role: routingCase.assistantRole
        )
        return RoutingCase(
            id: routingCase.id,
            prompt: routingCase.prompt,
            expectedIntent: frame?.detectedIntent,
            expectedTool: frame?.preferredTool,
            role: routingCase.role
        )
    }

    static func calibratedCases(from cases: [RoutingCase]) -> [RoutingCase] {
        cases.map(calibratedCase(from:))
    }

    static func exportJSON(from cases: [RoutingCase]) throws -> Data {
        struct Payload: Encodable {
            let version: Int
            let cases: [RoutingCase]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Payload(version: 1, cases: cases))
    }
}
