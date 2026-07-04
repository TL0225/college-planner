// CareerResumeSectionSegmenter.swift
// Feature: Career / ResumeParsing
// Purpose: Jobright-style section detection — split normalized resume text before entity extraction.

import Foundation

enum CareerResumeSectionSegmenter {
    enum Kind: String, Sendable, CaseIterable {
        case preamble
        case summary
        case education
        case experience
        case projects
        case skills
        case certifications
        case other
    }

    struct Segment: Sendable, Equatable {
        var kind: Kind
        var title: String
        var text: String
    }

    private static let headerMap: [(Kind, [String])] = [
        (.summary, ["summary", "professional summary", "profile", "objective", "career objective", "about", "about me", "overview"]),
        (.skills, ["skills", "technical skills", "core skills", "key skills", "technologies", "technical proficiencies", "core competencies", "competencies", "tools", "tools and technologies", "areas of expertise", "expertise", "tech stack"]),
        (.experience, ["experience", "work experience", "professional experience", "employment", "employment history", "work history", "relevant experience", "industry experience"]),
        (.education, ["education", "academic background", "academics", "educational background", "education and training"]),
        (.projects, ["projects", "personal projects", "academic projects", "selected projects", "key projects", "side projects", "notable projects"]),
        (.certifications, ["certifications", "certification", "certificates", "licenses", "licenses and certifications", "awards", "honors", "honors and awards", "achievements", "accomplishments"]),
    ]

    /// Splits normalized resume text into logical sections (Jobright pipeline stage 2).
    static func segment(normalizedText: String) -> [Segment] {
        let lines = normalizedText.components(separatedBy: .newlines)
        var segments: [Segment] = []
        var currentKind: Kind = .preamble
        var currentTitle = "Header"
        var body: [String] = []

        func flush() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                body = []
                return
            }
            segments.append(Segment(kind: currentKind, title: currentTitle, text: text))
            body = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if let (kind, title) = classifyHeader(trimmed) {
                flush()
                currentKind = kind
                currentTitle = title
                continue
            }
            body.append(trimmed)
        }
        flush()
        return segments
    }

    static func text(for kind: Kind, in segments: [Segment]) -> String? {
        segments.first(where: { $0.kind == kind })?.text
    }

    private static func classifyHeader(_ line: String) -> (Kind, String)? {
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 3, line.count <= 42, !line.contains("@") else { return nil }

        let normalized = line
            .lowercased()
            .replacingOccurrences(of: ":", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        for (kind, keys) in headerMap where keys.contains(normalized) {
            return (kind, prettyHeader(line))
        }

        let wordCount = normalized.split(separator: " ").count
        if line == line.uppercased(), wordCount <= 4, !line.contains(where: \.isNumber) {
            return (.other, prettyHeader(line))
        }
        return nil
    }

    private static func prettyHeader(_ line: String) -> String {
        let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: " :•-–—"))
        if cleaned == cleaned.uppercased() { return cleaned.capitalized }
        return cleaned
    }
}
