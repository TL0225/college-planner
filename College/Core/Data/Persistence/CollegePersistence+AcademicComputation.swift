// CollegePersistence+AcademicComputation.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CompletionInfo.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7f: local store academic/catalog computation (replaces CollegePersistenceLegacy reads)

@MainActor
extension CollegePersistence {
    private static let schoolPoliciesDefaultsKey = "persistence.university.schoolPolicies.v1"
    private static let schoolPolicyMetadataDefaultsKey = "catalog.schoolPolicyMetadata"

    func isLetterGradedForGPA(_ gradingType: String?) -> Bool {
        AcademicProgramHelpers.isLetterGradedForGPA(gradingType)
    }

    func sapStats() -> (attempted: Int, completed: Int, rate: Double) {
        let all = semesters.flatMap(\.coursesArray)
        let completedCredits = all.filter(\.isCompleted).reduce(0) { $0 + Int($1.credits) }
        let attemptedStatuses: Set<String> = ["Completed", "Dropped", "Failed", "Transfer"]
        let attemptedCredits = all.filter { course in
            let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
            return attemptedStatuses.contains(status) || course.isCompleted
        }.reduce(0) { $0 + Int($1.credits) }
        let rate = attemptedCredits > 0 ? Double(completedCredits) / Double(attemptedCredits) : 1.0
        return (attemptedCredits, completedCredits, rate)
    }

    func reconcileDeclaredProgramDegreeMetadata() {
        guard let profile else { return }
        var didChange = false
        let university = profile.collegeName ?? getActiveUniversityName() ?? ""

        func catalogFallback(cleanedName: String) -> String? {
            guard !university.isEmpty else { return nil }
            return fetchDegreeType(for: cleanedName, universityName: university)
        }

        func applyInference(
            to entity: AcademicProfile,
            majors: [String],
            repairMajors: inout [String]
        ) {
            var workingMajors = majors
            if let repaired = repairMajorsIfNeeded(majors: &workingMajors, universityName: university) {
                repairMajors = repaired
                entity.majorsCSV = ProgramListSerialization.encode(repaired)
                entity.major = repaired.first
                entity.secondaryMajor = repaired.count > 1 ? repaired[1] : nil
                didChange = true
            }

            if let effective = DeclaredProgramDegreeMetadata.effectiveMetadata(
                majors: workingMajors,
                storedDegreeType: entity.degreeType,
                storedDegreeLevel: entity.degreeLevel,
                catalogFallback: catalogFallback
            ),
               DeclaredProgramDegreeMetadata.shouldUpdateStoredDegreeType(
                current: entity.degreeType,
                inferred: effective
               ) {
                entity.degreeType = effective.fullDegreeType
                entity.degreeLevel = effective.degreeLevel
                if entity.creditsRequired == 120,
                   !DegreeConfiguration.isUndergraduate(effective.degreeLevel) {
                    entity.creditsRequired = 0
                }
                didChange = true
            } else if let raw = entity.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                      let canonical = DegreeTypeNormalizer.normalize(raw),
                      canonical.fullLabel != nil,
                      entity.degreeType != canonical.fullLabel {
                entity.degreeType = canonical.fullLabel
                entity.degreeLevel = canonical.degreeLevel
                didChange = true
            }
        }

        for academicProfile in academicProfiles {
            var repair: [String] = []
            let majors = AcademicProfileProgramLists.majors(from: academicProfile)
            applyInference(to: academicProfile, majors: majors, repairMajors: &repair)
        }

        if didChange {
            _ = try? appDataStore.profileSave()
            fetchAcademicProfiles()
            bumpProfileRevision()
        }
    }

    private func repairMajorsIfNeeded(majors: inout [String], universityName: String) -> [String]? {
        guard !universityName.isEmpty else { return nil }
        var repaired: [String] = []
        var changed = false
        for major in majors {
            let trimmed = major.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if DeclaredProgramDegreeMetadata.infer(fromProgramDisplay: trimmed) != nil {
                repaired.append(trimmed)
                continue
            }
            let cleaned = AcademicProgramHelpers.cleanedProgramNameFromDisplay(trimmed)
            if let catalogType = fetchDegreeType(for: cleaned.isEmpty ? trimmed : cleaned, universityName: universityName),
               !catalogType.isEmpty {
                let label = ProgramListSerialization.displayLabel(
                    programName: cleaned.isEmpty ? trimmed : cleaned,
                    degreeType: catalogType
                )
                repaired.append(label)
                changed = true
            } else {
                repaired.append(trimmed)
            }
        }
        return changed ? repaired : nil
    }

