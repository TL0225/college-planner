// JobBoardCompanyConfiguratorTests.swift
// Feature: Career / Openings / Config

import Foundation
import Testing
@testable import College

@Suite("JobBoardCompanyConfiguratorTests")
@MainActor
struct JobBoardCompanyConfiguratorTests {
    private let storageKey = "workday.companies.v1"

    @Test("configureIfNeeded creates company and returns created=true")
    func createsCompany() {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: storageKey)
        defer {
            defaults.set(original, forKey: storageKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
        }

        defaults.removeObject(forKey: storageKey)
        JobBoardCompaniesStore.shared.loadFromUserDefaults()

        let result = JobBoardCompanyConfigurator.configureIfNeeded(
            displayName: "USAJobs Federal",
            careersURL: "https://www.usajobs.gov/Search/Results",
            platform: .usajobs,
            enqueueScrape: false
        )

        #expect(result?.created == true)
        #expect(result?.company.platform == .usajobs)
        #expect(JobBoardCompaniesStore.shared.companies.count == 1)
    }

    @Test("configureIfNeeded dedupes by slug or URL")
    func dedupesExisting() {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: storageKey)
        defer {
            defaults.set(original, forKey: storageKey)
            JobBoardCompaniesStore.shared.loadFromUserDefaults()
        }

        defaults.removeObject(forKey: storageKey)
        JobBoardCompaniesStore.shared.loadFromUserDefaults()

        _ = JobBoardCompanyConfigurator.configureIfNeeded(
            displayName: "NYC Jobs",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs,
            enqueueScrape: false
        )
        let second = JobBoardCompanyConfigurator.configureIfNeeded(
            displayName: "NYC Jobs Duplicate",
            careersURL: "https://cityjobs.nyc.gov/jobs",
            platform: .nycCityJobs,
            enqueueScrape: false
        )

        #expect(second?.created == false)
        #expect(JobBoardCompaniesStore.shared.companies.count == 1)
    }
}
