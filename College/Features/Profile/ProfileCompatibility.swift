// ProfileCompatibility.swift
// Feature: Profile
// Purpose: Profile module — ProfileEditMajorSection.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI

enum AppExternalLinks {
    static let universityLibrary = URL(string: "https://library.buffalo.edu")
    static let studentAccounts = URL(string: "https://myubcard.com")
    static let careerHandshake = URL(string: "https://app.joinhandshake.com")
}

extension ProfileEditOptions {
    static let degreeLevels: [String] = DegreeConfiguration.allLevels
    static var degreeTypes: [String] {
        DegreeTokenRegistry.allFullPickerLabels()
    }
    static let pronounSuggestions: [String] = ["He/Him", "She/Her", "They/Them", "Prefer not to say"]
}

@MainActor
enum ProfileProgramLists {
    static let maxTrackColumns = 3

    static func syncToProfile(majors: [String], minors: [String], collegePersistence: CollegePersistence) {
        guard collegePersistence.ensurePrimaryAcademicProfile() != nil else { return }

        let cleanedMajors = majors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedMinors = minors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        collegePersistence.syncPrimaryPrograms(
            majors: ProgramListSerialization.coalesceProgramList(cleanedMajors),
            minors: ProgramListSerialization.coalesceProgramList(cleanedMinors)
        )
    }

    static func applyLegacyMajorSelection(
        major: String,
        profile: Profile,
        collegePersistence: CollegePersistence
    ) {
        let trimmed = major.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let minors = collegePersistence.resolvedMinorNames()
        syncToProfile(majors: [trimmed], minors: minors, collegePersistence: collegePersistence)

        guard let primary = collegePersistence.primaryAcademicProfile else { return }
        let currentType = (primary.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if currentType.isEmpty,
           let university = profile.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !university.isEmpty,
           let raw = collegePersistence.fetchDegreeType(for: trimmed, universityName: university),
           let canonical = DegreeTypeNormalizer.normalize(raw) {
            primary.degreeType = canonical.fullLabel
            primary.degreeLevel = canonical.degreeLevel
            collegePersistence.commitPrimaryAcademicProfileEdits()
        }
    }
}

@MainActor
enum ProfileEditProgramMenuData {
    static func programChoices(
        collegePersistence: CollegePersistence,
        profile: Profile,
        degreeLevelForQueries: String
    ) -> (majors: [String], majorSections: [ProfileEditMajorSection], minors: [String]) {
        let level = degreeLevelForQueries.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return ([], [], []) }
        let levelsToQuery = DegreeConfiguration.queryLevels(for: level, availableLevels: DegreeConfiguration.allLevels)

        let active = collegePersistence.getActiveUniversityName() ?? profile.collegeName ?? ""
        let university = active.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return ([], [], []) }