    func fetchDegreeType(for cleanedName: String, universityName: String) -> String? {
        guard let university = try? catalogRepository?.fetchUniversity(named: universityName),
              let repo = catalogRepository else { return nil }
        let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
        return majors.first(where: {
            $0.name.caseInsensitiveCompare(cleanedName) == .orderedSame && !$0.isMinor
        })?.degreeType
    }

    func declaredProgramsCreditsBreakdown() -> DeclaredProgramsCreditsBreakdown {
        if let profile = academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first {
            return declaredProgramsCreditsBreakdown(for: profile)
        }
        return DeclaredProgramsCreditsBreakdown(
            primary: CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
            additionalPrograms: []
        )
    }

    func declaredProgramsCreditsBreakdown(for academicProfile: AcademicProfile) -> DeclaredProgramsCreditsBreakdown {
        let majors = AcademicProfileProgramLists.majors(from: academicProfile)
        let minors = AcademicProfileProgramLists.minors(from: academicProfile)

        guard !majors.isEmpty || !minors.isEmpty else {
            let required = Double(max(0, Int(academicProfile.creditsRequired ?? 0)))
            let completed = Double(max(0, Int(academicProfile.creditsEarned ?? 0)))
            let fraction = required > 0 ? min(max(completed / required, 0), 1) : 0
            return DeclaredProgramsCreditsBreakdown(
                primary: CreditsProgressSummary(completed: completed, required: required, fraction: fraction),
                additionalPrograms: []
            )
        }

        let primaryMajor = majors.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primary: CreditsProgressSummary = {
            guard !primaryMajor.isEmpty else {
                return CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
            }
            return majorRequirementsCreditsProgress(forMajorDisplay: primaryMajor, academicProfile: academicProfile)
        }()

        var additional: [DeclaredProgramsCreditsBreakdown.AdditionalProgram] = []
        for major in majors.dropFirst() {
            let trimmed = major.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            additional.append(
                .init(
                    displayName: trimmed,
                    kind: .major,
                    progress: majorRequirementsCreditsProgress(forMajorDisplay: trimmed, academicProfile: academicProfile)
                )
            )
        }
        for minor in minors {
            let trimmed = minor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.lowercased() != "none" else { continue }
            additional.append(
                .init(
                    displayName: trimmed,
                    kind: .minor,
                    progress: minorRequirementsCreditsProgress(forMinorDisplay: trimmed, academicProfile: academicProfile)
                )
            )
        }
        return DeclaredProgramsCreditsBreakdown(primary: primary, additionalPrograms: additional)
    }

    func primaryDeclaredProgramRequirementCredits() -> Double {
        declaredProgramsCreditsBreakdown().primary.required
    }

    func academicProfileAggregateCreditsProgress(for profile: AcademicProfile) -> CreditsProgressSummary {
        let breakdown = declaredProgramsCreditsBreakdown(for: profile)
        let required = Double(breakdown.allProgramsRequiredTotal)
        let completed = breakdown.primary.completed
        let fraction = required > 0 ? min(max(completed / required, 0), 1) : breakdown.primary.fraction
        return CreditsProgressSummary(completed: completed, required: required, fraction: fraction)
    }

    func majorRequirementsCreditsProgress(forMajorDisplay name: String) -> CreditsProgressSummary {
        let primary = academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first
        if let primary {
            return majorRequirementsCreditsProgress(forMajorDisplay: name, academicProfile: primary)
        }
        return creditsProgressSummary(requirements: getDegreeRequirementsForMajorDisplay(name))
    }

    func majorRequirementsCreditsProgress(
        forMajorDisplay name: String,
        academicProfile: AcademicProfile
    ) -> CreditsProgressSummary {
        creditsProgressSummary(
            requirements: resolvedFilteredRequirementsForMajorDisplay(name, academicProfile: academicProfile)
        )
    }

    func minorRequirementsCreditsProgress(forMinorDisplay name: String) -> CreditsProgressSummary {
        let filtered = resolvedFilteredRequirementsForMinorDisplay(name)
        guard !filtered.isEmpty else {
            return CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
        }
        return creditsProgressSummary(requirements: filtered)
    }

    func minorRequirementsCreditsProgress(
        forMinorDisplay name: String,
        academicProfile: AcademicProfile
    ) -> CreditsProgressSummary {
        _ = academicProfile
        return minorRequirementsCreditsProgress(forMinorDisplay: name)
    }

    func genEdCreditsProgress(for plan: PlannerPlan?) -> CreditsProgressSummary {
        guard let plan else {
            return CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
        }
        let courses = plan.semestersArray.flatMap(\.coursesArray).filter(\.countsTowardGenEd)
        let required = courses.reduce(0.0) { $0 + Double($1.credits) }
        let completed = courses.filter(\.isCompleted).reduce(0.0) { $0 + Double($1.credits) }
        let fraction = required > 0 ? min(max(completed / required, 0), 1) : 0
        return CreditsProgressSummary(completed: completed, required: required, fraction: fraction)
    }

