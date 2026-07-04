// CareerResumeParserCompliance.swift
// Feature: Career
// Purpose: Structural parser-compliance analysis for uploaded resumes.

import Foundation

enum ParserComplianceStatus: String, Codable, Sendable {
    case compliant
    case warning
    case critical
}

struct ParserComplianceIssue: Codable, Sendable, Equatable {
    var code: String
    var message: String
    var severity: ParserComplianceStatus
}

enum CareerResumeParserCompliance {
    struct Report: Sendable {
        let status: ParserComplianceStatus
        let healthPercent: Int
        let issues: [ParserComplianceIssue]
    }

    static func analyze(plainText: String, pageCount: Int, usedOCR: Bool) -> Report {
        var issues: [ParserComplianceIssue] = []
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < 120 {
            issues.append(ParserComplianceIssue(
                code: "sparse_text",
                message: "Very little text was extracted — ATS parsers may fail to read this PDF.",
                severity: .critical
            ))
        }

        if usedOCR {
            issues.append(ParserComplianceIssue(
                code: "ocr_required",
                message: "This PDF appears scanned or image-based. Export a text-based PDF from Word or Google Docs.",
                severity: .warning
            ))
        }

        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.count >= 8 {
            let shortLines = lines.filter { $0.count < 28 }.count
            if Double(shortLines) / Double(lines.count) > 0.55 {
                issues.append(ParserComplianceIssue(
                    code: "multi_column",
                    message: "Short fragmented lines suggest multi-column layout — Workday parsers often scramble column order.",
                    severity: .warning
                ))
            }
        }

        if pageCount > 2 {
            issues.append(ParserComplianceIssue(
                code: "long_resume",
                message: "Resume exceeds 2 pages — some ATS systems truncate after page 2.",
                severity: .warning
            ))
        }

        let hasEmail = trimmed.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.regularExpression, .caseInsensitive]) != nil
        if !hasEmail {
            issues.append(ParserComplianceIssue(
                code: "missing_email",
                message: "No email address detected in extracted text.",
                severity: .warning
            ))
        }

        let hasPhone = trimmed.range(of: #"\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#, options: .regularExpression) != nil
        if !hasPhone {
            issues.append(ParserComplianceIssue(
                code: "missing_phone",
                message: "No phone number detected in extracted text.",
                severity: .warning
            ))
        }

        let sectionHeaders = ["experience", "education", "skills", "summary", "projects"]
        let lower = trimmed.lowercased()
        let foundSections = sectionHeaders.filter { lower.contains($0) }.count
        if foundSections < 2 {
            issues.append(ParserComplianceIssue(
                code: "weak_sections",
                message: "Few standard section headers detected — parsers rely on headings to place content.",
                severity: .warning
            ))
        }

        let criticalCount = issues.filter { $0.severity == .critical }.count
        let warningCount = issues.filter { $0.severity == .warning }.count

        let status: ParserComplianceStatus
        if criticalCount > 0 {
            status = .critical
        } else if warningCount > 0 {
            status = .warning
        } else {
            status = .compliant
        }

        var health = 100
        health -= criticalCount * 35
        health -= warningCount * 12
        health = min(100, max(0, health))

        return Report(status: status, healthPercent: health, issues: issues)
    }
}
