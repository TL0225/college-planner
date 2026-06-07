// WorkdayCompaniesStore.swift
// Feature: Career
// Purpose: Career module — WorkdayCompaniesStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

/// Persists Workday company list for in-app scraping.
@Observable
@MainActor
final class WorkdayCompaniesStore {
    static let shared = WorkdayCompaniesStore()

    private static let storageKey = "workday.companies.v1"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private(set) var companies: [WorkdayCompanyConfigEntry] = []

    var enabledCompanies: [WorkdayCompanyConfigEntry] {
        companies.filter(\.enabled)
    }

    var enabledCount: Int { enabledCompanies.count }

    private init() {
        loadFromUserDefaults()
    }

    func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? decoder.decode([WorkdayCompanyConfigEntry].self, from: data)
        else {
            companies = []
            return
        }
        companies = decoded
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
        let entry = WorkdayCompanyConfigEntry(
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

    func updateCompany(_ entry: WorkdayCompanyConfigEntry) {
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