    func majorRequirementCreditBuckets(forMajorDisplay majorDisplay: String) -> RequirementCreditBuckets {
        requirementCreditBuckets(requirements: getDegreeRequirementsForMajorDisplay(majorDisplay))
    }

    func minorRequirementCreditBuckets(forMinorDisplay minorDisplay: String) -> RequirementCreditBuckets {
        requirementCreditBuckets(requirements: resolvedFilteredRequirementsForMinorDisplay(minorDisplay))
    }

    func majorGPASummary(requirements: [CatalogDegreeRequirement]) -> GPASummary? {
        let eligibleCodes = eligibleCourseCodes(from: requirements)
        guard !eligibleCodes.isEmpty else { return nil }

        let completedPlanned = plans
            .flatMap { $0.semestersArray.flatMap(\.coursesArray) }
            .filter(\.isCompleted)

        func courseRecencyKey(_ course: PlannerCourse) -> (Int, Int) {
            let year = Int(course.semester?.year ?? 0)
            let season = Int(course.semester?.seasonOrder ?? 0)
            return (year, season)
        }

        var plannedByCode: [String: PlannerCourse] = [:]
        for course in completedPlanned {
            let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(course.code)
            guard eligibleCodes.contains(code) else { continue }
            if let existing = plannedByCode[code] {
                if courseRecencyKey(course) > courseRecencyKey(existing) {
                    plannedByCode[code] = course
                }
            } else {
                plannedByCode[code] = course
            }
        }

        var qualityPoints = 0.0
        var creditsCounted = 0.0

        for code in eligibleCodes {
            if let planned = plannedByCode[code] {
                guard isLetterGradedForGPA(planned.gradingType),
                      let grade = planned.grade,
                      let gp = AcademicProgramHelpers.gradePoints(for: grade) else { continue }
                let credits = Double(planned.credits)
                guard credits > 0 else { continue }
                qualityPoints += gp * credits
                creditsCounted += credits
                continue
            }
            if let override = getCourseOverride(courseCode: code) {
                let status = (override.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard status == "Completed" else { continue }
                guard isLetterGradedForGPA(override.gradingType),
                      let grade = override.grade,
                      let gp = AcademicProgramHelpers.gradePoints(for: grade) else { continue }
                let credits = override.credits ?? 0
                guard credits > 0 else { continue }
                qualityPoints += gp * credits
                creditsCounted += credits
            }
        }

        guard creditsCounted > 0 else { return nil }
        return GPASummary(gpa: qualityPoints / creditsCounted, credits: creditsCounted)
    }

    func minorGPASummary(minorName: String) -> GPASummary? {
        majorGPASummary(requirements: resolvedFilteredRequirementsForMinorDisplay(minorName))
    }

    func computeMajorRequirementsCreditsProgressSummariesAsync(
        majorDisplays: [String],
        degreeTypeRaw: String
    ) async -> [String: CreditsProgressSummary] {
        _ = degreeTypeRaw
        var out: [String: CreditsProgressSummary] = [:]
        for display in majorDisplays {
            out[display] = majorRequirementsCreditsProgress(forMajorDisplay: display)
        }
        return out
    }

    func decodeDetailedCourseList(_ json: String?) -> [CourseDetail]? {
        AcademicProgramHelpers.decodeDetailedCourseList(json)
    }

    func decodeJSONCourseList(_ json: String?) -> [String] {
        AcademicProgramHelpers.decodeJSONCourseList(json)
    }

    func getCourseOverride(courseCode: String) -> CourseOverride? {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return nil }
        return try? repo.fetchCourseOverride(universityID: university.id, courseCode: courseCode)
    }

