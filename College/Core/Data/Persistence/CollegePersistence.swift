// CollegePersistence.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogImportPolicy.
// Data: CollegePersistence / repositories when applicable.

import Combine
import Foundation
import SwiftData

@MainActor
final class CollegePersistence: ObservableObject {
    static let shared = CollegePersistence()

    let appDataStore: AppDataStore

    @Published private(set) var isStoreLoaded = false
    @Published var plans: [PlannerPlan] = []
    @Published var semesters: [PlannerSemester] = []
    @Published var profile: Profile?
    @Published var academicProfiles: [AcademicProfile] = []
    @Published var vaultDocuments: [VaultDocument] = []
    @Published private(set) var profileRevision: Int = 0
    @Published private(set) var catalogDataRevision: Int = 0
    @Published private(set) var calendarDidChangeToken: Int = 0
    @Published var careerDidChangeToken: Int = 0
    @Published var vaultDidChangeToken: Int = 0
    @Published private(set) var plannerChangeToken: Int = 0
    @Published var calendarSelectedSemesterID: UUID?
    @Published var activePlanID: UUID?

    var profileContext: ModelContext { appDataStore.profileContext }

    private init(appDataStore: AppDataStore = .shared) {
        self.appDataStore = appDataStore
        finishStoreLoad()
    }

    func finishStoreLoad() {
        refreshAll()
        isStoreLoaded = true
    }

    func refreshAll() {
        let repo = profileRepository
        plans = (try? repo.fetchPlans(limit: 100)) ?? []
        semesters = (try? repo.fetchSemesters(limit: 200)) ?? []
        profile = try? repo.fetchPrimaryProfile()
        academicProfiles = (try? repo.fetchAcademicProfiles()) ?? []
        vaultDocuments = (try? vaultRepository.fetchDocuments(limit: 5000)) ?? []
    }

    var profileRepository: ProfileRepository {
        ProfileRepository(context: profileContext)
    }

    var calendarRepository: CalendarRepository {
        CalendarRepository(context: profileContext)
    }

    var vaultRepository: VaultRepository {
        VaultRepository(context: profileContext)
    }

    var careerRepository: CareerRepository {
        CareerRepository(context: profileContext)
    }

    var catalogRepository: CatalogRepository? {
        appDataStore.catalogRepository
    }

    func bumpProfileRevision() {
        profileRevision &+= 1
        plannerChangeToken &+= 1
        objectWillChange.send()
    }

    func bumpCatalogDataRevision() {
        catalogDataRevision &+= 1
        appDataStore.bumpCatalogDataRevision()
    }

    func bumpCareerRevision() {
        careerDidChangeToken &+= 1
        objectWillChange.send()
    }

    func bumpVaultRevision() {
        vaultDidChangeToken &+= 1
        objectWillChange.send()
    }

    // MARK: - Profile / planner reads

    func fetchPlans() { plans = (try? profileRepository.fetchPlans(limit: 100)) ?? [] }
    func fetchSemesters() { semesters = (try? profileRepository.fetchSemesters(limit: 200)) ?? [] }
    func fetchProfile() { profile = try? profileRepository.fetchPrimaryProfile() }
    func fetchAcademicProfiles() { academicProfiles = (try? profileRepository.fetchAcademicProfiles()) ?? [] }
    func fetchVaultDocuments() { vaultDocuments = (try? vaultRepository.fetchDocuments(limit: 5000)) ?? [] }

    func semester(with id: UUID) -> PlannerSemester? {
        try? profileRepository.fetchSemester(id: id)
    }

    func getActivePlan() -> PlannerPlan? {
        if let activePlanID, let plan = try? profileRepository.fetchPlan(id: activePlanID) {
            return plan
        }
        return plans.last
    }

    func setActivePlan(_ plan: PlannerPlan?) {
        activePlanID = plan?.id
    }

