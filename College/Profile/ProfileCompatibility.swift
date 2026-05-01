import Foundation
import SwiftUI
import CoreData

enum AppExternalLinks {
    static let universityLibrary = URL(string: "https://library.buffalo.edu")
    static let studentAccounts = URL(string: "https://myubcard.com")
    static let careerHandshake = URL(string: "https://app.joinhandshake.com")
}

extension ProfileEditOptions {
    static let degreeLevels: [String] = DegreeConfiguration.allLevels
    static let degreeTypes: [String] = [
        "Bachelor of Science (BS)",
        "Bachelor of Arts (BA)",
        "Master of Science (MS)",
        "Master of Arts (MA)",
        "Doctor of Philosophy (PhD)"
    ]
    static let pronounSuggestions: [String] = ["He/Him", "She/Her", "They/Them", "Prefer not to say"]
}

enum ProfileProgramLists {
    static let maxTrackColumns = 3

    static func majors(from profile: ProfileEntity) -> [String] {
        values(fromCSV: profile.major)
    }

    static func minors(from profile: ProfileEntity) -> [String] {
        values(fromCSV: profile.minor)
    }

    static func syncToProfile(majors: [String], minors: [String], profile: ProfileEntity) {
        profile.major = csv(from: majors)
        profile.minor = csv(from: minors)
    }

    private static func values(fromCSV raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func csv(from values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }
}

enum ProfileEditProgramMenuData {
    static func programChoices(
        coreData: CoreDataManager,
        profile: ProfileEntity,
        degreeLevelForQueries: String
    ) -> (majors: [String], majorSections: [ProfileEditMajorSection], minors: [String]) {
        let level = degreeLevelForQueries.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return ([], [], []) }
        let levelsToQuery = DegreeConfiguration.queryLevels(for: level, availableLevels: DegreeConfiguration.allLevels)

        let active = coreData.getActiveUniversityName() ?? profile.collegeName ?? ""
        let university = active.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return ([], [], []) }

        var flatMajors: [String] = []
        var seenFlatMajors = Set<String>()
        for queryLevel in levelsToQuery {
            let majorsForLevel = coreData.fetchMajors(
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
            let groupsForLevel = coreData.fetchDepartmentGroups(for: university, degreeLevel: queryLevel, sourceCatoid: nil)
            for group in groupsForLevel {
                let key = group.group.lowercased() + "|" + group.departments.joined(separator: "|").lowercased()
                if seenDepartmentGroups.insert(key).inserted {
                    departmentGroups.append(group)
                }
            }
        }
        var groupedSections: [ProfileEditMajorSection] = []
        for group in departmentGroups {
            for department in group.departments {
                var majors: [String] = []
                var seenMajors = Set<String>()
                for queryLevel in levelsToQuery {
                    let majorsForLevel = coreData.fetchMajors(
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

        var minors: [String] = []
        var seenMinors = Set<String>()
        for queryLevel in levelsToQuery {
            let minorsForLevel = coreData.fetchMinors(for: university, degreeLevel: queryLevel, sourceCatoid: nil)
            for minor in minorsForLevel where seenMinors.insert(minor).inserted {
                minors.append(minor)
            }
        }
        let minorOptions: [String]
        if minors.isEmpty {
            minorOptions = coreData.fetchCertificates(for: university, sourceCatoid: nil)
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
        coreData: CoreDataManager,
        profile: ProfileEntity,
        degreeLevelForQueries: String
    ) -> [String] {
        let active = coreData.getActiveUniversityName() ?? profile.collegeName ?? ""
        let university = active.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return [] }
        let majors = coreData.fetchMajors(for: university, degreeLevel: degreeLevelForQueries)
        return majors.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func minorChoices(coreData: CoreDataManager, profile: ProfileEntity) -> [String] {
        let active = coreData.getActiveUniversityName() ?? profile.collegeName ?? ""
        let university = active.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !university.isEmpty else { return [] }
        return coreData.fetchMinors(for: university, degreeLevel: "Undergraduate")
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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

extension ProfileEntity {
    private var portfolioProjectsStoreKey: String {
        let keyPart = id?.uuidString ?? objectID.uriRepresentation().absoluteString
        return "profile.portfolio.projects.\(keyPart)"
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
    @ObservedObject var profile: ProfileEntity

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