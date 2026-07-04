// LoadOperationTrace.swift
// Feature: Core
// Purpose: Structured load-timing spans correlated with main-thread lag and memory deltas.

import Foundation

/// Where the measured work ran (declared by the call site; async hops may differ).
enum LoadExecutionContext: String, Sendable, Codable {
    case mainThread
    case background
}

enum LoadOperationCategory: String, Sendable, Codable {
    case launch
    case audit
    case catalog
    case career
    case calendar
    case assistant
    case backgroundService
    case shell
    case general
}

struct LoadOperationRecord: Sendable, Identifiable, Codable {
    let id: UUID
    let name: String
    let category: LoadOperationCategory
    let startedAt: Date
    let durationMs: Int
    let executionContext: LoadExecutionContext
    /// Peak main-thread ack lag sampled during the span (proxy for UI stalls).
    let peakMainThreadLagMs: Int
    let memoryDeltaMB: Double
    let footprintDeltaMB: Double
    let budgetMs: Int?
    let exceededBudget: Bool
    let succeeded: Bool
    let metadata: [String: String]

    var summaryLine: String {
        let budget = budgetMs.map { " / \($0)ms budget" } ?? ""
        let stall = peakMainThreadLagMs > 0 ? " · main lag peak \(peakMainThreadLagMs)ms" : ""
        let mem = abs(memoryDeltaMB) >= 0.5
            ? String(format: " · Δmem %+.1f MB", memoryDeltaMB)
            : ""
        let status = succeeded ? "" : " · failed"
        return "\(name) \(durationMs)ms\(budget)\(stall)\(mem)\(status)"
    }
}

actor LoadOperationRecorder {
    static let shared = LoadOperationRecorder()

    private var records: [LoadOperationRecord] = []
    private let limit = 80

    func append(_ record: LoadOperationRecord) {
        records.append(record)
        if records.count > limit {
            records.removeFirst(records.count - limit)
        }
    }

    func recent(limit: Int = 20) -> [LoadOperationRecord] {
        Array(records.suffix(max(0, limit)))
    }

    func clear() {
        records.removeAll()
    }

    func exportJSONLines() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return records.compactMap { record in
            guard let data = try? encoder.encode(record) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
    }
}

/// Wraps hot load paths with wall-clock timing, memory deltas, and main-thread stall sampling.
enum LoadOperationTrace {
    private static let samplerIntervalNs: UInt64 = 40_000_000

    static func recent(limit: Int = 20) async -> [LoadOperationRecord] {
        await LoadOperationRecorder.shared.recent(limit: limit)
    }

    /// Records a completed operation without wrapping (e.g. launch splash wall time measured elsewhere).
    static func recordCompleted(
        name: String,
        category: LoadOperationCategory,
        durationMs: Int,
        budgetMs: Int? = nil,
        executionContext: LoadExecutionContext = .mainThread,
        peakMainThreadLagMs: Int = 0,
        memoryDeltaMB: Double = 0,
        footprintDeltaMB: Double = 0,
        succeeded: Bool = true,
        metadata: [String: String] = [:]
    ) async {
        let exceeded = budgetMs.map { durationMs > $0 } ?? false
        let record = LoadOperationRecord(
            id: UUID(),
            name: name,
            category: category,
            startedAt: Date().addingTimeInterval(-Double(durationMs) / 1000),
            durationMs: durationMs,
            executionContext: executionContext,
            peakMainThreadLagMs: peakMainThreadLagMs,
            memoryDeltaMB: memoryDeltaMB,
            footprintDeltaMB: footprintDeltaMB,
            budgetMs: budgetMs,
            exceededBudget: exceeded,
            succeeded: succeeded,
            metadata: metadata
        )
        await LoadOperationRecorder.shared.append(record)
        logIfNeeded(record)
    }

    /// MainActor / non-Sendable workloads (audit rebuild, launch steps).
    static func withSpan<T>(
        name: String,
        category: LoadOperationCategory,
        budgetMs: Int? = nil,
        executionContext: LoadExecutionContext = .mainThread,
        metadata: [String: String] = [:],
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await runSpan(
            name: name,
            category: category,
            budgetMs: budgetMs,
            executionContext: executionContext,
            metadata: metadata,
            body: body
        )
    }

