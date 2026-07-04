// JobBoardCompaniesStore.swift
// Feature: Career
// Purpose: Career module — JobBoardCompaniesStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

/// Persists configured job-board companies for in-app scraping.
@Observable
@MainActor
final class JobBoardCompaniesStore {
    static let shared = JobBoardCompaniesStore()

    private static let storageKey = "workday.companies.v1"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private(set) var companies: [JobBoardCompany] = []

    var enabledCompanies: [JobBoardCompany] {
        companies.filter(\.enabled)
    }

    var enabledCount: Int { enabledCompanies.count }

    private init() {
        loadFromUserDefaults()
    }

    func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            companies = []
            return
        }
        let sanitized = Self.sanitizedCompanyData(data)
        guard let decoded = try? decoder.decode([JobBoardCompany].self, from: sanitized) else {
            companies = []
            return
        }
        companies = decoded
        if sanitized != data {
            persistToUserDefaults()
        }
    }

    /// Strips tracked sources for platforms removed from the app (e.g. retired scrapers).
    private static func sanitizedCompanyData(_ data: Data) -> Data {
        guard
            var rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return data }
        let before = rows.count
        rows.removeAll { ($0["platform"] as? String) == "wellfound" }
        guard rows.count != before else { return data }
        return (try? JSONSerialization.data(withJSONObject: rows)) ?? data
    }

    private func persistToUserDefaults() {
        guard let data = try? JSONEncoder().encode(companies) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func addCompany(
        displayName: String,
        careersURL: String,
        slug: String? = nil,
        platform: JobBoardPlatform = .workday
    ) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = normalizedCareersURL(careersURL)
        let resolvedSlug = (slug?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? slug!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            : Self.slugify(name)
        let entry = JobBoardCompany(
            slug: resolvedSlug,
            displayName: name.isEmpty ? resolvedSlug : name,
            careersURL: url,
            enabled: true,
            platform: platform
        )
        companies.append(entry)
        persistToUserDefaults()
    }

    func removeCompany(id: UUID) {
        companies.removeAll { $0.id == id }
        persistToUserDefaults()
    }

    func updateCompany(_ entry: JobBoardCompany) {
        guard let index = companies.firstIndex(where: { $0.id == entry.id }) else { return }
        var normalized = entry
        normalized.careersURL = normalizedCareersURL(entry.careersURL)
        companies[index] = normalized
        persistToUserDefaults()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = companies.firstIndex(where: { $0.id == id }) else { return }
        companies[index].enabled = enabled
        persistToUserDefaults()
    }

    static func slugify(_ displayName: String) -> String {
        let lowered = displayName.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func normalizedCareersURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if JobBoardPlatformDetector.detect(from: trimmed) == .workday {
            return WorkdayScraper.normalizeCareersURLString(trimmed)
        }
        return trimmed
    }
}
