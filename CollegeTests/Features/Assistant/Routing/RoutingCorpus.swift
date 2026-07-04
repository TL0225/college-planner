// RoutingCorpus.swift
// Loads parameterized routing cases from JSON fixtures.

import Foundation
@testable import College

struct RoutingCase: Codable, Sendable, Hashable {
    let id: String
    let prompt: String
    let expectedIntent: String?
    let expectedTool: String?
    let role: String?

    var assistantRole: AIAssistantService.Role {
        switch role?.lowercased() {
        case "financialaid", "financial_aid":
            return .financialAid
        default:
            return .academicAdvisor
        }
    }
}

enum RoutingCorpus {
    static let all: [RoutingCase] = load()

    private static func load() -> [RoutingCase] {
        if let url = fixtureURL(),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            return decoded.cases
        }
        return fallbackCases
    }

    private struct Payload: Decodable {
        let cases: [RoutingCase]
    }

    private static func fixtureURL() -> URL? {
        try? TestFixturePaths.url("Assistant/routing-corpus.json")
    }

    /// Minimal inline fallback if bundle path resolution fails in CI.
    private static let fallbackCases: [RoutingCase] = [
        RoutingCase(id: "fallback_001", prompt: "What classes do I need to graduate?", expectedIntent: "requirement_explanation", expectedTool: "explainRequirements", role: "academicAdvisor"),
        RoutingCase(id: "fallback_002", prompt: "When is FAFSA due?", expectedIntent: "fafsa_help", expectedTool: "getAidDeadlines", role: "academicAdvisor"),
    ]
}