    private static func runSpan<T>(
        name: String,
        category: LoadOperationCategory,
        budgetMs: Int?,
        executionContext: LoadExecutionContext,
        metadata: [String: String],
        body: () async throws -> T
    ) async rethrows -> T {
        let startedAt = Date()
        let memStart = PerformanceDiagnostics.residentMemoryMB()
        let footprintStart = PerformanceDiagnostics.footprintMemoryMB()

        let sampler = Task.detached(priority: .utility) {
            var peakMs = 0
            while !Task.isCancelled {
                let lag = await RuntimeTelemetryMonitor.shared.mainThreadLagSeconds()
                peakMs = max(peakMs, Int((lag * 1000).rounded()))
                try? await Task.sleep(nanoseconds: samplerIntervalNs)
            }
            return peakMs
        }

        do {
            let result = try await body()
            sampler.cancel()
            let peakLagMs = await sampler.value
            await finish(
                name: name,
                category: category,
                startedAt: startedAt,
                memStart: memStart,
                footprintStart: footprintStart,
                executionContext: executionContext,
                peakMainThreadLagMs: peakLagMs,
                budgetMs: budgetMs,
                metadata: metadata,
                succeeded: true
            )
            return result
        } catch {
            sampler.cancel()
            let peakLagMs = await sampler.value
            await finish(
                name: name,
                category: category,
                startedAt: startedAt,
                memStart: memStart,
                footprintStart: footprintStart,
                executionContext: executionContext,
                peakMainThreadLagMs: peakLagMs,
                budgetMs: budgetMs,
                metadata: metadata,
                succeeded: false
            )
            throw error
        }
    }

    private static func finish(
        name: String,
        category: LoadOperationCategory,
        startedAt: Date,
        memStart: Double,
        footprintStart: Double,
        executionContext: LoadExecutionContext,
        peakMainThreadLagMs: Int,
        budgetMs: Int?,
        metadata: [String: String],
        succeeded: Bool
    ) async {
        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        let exceeded = budgetMs.map { durationMs > $0 } ?? false
        let record = LoadOperationRecord(
            id: UUID(),
            name: name,
            category: category,
            startedAt: startedAt,
            durationMs: durationMs,
            executionContext: executionContext,
            peakMainThreadLagMs: peakMainThreadLagMs,
            memoryDeltaMB: PerformanceDiagnostics.residentMemoryMB() - memStart,
            footprintDeltaMB: PerformanceDiagnostics.footprintMemoryMB() - footprintStart,
            budgetMs: budgetMs,
            exceededBudget: exceeded,
            succeeded: succeeded,
            metadata: metadata
        )
        await LoadOperationRecorder.shared.append(record)
        logIfNeeded(record)
    }

    private static func logIfNeeded(_ record: LoadOperationRecord) {
        var metadata: [String: String] = [
            "name": record.name,
            "category": record.category.rawValue,
            "duration_ms": "\(record.durationMs)",
            "execution": record.executionContext.rawValue,
            "peak_main_lag_ms": "\(record.peakMainThreadLagMs)",
            "memory_delta_mb": String(format: "%.1f", record.memoryDeltaMB),
            "footprint_delta_mb": String(format: "%.1f", record.footprintDeltaMB),
            "succeeded": record.succeeded ? "true" : "false"
        ]
        if let budgetMs = record.budgetMs {
            metadata["budget_ms"] = "\(budgetMs)"
            metadata["exceeded_budget"] = record.exceededBudget ? "true" : "false"
        }
        for (key, value) in record.metadata {
            metadata["meta.\(key)"] = value
        }

        let level: AppLogger.Level = record.exceededBudget || record.peakMainThreadLagMs >= 500
            ? .warning
            : .info
        AppLogger.shared.log(
            "load.operation.completed",
            level: level,
            category: .performance,
            metadata: metadata
        )

        if record.exceededBudget {
            DiagnosticsEvent.emit(
                subsystem: diagnosticsSubsystem(for: record.category),
                severity: .warning,
                code: "LOAD_SLOW",
                message: "\(record.name) took \(record.durationMs) ms (budget \(record.budgetMs ?? 0) ms)."
            )
        }

        if record.peakMainThreadLagMs >= RuntimeTelemetryMonitor.mainThreadStallThresholdMs {
            DiagnosticsEvent.emit(
                subsystem: .runtime,
                severity: .warning,
                code: "LOAD_MAIN_STALL",
                message: "\(record.name) overlapped main-thread lag up to \(record.peakMainThreadLagMs) ms."
            )
        }
    }

    private static func diagnosticsSubsystem(for category: LoadOperationCategory) -> DiagnosticsEventSubsystem {
        switch category {
        case .launch: return .launch
        case .catalog: return .catalog
        case .assistant: return .assistant
        case .audit, .career, .calendar, .backgroundService, .shell, .general:
            return .runtime
        }
    }
}
