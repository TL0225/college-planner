// PlannerVectorStore.swift
// Feature: Assistant
// Purpose: Assistant module — Row.
// Data: CollegePersistence / repositories when applicable.

// Isolation: `actor PlannerVectorStore` — serializes SQLite access.
// Incremental updates are in-place; full rebuild uses shadow swap (catalog full rebuild does not).

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func nonNullSQLiteText(_ stmt: OpaquePointer?, _ column: Int32) -> String {
    guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
          let ptr = sqlite3_column_text(stmt, column) else { return "" }
    return String(cString: ptr)
}

/// Hybrid FTS5 + blended score for planner chunks (separate SQLite file from local store).
actor PlannerVectorStore {
    static let shared = PlannerVectorStore()

    private var db: OpaquePointer?
    private let path: String
    private let isMemory: Bool

    private static let ftsSchemaUserVersion: Int32 = 1
    private static let databaseFileName = "planner_vector.sqlite"
    private static let buildDatabaseFileName = "planner_vector_build.sqlite"

    struct Row: Sendable, Equatable {
        let chunkId: String
        let sourceType: String
        let sourceId: String
        let segmentIndex: Int
        let ftsBody: String
        let metadataJSON: String
        let contentHash: String
        let embeddingVersion: String
        let createdAt: Date
        let referenceDate: Date?
        let embedding: Data?
    }

    struct ScoredRow: Sendable, Equatable {
        let row: Row
        let finalScore: Float
        let cosineSimilarity: Float?
        let recencyBoost: Float
    }

    init(inMemory: Bool = false) {
        self.isMemory = inMemory
        if inMemory {
            self.path = ":memory:"
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = base.appendingPathComponent("College", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.path = dir.appendingPathComponent(Self.databaseFileName).path
        }
    }

    private init(buildPath: String) {
        self.isMemory = false
        self.path = buildPath
    }

    func upsert(
        chunkId: String,
        sourceType: String,
        sourceId: String,
        segmentIndex: Int,
        ftsBody: String,
        metadataJSON: String,
        contentHash: String,
        embeddingVersion: String,
        referenceDate: Date?,
        embedding: Data?
    ) async throws {
        try await ensureOpen()
        try await deleteRows(matchingChunkId: chunkId)
        let created = Date().timeIntervalSince1970
        let ref = referenceDate?.timeIntervalSince1970
        let sql = """
        INSERT INTO planner_vector_fts(
          chunk_id, source_type, source_id, segment_index, metadata_json, content_hash,
          embedding_version, created_at, reference_date, embedding, fts_body
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare upsert")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, chunkId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sourceType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, sourceId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(segmentIndex))
        sqlite3_bind_text(stmt, 5, metadataJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, embeddingVersion, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 8, created)
        if let ref {
            sqlite3_bind_double(stmt, 9, ref)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        if let emb = embedding {
            _ = emb.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, 10, buf.baseAddress, Int32(emb.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        sqlite3_bind_text(stmt, 11, ftsBody, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step upsert")
        }
    }

    func contentHash(forChunkId chunkId: String) async throws -> String? {
        try await ensureOpen()
        let sql = "SELECT content_hash FROM planner_vector_fts WHERE chunk_id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare content_hash")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, chunkId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let h = nonNullSQLiteText(stmt, 0)
        return h.isEmpty ? nil : h
    }

    func deleteChunks(sourceType: String, sourceId: String) async throws {
        try await ensureOpen()
        let sql = "DELETE FROM planner_vector_fts WHERE source_type = ? AND source_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare deleteChunks")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sourceType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sourceId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step deleteChunks")
        }
    }

    func deleteAllRows() async throws {
        try await ensureOpen()
        guard sqlite3_exec(db, "DELETE FROM planner_vector_fts;", nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "deleteAllRows")
        }
    }

    func chunkCount() async throws -> Int {
        try await ensureOpen()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM planner_vector_fts;", -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare count")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// FTS prefetch + planner hybrid blend (`PlannerVectorSearchConfig` weights).
    func searchHybrid(
        query: String,
        ftsPrefetch: Int = 24,
        limit: Int = 6,
        queryVector: [Float]?,
        semanticEnabled: Bool,
        usesNeuralEmbedding: Bool = false,
        now: Date = Date()
    ) async throws -> [ScoredRow] {
        try await ensureOpen()
        let match = AssistantWebMemoryStore.sanitizedFtsMatch(query)
        guard !match.isEmpty else { return [] }
        let prefetch = Int32(max(1, min(ftsPrefetch, 120)))
        let cap = max(1, min(limit, 16))
        let floor = PlannerVectorSearchConfig.similarityFloor(
            semanticEnabled: semanticEnabled,
            usesNeuralEmbedding: usesNeuralEmbedding
        )

        let sql = """
        SELECT chunk_id, source_type, source_id, segment_index, metadata_json, content_hash,
               embedding_version, created_at, reference_date, embedding, fts_body,
               bm25(planner_vector_fts) AS r
        FROM planner_vector_fts
        WHERE planner_vector_fts MATCH ?
        ORDER BY r ASC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare search")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, prefetch)

        struct Candidate {
            let row: Row
            let bm25Rank: Int
        }
        var candidates: [Candidate] = []
        var rank = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            rank += 1
            let chunkId = nonNullSQLiteText(stmt, 0)
            let sourceType = nonNullSQLiteText(stmt, 1)
            let sourceId = nonNullSQLiteText(stmt, 2)
            let segmentIndex = Int(sqlite3_column_int(stmt, 3))
            let metadataJSON = nonNullSQLiteText(stmt, 4)
            let contentHash = nonNullSQLiteText(stmt, 5)
            let embeddingVersion = nonNullSQLiteText(stmt, 6)
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            let referenceDate: Date?
            if sqlite3_column_type(stmt, 8) != SQLITE_NULL {
                referenceDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
            } else {
                referenceDate = nil
            }
            let emb: Data?
            if sqlite3_column_type(stmt, 9) != SQLITE_NULL,
               let blob = sqlite3_column_blob(stmt, 9) {
                emb = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 9)))
            } else {
                emb = nil
            }
            let ftsBody = nonNullSQLiteText(stmt, 10)
            let row = Row(
                chunkId: chunkId,
                sourceType: sourceType,
                sourceId: sourceId,
                segmentIndex: segmentIndex,
                ftsBody: ftsBody,
                metadataJSON: metadataJSON,
                contentHash: contentHash,
                embeddingVersion: embeddingVersion,
                createdAt: created,
                referenceDate: referenceDate,
                embedding: emb
            )
            candidates.append(Candidate(row: row, bm25Rank: rank))
        }

        guard !candidates.isEmpty else { return [] }

        let maxRank = Float(max(candidates.count, 1))
        var scored: [ScoredRow] = []
        for c in candidates {
            let bm25Norm = 1 - (Float(c.bm25Rank) - 1) / maxRank
            let recency = Self.recencyBoost(sourceType: c.row.sourceType, referenceDate: c.row.referenceDate, now: now)
            var cosine: Float?
            if semanticEnabled, let qVec = queryVector, !qVec.isEmpty,
               let blob = c.row.embedding,
               let rv = Self.floats(from: blob),
               rv.count == qVec.count,
               let sim = VectorMath.cosineSimilarity(qVec, rv) {
                cosine = sim
            }
            let cosVal = cosine ?? 0
            let final = PlannerVectorSearchConfig.bm25Weight * bm25Norm
                + PlannerVectorSearchConfig.cosineWeight * cosVal
                + PlannerVectorSearchConfig.recencyWeight * recency
            if semanticEnabled, let cos = cosine, cos < floor { continue }
            if !semanticEnabled {
                let half = max(1, candidates.count / 2)
                guard c.bm25Rank <= half else { continue }
            }
            scored.append(ScoredRow(row: c.row, finalScore: final, cosineSimilarity: cosine, recencyBoost: recency))
        }

        scored.sort { lhs, rhs in
            if lhs.finalScore != rhs.finalScore { return lhs.finalScore > rhs.finalScore }
            return (lhs.cosineSimilarity ?? 0) > (rhs.cosineSimilarity ?? 0)
        }
        return Array(scored.prefix(Int(cap)))
    }

    /// Builds into a shadow file, then atomically replaces the live database.
    func swapFromShadowBuild(_ build: PlannerVectorStore) async throws {
        guard !isMemory else {
            try await deleteAllRows()
            return
        }
        try await build.ensureOpen()
        let buildCount = try await build.chunkCount()
        guard buildCount >= 0 else { return }

        closeHandle()
        let liveURL = URL(fileURLWithPath: path)
        let buildURL = URL(fileURLWithPath: build.path)
        let fm = FileManager.default
        let backupURL = liveURL.deletingLastPathComponent().appendingPathComponent("planner_vector.sqlite.prev")
        if fm.fileExists(atPath: liveURL.path) {
            _ = try? fm.removeItem(at: backupURL)
            try? fm.moveItem(at: liveURL, to: backupURL)
        }
        try fm.moveItem(at: buildURL, to: liveURL)
        _ = try? fm.removeItem(at: backupURL)
        try await ensureOpen()
    }

    static func openShadowBuildStore() -> PlannerVectorStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("College", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let buildPath = dir.appendingPathComponent(buildDatabaseFileName).path
        try? FileManager.default.removeItem(atPath: buildPath)
        return PlannerVectorStore(buildPath: buildPath)
    }

    func journalMode() async throws -> String {
        try await ensureOpen()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "pragma journal_mode")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return nonNullSQLiteText(stmt, 0)
    }

    // MARK: - Scoring helpers

    static func recencyBoost(sourceType: String, referenceDate: Date?, now: Date) -> Float {
        let window = recencyWindowDays(sourceType: sourceType)
        guard window > 0, let ref = referenceDate else {
            return window == 0 ? 1.0 : 0.5
        }
        let ageDays = max(0, Calendar.current.dateComponents([.day], from: ref, to: now).day ?? 0)
        return max(0, 1 - Float(ageDays) / Float(window))
    }

    static func recencyWindowDays(sourceType: String) -> Int {
        if sourceType == "calendar_event" || sourceType == "task" { return 14 }
        if sourceType.hasPrefix("career_") || sourceType == "vault_document" { return 30 }
        return 0
    }

    // MARK: - Internals

    private func deleteRows(matchingChunkId chunkId: String) async throws {
        let sql = "DELETE FROM planner_vector_fts WHERE chunk_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare delete chunk")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, chunkId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step delete chunk")
        }
    }

    private func ensureOpen() async throws {
        if db != nil { return }
        var handle: OpaquePointer?
        let flags = isMemory ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_MEMORY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let h = handle else {
            throw Self.dbError(handle, "open")
        }
        db = h
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "wal")
        }
        try applyMigrations()
    }

    private func closeHandle() {
        if let db {
            sqlite3_close(db)
        }
        self.db = nil
    }

    private func applyMigrations() throws {
        var userVersion: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                userVersion = sqlite3_column_int(stmt, 0)
            }
        }

        if userVersion < Self.ftsSchemaUserVersion {
            _ = sqlite3_exec(db, "DROP TABLE IF EXISTS planner_vector_fts;", nil, nil, nil)
            let ddl = """
            CREATE VIRTUAL TABLE planner_vector_fts USING fts5(
                chunk_id UNINDEXED,
                source_type UNINDEXED,
                source_id UNINDEXED,
                segment_index UNINDEXED,
                metadata_json UNINDEXED,
                content_hash UNINDEXED,
                embedding_version UNINDEXED,
                created_at UNINDEXED,
                reference_date UNINDEXED,
                embedding UNINDEXED,
                fts_body,
                tokenize = 'porter unicode61'
            );
            """
            guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else {
                throw Self.dbError(db, "migration fts create")
            }
            let verSql = "PRAGMA user_version = \(Self.ftsSchemaUserVersion)"
            guard sqlite3_exec(db, verSql, nil, nil, nil) == SQLITE_OK else {
                throw Self.dbError(db, "migration user_version")
            }
        }
    }

    private static func dbError(_ db: OpaquePointer?, _ ctx: String) -> NSError {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error"
        return NSError(domain: "PlannerVectorStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(ctx): \(msg)"])
    }

    private static func floats(from data: Data) -> [Float]? {
        AssistantWebMemoryEmbedding.vector(fromStored: data)
    }
}
