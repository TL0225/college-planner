// Banner8ArticulationEngine.swift
// Feature: Transfer / Sources
// Purpose: Transfer Database — Banner 8 transfer-articulation table parser.
// Data: Parses minimal HTML tables (fixture sample or paced live fetch).

import Foundation

/// Parses the classic Banner 8 `bwcktrans`-style transfer articulation grid.
struct Banner8ArticulationEngine: TransferSourceEngine {
    let sourceKind: TransferSourceKind = .banner8Articulation
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
            guard let liveBaseURL else { throw TransferError.network("Banner8 live base URL not configured") }
            await scrapeSession.pace(using: cachePolicy)
            html = try await TransferLiveHTMLFetch.fetch(
                base: liveBaseURL,
                input: input,
                session: session,
                pathSuffix: "banner8.html"
            )
        }
        return Self.parse(html: html, input: input)
    }

    /// Banner 8 layout: source subj+num | source title | source credit | target subj+num | target title | target credit
    static func parse(html: String, input: TransferEvaluationInput) -> [TransferEquivalencyDTO] {
        var results: [TransferEquivalencyDTO] = []
        for row in TransferHTMLTableParser.rows(in: html) where row.count >= 6 {
            let sourceCode = CatalogImportTransforms.normalizeCourseCode(row[0])
            let targetCode = CatalogImportTransforms.normalizeCourseCode(row[3])
            guard !sourceCode.isEmpty, !targetCode.isEmpty,
                  sourceCode.rangeOfCharacter(from: .decimalDigits) != nil else { continue }
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
                    equivalencyKind: TransferEquivalencyKindParsing.parse(targetCode),
                    degreeLevel: input.degreeLevel,
                    sourceTier: .official,
                    sourceKind: .banner8Articulation,
                    externalID: "\(sourceCode)->\(targetCode)",
                    verificationStatus: .verified
                )
            )
        }
        return results
    }

    static let fixtureHTML = """
    <table class="datadisplaytable">
      <tr><th>Transfer Course</th><th>Title</th><th>Hrs</th><th>Equivalent Course</th><th>Title</th><th>Hrs</th></tr>
      <tr><td>BIO 110</td><td>General Biology</td><td>4</td><td>BIO 200</td><td>Evolutionary Biology</td><td>4</td></tr>
      <tr><td>CHEM 105</td><td>General Chemistry</td><td>4</td><td>CHE 101</td><td>General Chemistry</td><td>4</td></tr>
    </table>
    """
}

/// Shared live HTML fetch used by the Banner engines.
enum TransferLiveHTMLFetch {
    static func fetch(
        base: URL,
        input: TransferEvaluationInput,
        session: URLSession,
        pathSuffix: String
    ) async throws -> String {
        let source = TransferNormalization.normalizeSchoolID(input.sourceSchoolID)
        let target = TransferNormalization.normalizeSchoolID(input.targetSchoolID)
        let url = base.appendingPathComponent("\(target)/\(source)/\(pathSuffix)")
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
}
