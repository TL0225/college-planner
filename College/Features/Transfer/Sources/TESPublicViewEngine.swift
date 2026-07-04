// TESPublicViewEngine.swift
// Feature: Transfer / Sources
// Purpose: Transfer Database — Transfer Evaluation System (TES) public-view table parser.
// Data: Parses minimal HTML tables (fixture sample or paced live fetch).

import Foundation

/// Parses the College Source / TES public "Browse Equivalencies" table layout.
struct TESPublicViewEngine: TransferSourceEngine {
    let sourceKind: TransferSourceKind = .tesPublicView
    let cachePolicy: TransferSourceCachePolicy = .default

    let liveBaseURL: URL?
    let session: URLSession

    init(
        liveBaseURL: URL? = nil,
        session: URLSession = .shared
    ) {
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
            guard let liveBaseURL else { throw TransferError.network("TES live base URL not configured") }
            await scrapeSession.pace(using: cachePolicy)
            html = try await fetchHTML(base: liveBaseURL, input: input)
        }
        return Self.parse(html: html, input: input)
    }

    private func fetchHTML(base: URL, input: TransferEvaluationInput) async throws -> String {
        let source = TransferNormalization.normalizeSchoolID(input.sourceSchoolID)
        let target = TransferNormalization.normalizeSchoolID(input.targetSchoolID)
        let url = base.appendingPathComponent("\(target)/\(source).html")
        var request = URLRequest(url: url)
        request.setValue("CollegePlanner-macOS", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TransferError.network("invalid response") }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 { throw TransferError.throttled }
                throw TransferError.network("HTTP \(http.statusCode)")
            }
            return String(decoding: data, as: UTF8.self)
        } catch let error as TransferError {
            throw error
        } catch let urlError as URLError {
            throw TransferError.network(urlError.localizedDescription)
        }
    }

    /// Column layout: source code | source title | source credits | target code | target title | target credits | type
    static func parse(html: String, input: TransferEvaluationInput) -> [TransferEquivalencyDTO] {
        var results: [TransferEquivalencyDTO] = []
        for row in TransferHTMLTableParser.rows(in: html) where row.count >= 6 {
            // Skip header rows (no parseable source course code).
            let sourceCode = CatalogImportTransforms.normalizeCourseCode(row[0])
            let targetCode = CatalogImportTransforms.normalizeCourseCode(row[3])
            guard !sourceCode.isEmpty, !targetCode.isEmpty,
                  sourceCode.rangeOfCharacter(from: .decimalDigits) != nil else { continue }
            let kind = row.count >= 7 ? TransferEquivalencyKindParsing.parse(row[6]) : .direct
            results.append(
                TransferEquivalencyDTO(
                    sourceSchoolID: input.sourceSchoolID,
                    sourceSchoolName: input.sourceSchoolName,
                    sourceCourseCode: sourceCode,
                    sourceCourseTitle: row[1].isEmpty ? nil : row[1],
                    sourceCredits: Int(row[2].prefix(while: { $0.isNumber })) ?? 0,
                    targetSchoolID: input.targetSchoolID,
                    targetSchoolName: input.targetSchoolName,
                    targetCourseCode: targetCode,
                    targetCourseTitle: row[4].isEmpty ? nil : row[4],
                    targetCredits: Int(row[5].prefix(while: { $0.isNumber })) ?? 0,
                    equivalencyKind: kind,
                    degreeLevel: input.degreeLevel,
                    sourceTier: .official,
                    sourceKind: .tesPublicView,
                    externalID: "\(sourceCode)->\(targetCode)",
                    verificationStatus: .verified
                )
            )
        }
        return results
    }

    static let fixtureHTML = """
    <table>
      <tr><th>Source</th><th>Title</th><th>Cr</th><th>Equivalent</th><th>Title</th><th>Cr</th><th>Type</th></tr>
      <tr><td>CS 101</td><td>Intro to Programming</td><td>4</td><td>CSE 115</td><td>Intro to CS I</td><td>4</td><td>Direct</td></tr>
      <tr><td>MATH 150</td><td>Calculus I</td><td>4</td><td>MTH 141</td><td>College Calculus I</td><td>4</td><td>Direct</td></tr>
      <tr><td>ENG 100</td><td>Composition</td><td>3</td><td>ENG 105</td><td>Writing</td><td>3</td><td>Partial</td></tr>
    </table>
    """
}

/// Shared text → `TransferEquivalencyKind` parsing used by HTML table engines.
enum TransferEquivalencyKindParsing {
    static func parse(_ raw: String) -> TransferEquivalencyKind {
        let value = raw.lowercased()
        if value.contains("not") || value.contains("no credit") || value.contains("denied") {
            return .notTransferable
        }
        if value.contains("partial") { return .partial }
        if value.contains("elect") { return .elective }
        if value.contains("condition") { return .conditional }
        return .direct
    }
}
