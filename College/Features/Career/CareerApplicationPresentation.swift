// CareerApplicationPresentation.swift
// Feature: Career
// Purpose: Career module — CareerApplicationPresentation.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

enum CareerApplicationPresentation {
    static func status(for application: JobApplication) -> CareerApplicationStatus {
        CareerApplicationStatus(rawValue: application.statusRaw) ?? .interested
    }

    static func companyName(for application: JobApplication) -> String {
        (application.company?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown Company"
    }

    static func roleTitle(for application: JobApplication) -> String {
        (application.title?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Role"
    }

    static func locationLine(for application: JobApplication) -> String {
        (application.locationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func brandColor(for application: JobApplication) -> Color {
        CareerKanbanTheme.laneAccent(for: status(for: application))
    }

    static func companyInitials(_ company: String) -> String {
        let tokens = company
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let first = tokens.first else { return "?" }
        if tokens.count == 1 {
            return String(first.prefix(2)).uppercased()
        }
        let second = tokens[1]
        return String(first.prefix(1) + second.prefix(1)).uppercased()
    }

    static func keywords(from application: JobApplication, limit: Int) -> [String] {
        Array(keywordsAll(from: application).prefix(limit))
    }

    static func keywordsOverflowCount(from application: JobApplication, limit: Int) -> Int {
        max(0, keywordsAll(from: application).count - limit)
    }

    static func keywordsAll(from application: JobApplication) -> [String] {
        let raw = (application.extractedKeywordsJSON ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return normalizeKeywords(decoded)
        }

        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return normalizeKeywords(decoded.split(separator: ",").map(String.init))
        }

        return normalizeKeywords(raw.split(separator: ",").map(String.init))
    }

    static func formattedLastApplied(for application: JobApplication) -> String {
        let date = application.dateApplied ?? application.updatedAt
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func lastAppliedDate(for application: JobApplication) -> Date {
        application.dateApplied ?? application.updatedAt ?? .distantPast
    }

    static func priorityLabel(_ priority: CareerKanbanTheme.Priority) -> String {
        switch priority {
        case .high: return "High priority"
        case .medium: return "Medium priority"
        case .low: return "Low priority"
        }
    }

    static func prioritySubheadlineColor(_ priority: CareerKanbanTheme.Priority) -> Color {
        switch priority {
        case .high: return Color.red.opacity(0.85)
        case .medium: return Color(red: 0.62, green: 0.45, blue: 0.12)
        case .low: return Color.secondary
        }
    }

    private static func normalizeKeywords(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for token in raw {
            let trimmed = token
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }
}
