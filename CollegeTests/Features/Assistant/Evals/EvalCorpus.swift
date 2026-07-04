// EvalCorpus.swift
// Layer 5 — eval fixture loaders.

import Foundation
@testable import College

struct EvalCase: Codable, Sendable, Hashable {
    let id: String
    let prompt: String?
    let turns: [EvalTurn]?
    let quality: EvalQualityRules

    struct EvalTurn: Codable, Sendable, Hashable {
        let user: String
    }
}

struct EvalQualityRules: Codable, Sendable, Hashable {
    let replyContainsAny: [String]?
    let replyExcludes: [String]?
    let finalReplyContainsAny: [String]?
    let contextMustInclude: [String]?
}

enum EvalCorpus {
    static let singleTurn: [EvalCase] = load(filename: "eval-corpus.json")
    static let multiTurn: [EvalCase] = load(filename: "multi-turn-eval-corpus.json")

    private static func load(filename: String) -> [EvalCase] {
        guard let url = try? TestFixturePaths.url("Assistant/\(filename)"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.cases
    }

    private struct Payload: Decodable {
        let cases: [EvalCase]
    }
}

enum EvalQualityChecker {
    static func flags(reply: String, rules: EvalQualityRules) -> [String] {
        var flags: [String] = []
        if let any = rules.replyContainsAny ?? rules.finalReplyContainsAny {
            let hit = any.contains { reply.localizedCaseInsensitiveContains($0) }
            if !hit { flags.append("missing_expected_substring") }
        }
        if let excludes = rules.replyExcludes {
            for ex in excludes where reply.contains(ex) {
                flags.append("forbidden_substring:\(ex)")
            }
        }
        if reply.contains("Current programs:\n- Majors:") {
            flags.append("robotic_program_dump")
        }
        return flags
    }
}
