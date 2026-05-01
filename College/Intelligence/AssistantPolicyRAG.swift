import Foundation

struct AssistantPolicyContext: Sendable, Equatable {
    let jurisdiction: UniversityPolicyJurisdiction
    let explicitStateOverride: String?

    static func from(metadata: SchoolPolicyMetadata?, activeUniversityName: String?, message: String) -> AssistantPolicyContext {
        let base = metadata.map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
            ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: activeUniversityName)
        guard let override = StateAidRegistry.stateCode(in: message),
              override != base.normalizedStateCode else {
            return AssistantPolicyContext(jurisdiction: base, explicitStateOverride: nil)
        }
        return AssistantPolicyContext(
            jurisdiction: UniversityPolicyJurisdiction(
                schoolID: nil,
                unitID: nil,
                opeID: nil,
                countryCode: "US",
                stateCode: override,
                universityName: "",
                officialWebsiteURL: nil,
                catalogURL: nil,
                financialAidURL: nil,
                registrarURL: nil,
                stateAidAgencyURL: StateAidRegistry.agencyURL(for: override),
                evidenceSource: "explicit user state override"
            ),
            explicitStateOverride: override
        )
    }
}

enum AssistantPolicyRAGSourceKind: String, Codable, Sendable, CaseIterable {
    case schoolFinancialAid = "school_financial_aid"
    case federalStudentAid = "federal_student_aid"
    case stateAid = "state_aid"
    case academicCatalog = "academic_catalog"
}

struct AssistantPolicyRAGChunk: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let sourceURL: String
    let sourceTitle: String
    let sourceKind: AssistantPolicyRAGSourceKind
    let schoolID: String?
    let unitID: String?
    let opeID: String?
    let stateCode: String?
    let jurisdictionKey: String
    let retrievedAt: Date
    let effectiveYear: String?
    let officialHost: String
    let confidence: Double
    let text: String
    let embedding: [Float]
    let etag: String?
    let lastModified: String?

    var isStale: Bool {
        Date().timeIntervalSince(retrievedAt) > 180 * 24 * 60 * 60
    }
}

struct AssistantPolicyRAGFilter: Sendable, Equatable {
    let schoolID: String?
    let unitID: String?
    let opeID: String?
    let stateCode: String?
    let allowedJurisdictionKeys: Set<String>
    let sourceKinds: Set<AssistantPolicyRAGSourceKind>

    static func financialAid(context: AssistantPolicyContext) -> AssistantPolicyRAGFilter {
        let jurisdiction = context.jurisdiction
        var keys: Set<String> = [AssistantPolicyJurisdiction.federalUS.key]
        if let schoolID = jurisdiction.schoolID {
            keys.insert(AssistantPolicyJurisdiction.institution(schoolID).key)
        } else if jurisdiction.isUniversityAtBuffalo {
            keys.insert(AssistantPolicyJurisdiction.universityAtBuffalo.key)
        }
        if let state = jurisdiction.normalizedStateCode {
            keys.insert(AssistantPolicyJurisdiction.state(state).key)
        }
        return AssistantPolicyRAGFilter(
            schoolID: jurisdiction.schoolID,
            unitID: jurisdiction.unitID,
            opeID: jurisdiction.opeID,
            stateCode: jurisdiction.normalizedStateCode,
            allowedJurisdictionKeys: keys,
            sourceKinds: [.schoolFinancialAid, .academicCatalog, .stateAid, .federalStudentAid]
        )
    }
}

struct AssistantPolicyRAGHit: Sendable, Equatable {
    let chunk: AssistantPolicyRAGChunk
    let score: Float
}

actor AssistantPolicyRAGStore {
    static let shared = AssistantPolicyRAGStore()

    private var chunks: [AssistantPolicyRAGChunk] = []

    func upsert(_ incoming: [AssistantPolicyRAGChunk]) {
        var byID = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })
        for chunk in incoming {
            byID[chunk.id] = chunk
        }
        chunks = Array(byID.values)
    }

    func clearForTests() {
        chunks = []
    }

    func retrieve(query: String, filter: AssistantPolicyRAGFilter, limit: Int = 6) -> [AssistantPolicyRAGHit] {
        let queryVector = AssistantPolicyEmbeddingRuntime.shared.embed(query)
        let candidates = chunks.filter { chunk in
            guard filter.sourceKinds.contains(chunk.sourceKind) else { return false }
            guard filter.allowedJurisdictionKeys.contains(chunk.jurisdictionKey) else { return false }
            if chunk.sourceKind == .schoolFinancialAid || chunk.sourceKind == .academicCatalog {
                if let expected = filter.schoolID, chunk.schoolID != expected { return false }
                if let expected = filter.unitID, let chunkUnit = chunk.unitID, chunkUnit != expected { return false }
                if let expected = filter.opeID, let chunkOPE = chunk.opeID, chunkOPE != expected { return false }
            }
            if chunk.sourceKind == .stateAid, let expected = filter.stateCode, chunk.stateCode != expected { return false }
            return true
        }
        return candidates
            .map { chunk in
                AssistantPolicyRAGHit(chunk: chunk, score: weightedScore(chunk: chunk, queryVector: queryVector))
            }
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .prefix(max(1, min(limit, 12)))
            .map { $0 }
    }

    private func weightedScore(chunk: AssistantPolicyRAGChunk, queryVector: [Float]) -> Float {
        let semantic = AssistantWebMemoryEmbedding.cosineSimilarity(queryVector, chunk.embedding)
        let priority: Float
        switch chunk.sourceKind {
        case .schoolFinancialAid, .academicCatalog:
            priority = 0.35
        case .stateAid:
            priority = 0.20
        case .federalStudentAid:
            priority = 0.10
        }
        let freshnessPenalty: Float = chunk.isStale ? 0.08 : 0
        return semantic + priority - freshnessPenalty
    }
}

