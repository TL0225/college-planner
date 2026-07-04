// Banner9SSBEngine.swift
// Feature: Transfer / Sources
// Purpose: Transfer Database — Banner 9 Self-Service (SSB) transfer-equivalency parser.
// Data: Parses minimal HTML tables (fixture sample or paced live fetch).

import Foundation

/// Parses the Banner 9 Self-Service "Transfer Course Equivalencies" responsive grid.
struct Banner9SSBEngine: TransferSourceEngine {
    let sourceKind: TransferSourceKind = .banner9SSB
    let cachePolicy: TransferSourceCachePolicy = .default

    let liveBaseURL: URL?
    let session: URLSession

    init(liveBaseURL: URL? = nil, session: URLSession = .shared) {
        self.liveBaseURL = liveBaseURL
        self.session = session
    }

    func fetchEquivalencies(
        input: TransferEvaluationInput,
        session scrapeSession: TransferScrapeSession
    ) async throws -> [TransferEquivalencyDTO] {
        let html: String
        switch input.mode {
        case .fixture:
            html = Self.fixtureHTML
        case .live:
            guard let liveBaseURL else { throw TransferError.network("Banner9 live base URL not configured") }
            await scrapeSession.pace(using: cachePolicy)
            html = try await TransferLiveHTMLFetch.fetch(
                base: liveBaseURL,
                input: input,
                session: session,
                pathSuffix: "banner9.html"
            )
        }
        return Self.parse(html: html, input: input)
    }

    /// Banner 9 SSB layout: source subject | source number | source title | target subject | target number | target title | credits
    static func parse(html: String, input: TransferEvaluationInput) -> [TransferEquivalencyDTO] {
        var results: [TransferEquivalencyDTO] = []
        for row in TransferHTMLTableParser.rows(in: html) where row.count >= 7 {
            let sourceCode = CatalogImportTransforms.normalizeCourseCode("\(row[0]) \(row[1])")
            let targetCode = CatalogImportTransforms.normalizeCourseCode("\(row[3]) \(row[4])")
            guard !sourceCode.isEmpty, !targetCode.isEmpty,
                  sourceCode.rangeOfCharacter(from: .decimalDigits) != nil else { continue }
            let credits = Int(row[6].prefix(while: { $0.isNumber })) ?? 0
            results.append(
                TransferEquivalencyDTO(
                    sourceSchoolID: input.sourceSchoolID,
                    sourceSchoolName: input.sourceSchoolName,
                    sourceCourseCode: sourceCode,
                    sourceCourseTitle: row[2].isEmpty ? nil : row[2],
                    sourceCredits: credits,
                    targetSchoolID: input.targetSchoolID,
                    targetSchoolName: input.targetSchoolName,
                    targetCourseCode: targetCode,
                    targetCourseTitle: row[5].isEmpty ? nil : row[5],
                    targetCredits: credits,
                    equivalencyKind: .direct,
                    degreeLevel: input.degreeLevel,
                    sourceTier: .official,
                    sourceKind: .banner9SSB,
                    externalID: "\(sourceCode)->\(targetCode)",
                    verificationStatus: .verified
                )
            )
        }
        return results
    }

    static let fixtureHTML = """
    <table>
      <tr><th>Subj</th><th>Num</th><th>Title</th><th>Subj</th><th>Num</th><th>Title</th><th>Cr</th></tr>
      <tr><td>PHYS</td><td>201</td><td>Physics I</td><td>PHY</td><td>107</td><td>General Physics I</td><td>4</td></tr>
      <tr><td>HIST</td><td>110</td><td>US History</td><td>HIS</td><td>161</td><td>US History</td><td>3</td></tr>
    </table>
    """
}