        var flatMajors: [String] = []
        var seenFlatMajors = Set<String>()
        for queryLevel in levelsToQuery {
            let majorsForLevel = CatalogProgramReadBridge.fetchMajors(
                for: university,
                degreeLevel: queryLevel,
                department: nil,
                degreeType: nil,
                includeMinors: false,
                sourceCatoid: nil
            )
            for major in majorsForLevel where seenFlatMajors.insert(major).inserted {
                flatMajors.append(major)
            }
        }
        let filteredMajors = flatMajors.filter(isSelectableMajorLabel(_:))
        let uniqueMajors = Array(Set(filteredMajors)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var departmentGroups: [(group: String, departments: [String])] = []
        var seenDepartmentGroups = Set<String>()
        for queryLevel in levelsToQuery {
            let groupsForLevel = collegePersistence.fetchDepartmentGroups(for: university, degreeLevel: queryLevel, sourceCatoid: nil)
            for group in groupsForLevel {
                let key = group.group.lowercased() + "|" + group.departments.joined(separator: "|").lowercased()
                if seenDepartmentGroups.insert(key).inserted {
                    departmentGroups.append(group)
                }
            }
        }
        var groupedSections: [ProfileEditMajorSection] = []
        var seenSectionTitles = Set<String>()
        for queryLevel in levelsToQuery {
            let pickerSections = collegePersistence.fetchProgramPickerSections(
                for: university,
                degreeLevels: [queryLevel],
                sourceCatoid: nil,
                includeMinors: false,
                includeCollegeBuckets: true,
                allowLegacyCatoidFallback: true
            )
            for section in pickerSections {
                guard seenSectionTitles.insert(section.title).inserted else { continue }
                let filtered = section.labels.filter(isSelectableMajorLabel(_:))
                guard !filtered.isEmpty else { continue }
                groupedSections.append(ProfileEditMajorSection(title: section.title, majors: filtered))
            }
        }

        if groupedSections.isEmpty {
            for group in departmentGroups {
                for department in group.departments {
                    var majors: [String] = []
                    var seenMajors = Set<String>()
                    for queryLevel in levelsToQuery {
                        let majorsForLevel = CatalogProgramReadBridge.fetchMajors(
                            for: university,
                            degreeLevel: queryLevel,
                            department: department,
                            degreeType: nil,
                            includeMinors: false,
                            sourceCatoid: nil
                        )
                        for major in majorsForLevel where seenMajors.insert(major).inserted {
                            majors.append(major)
                        }
                    }
                    let filtered = majors.filter(isSelectableMajorLabel(_:))
                    if filtered.isEmpty { continue }
                    let unique = Array(Set(filtered)).sorted {
                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                    groupedSections.append(
                        ProfileEditMajorSection(title: "\(group.group) > \(department)", majors: unique)
                    )
                }
            }
        }

        var minors: [String] = []
        var seenMinors = Set<String>()
        for queryLevel in levelsToQuery {
            let minorsForLevel = CatalogProgramReadBridge.fetchMinors(
                for: university,
                degreeLevel: queryLevel,
                sourceCatoid: nil
            )
            for minor in minorsForLevel where seenMinors.insert(minor).inserted {
                minors.append(minor)
            }
        }
        let minorOptions: [String]
        if minors.isEmpty {
            minorOptions = collegePersistence.fetchCertificates(for: university, sourceCatoid: nil)
        } else {
            minorOptions = minors
        }

        return (
            uniqueMajors,
            groupedSections,
            minorOptions.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        )
    }

    static func majorChoices(
        collegePersistence: CollegePersistence,
        profile: Profile,
        degreeLevelForQueries: String
    ) -> [String] {
        let active = collegePersistence.getActiveUniversityName() ?? profile.collegeName ?? ""
        let university = active.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return [] }
        let majors = CatalogProgramReadBridge.fetchMajors(
            for: university,
            degreeLevel: degreeLevelForQueries
        )
        return majors.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func minorChoices(collegePersistence: CollegePersistence, profile: Profile) -> [String] {
        let active = collegePersistence.getActiveUniversityName() ?? profile.collegeName ?? ""
        let university = active.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return [] }
        return CatalogProgramReadBridge.fetchMinors(for: university, degreeLevel: "Undergraduate")
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func programChoices(
        collegePersistence: CollegePersistence,
        universityName: String,
        degreeLevelForQueries: String,
        degreeTypeForQueries: String?
    ) -> (majors: [String], majorSections: [ProfileEditMajorSection], minors: [String]) {
        _ = degreeTypeForQueries
        let profile = collegePersistence.profile ?? {
            let created = Profile(name: nil)
            created.collegeName = universityName
            return created
        }()
        return programChoices(
            collegePersistence: collegePersistence,
            profile: profile,
            degreeLevelForQueries: degreeLevelForQueries
        )
    }

    static func isNonMajorDegreeType(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("certificate") || normalized.contains("credential")
    }

    static func majorsForPickerSection(
        section: ProfileEditMajorSection,
        sectionIndex: Int,
        allSections: [ProfileEditMajorSection],
        current: String
    ) -> [String] {
        _ = (sectionIndex, allSections)
        return optionsPreservingCurrentSelection(base: section.majors, current: current)
    }

    /// When the same program name appears under multiple colleges, infer the bucket from the
    /// single matching picker section (onboarding / profile grouped menus).
    static func departmentBucket(forMajor major: String, sections: [ProfileEditMajorSection]) -> String? {
        let trimmed = major.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let matches = sections.filter { section in
            section.majors.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
        guard matches.count == 1 else { return nil }
        return parseDepartmentBucketFromSectionTitle(matches[0].title)
    }

    static func parseDepartmentBucketFromSectionTitle(_ title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = trimmed.range(of: " > ") {
            let bucket = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return bucket.isEmpty ? nil : bucket
        }
        return trimmed
    }

    static func optionsPreservingCurrentSelection(base: [String], current: String) -> [String] {
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentTrimmed.isEmpty { return base }
        if base.contains(where: { $0.caseInsensitiveCompare(currentTrimmed) == .orderedSame }) {
            return base
        }
        return [currentTrimmed] + base
    }

    private static func isSelectableMajorLabel(_ major: String) -> Bool {
        let normalized = major.uppercased()
        if normalized.hasSuffix(", UNKNOWN") { return false }
        if normalized.contains("CERTIFICATE") { return false }
        if normalized.contains("MICRO-CREDENTIAL") { return false }
        if normalized.contains("MICRO CREDENTIAL") { return false }
        if normalized.contains(" CREDENTIAL") { return false }
        return true
    }
}

struct ProfileEditMajorSection: Identifiable, Hashable {
    let title: String
    let majors: [String]
    var id: String { title }
}

struct DashboardMetricValue: View {
    let valueText: String
    let caption: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(valueText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct DashboardGPAScaleBar: View {
    let gpa: Double?

    private var clamped: Double {
        min(max(gpa ?? 0, 0), 4.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(clamped / 4.0))
            }
        }
        .frame(height: 6)
    }
}

extension Profile {
    private var portfolioProjectsStoreKey: String {
        "profile.portfolio.projects.\(id.uuidString)"
    }

    var portfolioProjectsList: [PortfolioProject] {
        get {
            guard let data = UserDefaults.standard.data(forKey: portfolioProjectsStoreKey) else { return [] }
            return (try? JSONDecoder().decode([PortfolioProject].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: portfolioProjectsStoreKey)
        }
    }
}

struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: Profile

    @State private var title: String = ""
    @State private var role: String = ""
    @State private var technologies: String = ""
    @State private var summary: String = ""
    @State private var projectURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Project")
                .font(.title3.weight(.semibold))

            TextField("Project title", text: $title)
            TextField("Role", text: $role)
            TextField("Technologies", text: $technologies)
            TextField("Summary", text: $summary, axis: .vertical)
                .lineLimit(3...6)
            TextField("Project URL", text: $projectURL)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var list = profile.portfolioProjectsList
                    list.append(
                        PortfolioProject(
                            title: title,
                            role: role,
                            technologies: technologies,
                            summary: summary,
                            projectURL: projectURL
                        )
                    )
                    profile.portfolioProjectsList = list
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 480)
    }
}