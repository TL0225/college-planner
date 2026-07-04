// DiagnosticsEventStore.swift
// Feature: Debug
// Purpose: Structured SQLite timeline of notable diagnostic events.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DiagnosticsEventSeverity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case error
    case critical
}

enum DiagnosticsEventSubsystem: String, Codable, Sendable, CaseIterable {
    case catalog
    case model
    case sync
    case memory
    case crash
    case launch
    case metrickit
    case assistant
    case runtime
    case app
}

struct DiagnosticsEventRecord: Sendable, Identifiable, Equatable {
    let id: Int64
    let timestamp: Date
    let sessionID: String
    let correlationID: String?
    let subsystem: DiagnosticsEventSubsystem
    let severity: DiagnosticsEventSeverity
    let category: String?
    let code: String?
    let message: String
}

struct DiagnosticsEventEmitRequest: Sendable {
    let subsystem: DiagnosticsEventSubsystem
    let severity: DiagnosticsEventSeverity
    let category: String?
    let code: String?
    let message: String
    let correlationID: String?
    let sessionID: String
    let timestamp: Date
}

enum DiagnosticsEvent {
    /// Fire-and-forget emit for notable events only (not high-frequency telemetry).
    nonisolated static func emit(
        subsystem: DiagnosticsEventSubsystem,
        severity: DiagnosticsEventSeverity,
        code: String,
        message: String,
        category: String? = nil,
        correlationID: String? = nil
    ) {
        let request = DiagnosticsEventEmitRequest(
            subsystem: subsystem,
            severity: severity,
            category: category,
            code: code,
            message: message,
            correlationID: correlationID ?? DiagnosticsSession.currentCorrelationID(),
            sessionID: DiagnosticsSession.sessionID,
            timestamp: Date()
        )
        Task { await DiagnosticsEventStore.shared.enqueue(request) }
    }
}

