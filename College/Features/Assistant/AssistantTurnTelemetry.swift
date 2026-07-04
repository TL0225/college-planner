// AssistantTurnTelemetry.swift
// Feature: Assistant
// Purpose: Per-turn routing and outcome metrics (local, testable).

import Foundation

enum AssistantTurnPath: String, Codable, Sendable {
    case deterministic
    case guided
    case llmPreferred
    case toolLoop
}

struct AssistantTurnTelemetryRecord: Codable, Sendable, Equatable {
    let intent: String?
    let path: AssistantTurnPath
    let latencyMS: Int
    let personalizationEligible: Bool?
    let fallbackKind: String?
    let toolHopCount: Int
    let timestamp: Date
}

enum AssistantTurnTelemetry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var records: [AssistantTurnTelemetryRecord] = []
    nonisolated(unsafe) private static var counters: [String: Int] = [:]

    static let maxRecords = 200

    static func record(_ record: AssistantTurnTelemetryRecord) {
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        let key = "path.\(record.path.rawValue)"
        counters[key, default: 0] += 1
        if let intent = record.intent {
            counters["intent.\(intent)", default: 0] += 1
        }
        if let fallback = record.fallbackKind {
            counters["fallback.\(fallback)", default: 0] += 1
        }
#if DEBUG
        DebugLogger.shared.log(
            "AssistantTurnTelemetry path=\(record.path.rawValue) intent=\(record.intent ?? "nil") ms=\(record.latencyMS) hops=\(record.toolHopCount)",
            category: .intelligence,
            level: .trace
        )
#endif
    }

    static func recentRecords(limit: Int = 50) -> [AssistantTurnTelemetryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records.suffix(max(1, limit)))
    }

    static func counter(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counters[key] ?? 0
    }

    static func rawDeterministicDumpCount() -> Int {
        counter("fallback.raw_program_dump")
    }

#if DEBUG
    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        records = []
        counters = [:]
    }
#endif
}
