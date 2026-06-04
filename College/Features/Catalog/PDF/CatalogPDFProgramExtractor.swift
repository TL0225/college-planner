// CatalogPDFProgramExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFProgramExtractor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Stage 4 recognition: programs from classified blocks only.
enum CatalogPDFProgramExtractor {
    private static let degreeTokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\b(AA|AS|AAS|BA|BS|MA|MS|MBA|MENG|MPH|MFA|BFA|BM|JD|MD|PhD|PHD|DMD|DDS|DPT|PHARMD|MSTAT|MPP)\b"#,
        options: []
    )

    private static let minorRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\bminor(s)?\b"#,
        options: []
    )

    static func extract(
        from classifiedBlocks: [CatalogPDFClassifiedBlock],
        minConfidence: Float
    ) -> (programs: [ScrapedProgram], diagnostics: CatalogPDFBlockClassificationDiagnostics) {
        var programs: [ScrapedProgram] = []
        var seen: Set<String> = []
        var candidates = 0
        var accepted = 0
        var rejected = 0
        var sampleRejections: [String] = []
        var sampleAccepted: [String] = []
        var blocksByType: [String: Int] = [:]
        var acceptedConfidenceTotal: Double = 0

        for block in classifiedBlocks {
            blocksByType[block.type.rawValue, default: 0] += 1
        }

        for classified in classifiedBlocks where classified.type == .program {
            candidates += 1
            guard classified.confidence >= minConfidence else {
                rejected += 1
                if sampleRejections.count < 8 {
                    sampleRejections.append("below_threshold(\(classified.confidence)): \(classified.block.text.prefix(80))")
                }
                continue
            }

            if CatalogPDFProgramRejectLexicon.hasStrongNegative(classified.block.text) {
                rejected += 1
                if sampleRejections.count < 8 {
                    sampleRejections.append("lexicon: \(classified.block.text.prefix(80))")
                }
                continue
            }

            guard let program = parseProgram(from: classified) else {
                rejected += 1
                if sampleRejections.count < 8 {
                    sampleRejections.append("parse_failed: \(classified.block.text.prefix(80))")
                }
                continue
            }

            let key = "\(program.type)|\(program.name)".lowercased()
            guard seen.insert(key).inserted else { continue }

            programs.append(program)
            accepted += 1
            acceptedConfidenceTotal += Double(classified.confidence)
            if sampleAccepted.count < 8 {
                let ev = classified.evidence.matchedRules.joined(separator: ",")
                sampleAccepted.append("\(program.name) conf=\(classified.confidence) [\(ev)]")
            }
        }

        let diagnostics = CatalogPDFBlockClassificationDiagnostics(
            totalBlocks: classifiedBlocks.count,
            blocksByType: blocksByType,
            programCandidates: candidates,
            programAccepted: accepted,
            programRejected: rejected,
            sampleRejections: sampleRejections,
            sampleAcceptedEvidence: sampleAccepted,
            averageAcceptedProgramConfidence: accepted > 0 ? (acceptedConfidenceTotal / Double(accepted)) : nil
        )

        return (programs, diagnostics)
    }

    private static func parseProgram(from classified: CatalogPDFClassifiedBlock) -> ScrapedProgram? {
        let line = classified.block.text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? classified.block.text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !line.isEmpty, line.count <= 200 else { return nil }

        let ns = NSRange(line.startIndex..<line.endIndex, in: line)
        let isMinor = minorRegex?.firstMatch(in: line, range: ns) != nil
        let degreeToken = extractDegreeToken(from: line) ?? ""
        let programType = isMinor ? "Minor" : "Major"

        var name = line
        if !degreeToken.isEmpty {
            name = name.replacingOccurrences(of: degreeToken, with: "", options: [.caseInsensitive])
        }
        name = name
            .replacingOccurrences(of: "(?i)\\bminor(s)?\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\b(bachelor|master|associate)\\s+of\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[-–—:.;]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard name.count >= 3, name.count <= 120 else { return nil }
        guard !CatalogPDFProgramRejectLexicon.hasStrongNegative(name) else { return nil }

        let department = name.split(separator: " ").first.map(String.init)

        return ScrapedProgram(
            name: name,
            type: programType,
            url: "",
            group: nil,
            department: department,
            college: nil,
            degreeType: degreeToken.isEmpty ? nil : degreeToken.uppercased(),
            requirements: nil
        )
    }

    private static func extractDegreeToken(from line: String) -> String? {
        guard let re = degreeTokenRegex else { return nil }
        let ns = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = re.firstMatch(in: line, range: ns),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "PHD", with: "PhD", options: [.caseInsensitive])
    }
}