    func upsertCourseOverride(
        courseCode: String,
        courseName: String?,
        credits: Double?,
        professor: String?,
        semesterText: String?,
        status: String,
        grade: String?,
        gradingType: String,
        externalURL: String?
    ) {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return }
        do {
            _ = try repo.upsertCourseOverride(
                universityID: university.id,
                courseCode: courseCode,
                courseName: courseName,
                credits: credits,
                professor: professor,
                semesterText: semesterText,
                status: status,
                grade: grade,
                gradingType: gradingType,
                externalURL: externalURL
            )
            _ = try? appDataStore.catalogSave()

            let normalized = courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            for course in semesters.flatMap(\.coursesArray) where course.code.uppercased() == normalized {
                if let grade { course.grade = grade }
                if !status.isEmpty { course.status = status }
                course.isCompleted = (status == "Completed")
            }
            _ = try? appDataStore.profileSave()
            bumpProfileRevision()
        } catch {
            AppLogger.shared.error("upsertCourseOverride failed: \(error)")
        }
    }

    func schoolForDepartment(universityName: String, departmentName: String) -> String? {
        guard let university = try? catalogRepository?.fetchUniversity(named: universityName),
              let repo = catalogRepository else { return nil }
        return try? repo.schoolForDepartment(universityID: university.id, departmentName: departmentName)
    }

    func searchCatalogCourses(query: String, limit: Int = 50) -> [CourseCatalog] {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return [] }
        return (try? repo.searchCatalogCourses(universityID: university.id, query: query, limit: limit)) ?? []
    }

    func getDegreeRequirements(programURL: String, degreeType: String) -> [CatalogDegreeRequirement] {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return [] }
        return (try? repo.fetchDegreeRequirements(
            universityID: university.id,
            programURL: programURL,
            degreeType: degreeType
        )) ?? []
    }

    func getDegreeRequirementsForMajorDisplay(_ name: String) -> [CatalogDegreeRequirement] {
        let primary = academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first
        return getDegreeRequirementsForMajorDisplay(
            name,
            degreeType: primary?.degreeType,
            degreeLevel: primary?.degreeLevel
        )
    }

    func getDegreeRequirementsForMajorDisplay(
        _ majorDisplay: String,
        degreeType: String?,
        degreeLevel: String?
    ) -> [CatalogDegreeRequirement] {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return [] }
        return (try? repo.fetchDegreeRequirementsForMajor(
            universityID: university.id,
            majorDisplay: majorDisplay,
            degreeType: degreeType,
            degreeLevel: degreeLevel
        )) ?? []
    }

    func getDegreeRequirementsByName(
        _ name: String,
        requireDegreeType: String? = nil,
        excludeDegreeTypes: [String] = []
    ) -> [CatalogDegreeRequirement] {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return [] }
        return (try? repo.fetchDegreeRequirementsByName(
            universityID: university.id,
            name: name,
            requireDegreeType: requireDegreeType,
            excludeDegreeTypes: excludeDegreeTypes
        )) ?? []
    }

    func resolveMajorProgramURL(majorDisplay: String, degreeType: String?) -> String? {
        resolveMajorProgramURL(
            display: majorDisplay,
            degreeLevel: primaryDegreeLevel(default: "Undergraduate"),
            degreeType: degreeType
        )
    }

    func resolveMajorProgramURL(
        display: String,
        degreeLevel: String?,
        degreeType: String?
    ) -> String? {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return nil }
        return try? repo.resolveProgramURL(
            universityID: university.id,
            programDisplay: display,
            degreeLevel: degreeLevel,
            degreeType: degreeType,
            isMinor: false
        )
    }

    func resolveProgramProgramURL(programDisplay: String, isMinor: Bool) -> String? {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return nil }
        let level = isMinor ? "Undergraduate" : primaryDegreeLevel(default: "Undergraduate")
        let degreeType = isMinor ? nil : (academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first)?.degreeType
        return try? repo.resolveProgramURL(
            universityID: university.id,
            programDisplay: programDisplay,
            degreeLevel: level,
            degreeType: degreeType,
            isMinor: isMinor
        )
    }

    func fetchCatalogCourseForCodeBroadSearch(_ code: String) -> CourseCatalog? {
        getCatalogCourseMatching(code: code)
    }

    func activeSchoolPolicies() -> SchoolPolicies? {
        guard let university = getActiveUniversity(),
              let uid = university.id.uuidString as String? else { return nil }
        guard let dataByUniversity = UserDefaults.standard.dictionary(forKey: Self.schoolPoliciesDefaultsKey) as? [String: Data],
              let encoded = dataByUniversity[uid] else { return nil }
        return try? JSONDecoder().decode(SchoolPolicies.self, from: encoded)
    }

    func activeSchoolPolicyMetadata() -> SchoolPolicyMetadata? {
        guard let university = getActiveUniversity() else { return nil }
        let keys = [
            university.id.uuidString,
            university.name
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let dataByKey = UserDefaults.standard.dictionary(forKey: Self.schoolPolicyMetadataDefaultsKey) as? [String: Data] ?? [:]
        for key in keys where !key.isEmpty {
            if let data = dataByKey[key],
               let decoded = try? JSONDecoder().decode(SchoolPolicyMetadata.self, from: data) {
                return decoded
            }
        }
        let name = university.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return SchoolPolicyMetadataEnricher.metadata(profile: SchoolProfile(
            schoolID: university.id.uuidString,
            schoolName: name,
            catalogURL: university.catalogURL ?? "",
            version: "active-university-fallback",
            lastUpdated: Date(),
            courses: [],
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        ))
    }

    func graduationPlanTerms(for academicProfile: AcademicProfile) -> [GraduationPlanTerm] {
        (try? profileRepository.fetchGraduationPlanTerms(profileID: academicProfile.id)) ?? []
    }

    func structuredExpectedGraduation(for profile: AcademicProfile) -> (year: Int, season: String)? {
        profileRepository.structuredExpectedGraduation(for: profile)
    }

    func setStructuredExpectedGraduation(year: Int, season: String, on profile: AcademicProfile) {
        profileRepository.setStructuredExpectedGraduation(year: year, season: season, on: profile)
        _ = try? appDataStore.profileSave()
        bumpProfileRevision()
    }

    func clearGraduationPlanTerms(for profile: AcademicProfile) {
        _ = try? profileRepository.clearGraduationPlanTerms(profileID: profile.id)
        _ = try? appDataStore.profileSave()
        bumpProfileRevision()
    }

    @discardableResult
    func upsertGraduationPlanTerm(
        profile: AcademicProfile,
        year: Int,
        season: String,
        plannedCreditCap: Int,
        note: String? = nil
    ) -> GraduationPlanTerm? {
        let term = try? profileRepository.upsertGraduationPlanTerm(
            profileID: profile.id,
            year: year,
            season: season,
            plannedCreditCap: plannedCreditCap,
            note: note
        )
        _ = try? appDataStore.profileSave()
        bumpProfileRevision()
        return term
    }

    func checkPrerequisites(for catalogCourse: CourseCatalog, plan: PlannerPlan) -> PrerequisiteValidationResult {
        let validator = PrerequisiteValidator(collegePersistence: self)
        let completedCourses = plan.semestersArray
            .flatMap(\.coursesArray)
            .filter(\.isCompleted)
        return validator.validatePrerequisites(for: catalogCourse, completedCourses: completedCourses)
    }

    func getGraduationStatus(for plan: PlannerPlan) -> GraduationValidationResult? {
        guard let university = getActiveUniversity() else { return nil }
        let validator = GraduationValidator(collegePersistence: self)
        return validator.validateGraduationReadiness(for: plan, university: university)
    }

    // MARK: - Requirement resolution

    private func resolvedFilteredRequirementsForMajorDisplay(
        _ majorDisplay: String,
        academicProfile: AcademicProfile
    ) -> [CatalogDegreeRequirement] {
        var reqs = getDegreeRequirementsForMajorDisplay(
            majorDisplay,
            degreeType: academicProfile.degreeType,
            degreeLevel: academicProfile.degreeLevel
        )
        var resolvedDegreeKey = majorDisplay

        if reqs.isEmpty {
            let degreeType = (academicProfile.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let profileMajors = AcademicProfileProgramLists.majors(from: academicProfile)
            let primaryMajor = profileMajors.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanedRequest = AcademicProgramHelpers.cleanedProgramNameFromDisplay(
                majorDisplay,
                profileDegreeType: academicProfile.degreeType
            )
            let cleanedPrimary = AcademicProgramHelpers.cleanedProgramNameFromDisplay(
                primaryMajor,
                profileDegreeType: academicProfile.degreeType
            )
            let matchesPrimary = !primaryMajor.isEmpty &&
                (majorDisplay == primaryMajor || cleanedRequest == cleanedPrimary)

            let resolvedURL: String?
            if matchesPrimary {
                resolvedURL = resolveMajorProgramURL(
                    display: majorDisplay,
                    degreeLevel: academicProfile.degreeLevel,
                    degreeType: academicProfile.degreeType
                )
            } else {
                resolvedURL = resolveMajorProgramURL(
                    display: majorDisplay,
                    degreeLevel: academicProfile.degreeLevel,
                    degreeType: academicProfile.degreeType
                )
            }

            if let programURL = resolvedURL {
                reqs = getDegreeRequirements(programURL: programURL, degreeType: degreeType)
                resolvedDegreeKey = programURL
            }
        } else if let url = reqs.first?.programURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            resolvedDegreeKey = url
        }

        return SpecializationRequirementFilter.apply(requirements: reqs, degreeKey: resolvedDegreeKey)
    }

    private func resolvedFilteredRequirementsForMinorDisplay(_ minorDisplay: String) -> [CatalogDegreeRequirement] {
        let trimmed = minorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else { return [] }
        var reqs = getDegreeRequirementsForMajorDisplay(trimmed, degreeType: "Minor", degreeLevel: nil)
        if reqs.isEmpty, let programURL = resolveProgramProgramURL(programDisplay: trimmed, isMinor: true) {
            reqs = getDegreeRequirements(programURL: programURL, degreeType: "Minor")
        }
        return reqs
    }

    func creditsProgressSummary(requirements: [CatalogDegreeRequirement]) -> CreditsProgressSummary {
        var byKey: [String: [CatalogDegreeRequirement]] = [:]
        var orderedKeys: [String] = []
        for requirement in requirements {
            let display = requirement.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = display.lowercased()
            guard !key.isEmpty else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                orderedKeys.append(key)
            }
            byKey[key, default: []].append(requirement)
        }

        let sections: [(title: String, requirements: [CatalogDegreeRequirement])] = orderedKeys.compactMap { key in
            guard var sectionReqs = byKey[key], !sectionReqs.isEmpty else { return nil }
            sectionReqs.sort { $0.sectionOrder < $1.sectionOrder }
            let title = sectionReqs.first?.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Requirements"
            return (title: title.isEmpty ? "Requirements" : title, requirements: sectionReqs)
        }

        var requiredMin = 0.0
        for section in sections {
            requiredMin += creditsRequiredMinMaxForCategoryTitle(section.title, requirements: section.requirements).min
        }

        var claimed = Set<String>()
        for requirement in requirements {
            if let detailedJSON = requirement.requiredCoursesDetailedJSON,
               let detailed = decodeDetailedCourseList(detailedJSON) {
                for detail in detailed {
                    let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(detail.code)
                    if !code.isEmpty { claimed.insert(code) }
                }
            }
            let requiredCodes = (requirement.requiredCourses ?? "")
                .split(separator: ",")
                .map { AcademicProgramHelpers.normalizeCourseCodeForProgress(String($0)) }
                .filter { !$0.isEmpty }
            for code in requiredCodes { claimed.insert(code) }

            if let selectDetailedJSON = requirement.selectFromDetailedJSON,
               let selectDetailed = decodeDetailedCourseList(selectDetailedJSON) {
                for detail in selectDetailed {
                    let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(detail.code)
                    if !code.isEmpty { claimed.insert(code) }
                }
            }
            for code in decodeJSONCourseList(requirement.selectFromJSON)
                .map(AcademicProgramHelpers.normalizeCourseCodeForProgress)
                .filter({ !$0.isEmpty }) {
                claimed.insert(code)
            }
        }

        struct CompletionInfo {
            let isCompleted: Bool
            let credits: Double
        }

        var completionByCode: [String: CompletionInfo] = [:]
        let today = Date()

        func semesterHasEnded(_ course: PlannerCourse) -> Bool {
            guard let sem = course.semester else { return false }
            let year = Int(sem.year)
            let month: Int
            switch sem.season.lowercased() {
            case "winter": month = 1
            case "spring": month = 5
            case "summer": month = 8
            default: month = 12
            }
            let end = Calendar.current.date(from: DateComponents(year: year, month: month, day: 28)) ?? .distantPast
            return end < today
        }

        for course in plans.flatMap({ $0.semestersArray.flatMap(\.coursesArray) }) {
            let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(course.code)
            guard !code.isEmpty else { continue }
            let effectivelyCompleted = course.isCompleted || semesterHasEnded(course)
            completionByCode[code] = CompletionInfo(
                isCompleted: effectivelyCompleted,
                credits: Double(course.credits)
            )
        }

        if let university = getActiveUniversity(),
           let repo = catalogRepository,
           let overrides = try? repo.fetchCompletedCourseOverrides(universityID: university.id) {
            for override in overrides {
                let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(override.courseCode)
                guard !code.isEmpty else { continue }
                let existing = completionByCode[code]
                let credits = (override.credits ?? 0) > 0 ? (override.credits ?? 0) : (existing?.credits ?? 0)
                completionByCode[code] = CompletionInfo(isCompleted: true, credits: credits)
            }
        }

        func completedCredits(for codes: Set<String>) -> Double {
            codes.reduce(0.0) { partial, code in
                guard let info = completionByCode[code], info.isCompleted else { return partial }
                return partial + info.credits
            }
        }

        let completedFromClaimed = completedCredits(for: claimed)

        if requiredMin == 0, !claimed.isEmpty {
            func catalogCreditsForNormalizedCode(_ code: String) -> Double {
                if let catalog = getCatalogCourse(code: code), Double(catalog.credits) > 0 {
                    return Double(catalog.credits)
                }
                let spaced = code.replacingOccurrences(
                    of: "([A-Za-z]+)(\\d+)",
                    with: "$1 $2",
                    options: .regularExpression
                )
                if spaced != code, let catalog = getCatalogCourse(code: spaced), Double(catalog.credits) > 0 {
                    return Double(catalog.credits)
                }
                return 0
            }
            var estimate = 0.0
            for code in claimed {
                if let info = completionByCode[code], info.credits > 0 {
                    estimate += info.credits
                } else {
                    estimate += catalogCreditsForNormalizedCode(code)
                }
            }
            if estimate > 0 { requiredMin = estimate }
        }

        let completed = completedFromClaimed
        let fraction = requiredMin > 0 ? min(max(completed / requiredMin, 0), 1) : 0
        return CreditsProgressSummary(completed: completed, required: requiredMin, fraction: fraction)
    }

    private func requirementCreditBuckets(requirements: [CatalogDegreeRequirement]) -> RequirementCreditBuckets {
        var byKey: [String: [CatalogDegreeRequirement]] = [:]
        var orderedKeys: [String] = []
        for requirement in requirements {
            let key = requirement.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                orderedKeys.append(key)
            }
            byKey[key, default: []].append(requirement)
        }

        let sections = orderedKeys.compactMap { key -> (title: String, requirements: [CatalogDegreeRequirement])? in
            guard var sectionReqs = byKey[key], !sectionReqs.isEmpty else { return nil }
            sectionReqs.sort { $0.sectionOrder < $1.sectionOrder }
            let title = sectionReqs.first?.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Requirements"
            return (title: title.isEmpty ? "Requirements" : title, requirements: sectionReqs)
        }

        var core = 0.0
        var elective = 0.0
        for section in sections {
            let required = creditsRequiredMinMaxForCategoryTitle(section.title, requirements: section.requirements).min
            guard required > 0 else { continue }
            if isElectiveRequirementCategory(section.title) {
                elective += required
            } else {
                core += required
            }
        }

        if core + elective == 0 {
            let required = creditsProgressSummary(requirements: requirements).required
            return RequirementCreditBuckets(requiredCore: required, requiredElective: 0)
        }
        return RequirementCreditBuckets(requiredCore: core, requiredElective: elective)
    }

    private func creditsRequiredMinMaxForCategoryTitle(
        _ title: String,
        requirements: [CatalogDegreeRequirement]
    ) -> (min: Double, max: Double?) {
        if let parsed = parseCreditsRequirementFromTitle(title) {
            return (parsed.min, parsed.max)
        }
        let fallback = Double(requirements.first(where: { $0.creditsRequired > 0 })?.creditsRequired ?? 0)
        return (fallback, nil)
    }

    private func parseCreditsRequirementFromTitle(_ title: String) -> (min: Double, max: Double?)? {
        let pattern = #"\((\d+(?:\.\d+)?)\s*(?:[-–]\s*(\d+(?:\.\d+)?))?\s*credits?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = regex.firstMatch(in: title, options: [], range: ns) else { return nil }
        func capture(_ index: Int) -> String? {
            guard match.numberOfRanges > index else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: title) else { return nil }
            return String(title[swiftRange])
        }
        guard let minString = capture(1), let min = Double(minString) else { return nil }
        let max = capture(2).flatMap(Double.init)
        return (min: min, max: max)
    }

    private func isElectiveRequirementCategory(_ title: String) -> Bool {
        let normalized = title
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        let signals = ["elective", "electives", "optional", "option", "options", "choose", "select", "approved", "free"]
        return signals.contains(where: { normalized.contains($0) })
    }

    private func eligibleCourseCodes(from requirements: [CatalogDegreeRequirement]) -> Set<String> {
        var codes = Set<String>()
        for requirement in requirements {
            if let detailedJSON = requirement.requiredCoursesDetailedJSON,
               let detailed = decodeDetailedCourseList(detailedJSON) {
                for detail in detailed {
                    let code = AcademicProgramHelpers.normalizeCourseCodeForProgress(detail.code)
                    if !code.isEmpty { codes.insert(code) }
                }
            } else {
                for code in (requirement.requiredCourses ?? "")
                    .split(separator: ",")
                    .map({ AcademicProgramHelpers.normalizeCourseCodeForProgress(String($0)) })
                    .filter({ !$0.isEmpty }) {
                    codes.insert(code)
                }
            }
            for code in decodeJSONCourseList(requirement.selectFromJSON)
                .map(AcademicProgramHelpers.normalizeCourseCodeForProgress)
                .filter({ !$0.isEmpty }) {
                codes.insert(code)
            }
        }
        return codes
    }

    private struct CourseProgressSummary {
        let done: Int
        let total: Int
        let remaining: Int
        let fraction: Double
    }

    func programCreditStatusBuckets(requirements: [CatalogDegreeRequirement]) -> ProgramCreditStatusBuckets {
        let summary = courseProgressSummary(requirements: requirements)
        return ProgramCreditStatusBuckets(
            completed: summary.done,
            inProgress: max(0, summary.total - summary.done - summary.remaining),
            remaining: summary.remaining
        )
    }

    func majorProgramCreditStatusBuckets(
        forMajorDisplay majorDisplay: String,
        academicProfile: AcademicProfile
    ) -> ProgramCreditStatusBuckets {
        programCreditStatusBuckets(
            requirements: resolvedFilteredRequirementsForMajorDisplay(majorDisplay, academicProfile: academicProfile)
        )
    }

    func majorProgramCreditStatusBuckets(forMajorDisplay majorDisplay: String) -> ProgramCreditStatusBuckets {
        programCreditStatusBuckets(requirements: getDegreeRequirementsForMajorDisplay(majorDisplay))
    }

    func minorProgramCreditStatusBuckets(
        forMinorDisplay minorDisplay: String,
        academicProfile: AcademicProfile
    ) -> ProgramCreditStatusBuckets {
        _ = academicProfile
        return minorProgramCreditStatusBuckets(forMinorDisplay: minorDisplay)
    }

    func minorProgramCreditStatusBuckets(forMinorDisplay minorDisplay: String) -> ProgramCreditStatusBuckets {
        programCreditStatusBuckets(
            requirements: resolvedFilteredRequirementsForMinorDisplay(minorDisplay)
        )
    }

    private func courseProgressSummary(requirements: [CatalogDegreeRequirement]) -> CourseProgressSummary {
        let completedPlanCodes: Set<String> = Set(
            plans.flatMap(\.semestersArray).flatMap(\.coursesArray)
                .filter(\.isCompleted)
                .map { AcademicProgramHelpers.normalizeCourseCodeForProgress($0.code) }
                .filter { !$0.isEmpty }
        )

        func isCourseCompleted(courseCode raw: String) -> Bool {
            let needle = AcademicProgramHelpers.normalizeCourseCodeForProgress(raw)
            guard !needle.isEmpty else { return false }
            if let override = getCourseOverride(courseCode: needle),
               (override.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "Completed" {
                return true
            }
            return completedPlanCodes.contains(needle)
        }

        var total = 0
        var done = 0

        for requirement in requirements {
            let selectCount = Int(requirement.selectCount)
            if selectCount > 0 {
                total += selectCount
                var selectCodes: [String] = []
                if let selectDetailedJSON = requirement.selectFromDetailedJSON,
                   let selectDetailed = decodeDetailedCourseList(selectDetailedJSON),
                   !selectDetailed.isEmpty {
                    selectCodes = selectDetailed.map(\.code)
                } else {
                    selectCodes = decodeJSONCourseList(requirement.selectFromJSON)
                }
                if selectCodes.isEmpty,
                   let detailedJSON = requirement.requiredCoursesDetailedJSON,
                   let detailed = decodeDetailedCourseList(detailedJSON),
                   !detailed.isEmpty {
                    selectCodes = detailed.map(\.code)
                }
                if selectCodes.isEmpty {
                    selectCodes = (requirement.requiredCourses ?? "")
                        .split(separator: ",")
                        .map { AcademicProgramHelpers.normalizeCourseCodeForProgress(String($0)) }
                        .filter { !$0.isEmpty }
                }
                let uniqueSelectable = Set(selectCodes.map(AcademicProgramHelpers.normalizeCourseCodeForProgress)).filter { !$0.isEmpty }
                let completedCount = uniqueSelectable.filter { isCourseCompleted(courseCode: $0) }.count
                done += min(completedCount, selectCount)
                continue
            }

            if let detailedJSON = requirement.requiredCoursesDetailedJSON,
               let detailed = decodeDetailedCourseList(detailedJSON),
               !detailed.isEmpty {
                total += detailed.count
                done += detailed.filter { isCourseCompleted(courseCode: $0.code) }.count
                continue
            }

            let legacyCodes = (requirement.requiredCourses ?? "")
                .split(separator: ",")
                .map { AcademicProgramHelpers.normalizeCourseCodeForProgress(String($0)) }
                .filter { !$0.isEmpty }
            if !legacyCodes.isEmpty {
                total += legacyCodes.count
                done += legacyCodes.filter { isCourseCompleted(courseCode: $0) }.count
            }
        }

        let remaining = max(0, total - done)
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        return CourseProgressSummary(done: done, total: total, remaining: remaining, fraction: fraction)
    }

    func graduationPlanScheduledCourses(
        for academicProfile: AcademicProfile? = nil
    ) -> [GraduationTimelinePrereqValidator.ScheduledCourse] {
        let semesterList: [PlannerSemester]
        if let plan = academicProfile?.plan {
            semesterList = plan.semestersArray
        } else {
            semesterList = semesters
        }

        var out: [GraduationTimelinePrereqValidator.ScheduledCourse] = []
        out.reserveCapacity(semesterList.count * 4)
        for semester in semesterList {
            let year = Int(semester.year)
            let season = semester.season
            for course in semester.coursesArray {
                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { continue }
                out.append(
                    GraduationTimelinePrereqValidator.ScheduledCourse(
                        code: code,
                        year: year,
                        season: season,
                        isCompleted: course.isCompleted
                    )
                )
            }
        }
        return out
    }
}