// DiagnosticsPlainLanguage.swift
// Feature: Debug
// Purpose: Human-readable summaries for diagnostic events and logs.

import Foundation
import SwiftUI

enum DiagnosticsPlainLanguage {
    static func summary(for record: DiagnosticsEventRecord) -> String {
        if let code = record.code, let mapped = codeSummaries[code] {
            return mapped
        }
        if !record.message.isEmpty { return record.message }
        return "Something happened in \(record.subsystem.rawValue)."
    }

    static func summary(for entry: AppLogger.Entry) -> String {
        let msg = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty { return "App activity recorded." }
        if msg.contains(".") {
            let parts = msg.split(separator: ".", maxSplits: 1).map(String.init)
            if parts.count == 2, let mapped = codeSummaries[parts[0]] {
                return mapped
            }
        }
        return friendlyLogLine(msg)
    }

    static func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func absoluteTimestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Relative timestamps stay precise for recent entries, but older entries
    /// switch to an absolute format ("Jun 11 at 2:34:07 PM") so they remain readable.
    static func smartTimestamp(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 86_400 {
            return relativeTimestamp(date)
        }
        return date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .second()
        )
    }

    static func severityLabel(_ severity: DiagnosticsEventSeverity) -> String {
        switch severity {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }

    static func severityColor(_ severity: DiagnosticsEventSeverity) -> Color {
        switch severity {
        case .info: return DesignSystem.Colors.info
        case .warning: return DesignSystem.Colors.warning
        case .error: return DesignSystem.Colors.error
        case .critical: return DesignSystem.Colors.error
        }
    }

    static func levelColor(_ level: AppLogger.Level) -> Color {
        switch level {
        case .trace, .info: return DesignSystem.Colors.info
        case .warning: return DesignSystem.Colors.warning
        case .error, .fault: return DesignSystem.Colors.error
        }
    }

    static func levelLabel(_ level: AppLogger.Level) -> String {
        switch level {
        case .trace: return "Trace"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .fault: return "Critical"
        }
    }

    private static let codeSummaries: [String: String] = [
        "CATALOG_IMPORT_STARTED": "Started updating your school's course catalog.",
        "CATALOG_IMPORT_FAILED": "Couldn't finish updating your school's course catalog.",
        "CATALOG_IMPORT_ABORTED": "Course catalog update was stopped.",
        "CATALOG_INTEGRITY_FAILED": "Course catalog data didn't pass integrity checks.",
        "MODEL_LOAD_STARTED": "Loading the on-device assistant model.",
        "MODEL_LOAD_FAILED": "The on-device assistant model couldn't load.",
        "MEMORY_PRESSURE_WARNING": "The app was low on memory and freed some resources.",
        "SYNC_TIMEOUT": "A background sync took too long and may have failed.",
        "CRASH_DETECTED": "The app crashed or stopped unexpectedly.",
        "LAUNCH_SLOW": "The app took longer than usual to start.",
        "LAUNCH_FAILED": "The app had trouble during startup.",
        "HANG_DETECTED": "The app became unresponsive for a while.",
        "METRICKIT_CRASH": "Apple reported a crash from a previous session.",
        "METRICKIT_HANG": "Apple reported the app was unresponsive.",
        "SESSION_ABRUPT_EXIT": "The previous session ended unexpectedly.",
    ]

    private static func friendlyLogLine(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " — ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