actor DiagnosticsEventStore {
    static let shared = DiagnosticsEventStore()

    private static let maxRows = 10_000
    private static let maxAgeDays = 30
    private static let batchSize = 32
    private static let flushIntervalSeconds: TimeInterval = 1.0
    private static let dedupeWindowSeconds: TimeInterval = 5.0

    private var db: OpaquePointer?
    private var insertStmt: OpaquePointer?
    private var pending: [DiagnosticsEventEmitRequest] = []
    private var flushTask: Task<Void, Never>?
    private var isOpen = false
    private var recentDedupe: [String: Date] = [:]

    private init() {}

    func openIfNeeded() async {
        guard !isOpen else { return }
        guard let path = DiagnosticsArtifacts.eventStoreURL(create: true)?.path else { return }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let db = handle else {
            return
        }
        self.db = db
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        guard await createSchema() else { return }
        guard await prepareInsertStatement() else { return }
        isOpen = true
        schedulePrune()
    }

    func enqueue(_ request: DiagnosticsEventEmitRequest) async {
        if !isOpen { await openIfNeeded() }
        guard isOpen else { return }

        if let code = request.code, shouldDedupe(code: code, subsystem: request.subsystem) {
            return
        }

        pending.append(request)
        if pending.count >= Self.batchSize {
            await flushPending()
        } else {
            scheduleFlush()
        }
    }

    func flushPending() async {
        guard isOpen, let db, let stmt = insertStmt, !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        for row in batch {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_double(stmt, 1, row.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, row.sessionID, -1, SQLITE_TRANSIENT)
            if let correlation = row.correlationID {
                sqlite3_bind_text(stmt, 3, correlation, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, row.subsystem.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, row.severity.rawValue, -1, SQLITE_TRANSIENT)
            if let category = row.category {
                sqlite3_bind_text(stmt, 6, category, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let code = row.code {
                sqlite3_bind_text(stmt, 7, code, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_text(stmt, 8, row.message, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    func fetchRecent(
        limit: Int = 200,
        since: Date? = nil,
        subsystem: DiagnosticsEventSubsystem? = nil,
        sessionID: String? = nil,
        correlationID: String? = nil,
        minSeverity: DiagnosticsEventSeverity? = nil
    ) async -> [DiagnosticsEventRecord] {
        if !isOpen { await openIfNeeded() }
        guard isOpen, let db else { return [] }

        var sql = """
        SELECT id, timestamp, session_id, correlation_id, subsystem, severity, category, code, message
        FROM diagnostics_events WHERE 1=1
        """
        var binds: [String] = []
        if since != nil { sql += " AND timestamp >= ?" }
        if subsystem != nil { sql += " AND subsystem = ?" }
        if sessionID != nil { sql += " AND session_id = ?" }
        if correlationID != nil { sql += " AND correlation_id = ?" }
        if minSeverity != nil { sql += " AND severity IN ('warning','error','critical')" }
        sql += " ORDER BY timestamp DESC LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var index: Int32 = 1
        if let since {
            sqlite3_bind_double(stmt, index, since.timeIntervalSince1970)
            index += 1
        }
        if let subsystem {
            binds.append(subsystem.rawValue)
            sqlite3_bind_text(stmt, index, subsystem.rawValue, -1, SQLITE_TRANSIENT)
            index += 1
        }
        if let sessionID {
            sqlite3_bind_text(stmt, index, sessionID, -1, SQLITE_TRANSIENT)
            index += 1
        }
        if let correlationID {
            sqlite3_bind_text(stmt, index, correlationID, -1, SQLITE_TRANSIENT)
            index += 1
        }
        sqlite3_bind_int(stmt, index, Int32(limit))

        var results: [DiagnosticsEventRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let sid = String(cString: sqlite3_column_text(stmt, 2))
            let corr = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 3)) : nil
            let subRaw = String(cString: sqlite3_column_text(stmt, 4))
            let sevRaw = String(cString: sqlite3_column_text(stmt, 5))
            let category = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 6)) : nil
            let code = sqlite3_column_type(stmt, 7) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 7)) : nil
            let message = String(cString: sqlite3_column_text(stmt, 8))
            guard let sub = DiagnosticsEventSubsystem(rawValue: subRaw),
                  let sev = DiagnosticsEventSeverity(rawValue: sevRaw) else { continue }
            results.append(DiagnosticsEventRecord(
                id: id,
                timestamp: ts,
                sessionID: sid,
                correlationID: corr,
                subsystem: sub,
                severity: sev,
                category: category,
                code: code,
                message: message
            ))
        }
        _ = binds
        return results
    }

    func countEvents(since: Date, severity: DiagnosticsEventSeverity? = nil) async -> Int {
        if !isOpen { await openIfNeeded() }
        guard isOpen, let db else { return 0 }
        var sql = "SELECT COUNT(*) FROM diagnostics_events WHERE timestamp >= ?"
        if severity != nil { sql += " AND severity = ?" }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
        if let severity {
            sqlite3_bind_text(stmt, 2, severity.rawValue, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    func distinctCorrelationThreads(since: Date, limit: Int = 50) async -> [[DiagnosticsEventRecord]] {
        let events = await fetchRecent(limit: 500, since: since)
        let grouped = Dictionary(grouping: events.filter { $0.correlationID != nil }) {
            $0.correlationID!
        }
        return grouped.values
            .sorted { ($0.first?.timestamp ?? .distantPast) > ($1.first?.timestamp ?? .distantPast) }
            .prefix(limit)
            .map { $0.sorted { $0.timestamp < $1.timestamp } }
    }

    func databaseURL() -> URL? {
        DiagnosticsArtifacts.eventStoreURL()
    }

    // MARK: - Private

    private func createSchema() async -> Bool {
        guard let db else { return false }
        let sql = """
        CREATE TABLE IF NOT EXISTS diagnostics_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            session_id TEXT NOT NULL,
            correlation_id TEXT,
            subsystem TEXT NOT NULL,
            severity TEXT NOT NULL,
            category TEXT,
            code TEXT,
            message TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_events_session ON diagnostics_events(session_id);
        CREATE INDEX IF NOT EXISTS idx_events_correlation ON diagnostics_events(correlation_id);
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON diagnostics_events(timestamp);
        """
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func prepareInsertStatement() async -> Bool {
        guard let db else { return false }
        let sql = """
        INSERT INTO diagnostics_events(
          timestamp, session_id, correlation_id, subsystem, severity, category, code, message
        ) VALUES (?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        insertStmt = stmt
        return true
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: .seconds(Self.flushIntervalSeconds))
            await self.flushPending()
            self.flushTask = nil
        }
    }

    private func schedulePrune() {
        Task.detached(priority: .utility) {
            await self.pruneIfNeeded()
        }
    }

    private func pruneIfNeeded() async {
        guard let db else { return }
        let cutoff = Date().addingTimeInterval(-Double(Self.maxAgeDays) * 86_400)
        let deleteOld = "DELETE FROM diagnostics_events WHERE timestamp < ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteOld, -1, &stmt, nil) == SQLITE_OK, let stmt {
            sqlite3_bind_double(stmt, 1, cutoff.timeIntervalSince1970)
            _ = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        let countSQL = "SELECT COUNT(*) FROM diagnostics_events;"
        var countStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK, let countStmt else { return }
        defer { sqlite3_finalize(countStmt) }
        guard sqlite3_step(countStmt) == SQLITE_ROW else { return }
        let count = Int(sqlite3_column_int(countStmt, 0))
        guard count > Self.maxRows else { return }

        let excess = count - Self.maxRows
        let trimSQL = """
        DELETE FROM diagnostics_events WHERE id IN (
          SELECT id FROM diagnostics_events ORDER BY timestamp ASC LIMIT ?
        );
        """
        var trimStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, trimSQL, -1, &trimStmt, nil) == SQLITE_OK, let trimStmt {
            sqlite3_bind_int(trimStmt, 1, Int32(excess))
            _ = sqlite3_step(trimStmt)
            sqlite3_finalize(trimStmt)
        }
    }

    private func shouldDedupe(code: String, subsystem: DiagnosticsEventSubsystem) -> Bool {
        let key = "\(subsystem.rawValue)|\(code)"
        let now = Date()
        if let last = recentDedupe[key], now.timeIntervalSince(last) < Self.dedupeWindowSeconds {
            return true
        }
        recentDedupe[key] = now
        if recentDedupe.count > 200 {
            recentDedupe = recentDedupe.filter { now.timeIntervalSince($0.value) < 60 }
        }
        return false
    }
}
