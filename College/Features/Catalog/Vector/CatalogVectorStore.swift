// CatalogVectorStore.swift
// Feature: Catalog
// Purpose: Catalog module — Row.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func nonNullSQLiteText(_ stmt: OpaquePointer?, _ column: Int32) -> String {
    guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
          let ptr = sqlite3_column_text(stmt, column) else { return "" }
    return String(cString: ptr)
}

/// Hybrid FTS5 + cosine rerank for catalog chunks (separate SQLite file from local store).
actor CatalogVectorStore {
    static let shared = CatalogVectorStore()

    private var db: OpaquePointer?
    private let path: String
    private let isMemory: Bool

    private static let ftsSchemaUserVersion: Int32 = 2
    private static let databaseFileName = "catalog_vector_v2.sqlite"

    struct Row: Sendable, Equatable {
        let chunkId: String
        let universityId: String
        let sourceKind: String
        let ftsBody: String
        let metadataJSON: String
        let contentHash: String
        let embeddingVersion: String
        let createdAt: Date
        let courseCode: String?
        let programURL: String?
        let requirementCategory: String?
        /// Indexed column mirror for policy tier pruning (`catalog_policy`); empty for non-policy rows.
        let catalogScope: String?
        let embedding: Data?
    }

    init(inMemory: Bool = false) {
        self.isMemory = inMemory
        if inMemory {
            self.path = ":memory:"
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = base.appendingPathComponent("CollegeCatalogVector", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.path = dir.appendingPathComponent(Self.databaseFileName).path
        }
    }

    func upsert(
        chunkId: String,
        universityId: UUID,
        sourceKind: String,
        ftsBody: String,
        metadataJSON: String,
        contentHash: String,
        embeddingVersion: String,
        embedding: Data?,
        courseCode: String?,
        programURL: String?,
        requirementCategory: String?,
        catalogScope: String
    ) async throws {
        try await ensureOpen()
        try await deleteRows(matchingChunkId: chunkId)
        let uni = universityId.uuidString
        let cc = courseCode ?? ""
        let pu = programURL ?? ""
        let rc = requirementCategory ?? ""
        let cs = catalogScope.trimmingCharacters(in: .whitespacesAndNewlines)
        let created = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO catalog_vector_fts(
          chunk_id, university_id, source_kind, course_code, program_url, requirement_category,
          metadata_json, content_hash, embedding_version, created_at, embedding, catalog_scope, fts_body
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare upsert")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, chunkId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, uni, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, sourceKind, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, cc, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, pu, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, rc, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, metadataJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, embeddingVersion, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 10, created)
        if let emb = embedding {
            _ = emb.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, 11, buf.baseAddress, Int32(emb.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        sqlite3_bind_text(stmt, 12, cs, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 13, ftsBody, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step upsert")
        }
    }

    /// Removes every catalog embedding row (all universities). Used when the local store catalog is wiped or the active school is cleared.
    func deleteAllRows() async throws {
        try await ensureOpen()
        guard sqlite3_exec(db, "DELETE FROM catalog_vector_fts;", nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "deleteAllRows")
        }
    }

    func deleteAll(universityId: UUID) async throws {
        try await ensureOpen()
        let uni = universityId.uuidString
        let sql = "DELETE FROM catalog_vector_fts WHERE university_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare deleteAll")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, uni, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step deleteAll")
        }
    }

    func rowCount(universityId: UUID) async throws -> Int {
        try await ensureOpen()
        let uni = universityId.uuidString
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM catalog_vector_fts WHERE university_id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare count")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, uni, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// FTS prefetch filtered by `university_id`, optional cosine rerank when `queryVector` matches stored dimension.
    /// When `catalogScopeFilter` is set (e.g. `undergraduate` / `graduate`), policy rows (`catalog_policy`) are filtered with SQL using `catalog_scope`.
    func searchHybrid(
        query: String,
        universityId: UUID,
        ftsPrefetch: Int = 32,
        limit: Int = 8,
        queryVector: [Float]?,
        semanticEnabled: Bool,
        catalogScopeFilter: String? = nil,
        preferredProgramURL: String? = nil
    ) async throws -> [Row] {
        try await ensureOpen()
        let match = AssistantWebMemoryStore.sanitizedFtsMatch(query)
        guard !match.isEmpty else { return [] }
        let uni = universityId.uuidString
        let scopeToken = catalogScopeFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wantsScope = (scopeToken?.isEmpty == false)
        let prefetch = Int32(max(1, min(ftsPrefetch, 160)))
        let cap = max(1, min(limit, 16))

        let sql: String
        if wantsScope, let token = scopeToken, !token.isEmpty {
            sql = """
            SELECT chunk_id, university_id, source_kind, course_code, program_url, requirement_category,
                   metadata_json, content_hash, embedding_version, created_at, embedding, catalog_scope, fts_body,
                   bm25(catalog_vector_fts) AS r
            FROM catalog_vector_fts
            WHERE catalog_vector_fts MATCH ? AND university_id = ?
              AND (
                source_kind != 'catalog_policy'
                OR TRIM(COALESCE(catalog_scope, '')) = ''
                OR LOWER(TRIM(catalog_scope)) = 'shared'
                OR LOWER(TRIM(catalog_scope)) = ?
              )
            ORDER BY r ASC
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT chunk_id, university_id, source_kind, course_code, program_url, requirement_category,
                   metadata_json, content_hash, embedding_version, created_at, embedding, catalog_scope, fts_body,
                   bm25(catalog_vector_fts) AS r
            FROM catalog_vector_fts
            WHERE catalog_vector_fts MATCH ? AND university_id = ?
            ORDER BY r ASC
            LIMIT ?;
            """
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare search")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, uni, -1, SQLITE_TRANSIENT)
        if wantsScope, let token = scopeToken, !token.isEmpty {
            sqlite3_bind_text(stmt, 3, token, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 4, prefetch)
        } else {
            sqlite3_bind_int(stmt, 3, prefetch)
        }

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkId = nonNullSQLiteText(stmt, 0)
            let universityIdStr = nonNullSQLiteText(stmt, 1)
            let sourceKind = nonNullSQLiteText(stmt, 2)
            let courseCode = nonNullSQLiteText(stmt, 3)
            let programURL = nonNullSQLiteText(stmt, 4)
            let requirementCategory = nonNullSQLiteText(stmt, 5)
            let metadataJSON = nonNullSQLiteText(stmt, 6)
            let contentHash = nonNullSQLiteText(stmt, 7)
            let embeddingVersion = nonNullSQLiteText(stmt, 8)
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
            let emb: Data?
            if sqlite3_column_type(stmt, 10) != SQLITE_NULL,
               let blob = sqlite3_column_blob(stmt, 10) {
                emb = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 10)))
            } else {
                emb = nil
            }
            let catalogScopeRaw = nonNullSQLiteText(stmt, 11)
            let catalogScope = catalogScopeRaw.isEmpty ? nil : catalogScopeRaw
            let ftsBody = nonNullSQLiteText(stmt, 12)
            rows.append(
                Row(
                    chunkId: chunkId,
                    universityId: universityIdStr,
                    sourceKind: sourceKind,
                    ftsBody: ftsBody,
                    metadataJSON: metadataJSON,
                    contentHash: contentHash,
                    embeddingVersion: embeddingVersion,
                    createdAt: created,
                    courseCode: courseCode.isEmpty ? nil : courseCode,
                    programURL: programURL.isEmpty ? nil : programURL,
                    requirementCategory: requirementCategory.isEmpty ? nil : requirementCategory,
                    catalogScope: catalogScope,
                    embedding: emb
                )
            )
        }

        let workingRows = rows

        let prefForBoost: String = {
            let t = preferredProgramURL?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return t
        }()

        guard semanticEnabled, let qVec = queryVector, !qVec.isEmpty else {
            let head = Array(workingRows.prefix(Int(cap)))
            return prefForBoost.isEmpty ? head : Self.prioritizeProgramURLMatches(rows: head, preferredLowercased: prefForBoost)
        }

        var scored: [(Row, Float)] = []
        var tail: [Row] = []
        for r in workingRows {
            if let blob = r.embedding,
               let rv = Self.floats(from: blob),
               rv.count == qVec.count,
               let s = VectorMath.cosineSimilarity(qVec, rv) {
                scored.append((r, s))
            } else {
                tail.append(r)
            }
        }
        if scored.isEmpty {
            return Array(workingRows.prefix(Int(cap)))
        }
        scored.sort { $0.1 > $1.1 }
        var out: [Row] = []
        var seen = Set<String>()
        for (r, _) in scored {
            guard out.count < cap else { break }
            if seen.insert(r.chunkId).inserted {
                out.append(r)
            }
        }
        for r in tail {
            guard out.count < cap else { break }
            if seen.insert(r.chunkId).inserted {
                out.append(r)
            }
        }
        return prefForBoost.isEmpty ? out : Self.prioritizeProgramURLMatches(rows: out, preferredLowercased: prefForBoost)
    }

    private static func metadataProgramURL(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["programURL"] as? String else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func prioritizeProgramURLMatches(rows: [Row], preferredLowercased: String) -> [Row] {
        guard !preferredLowercased.isEmpty else { return rows }
        func matches(_ r: Row) -> Bool {
            let pu = (r.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !pu.isEmpty, preferredLowercased.contains(pu) || pu.contains(preferredLowercased) { return true }
            let meta = (Self.metadataProgramURL(r.metadataJSON) ?? "").lowercased()
            if !meta.isEmpty, preferredLowercased.contains(meta) || meta.contains(preferredLowercased) { return true }
            return false
        }
        let yes = rows.filter(matches)
        let no = rows.filter { !matches($0) }
        return yes + no
    }

    // MARK: - Internals

    private func deleteRows(matchingChunkId chunkId: String) async throws {
        let sql = "DELETE FROM catalog_vector_fts WHERE chunk_id = ?;"
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
        try applyMigrations()
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
            _ = sqlite3_exec(db, "DROP TABLE IF EXISTS catalog_vector_fts;", nil, nil, nil)
            let ddl = """
            CREATE VIRTUAL TABLE catalog_vector_fts USING fts5(
                chunk_id UNINDEXED,
                university_id UNINDEXED,
                source_kind UNINDEXED,
                course_code UNINDEXED,
                program_url UNINDEXED,
                requirement_category UNINDEXED,
                metadata_json UNINDEXED,
                content_hash UNINDEXED,
                embedding_version UNINDEXED,
                created_at UNINDEXED,
                embedding UNINDEXED,
                catalog_scope UNINDEXED,
                fts_body,
                tokenize = 'porter unicode61'
            );
            """
            guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else {
                throw Self.dbError(db, "migration fts create")
            }
            Self.eraseVectorIndexReadinessKeys()
            let verSql = "PRAGMA user_version = \(Self.ftsSchemaUserVersion)"
            guard sqlite3_exec(db, verSql, nil, nil, nil) == SQLITE_OK else {
                throw Self.dbError(db, "migration user_version")
            }
        }
    }

    private static func eraseVectorIndexReadinessKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("catalog.vectorIndex.") {
            defaults.removeObject(forKey: key)
        }
    }

    private static func dbError(_ db: OpaquePointer?, _ ctx: String) -> NSError {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error"
        return NSError(domain: "CatalogVectorStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(ctx): \(msg)"])
    }

    private static func floats(from data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let n = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Float.self).baseAddress else { return nil }
            return Array(UnsafeBufferPointer(start: base, count: n))
        }
    }
}

// MARK: - sqlite-vec scale-out (optional)

extension CatalogVectorStore {
    /// Reserved hook: ANN via sqlite-vec would reuse `searchHybrid`'s cosine stage with a smaller candidate id set.
    enum ScaleOutPlaceholder {
        static let note = "Phase 1 uses FTS5 + Swift cosine only; sqlite-vec can plug in behind the same Row contract."
    }
}
