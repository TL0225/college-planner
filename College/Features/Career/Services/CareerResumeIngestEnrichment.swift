// CareerResumeIngestEnrichment.swift
// Feature: Career
// Purpose: Domain tagging and stale-skill detection during resume ingest.

import Foundation

struct CareerStaleSkillWarning: Codable, Sendable, Equatable {
    var term: String
    var reason: String
}

enum CareerResumeIngestEnrichment {
    private static let domainKeywords: [(domain: String, tokens: [String])] = [
        ("Cybersecurity", ["security", "soc", "siem", "penetration", "vulnerability", "firewall", "incident response"]),
        ("Software Engineering", ["software", "developer", "engineer", "swift", "python", "java", "api", "backend", "frontend"]),
        ("Data & Analytics", ["data analyst", "sql", "tableau", "power bi", "statistics", "machine learning", "analytics"]),
        ("Desktop Support", ["help desk", "desktop support", "it support", "troubleshoot", "active directory", "ticketing"]),
        ("Product Management", ["product manager", "roadmap", "stakeholder", "user research", "prd"]),
        ("Design", ["figma", "ui/ux", "user experience", "wireframe", "prototyp"]),
    ]

    private static let staleSkillPatterns: [(pattern: String, reason: String)] = [
        (#"windows\s*(7|8|xp|vista)"#, "Legacy Windows versions are rarely listed on modern job postings."),
        (#"windows server 2012"#, "Windows Server 2012 is end-of-life — list a current version if still relevant."),
        (#"\bflash\b"#, "Adobe Flash is deprecated."),
        (#"internet explorer"#, "Internet Explorer is retired — use Edge or a modern browser stack."),
        (#"visual basic 6"#, "VB6 is obsolete for most enterprise roles."),
        (#"objective-c(?!\s*\/\s*swift)"#, "Objective-C alone may read dated unless paired with modern iOS/Swift context."),
        (#"cobol"#, "COBOL is niche — keep only when the target role explicitly requires it."),
        (#"jquery(?!\s*\/)"#, "jQuery-only front-end stacks often read dated without a modern framework."),
    ]

    static func detectDomains(plainText: String) async -> [String] {
        if let llmDomains = await detectDomainsWithFoundationModels(plainText: plainText), !llmDomains.isEmpty {
            return llmDomains
        }
        return detectDomainsHeuristic(plainText: plainText)
    }

    static func detectStaleSkills(plainText: String) -> [CareerStaleSkillWarning] {
        let lower = plainText.lowercased()
        var warnings: [CareerStaleSkillWarning] = []
        var seen = Set<String>()

        for entry in staleSkillPatterns {
            guard let range = lower.range(of: entry.pattern, options: .regularExpression) else { continue }
            let term = String(lower[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            warnings.append(CareerStaleSkillWarning(term: term, reason: entry.reason))
            if warnings.count >= 3 { break }
        }
        return warnings
    }

    private static func detectDomainsHeuristic(plainText: String) -> [String] {
        let lower = plainText.lowercased()
        var hits: [(String, Int)] = []
        for entry in domainKeywords {
            let score = entry.tokens.reduce(0) { partial, token in
                partial + (lower.contains(token) ? 1 : 0)
            }
            if score > 0 {
                hits.append((entry.domain, score))
            }
        }
        return hits
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
    }

    private static func detectDomainsWithFoundationModels(plainText: String) async -> [String]? {
        guard CareerFoundationModelsJSONService.isAvailable() else { return nil }
        let prompt = """
        Classify this resume into 1-3 career domains.
        Return strict JSON: { "domains": [String], "suggestedTargetRole": String? }
        Resume excerpt:
        \(plainText.prefix(4_000))
        """
        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else { return nil }

        struct Response: Codable {
            var domains: [String]?
            var suggestedTargetRole: String?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return decoded.domains?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func suggestedTargetRole(plainText: String) async -> String? {
        guard CareerFoundationModelsJSONService.isAvailable() else { return nil }
        let prompt = """
        Suggest a concise target job title for this resume.
        Return strict JSON: { "suggestedTargetRole": String? }
        Resume excerpt:
        \(plainText.prefix(3_000))
        """
        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else { return nil }
        struct Response: Codable { var suggestedTargetRole: String? }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let role = decoded.suggestedTargetRole?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return role.isEmpty ? nil : role
    }
}
