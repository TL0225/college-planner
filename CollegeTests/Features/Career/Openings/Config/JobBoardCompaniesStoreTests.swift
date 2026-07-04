// JobBoardCompaniesStoreTests.swift
// Feature: Career / Openings / Config

import Foundation
import Testing
@testable import College

@Suite("JobBoardCompaniesStoreTests")
@MainActor
struct JobBoardCompaniesStoreTests {
    private let storageKey = "workday.companies.v1"

    @Test("slugify normalizes punctuation and spacing")
    func slugify() {
        #expect(JobBoardCompaniesStore.slugify("City of New York!") == "city-of-new-york")
        #expect(JobBoardCompaniesStore.slugify("  USA Jobs  ") == "usa-jobs")
    }

    @Test("addCompany persists normalized entry")
    func addCompanyPersists() {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: storageKey)
        defer {
            defaults.set(original, forKey: storageKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
        }

        defaults.removeObject(forKey: storageKey)
        JobBoardCompaniesStore.shared.loadFromUserDefaults()

        JobBoardCompaniesStore.shared.addCompany(
            displayName: "NYC Jobs",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs
        )

        let company = try! #require(JobBoardCompaniesStore.shared.companies.first)
        #expect(company.displayName == "NYC Jobs")
        #expect(company.normalizedSlug == "nyc-jobs")
        #expect(company.platform == .nycCityJobs)
    }

    @Test("loadFromUserDefaults removes retired wellfound platform entries")
    func legacyWellfoundMigration() throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: storageKey)
        defer {
            defaults.set(original, forKey: storageKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
        }

        let legacy: [[String: Any]] = [
            [
                "id": UUID().uuidString,
                "slug": "wellfound-jobs",
                "displayName": "Wellfound",
                "careersURL": "https://wellfound.com/jobs",
                "enabled": true,
                "platform": "wellfound",
            ],
            [
                "id": UUID().uuidString,
                "slug": "city-jobs",
                "displayName": "City Jobs",
                "careersURL": "https://cityjobs.nyc.gov/jobs",
                "enabled": true,
                "platform": "nycCityJobs",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        defaults.set(data, forKey: storageKey)

        JobBoardCompaniesStore.shared.loadFromUserDefaults()
        #expect(JobBoardCompaniesStore.shared.companies.count == 1)
        #expect(JobBoardCompaniesStore.shared.companies.first?.platform == .nycCityJobs)
    }
}
