// ASSISTOrgEngine.swift
// Feature: Transfer / Sources
// Purpose: Transfer Database — ASSIST.org aggregator engine (fixture + paced live modes).
// Data: Reads bundled fixtures or a hosted, pre-normalized articulation dataset.

import Foundation

/// Aggregator-style engine modeled on ASSIST.org articulation agreements.
///
/// In `fixture` mode it reads a bundled JSON sample. In `live` mode it performs human-paced
/// requests against a hosted, pre-normalized dataset (mirroring the app's GitHub data pattern)
/// rather than scraping the interactive site directly.
struct ASSISTOrgEngine: TransferSourceEngine {
    let sourceKind: TransferSourceKind = .assist
    let cachePolicy: TransferSourceCachePolicy = .aggressivePoliteness

    let fixtureResource: String
    let liveBaseURL: URL?
    let session: URLSession

    init(
        fixtureResource: String = "assist_sample",
        liveBaseURL: URL? = URL(string: "https://raw.githubusercontent.com/TL0225/college-planner-data/main/transfer/assist"),
        session: URLSession = .shared
    ) {
        self.fixtureResource = fixtureResource
        self.liveBaseURL = liveBaseURL
        self.session = session
    }

    func fetchEquivalencies(
        input: TransferEvaluationInput,
        session scrapeSession: TransferScrapeSession
    ) async throws -> [TransferEquivalencyDTO] {
        switch input.mode {
        case .fixture:
            let all = try TransferFixtureLoader.loadEquivalencies(resource: fixtureResource)
            return stamp(TransferFixtureLoader.filter(all, matching: input), input: input)
        case .live:
            return try await fetchLive(input: input, scrapeSession: scrapeSession)
        }
    }

    private func fetchLive(
        input: TransferEvaluationInput,
        scrapeSession: TransferScrapeSession
    ) async throws -> [TransferEquivalencyDTO] {
        guard let liveBaseURL else { throw TransferError.network("ASSIST live base URL not configured") }
        await scrapeSession.pace(using: cachePolicy)

        let source = TransferNormalization.normalizeSchoolID(input.sourceSchoolID)
        let target = TransferNormalization.normalizeSchoolID(input.targetSchoolID)
        let url = liveBaseURL.appendingPathComponent("\(source)__\(target).json")

        var request = URLRequest(url: url)
        request.setValue("CollegePlanner-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransferError.network("invalid response")
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 { throw TransferError.throttled }
                throw TransferError.network("HTTP \(http.statusCode)")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded: [TransferEquivalencyDTO]
            if let payload = try? decoder.decode(TransferCommunityPayload.self, from: data) {
                decoded = payload.equivalencies
            } else {
                decoded = try decoder.decode([TransferEquivalencyDTO].self, from: data)
            }
            return stamp(TransferFixtureLoader.filter(decoded, matching: input), input: input)
        } catch let error as TransferError {
            throw error
        } catch let urlError as URLError {
            throw TransferError.network(urlError.localizedDescription)
        }
    }

    /// Ensures returned DTOs carry the correct provenance + school identity for this pairing.
    private func stamp(
        _ dtos: [TransferEquivalencyDTO],
        input: TransferEvaluationInput
    ) -> [TransferEquivalencyDTO] {
        dtos.map { dto in
            var copy = dto
            copy.sourceKind = .assist
            copy.sourceTier = .official
            if copy.sourceSchoolID.isEmpty { copy.sourceSchoolID = input.sourceSchoolID }
            if copy.targetSchoolID.isEmpty { copy.targetSchoolID = input.targetSchoolID }
            if copy.sourceSchoolName.isEmpty { copy.sourceSchoolName = input.sourceSchoolName }
            if copy.targetSchoolName.isEmpty { copy.targetSchoolName = input.targetSchoolName }
            if copy.degreeLevel.isEmpty { copy.degreeLevel = input.degreeLevel }
            return copy
        }
    }
}
