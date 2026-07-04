// TransferSourceEngine.swift
// Feature: Transfer / Sources
// Purpose: Transfer Database — source engine protocol, paced scrape session, cache policy.
// Data: Network/parsing only; returns DTOs for the coordinator to persist.

import Foundation

/// TTL + pacing configuration for a source engine.
struct TransferSourceCachePolicy: Hashable, Sendable {
    /// How long a successful fetch for a (source, target) pair stays fresh.
    var freshnessInterval: TimeInterval
    /// Minimum delay between live requests (politeness floor).
    var minRequestInterval: TimeInterval
    /// Additional random jitter added on top of `minRequestInterval`.
    var maxJitter: TimeInterval

    static let `default` = TransferSourceCachePolicy(
        freshnessInterval: 60 * 60 * 24 * 7,
        minRequestInterval: 1.2,
        maxJitter: 1.8
    )

    static let aggressivePoliteness = TransferSourceCachePolicy(
        freshnessInterval: 60 * 60 * 24 * 14,
        minRequestInterval: 2.5,
        maxJitter: 3.0
    )
}

/// Coordinates human-paced requests for a single refresh pass so the app never hammers a source.
///
/// `TransferScrapeSession` is an actor: engines call `await session.pace()` before each live
/// request and the session enforces a minimum interval plus randomized jitter.
actor TransferScrapeSession {
    let mode: TransferSourceMode
    private(set) var requestCount: Int = 0
    private var lastRequestAt: Date?
    private let clock: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        mode: TransferSourceMode,
        clock: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.mode = mode
        self.clock = clock
        self.sleep = sleep
    }

    /// Sleeps just long enough to honor the policy's minimum interval and adds jitter.
    /// No-op in fixture mode.
    func pace(using policy: TransferSourceCachePolicy) async {
        requestCount += 1
        guard mode == .live else { return }
        let now = clock()
        if let last = lastRequestAt {
            let elapsed = now.timeIntervalSince(last)
            let required = policy.minRequestInterval - elapsed
            if required > 0 {
                await sleep(required)
            }
        }
        let jitter = Double.random(in: 0...max(0, policy.maxJitter))
        if jitter > 0 {
            await sleep(jitter)
        }
        lastRequestAt = clock()
    }
}

/// A pluggable transfer-equivalency source. Implementations stay off the main actor.
protocol TransferSourceEngine: Sendable {
    var sourceKind: TransferSourceKind { get }
    var cachePolicy: TransferSourceCachePolicy { get }

    /// Returns equivalencies for the requested pairing. May read fixtures or perform live,
    /// paced requests depending on `input.mode`.
    func fetchEquivalencies(
        input: TransferEvaluationInput,
        session: TransferScrapeSession
    ) async throws -> [TransferEquivalencyDTO]
}

extension TransferSourceEngine {
    var cachePolicy: TransferSourceCachePolicy { .default }
}

/// Shared helpers for engines that read bundled JSON fixtures.
enum TransferFixtureLoader {
    static func loadEquivalencies(
        resource: String,
        bundle: Bundle = .main
    ) throws -> [TransferEquivalencyDTO] {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw TransferError.fixtureNotFound("\(resource).json")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Fixtures may be a bare array or a `{ "equivalencies": [...] }` envelope.
        if let payload = try? decoder.decode(TransferCommunityPayload.self, from: data) {
            return payload.equivalencies
        }
        return try decoder.decode([TransferEquivalencyDTO].self, from: data)
    }

    static func filter(
        _ dtos: [TransferEquivalencyDTO],
        matching input: TransferEvaluationInput
    ) -> [TransferEquivalencyDTO] {
        let source = TransferNormalization.normalizeSchoolID(input.sourceSchoolID)
        let target = TransferNormalization.normalizeSchoolID(input.targetSchoolID)
        return dtos.filter { dto in
            let dtoSource = TransferNormalization.normalizeSchoolID(dto.sourceSchoolID)
            let dtoTarget = TransferNormalization.normalizeSchoolID(dto.targetSchoolID)
            let sourceMatches = source.isEmpty || dtoSource == source
            let targetMatches = target.isEmpty || dtoTarget == target
            return sourceMatches && targetMatches
        }
    }
}

/// Minimal, dependency-free extraction of `<table>` rows for fixture HTML parsing.
///
/// This is intentionally tiny: official fixtures are simple, well-formed tables. It is not a
/// general HTML parser and should not be pointed at arbitrary live markup.
enum TransferHTMLTableParser {
    /// Returns rows as arrays of trimmed cell text. Reads both `<td>` and `<th>` cells.
    static func rows(in html: String) -> [[String]] {
        var rows: [[String]] = []
        let lowered = html
        var searchRange = lowered.startIndex..<lowered.endIndex
        while let rowStart = lowered.range(of: "<tr", options: .caseInsensitive, range: searchRange),
              let rowClose = lowered.range(of: ">", range: rowStart.upperBound..<lowered.endIndex),
              let rowEnd = lowered.range(of: "</tr>", options: .caseInsensitive, range: rowClose.upperBound..<lowered.endIndex) {
            let rowContent = String(lowered[rowClose.upperBound..<rowEnd.lowerBound])
            let cells = cellTexts(in: rowContent)
            if !cells.isEmpty {
                rows.append(cells)
            }
            searchRange = rowEnd.upperBound..<lowered.endIndex
        }
        return rows
    }

    private static func cellTexts(in rowHTML: String) -> [String] {
        var cells: [String] = []
        var searchRange = rowHTML.startIndex..<rowHTML.endIndex
        let tags = ["td", "th"]
        while true {
            var earliest: (open: Range<String.Index>, tag: String)?
            for tag in tags {
                if let open = rowHTML.range(of: "<\(tag)", options: .caseInsensitive, range: searchRange) {
                    if earliest == nil || open.lowerBound < earliest!.open.lowerBound {
                        earliest = (open, tag)
                    }
                }
            }
            guard let found = earliest,
                  let openClose = rowHTML.range(of: ">", range: found.open.upperBound..<rowHTML.endIndex),
                  let closeTag = rowHTML.range(of: "</\(found.tag)>", options: .caseInsensitive, range: openClose.upperBound..<rowHTML.endIndex) else {
                break
            }
            let inner = String(rowHTML[openClose.upperBound..<closeTag.lowerBound])
            cells.append(stripTags(inner))
            searchRange = closeTag.upperBound..<rowHTML.endIndex
        }
        return cells
    }

    static func stripTags(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
