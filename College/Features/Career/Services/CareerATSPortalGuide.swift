// CareerATSPortalGuide.swift
// Feature: Career
// Purpose: Portal-specific ATS parser advice keyed by job board platform.

import Foundation

enum CareerATSPortalGuide {
    static func tips(for platform: JobBoardPlatform, parserIssues: [ParserComplianceIssue] = []) -> [String] {
        var tips: [String] = []
        switch platform {
        case .workday:
            tips.append("Workday parsers struggle with multi-column PDFs — use a single-column export.")
            tips.append("Avoid text boxes and floating shapes; use standard heading styles in Word.")
        case .greenhouse:
            tips.append("Greenhouse reads PDF text linearly — keep section headers on their own line.")
        case .lever:
            tips.append("Lever strips formatting — paste plain text fields if the PDF upload fails.")
        case .oracle:
            tips.append("Oracle HCM may truncate after page 2 — keep critical skills on page 1.")
        case .icims:
            tips.append("iCIMS often misreads headers/footers — disable repeating page headers in Word.")
        case .talemetry:
            tips.append("Talemetry/Jobvite prefers .docx over complex PDF layouts.")
        case .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            tips.append("Public boards redirect to employer apply sites — export a clean single-column PDF before uploading elsewhere.")
        }
        for issue in parserIssues.prefix(2) {
            tips.append(issue.message)
        }
        return Array(tips.prefix(4))
    }
}
