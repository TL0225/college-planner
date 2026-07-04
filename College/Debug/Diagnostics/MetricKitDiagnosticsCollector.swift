// MetricKitDiagnosticsCollector.swift
// Feature: Debug
// Purpose: Ingest Apple MetricKit diagnostic and metric payloads into the event store.

import Foundation
import MetricKit

final class MetricKitDiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitDiagnosticsCollector()

    private override init() {
        super.init()
    }

    func registerIfNeeded() {
        MXMetricManager.shared.add(self)
    }

    func unregister() {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let normalized = payloads.map { Self.normalizeDiagnosticPayload($0) }
        let rawDescriptions = payloads.map { String(describing: $0) }
        Task { @Sendable in
            await DiagnosticsEventStore.shared.openIfNeeded()
            for item in normalized {
                await DiagnosticsEventStore.shared.enqueue(item)
            }
            for description in rawDescriptions {
                await Self.persistRawDescription(description, prefix: "diagnostic")
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let rawDescriptions = payloads.map { String(describing: $0) }
        Task { @Sendable in
            await DiagnosticsEventStore.shared.openIfNeeded()
            if !rawDescriptions.isEmpty {
                DiagnosticsEvent.emit(
                    subsystem: .metrickit,
                    severity: .info,
                    code: "METRICKIT_METRICS",
                    message: "Daily performance metrics received from Apple."
                )
            }
            for description in rawDescriptions {
                await Self.persistRawDescription(description, prefix: "metrics")
            }
        }
    }

    private static func normalizeDiagnosticPayload(_ payload: MXDiagnosticPayload) -> DiagnosticsEventEmitRequest {
        var code = "METRICKIT_DIAGNOSTIC"
        var message = "Apple delivered a diagnostic report."
        var severity = DiagnosticsEventSeverity.warning

        if let crashes = payload.crashDiagnostics, let crash = crashes.first {
            code = "METRICKIT_CRASH"
            message = crash.terminationReason ?? "Apple reported a crash."
            severity = .critical
        } else if let hangs = payload.hangDiagnostics, let hang = hangs.first {
            code = "METRICKIT_HANG"
            message = "Apple reported the app was unresponsive for \(Int(hang.hangDuration.value)) seconds."
            severity = .warning
        } else if payload.cpuExceptionDiagnostics?.isEmpty == false {
            code = "METRICKIT_CPU"
            message = "Apple reported high CPU usage."
        } else if payload.diskWriteExceptionDiagnostics?.isEmpty == false {
            code = "METRICKIT_DISK"
            message = "Apple reported excessive disk writes."
        }

        return DiagnosticsEventEmitRequest(
            subsystem: .metrickit,
            severity: severity,
            category: "metrickit",
            code: code,
            message: message,
            correlationID: nil,
            sessionID: DiagnosticsSession.sessionID,
            timestamp: Date()
        )
    }

    private static func persistRawDescription(_ description: String, prefix: String) async {
        guard let dir = DiagnosticsArtifacts.metricKitPayloadsDirectory(create: true) else { return }
        let formatter = ISO8601DateFormatter()
        let name = "\(prefix)_\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")).json"
        let url = dir.appendingPathComponent(name)
        if let data = try? JSONSerialization.data(withJSONObject: ["payload": description], options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
