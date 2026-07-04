// CareerExperienceAnalyzer.swift
// Feature: Career
// Purpose: Years-of-experience parsing from JD + candidate date ranges from structured profile.

import Foundation

struct ExperienceAnalysis: Sendable {
    var score: Int
    var candidateMonths: Int
    var requiredYearsMin: Int?
    var requiredYearsMax: Int?
    var gapNote: String?
    var candidateYearsMonthsLabel: String
}

enum CareerExperienceAnalyzer {
    static func analyze(jdText: String, structuredProfile: CareerResumeStructuredProfile?) -> ExperienceAnalysis {
        let requirement = parseRequiredYears(from: jdText)
        let candidateMonths = computeCandidateMonths(from: structuredProfile)
        let label = formatMonths(candidateMonths)

        guard let minYears = requirement.min else {
            return ExperienceAnalysis(
                score: fallbackTitleScore(profile: structuredProfile, jdText: jdText),
                candidateMonths: candidateMonths,
                requiredYearsMin: nil,
                requiredYearsMax: requirement.max,
                gapNote: nil,
                candidateYearsMonthsLabel: label
            )
        }

        let requiredMonths = minYears * 12
        let ratio = requiredMonths > 0 ? Double(candidateMonths) / Double(requiredMonths) : 1.0
        let score: Int = {
            if ratio >= 1.0 { return 100 }
            if ratio >= 0.75 { return 75 }
            if ratio >= 0.5 { return 50 }
            return max(10, Int((ratio * 100).rounded()))
        }()

        var gapNote: String?
        if ratio < 1.0 {
            if let maxYears = requirement.max {
                gapNote = "Job asks \(minYears)–\(maxYears) yrs · ~\(label) detected"
            } else {
                gapNote = "Job asks \(minYears)+ yrs · ~\(label) detected"
            }
        }

        return ExperienceAnalysis(
            score: score,
            candidateMonths: candidateMonths,
            requiredYearsMin: minYears,
            requiredYearsMax: requirement.max,
            gapNote: gapNote,
            candidateYearsMonthsLabel: label
        )
    }

    private static func parseRequiredYears(from text: String) -> (min: Int?, max: Int?) {
        let lower = text.lowercased()

        if let match = lower.range(of: #"(\d+)\s*[–\-]\s*(\d+)\s*\+?\s*years?"#, options: .regularExpression) {
            let snippet = String(lower[match])
            if !snippet.contains("consecutive") {
                let nums = snippet.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
                if nums.count >= 2 { return (nums[0], nums[1]) }
            }
        }

        let qualificationPatterns = [
            #"(?:minimum|min\.?|at least)\s+(?:of\s+)?(\d+)\s*(?:\+?\s*)?years?"#,
            #"bachelor'?s?[^.\n]{0,120}?(?:minimum|at least)\s+(?:of\s+)?(\d+)\s*(?:\+?\s*)?years?"#,
            #"(\d+)\s*(?:\+?\s*)?years?\s+of\s+(?:[\w/]+\s+)*(?:experience|promotion|experience in)"#,
        ]
        for pattern in qualificationPatterns {
            if let match = lower.range(of: pattern, options: .regularExpression) {
                let snippet = String(lower[match])
                if snippet.contains("consecutive") || snippet.contains("employer") { continue }
                if let years = snippet.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first {
                    return (years, nil)
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*\+?\s*years?"#, options: .caseInsensitive) {
            let nsRange = NSRange(lower.startIndex..., in: lower)
            for match in regex.matches(in: lower, options: [], range: nsRange) {
                guard let yearRange = Range(match.range(at: 1), in: lower),
                      let years = Int(lower[yearRange]) else { continue }
                let contextStart = lower.index(lower.startIndex, offsetBy: max(0, match.range.location - 40))
                let contextEnd = lower.index(lower.startIndex, offsetBy: min(lower.count, match.range.location + match.range.length + 40))
                let window = String(lower[contextStart..<contextEnd])
                if window.contains("consecutive") || window.contains("top employer") || window.contains("magazine") {
                    continue
                }
                if window.contains("experience") || window.contains("promotion") || window.contains("minimum") || window.contains("required") {
                    return (years, nil)
                }
            }
        }

        return (nil, nil)
    }

    private static func computeCandidateMonths(from profile: CareerResumeStructuredProfile?) -> Int {
        guard let profile else { return 0 }
        var ranges: [(start: Date, end: Date)] = []
        let now = Date()
        for entry in profile.experience {
            let joined = entry.headingLines.joined(separator: " ")
            var parsed = CareerResumeDateParser.parseDateRange(from: joined)
            if parsed == nil {
                for line in entry.headingLines {
                    if let range = CareerResumeDateParser.parseDateRange(from: line) {
                        parsed = range
                        break
                    }
                }
            }
            if let range = parsed {
                ranges.append(range)
            }
        }
        guard !ranges.isEmpty else { return 0 }

        ranges.sort { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for range in ranges {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }

        let totalMonths = merged.reduce(0) { partial, range in
            let months = Calendar.current.dateComponents([.month], from: range.start, to: range.end).month ?? 0
            let endedYearsAgo = Calendar.current.dateComponents([.year], from: range.end, to: now).year ?? 0
            let decay: Double = endedYearsAgo > 5 ? 0.6 : 1.0
            return partial + Int((Double(max(months, 1)) * decay).rounded())
        }
        return totalMonths
    }

    private static func formatMonths(_ months: Int) -> String {
        if months < 12 { return "\(months) mo" }
        let years = months / 12
        let rem = months % 12
        if rem == 0 { return "\(years) yr" }
        return "\(years) yr \(rem) mo"
    }

    private static func fallbackTitleScore(profile: CareerResumeStructuredProfile?, jdText: String) -> Int {
        guard let profile else { return 50 }
        let titles = profile.experience.flatMap(\.headingLines).joined(separator: " ").lowercased()
        let jdLower = jdText.lowercased()
        let tokens = jdLower.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 4 }
        guard !tokens.isEmpty else { return 50 }
        let hits = tokens.filter { titles.contains($0) }.count
        return min(100, Int((Double(hits) / Double(tokens.count) * 100).rounded()))
    }
}
