// CollegePersistence.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogImportPolicy.
// Data: CollegePersistence / repositories when applicable.

import Combine
import Foundation
import SwiftData

/// Legacy façade over repositories. **Phase 7:** Features should use `ProfileRepository`, `VaultRepository`, etc. directly — not `CollegePersistence.shared`.
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
    @Published var transferDidChangeToken: Int = 0
    @Published private(set) var plannerChangeToken: Int = 0
    @Published var calendarSelectedSemesterID: UUID?
    @Published var activePlanID: UUID?

    var profileContext: ModelContext { appDataStore.profileContext }

    /// In-flight paginated job-board imports keyed by company slug.
    var jobBoardListImportSessionStates: [String: JobBoardListImportSessionState] = [:]

    private init(appDataStore: AppDataStore = .shared) {
        self.appDataStore = appDataStore
        finishStoreLoad()
    }

    func finishStoreLoad() {
        refreshAll()
        // Skip destructive profile cleanup when the on-disk store could not be opened.
        if appDataStore.storeOpenError == nil {
            pruneDuplicateEmptyAcademicProfiles()
        }
        isStoreLoaded = true
    }

    func refreshProfileCaches() {
        SnowLeopardHealthMetrics.recordRefreshProfileCaches()
        let repo = profileRepository
        do { plans = try repo.fetchPlans(limit: 100) }
        catch { plans = []; AppLogger.shared.error("refreshProfileCaches fetchPlans failed: \(error)", category: .persistence) }
        do { semesters = try repo.fetchSemesters(limit: 200) }
        catch { semesters = []; AppLogger.shared.error("refreshProfileCaches fetchSemesters failed: \(error)", category: .persistence) }
        do { profile = try repo.fetchPrimaryProfile() }
        catch { profile = nil; AppLogger.shared.error("refreshProfileCaches fetchPrimaryProfile failed: \(error)", category: .persistence) }
        do { academicProfiles = try repo.fetchAcademicProfiles() }
        catch { academicProfiles = []; AppLogger.shared.error("refreshProfileCaches fetchAcademicProfiles failed: \(error)", category: .persistence) }
    }

    func refreshAll() {
        SnowLeopardHealthMetrics.recordRefreshAll()
        refreshProfileCaches()
        do { vaultDocuments = try vaultRepository.fetchDocuments(limit: 500) }
        catch { vaultDocuments = []; AppLogger.shared.error("refreshAll fetchDocuments failed: \(error)", category: .persistence) }
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
        appDataStore.bumpProfileRevisionLocally()
    }

    /// Called when `AppDataStore` saved or otherwise bumped profile data without going through persistence helpers.
    func applyProfileRevisionBumpFromAppDataStore() {
        profileRevision &+= 1
        plannerChangeToken &+= 1
        objectWillChange.send()
    }

    func bumpCatalogDataRevision() {
        catalogDataRevision &+= 1
        objectWillChange.send()
        appDataStore.bumpCatalogDataRevisionLocally()
    }

    /// Called when `AppDataStore` saved or otherwise bumped catalog data without going through persistence helpers.
    func applyCatalogDataRevisionBumpFromAppDataStore() {
        catalogDataRevision &+= 1
        objectWillChange.send()
    }

    func bumpCareerRevision() {
        careerDidChangeToken &+= 1
        objectWillChange.send()
    }

    func bumpVaultRevision() {
        vaultDidChangeToken &+= 1
        objectWillChange.send()
    }

    func bumpTransferRevision() {
        transferDidChangeToken &+= 1
        objectWillChange.send()
    }

    // MARK: - Profile / planner reads

    func fetchPlans() { plans = (try? profileRepository.fetchPlans(limit: 100)) ?? [] }
    func fetchSemesters() { semesters = (try? profileRepository.fetchSemesters(limit: 200)) ?? [] }
    func fetchProfile() { profile = try? profileRepository.fetchPrimaryProfile() }
    func fetchAcademicProfiles() { academicProfiles = (try? profileRepository.fetchAcademicProfiles()) ?? [] }
    func fetchVaultDocuments() { vaultDocuments = (try? vaultRepository.fetchDocuments(limit: 500)) ?? [] }

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
        refreshProfileCaches()
    }

    func saveAsync() { save() }

    // MARK: - Catalog active university

    @discardableResult
    func setActiveUniversity(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard CatalogStoreSnapshotBridge.attachUniversity(
            named: trimmed,
            appDataStore: appDataStore,
            activate: true
        ) != nil else {
            return false
        }
        AppDataStoreBridge.syncActiveCatalogSchool(universityName: trimmed)
        bumpCatalogDataRevision()
        return true
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

    func taskExists(lmsItemId: String) -> Bool {
        (try? calendarRepository.taskExists(lmsItemId: lmsItemId)) == true
    }

    // MARK: - Calendar helpers

    func calendarEventEntity(id: UUID) -> CalendarEvent? {
        try? calendarRepository.fetchCalendarEvent(id: id)
    }

    func calendarEventEntities(ids: [UUID]) -> [CalendarEvent] {
        (try? calendarRepository.fetchCalendarEvents(ids: ids)) ?? []
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
