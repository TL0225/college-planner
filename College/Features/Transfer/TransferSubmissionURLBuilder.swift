// TransferSubmissionURLBuilder.swift
// Feature: Transfer
// Purpose: Transfer Database — builds prefilled GitHub issue URLs for community submissions.
// Data: Pure URL construction (mirrors GitHubDataService.submitCorrection).

import Foundation

/// Builds a GitHub "new issue" URL with a transfer equivalency prefilled, so users can submit
/// corrections/additions without any API token (browser-based contribution flow).
enum TransferSubmissionURLBuilder {
    static let repoOwner = "TL0225"
    static let repoName = "college-planner-data"

    static func issueURL(for dto: TransferEquivalencyDTO) -> URL? {
        let title = "Transfer: \(dto.sourceSchoolName) \(dto.sourceCourseCode) → \(dto.targetSchoolName) \(dto.targetCourseCode)"
        let body = """
        ### Proposed transfer equivalency

        | Field | Value |
        | --- | --- |
        | Source school | \(dto.sourceSchoolName) (`\(dto.sourceSchoolID)`) |
        | Source course | `\(dto.sourceCourseCode)` \(dto.sourceCourseTitle ?? "") |
        | Source credits | \(dto.sourceCredits) |
        | Target school | \(dto.targetSchoolName) (`\(dto.targetSchoolID)`) |
        | Target course | `\(dto.targetCourseCode)` \(dto.targetCourseTitle ?? "") |
        | Target credits | \(dto.targetCredits) |
        | Equivalency | \(dto.equivalencyKind.displayName) |
        | Degree level | \(dto.degreeLevel) |
        | Effective term | \(dto.effectiveTerm ?? "—") |
        | Source URL | \(dto.sourceURL ?? "—") |

        \(dto.notes.map { "Notes: \($0)\n" } ?? "")
        ---
        _Submitted via College Planner — Transfer Database_
        """

        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let labels = "transfer-equivalency,\(dto.targetSchoolID)"
        let urlString = "https://github.com/\(repoOwner)/\(repoName)/issues/new?title=\(encodedTitle)&body=\(encodedBody)&labels=\(labels)"
        return URL(string: urlString)
    }

    /// Bulk submission: links to a new issue summarizing a batch of equivalencies.
    static func batchIssueURL(for dtos: [TransferEquivalencyDTO]) -> URL? {
        guard let first = dtos.first else { return nil }
        let title = "Transfer batch: \(first.sourceSchoolName) → \(first.targetSchoolName) (\(dtos.count) mappings)"
        var lines = ["### Proposed transfer equivalencies", "", "| Source | Target | Type |", "| --- | --- | --- |"]
        for dto in dtos.prefix(100) {
            lines.append("| `\(dto.sourceCourseCode)` | `\(dto.targetCourseCode)` | \(dto.equivalencyKind.displayName) |")
        }
        lines.append("")
        lines.append("_Submitted via College Planner — Transfer Database_")
        let body = lines.joined(separator: "\n")
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let labels = "transfer-equivalency,\(first.targetSchoolID)"
        let urlString = "https://github.com/\(repoOwner)/\(repoName)/issues/new?title=\(encodedTitle)&body=\(encodedBody)&labels=\(labels)"
        return URL(string: urlString)
    }
}
