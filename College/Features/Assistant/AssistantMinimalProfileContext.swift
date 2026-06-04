// AssistantMinimalProfileContext.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantMinimalProfileContext.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Typed minimal student profile for assistant context (explicit `Sendable` — safe across actor hops).
struct AssistantMinimalProfileContext: Sendable {
    var role: String
    var activePage: String
    var university: String?
    var degreeLevel: String?
    var degreeType: String?
    var majors: [String]
    var minors: [String]
    var creditsEarned: Int
    var creditsRequired: Int
    var gpa: Double?
    var expectedGraduation: String?
    var todayISO: String
    /// One-line aid jurisdiction when role is financial aid (optional).
    var aidJurisdictionLine: String?

    func render(charBudget: Int) -> String {
        var lines: [String] = []
        lines.append("Current role: \(role)")
        lines.append("Active page: \(activePage)")
        lines.append("Active university: \(university ?? "unknown")")
        let level = (degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Student degree level: \(level.isEmpty ? "unknown" : level)")
        let dtype = (degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Student degree type: \(dtype.isEmpty ? "unknown" : dtype)")
        lines.append("Majors: \(majors.isEmpty ? "none" : majors.joined(separator: ", "))")
        lines.append("Minors: \(minors.isEmpty ? "none" : minors.joined(separator: ", "))")
        lines.append("Credits earned/required: \(creditsEarned)/\(creditsRequired)")
        lines.append("Current GPA: \(gpa.map { String(format: "%.2f", $0) } ?? "unknown")")
        lines.append("Expected graduation: \(expectedGraduation ?? "unknown")")
        lines.append("Today: \(todayISO)")
        if let aid = aidJurisdictionLine?.trimmingCharacters(in: .whitespacesAndNewlines), !aid.isEmpty {
            lines.append(aid)
        }
        var text = lines.joined(separator: "\n")
        if text.count > charBudget {
            if let aid = aidJurisdictionLine, !aid.isEmpty, text.count > charBudget {
                text = lines.filter { !$0.hasPrefix("Aid ") }.joined(separator: "\n")
            }
            if text.count > charBudget {
                text = String(text.prefix(charBudget))
            }
        }
        return text
    }
}