    @discardableResult
    func addPlan(name: String, type: String, major: String, minor: String, concentration: String) -> PlannerPlan {
        let plan = (try? profileRepository.createPlan(
            name: name,
            type: type,
            major: major,
            minor: minor,
            concentration: concentration
        )) ?? PlannerPlan(name: name, type: type, major: major, minor: minor, concentration: concentration)
        fetchPlans()
        bumpProfileRevision()
        return plan
    }

    @discardableResult
    func addSemester(to plan: PlannerPlan, name: String, year: Int, season: String) -> PlannerSemester {
        let order = profileRepository.seasonOrder(for: season)
        let semester = (try? profileRepository.createSemester(
            plan: plan,
            name: name,
            year: year,
            season: season,
            seasonOrder: order
        )) ?? PlannerSemester(name: name, year: Int16(year), season: season, seasonOrder: order)
        fetchSemesters()
        bumpProfileRevision()
        return semester
    }

    func save() {
        _ = try? appDataStore.profileSave()
        refreshAll()
    }

    func saveAsync() { save() }

    // MARK: - Catalog active university

    @discardableResult
    func setActiveUniversity(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let repo = catalogRepository else {
            return false
        }
        do {
            if let university = try repo.fetchUniversity(named: trimmed) {
                try repo.activateUniversity(id: university.id, name: trimmed)
                try appDataStore.catalogSave()
                AppDataStoreBridge.syncActiveCatalogSchool(universityName: trimmed)
                bumpCatalogDataRevision()
                return true
            }
        } catch {
            AppLogger.shared.error("setActiveUniversity: \(error)")
        }
        return false
    }

    func getActiveUniversity() -> University? {
        try? catalogRepository?.fetchActiveUniversity()
    }

    func getActiveUniversityName() -> String? {
        getActiveUniversity()?.name
    }

    func getCatalogCourse(code: String) -> CourseCatalog? {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return nil }
        return try? repo.fetchCatalogCourse(universityID: university.id, code: code)
    }

    func getCatalogCourseMatching(code raw: String) -> CourseCatalog? {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return nil }
        return try? repo.fetchCatalogCourseMatching(universityID: university.id, code: raw)
    }

    func bumpCalendarChangeToken() {
        calendarDidChangeToken &+= 1
    }

    func taskExists(brightspaceItemId: String) -> Bool {
        (try? calendarRepository.taskExists(brightspaceItemId: brightspaceItemId)) == true
    }

    // MARK: - Calendar helpers

    func calendarEventEntity(id: UUID) -> CalendarEvent? {
        try? calendarRepository.fetchCalendarEvent(id: id)
    }

    // MARK: - Catalog import

    struct CatalogImportPolicy: Sendable {
        let archiveMissingCourses: Bool
        static let fullSnapshot = CatalogImportPolicy(archiveMissingCourses: true)
        static let preserveExistingCourses = CatalogImportPolicy(archiveMissingCourses: false)
    }

    func importSchoolCatalog(
        _ schoolProfile: SchoolProfile,
        policy: CatalogImportPolicy = .fullSnapshot
    ) async throws {
        let swiftPolicy = CatalogSchoolImportService.ImportPolicy(
            archiveMissingCourses: policy.archiveMissingCourses
        )
        try await CatalogSchoolImportService.importSchoolCatalog(schoolProfile, policy: swiftPolicy)
        refreshAll()
        bumpCatalogDataRevision()
    }

    // MARK: - Identity helpers (local store)

    func resolvedMajorNames() -> [String] {
        guard let primary = academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first else {
            return []
        }
        return AcademicProfileProgramLists.majors(from: primary)
    }

    func resolvedMinorNames() -> [String] {
        guard let primary = academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first else {
            return []
        }
        return AcademicProfileProgramLists.minors(from: primary)
    }

    func primaryDegreeLevel(default defaultValue: String = "") -> String {
        let level = (academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first)?
            .degreeLevel?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return level.isEmpty ? defaultValue : level
    }
}
