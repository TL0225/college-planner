// CareerResumePlainTextNormalizer.swift
// Feature: Career / ResumeParsing
// Purpose: Repair PDF line breaks and orphan bullet glyphs before structured parsing.

import Foundation

enum CareerResumePlainTextNormalizer {
    private static let bulletOnlyPattern = #"^[•◦▪▫●‣·∙\*\s]+$"#

    static func normalize(_ plainText: String) -> String {
        let rawLines = plainText.components(separatedBy: .newlines)
        var logicalLines: [String] = []
        var buffer = ""

        func flushBuffer() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logicalLines.append(trimmed)
            }
            buffer = ""
        }

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushBuffer()
                continue
            }
            if isBulletOnlyLine(line) { continue }

            if buffer.isEmpty {
                buffer = line
                continue
            }

            if shouldJoin(previous: buffer, next: line) {
                buffer = joinLines(buffer, line)
            } else {
                flushBuffer()
                buffer = line
            }
        }
        flushBuffer()

        return logicalLines.joined(separator: "\n")
    }

    private static func isBulletOnlyLine(_ line: String) -> Bool {
        line.range(of: bulletOnlyPattern, options: .regularExpression) != nil
    }

    private static func shouldJoin(previous: String, next: String) -> Bool {
        if isLikelySectionHeader(next) || isLikelySectionHeader(previous) {
            return false
        }
        if isLikelyEducationInstitution(next) || isLikelyEducationInstitution(previous) {
            return false
        }
        if isLikelyJobOrProjectHeading(next) {
            return false
        }
        if isLikelyJobOrProjectHeading(previous) && isLikelySubtitleOrDateLine(next) {
            return false
        }

        let prevTrimmed = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)

        if nextTrimmed.first?.isNumber == true,
           prevTrimmed.hasSuffix("SOC") || prevTrimmed.hasSuffix("Type") {
            return true
        }

        if prevTrimmed.hasSuffix("-") || prevTrimmed.hasSuffix("–") || prevTrimmed.hasSuffix("—") {
            return true
        }

        if let first = nextTrimmed.first, first.isLowercase || first.isNumber {
            return true
        }

        if !prevTrimmed.hasSuffix(".") && !prevTrimmed.hasSuffix(":") && !prevTrimmed.hasSuffix(";") {
            if nextTrimmed.count < 48, isLikelySubtitleOrDateLine(nextTrimmed) {
                return false
            }
            if !startsWithActionVerb(nextTrimmed) {
                return true
            }
        }

        return false
    }

    private static func joinLines(_ previous: String, _ next: String) -> String {
        var prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let nxt = next.trimmingCharacters(in: .whitespacesAndNewlines)
        if prev.hasSuffix("-") || prev.hasSuffix("–") || prev.hasSuffix("—") {
            prev.removeLast()
            return prev + nxt
        }
        return prev + " " + nxt
    }

    private static func isLikelySectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 42 else { return false }
        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        if trimmed == trimmed.uppercased() { return true }
        let normalized = trimmed.lowercased()
        let headers = [
            "education", "experience", "work experience", "projects", "technical skills",
            "skills", "certifications", "awards", "summary",
        ]
        return headers.contains(normalized)
    }

    private static func isLikelyEducationInstitution(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 120 else { return false }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("coursework:") || lower.hasPrefix("gpa:") || lower.hasPrefix("graduated:") {
            return false
        }
        return lower.range(
            of: #"(?i)\b(university|college|institute|school of)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isLikelyJobOrProjectHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"(?i)\b(intern|analyst|engineer|consultant|specialist)\b"#, options: .regularExpression) != nil,
           trimmed.contains(" - ") || trimmed.contains(" – ") || trimmed.contains(" — ") {
            return true
        }
        if trimmed.range(of: #"(?i)\b(capstone|thesis|portfolio project|independent study|lab|deployment|reconstruction)\b"#, options: .regularExpression) != nil,
           trimmed.range(of: #"(?i)\b(fall|spring|summer|winter)\s+20\d{2}\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func isLikelySubtitleOrDateLine(_ line: String) -> Bool {
        if CareerResumeDateParser.parseDateRange(from: line) != nil { return true }
        return line.range(
            of: #"(?i)\b(january|february|march|april|may|june|july|august|september|october|november|december|fall|spring|summer|winter)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func startsWithActionVerb(_ line: String) -> Bool {
        let lower = line.lowercased()
        let verbs = [
            "assessed", "supported", "analyzed", "authored", "resolved", "architected", "deployed",
            "conducted", "executed", "designed", "compiled", "created", "managed", "developed",
            "implemented", "led", "collaborated", "researched", "presented", "monitored",
        ]
        return verbs.contains { lower.hasPrefix($0) }
    }
}