struct AssistantPolicyEmbeddingRuntime {
    static let shared = AssistantPolicyEmbeddingRuntime()

    func embed(_ text: String) -> [Float] {
        // Swap this implementation for a CoreML embedding model without changing store callers.
        AssistantWebMemoryEmbedding.vector(for: text)
    }
}

enum AssistantPolicyChunker {
    static func markdownChunks(
        text: String,
        targetCharacters: Int = 1_200,
        overlapRatio: Double = 0.10
    ) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let target = max(300, targetCharacters)
        let overlap = max(40, Int(Double(target) * overlapRatio))
        var chunks: [String] = []
        var start = normalized.startIndex
        while start < normalized.endIndex {
            let targetEnd = normalized.index(start, offsetBy: target, limitedBy: normalized.endIndex) ?? normalized.endIndex
            let end = preferredBoundary(in: normalized, start: start, proposedEnd: targetEnd)
            let piece = normalized[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                chunks.append(String(piece))
            }
            if end == normalized.endIndex { break }
            start = normalized.index(end, offsetBy: -min(overlap, normalized.distance(from: start, to: end)), limitedBy: start) ?? end
        }
        return chunks
    }

    private static func preferredBoundary(in text: String, start: String.Index, proposedEnd: String.Index) -> String.Index {
        guard proposedEnd < text.endIndex else { return text.endIndex }
        let window = text[start..<proposedEnd]
        for separator in ["\n\n", "\n|", ". "] {
            if let range = window.range(of: separator, options: .backwards) {
                return range.upperBound
            }
        }
        return proposedEnd
    }
}

enum AssistantPolicyRAGSeeder {
    static func chunks(from evidence: [AssistantPolicyEvidence], jurisdiction: UniversityPolicyJurisdiction, now: Date = Date()) -> [AssistantPolicyRAGChunk] {
        evidence.flatMap { item in
            let sourceKind: AssistantPolicyRAGSourceKind
            switch item.topic {
            case .schoolFinancialAid:
                sourceKind = .schoolFinancialAid
            case .academicCatalog:
                sourceKind = .academicCatalog
            case .stateAid:
                sourceKind = .stateAid
            default:
                sourceKind = .federalStudentAid
            }
            let text = "\(item.title)\n\n\(item.summary)\n\n\(item.cautions.joined(separator: " "))"
            return AssistantPolicyChunker.markdownChunks(text: text).enumerated().map { index, chunkText in
                AssistantPolicyRAGChunk(
                    id: "\(item.id)-chunk-\(index)",
                    sourceURL: item.sourceURL,
                    sourceTitle: item.title,
                    sourceKind: sourceKind,
                    schoolID: sourceKind == .schoolFinancialAid || sourceKind == .academicCatalog ? jurisdiction.schoolID : nil,
                    unitID: sourceKind == .schoolFinancialAid || sourceKind == .academicCatalog ? jurisdiction.unitID : nil,
                    opeID: sourceKind == .schoolFinancialAid || sourceKind == .academicCatalog ? jurisdiction.opeID : nil,
                    stateCode: sourceKind == .stateAid ? jurisdiction.normalizedStateCode : nil,
                    jurisdictionKey: item.jurisdiction.key,
                    retrievedAt: now,
                    effectiveYear: item.effectiveLabel,
                    officialHost: item.sourceHost,
                    confidence: 0.75,
                    text: chunkText,
                    embedding: AssistantPolicyEmbeddingRuntime.shared.embed(chunkText),
                    etag: nil,
                    lastModified: nil
                )
            }
        }
    }
}

enum AssistantPolicyRAGFormatter {
    static func promptBlock(hits: [AssistantPolicyRAGHit]) -> String {
        guard !hits.isEmpty else { return "" }
        let lines = hits.prefix(6).enumerated().map { idx, hit in
            let source = idx + 1
            let stale = hit.chunk.isStale ? " STALE_POLICY" : ""
            let retrieved = ISO8601DateFormatter().string(from: hit.chunk.retrievedAt)
            return """
            [[Source: \(source), Chunk: \(hit.chunk.id)]]\(stale)
            Title: \(hit.chunk.sourceTitle)
            URL: \(hit.chunk.sourceURL)
            Retrieved: \(retrieved)
            Scope: \(hit.chunk.jurisdictionKey) / \(hit.chunk.sourceKind.rawValue)
            Text: \(hit.chunk.text)
            """
        }
        return "Retrieved official policy evidence:\n" + lines.joined(separator: "\n\n")
    }
}
