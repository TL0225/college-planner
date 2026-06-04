// AssistantWebMemoryStore.swift
// Feature: Assistant
// Purpose: Assistant module — EntryPreference.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite exposes NULL text columns as `NULL` C pointers; `String(cString:)` must not receive those.
private func nonNullSQLiteText(_ stmt: OpaquePointer?, _ column: Int32) -> String {
    guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
          let ptr = sqlite3_column_text(stmt, column) else { return "" }
    return String(cString: ptr)
}

private func optionalSQLiteText(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
    guard sqlite3_column_type(stmt, column) != SQLITE_NULL,
          let ptr = sqlite3_column_text(stmt, column) else { return nil }
    return String(cString: ptr)
}

/// On-device assistant web learnings (FTS5). Optional embedding blob reserved for hybrid semantic search.
actor AssistantWebMemoryStore {

    static let shared = AssistantWebMemoryStore()

    /// Shared on-device retention bounds (web FTS rows and in-memory policy RAG chunks).
    static let retentionHighWaterMark = 1_500
    static let retentionTargetCount = 1_200
    private static let acceptedAnswerHighWaterMark = 400
    private static let acceptedAnswerTargetCount = 320

    private var db: OpaquePointer?
    private let path: String
    private let isMemory: Bool
    private let entryPrefsDefaultsKey = "assistant.webMemory.entryPrefs.v1"

    private struct EntryPreference: Codable, Sendable {
        var isPinned: Bool
        var isIncludedInContext: Bool
    }

    init(inMemory: Bool = false) {
        self.isMemory = inMemory
        if inMemory {
            self.path = ":memory:"
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = base.appendingPathComponent("AssistantWebMemory", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.path = dir.appendingPathComponent("assistant_web.sqlite").path
        }
    }

    struct Row: Sendable, Equatable {
        let id: String
        let createdAt: Date
        let title: String
        let body: String
        let urlsJSON: String
        let tags: String?
        /// Raw blob from SQLite when selected (for hybrid rerank); omitted in many call sites.
        let embedding: Data?
    }

    struct AcceptedWebAnswer: Sendable, Equatable {
        let cacheKey: String
        let query: String
        let role: String
        let universityName: String?
        let answer: String
        let sourcesJSON: String
        let createdAt: Date
    }

    func insert(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        sourceURLs: [String],
        tags: String?,
        embedding: Data? = nil
    ) async throws {
        try await ensureOpen()
        let urlsJSON = (try? JSONEncoder().encode(sourceURLs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let tagsVal = tags ?? ""
        let created = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO assistant_web_memory(mem_id, title, body, tags, urls_json, created_at, embedding)
        VALUES(?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare insert")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, body, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, tagsVal, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, urlsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 6, created)
        if let emb = embedding {
            _ = emb.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, 7, buf.baseAddress, Int32(emb.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step insert")
        }
        try await pruneIfNeeded()
    }

    /// Full-text search (BM25). Returned rows omit embedding blobs.
    func searchFTS(query: String, limit: Int = 8) async throws -> [Row] {
        try await searchFTSIncludingEmbeddings(query: query, limit: limit).map { $0.strippingEmbeddingBlob() }
    }

    private func searchFTSIncludingEmbeddings(query: String, limit: Int) async throws -> [Row] {
        try await ensureOpen()
        let match = Self.sanitizedFtsMatch(query)
        guard !match.isEmpty else { return [] }

        let sql = """
        SELECT mem_id, title, body, tags, urls_json, created_at, embedding, bm25(assistant_web_memory) AS r
        FROM assistant_web_memory
        WHERE assistant_web_memory MATCH ?
        ORDER BY r ASC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare search")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(max(1, min(limit, 32))))

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = nonNullSQLiteText(stmt, 0)
            let title = nonNullSQLiteText(stmt, 1)
            let body = nonNullSQLiteText(stmt, 2)
            let tags = optionalSQLiteText(stmt, 3)
            let urls = nonNullSQLiteText(stmt, 4)
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            let emb: Data?
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL,
               let blob = sqlite3_column_blob(stmt, 6) {
                emb = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 6)))
            } else {
                emb = nil
            }
            rows.append(Row(id: id, createdAt: created, title: title, body: body, urlsJSON: urls, tags: tags, embedding: emb))
        }
        return rows
    }

    /// FTS candidates, optionally reranked by cosine similarity when `semanticEnabled` and stored vectors exist.
    func searchHybrid(query: String, ftsPrefetch: Int = 24, limit: Int = 8, semanticEnabled: Bool) async throws -> [Row] {
        let ftsRows = try await searchFTSIncludingEmbeddings(query: query, limit: ftsPrefetch)
        let cap = max(1, min(limit, 16))
        guard semanticEnabled else {
            return Array(ftsRows.prefix(cap)).map { $0.strippingEmbeddingBlob() }
        }
        let qText = String(query.prefix(2000))
        let qVec = AssistantWebMemoryEmbedding.vector(for: qText)
        var scored: [(Row, Float)] = []
        var tail: [Row] = []
        for r in ftsRows {
            if let blob = r.embedding,
               let rv = AssistantWebMemoryEmbedding.vector(fromStored: blob) {
                let s = AssistantWebMemoryEmbedding.cosineSimilarity(qVec, rv)
                scored.append((r, s))
            } else {
                tail.append(r)
            }
        }
        if scored.isEmpty {
            return Array(ftsRows.prefix(cap)).map { $0.strippingEmbeddingBlob() }
        }
        scored.sort { $0.1 > $1.1 }
        var out: [Row] = []
        var seen = Set<String>()
        for (r, _) in scored {
            guard out.count < cap else { break }
            let stripped = r.strippingEmbeddingBlob()
            if seen.insert(stripped.id).inserted {
                out.append(stripped)
            }
        }
        for r in tail {
            guard out.count < cap else { break }
            let stripped = r.strippingEmbeddingBlob()
            if seen.insert(stripped.id).inserted {
                out.append(stripped)
            }
        }
        return out
    }

    /// Planner-facing snippet: entries whose FTS / hybrid score matches the current user message.
    func contextForUserQuery(_ rawQuery: String, charBudget: Int, maxRows: Int = 8, semanticEnabled: Bool) async -> String {
        guard charBudget > 60 else { return "" }
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return "" }
        let clipped = String(trimmed.prefix(400))
        let rows: [Row]
        do {
            rows = try await searchHybrid(
                query: clipped,
                ftsPrefetch: 28,
                limit: max(1, min(maxRows, 12)),
                semanticEnabled: semanticEnabled
            )
        } catch {
            return ""
        }
        guard !rows.isEmpty else { return "" }
        let prefs = loadEntryPreferences()
        let includedRows = rows.filter { prefs[$0.id]?.isIncludedInContext ?? true }
        guard !includedRows.isEmpty else { return "" }
        let header = "Web memory relevant to this message:\n"
        var parts: [String] = []
        var used = header.utf8.count
        for r in includedRows {
            let tagSuffix: String
            if let t = r.tags, !t.isEmpty { tagSuffix = " [tags: \(t)]" } else { tagSuffix = "" }
            let line = "- \(r.title): \(String(r.body.prefix(200)))\(tagSuffix)\n"
            if used + line.utf8.count > charBudget { break }
            parts.append(line)
            used += line.utf8.count
        }
        if parts.isEmpty { return "" }
        return header + parts.joined()
    }

    func recentSummaries(charBudget: Int, maxRows: Int = 12) async -> String {
        guard charBudget > 40 else { return "" }
        do {
            try await ensureOpen()
        } catch {
            return ""
        }
        let sql = """
        SELECT mem_id, title, body, tags, urls_json, created_at
        FROM assistant_web_memory
        ORDER BY created_at DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return "" }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(max(1, min(maxRows, 24))))

        let prefs = loadEntryPreferences()
        let header = "Saved web learnings (on-device):\n"
        var parts: [String] = []
        var used = header.utf8.count
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = nonNullSQLiteText(stmt, 0)
            let pref = prefs[id] ?? EntryPreference(isPinned: false, isIncludedInContext: true)
            guard pref.isIncludedInContext else { continue }
            let title = nonNullSQLiteText(stmt, 1)
            let body = nonNullSQLiteText(stmt, 2)
            let tags = optionalSQLiteText(stmt, 3) ?? ""
            let line = "- \(title): \(String(body.prefix(220)))\(tags.isEmpty ? "" : " [tags: \(tags)]")\n"
            if used + line.utf8.count > charBudget { break }
            parts.append(line)
            used += line.utf8.count
        }
        if parts.isEmpty { return "" }
        return header + parts.joined()
    }

    func count() async throws -> Int {
        try await ensureOpen()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM assistant_web_memory;", -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare count")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    struct EntryListItem: Sendable {
        let id: String
        let createdAt: Date
        let title: String
        let bodyPreview: String
        let tags: String?
        let isPinned: Bool
        let isIncludedInContext: Bool
    }

    func listRecentEntries(limit: Int = 200) async throws -> [EntryListItem] {
        try await ensureOpen()
        let cap = max(1, min(limit, 500))
        let sql = """
        SELECT mem_id, title, body, tags, created_at
        FROM assistant_web_memory
        ORDER BY CAST(created_at AS REAL) DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare list entries")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(cap))
        let prefs = loadEntryPreferences()
        var items: [EntryListItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = nonNullSQLiteText(stmt, 0)
            let title = nonNullSQLiteText(stmt, 1)
            let body = nonNullSQLiteText(stmt, 2)
            let tags = optionalSQLiteText(stmt, 3)
            let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            let preview = String(body.prefix(280))
            let pref = prefs[id] ?? EntryPreference(isPinned: false, isIncludedInContext: true)
            items.append(
                EntryListItem(
                    id: id,
                    createdAt: created,
                    title: title,
                    bodyPreview: preview,
                    tags: tags,
                    isPinned: pref.isPinned,
                    isIncludedInContext: pref.isIncludedInContext
                )
            )
        }
        return items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    func deleteEntry(id: String) async throws {
        try await ensureOpen()
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sql = "DELETE FROM assistant_web_memory WHERE mem_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare delete")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step delete")
        }
        var prefs = loadEntryPreferences()
        prefs.removeValue(forKey: trimmed)
        saveEntryPreferences(prefs)
    }

    func setEntryPinned(id: String, pinned: Bool) async {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var prefs = loadEntryPreferences()
        var pref = prefs[trimmed] ?? EntryPreference(isPinned: false, isIncludedInContext: true)
        pref.isPinned = pinned
        prefs[trimmed] = pref
        saveEntryPreferences(prefs)
    }

    func setEntryIncludedInContext(id: String, included: Bool) async {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var prefs = loadEntryPreferences()
        var pref = prefs[trimmed] ?? EntryPreference(isPinned: false, isIncludedInContext: true)
        pref.isIncludedInContext = included
        prefs[trimmed] = pref
        saveEntryPreferences(prefs)
    }

    func saveAcceptedWebAnswer(
        cacheKey: String,
        query: String,
        role: String,
        universityName: String?,
        answer: String,
        sourcesJSON: String
    ) async throws {
        try await ensureOpen()
        let trimmedKey = cacheKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        let sql = """
        INSERT OR REPLACE INTO assistant_web_answer_cache(
          cache_key, query, role, university_name, answer, sources_json, created_at
        ) VALUES(?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare accepted insert")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, trimmedKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, role, -1, SQLITE_TRANSIENT)
        if let universityName {
            sqlite3_bind_text(stmt, 4, universityName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, answer, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, sourcesJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 7, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step accepted insert")
        }
        try await pruneAcceptedAnswersIfNeeded()
    }

    func lookupAcceptedWebAnswer(cacheKey: String, maxAgeDays: Int = 14) async throws -> AcceptedWebAnswer? {
        try await ensureOpen()
        let trimmedKey = cacheKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        let minCreated = Date().addingTimeInterval(TimeInterval(-86400 * max(1, maxAgeDays))).timeIntervalSince1970
        let sql = """
        SELECT cache_key, query, role, university_name, answer, sources_json, created_at
        FROM assistant_web_answer_cache
        WHERE cache_key = ? AND created_at >= ?
        LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare accepted lookup")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, trimmedKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, minCreated)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let key = nonNullSQLiteText(stmt, 0)
        let query = nonNullSQLiteText(stmt, 1)
        let role = nonNullSQLiteText(stmt, 2)
        let universityName = optionalSQLiteText(stmt, 3)
        let answer = nonNullSQLiteText(stmt, 4)
        let sources = nonNullSQLiteText(stmt, 5)
        let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        return AcceptedWebAnswer(
            cacheKey: key,
            query: query,
            role: role,
            universityName: universityName,
            answer: answer,
            sourcesJSON: sources,
            createdAt: created
        )
    }

    // MARK: - Internals

    private func loadEntryPreferences() -> [String: EntryPreference] {
        guard let raw = UserDefaults.standard.string(forKey: entryPrefsDefaultsKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: EntryPreference].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveEntryPreferences(_ prefs: [String: EntryPreference]) {
        guard let data = try? JSONEncoder().encode(prefs),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(raw, forKey: entryPrefsDefaultsKey)
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
        let ddl = """
        CREATE VIRTUAL TABLE IF NOT EXISTS assistant_web_memory USING fts5(
            mem_id UNINDEXED,
            title,
            body,
            tags UNINDEXED,
            urls_json UNINDEXED,
            created_at UNINDEXED,
            embedding UNINDEXED,
            tokenize = 'porter unicode61'
        );
        """
        guard sqlite3_exec(db, ddl, nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "migration fts")
        }
        let acceptedDDL = """
        CREATE TABLE IF NOT EXISTS assistant_web_answer_cache (
            cache_key TEXT PRIMARY KEY,
            query TEXT NOT NULL,
            role TEXT NOT NULL,
            university_name TEXT,
            answer TEXT NOT NULL,
            sources_json TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """
        guard sqlite3_exec(db, acceptedDDL, nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "migration accepted")
        }
    }

    private func pruneIfNeeded() async throws {
        let c = try await count()
        guard c > Self.retentionHighWaterMark else { return }
        let drop = c - Self.retentionTargetCount
        guard drop > 0 else { return }
        let sql = """
        DELETE FROM assistant_web_memory WHERE rowid IN (
          SELECT rowid FROM assistant_web_memory ORDER BY CAST(created_at AS REAL) ASC LIMIT ?
        );
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare prune")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(drop))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step prune")
        }
    }

    private func pruneAcceptedAnswersIfNeeded() async throws {
        try await ensureOpen()
        var countStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM assistant_web_answer_cache;", -1, &countStmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare accepted count")
        }
        defer { sqlite3_finalize(countStmt) }
        guard sqlite3_step(countStmt) == SQLITE_ROW else { return }
        let c = Int(sqlite3_column_int(countStmt, 0))
        guard c > Self.acceptedAnswerHighWaterMark else { return }
        let drop = c - Self.acceptedAnswerTargetCount
        guard drop > 0 else { return }
        let sql = """
        DELETE FROM assistant_web_answer_cache WHERE cache_key IN (
          SELECT cache_key FROM assistant_web_answer_cache ORDER BY created_at ASC LIMIT ?
        );
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Self.dbError(db, "prepare accepted prune")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(drop))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw Self.dbError(db, "step accepted prune")
        }
    }

    private static func dbError(_ db: OpaquePointer?, _ ctx: String) -> NSError {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error"
        return NSError(domain: "AssistantWebMemoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(ctx): \(msg)"])
    }

    /// FTS5 `MATCH` clause using high-signal tokens only.
    /// Stop words are removed before BM25 prefetch so common terms do not crowd out relevant rows.
    static func sanitizedFtsMatch(_ raw: String) -> String {
        let tokens = raw.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 && !ftsStopWords.contains($0) }
            .prefix(12)
        guard !tokens.isEmpty else { return "" }
        return tokens.map { tok in
            let esc = tok.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(esc)\""
        }.joined(separator: " OR ")
    }

    private static let ftsStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "could",
        "did", "do", "does", "for", "from", "had", "has", "have", "how", "if",
        "in", "into", "is", "it", "me", "my", "of", "on", "or", "our", "should",
        "so", "that", "the", "their", "then", "there", "this", "to", "was", "we",
        "were", "what", "when", "where", "which", "who", "why", "will", "with",
        "would", "you", "your"
    ]

    #if DEBUG
    /// Test helper: wipe all rows (rebuild FTS table).
    func resetForTesting() async throws {
        try await ensureOpen()
        guard sqlite3_exec(db, "DELETE FROM assistant_web_memory;", nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "delete all")
        }
        guard sqlite3_exec(db, "DELETE FROM assistant_web_answer_cache;", nil, nil, nil) == SQLITE_OK else {
            throw Self.dbError(db, "delete accepted")
        }
        UserDefaults.standard.removeObject(forKey: entryPrefsDefaultsKey)
    }
    #endif
}

extension AssistantWebMemoryStore.Row {
    func strippingEmbeddingBlob() -> AssistantWebMemoryStore.Row {
        AssistantWebMemoryStore.Row(
            id: id,
            createdAt: createdAt,
            title: title,
            body: body,
            urlsJSON: urlsJSON,
            tags: tags,
            embedding: nil
        )
    }
}
