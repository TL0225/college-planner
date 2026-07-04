// AcademicsAuditPanel.swift
// Feature: Academics
// Purpose: Audit panel + requirements breakdown (Phase 6 decomposition).

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CollegeAcademics

// MARK: - Detailed Audit Panel

struct AcademicsAuditPanel: View {
    let majors: [String]
    let minors: [String]
    let academicProfile: AcademicProfile?
    @Binding var activePage: AppPage
    @Binding var isInspectorPresented: Bool
    @Binding var scrollToProgramID: String?

    private var collegePersistence: CollegePersistence { appContainer.persistence }
    @Environment(AppContainer.self) private var appContainer

    private var persistence: CollegePersistence { appContainer.persistence }
    private var auditSnapshotStore: AuditSnapshotStore { appContainer.auditSnapshotStore }

    private var auditRefreshToken: String {
        "\(majors.joined(separator: "\u{1e}"))|\(minors.joined(separator: "\u{1e}"))"
    }

    // MARK: Data model

    struct AuditItem: Identifiable {
        let id = UUID()
        let code: String
        let credits: String
        /// Course title resolved from `CourseDetail.title` (program-page scrape) → `CourseCatalogEntity.title`
        /// → empty. Displayed alongside the course code in the redesigned row.
        let title: String
        /// Letter grade (e.g. "A-", "B+") resolved from the plan's matching `CourseEntity` or
        /// `CourseOverrideEntity` for the active university. `nil` when no grade has been entered.
        let grade: String?
        /// Aligned with semester-card status (completed / in progress / on plan / not scheduled).
        let planProgress: RequirementPlanProgress
        let isElective: Bool  // true = from selectFromJSON, false = required
        /// Courses sharing a key are catalog "or" alternatives within one requirement row.
        var alternativeGroupKey: String? = nil
        /// Transfer Database provenance label (Official / ASSIST / Community / etc.) when catalog + transfer data exist.
        var transferSourceLabel: String? = nil
        /// Term the course is scheduled in (e.g. "Fall 2026") once it's dragged onto a planner
        /// semester. `nil` when the course isn't on the plan yet.
        var scheduledTermLabel: String? = nil

        /// Only `.completed` rows count credit totals toward met requirements.
        var isCompleted: Bool { planProgress == .completed }
    }

    struct AuditCategory: Identifiable {
        let id = UUID()
        let title: String
        let items: [AuditItem]
        let selectCount: Int   // 0 = all required; >0 = "choose N from"
        /// App-computed target for this row (listed courses + choose-N + prose credits).
        /// Kept as `creditsRequired` for call-site compatibility; never copied from scraper.
        let creditsRequired: Int
        /// Official catalog hourscol denominator (scraper `creditsRequired` on the entity).
        var catalogCreditsRequired: Int = 0
        /// Credits parsed from catalog description when no course codes were scraped (e.g. "6 credits").
        let descriptionCredits: Int
        /// Header credits from catalog hourscol for choose-one rows.
        var headerCredits: Int = 0
        var rowKind: RequirementKind? = nil
        var parentSectionTitle: String? = nil
        var displayTitle: String? = nil
        var sectionHeader: String? = nil
        var indentLevel: Int = 0
        var allowsManualFulfillment: Bool = false
        /// Non-nil when this category is one option inside a "choose one of the following
        /// specializations" XOR group. All sibling options share the same key. The audit
        /// sidebar reads this to render a picker and gray out non-chosen siblings; credit
        /// totals only count the chosen sibling.
        var specializationGroupKey: String? = nil
        /// Human-readable label for the picker header (typically "Specialization").
        var specializationGroupTitle: String? = nil
    }

    enum AuditDegreeKind { case major, minor }

    struct AuditDegree: Identifiable {
        let id = UUID()
        let label: String
        let rawName: String
        let kind: AuditDegreeKind
        let color: Color
        let categories: [AuditCategory]
        let programURL: String
        let degreeType: String
        /// True for the first declared major — credits here count toward the graduation target.
        var isGraduationRequirement: Bool = false

        /// Buckets categories that belong to the same XOR specialization group. The audit
        /// sidebar uses this to render one picker per group above its first member.
        var specializationGroups: [SpecializationGroup] {
            var order: [String] = []
            var buckets: [String: [AuditCategory]] = [:]
            for cat in categories {
                guard let key = cat.specializationGroupKey else { continue }
                if buckets[key] == nil {
                    order.append(key)
                    buckets[key] = []
                }
                buckets[key]?.append(cat)
            }
            return order.compactMap { key in
                guard let members = buckets[key], !members.isEmpty else { return nil }
                let title = members.first?.specializationGroupTitle ?? "Specialization"
                return SpecializationGroup(
                    key: key,
                    title: title,
                    options: members
                )
            }
        }
    }

    /// A "choose one of the following specializations" XOR group within an `AuditDegree`.
    /// The user's selection is persisted in `@AppStorage` keyed by `(programURL, key)`.
    struct SpecializationGroup: Identifiable {
        let id = UUID()
        let key: String
        let title: String
        let options: [AuditCategory]
    }

    // MARK: State

    @State private var expandedCategories: Set<UUID> = []
    @State private var selectedDegreeForDetail: AuditDegree? = nil

    // MARK: Body

    private var hasDeclaredPrograms: Bool {
        let m = majors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let n = minors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return !m.isEmpty || !n.isEmpty
    }

        var body: some View {
        RequirementsBreakdownView(
            primaryMajor: majors.first ?? "",
            hasDeclaredPrograms: hasDeclaredPrograms,
            auditDegrees: auditSnapshotStore.auditDegrees,
            isLoading: auditSnapshotStore.isLoadingAudit,
            expandedCategories: $expandedCategories,
            isInspectorPresented: $isInspectorPresented,
            scrollToProgramID: $scrollToProgramID
        )
        .task(id: auditRefreshToken) {
            let hints = await auditSnapshotStore.reloadAudit(
                collegePersistence: collegePersistence,
                majors: majors,
                minors: minors,
                academicProfile: academicProfile
            )
            if !hints.isEmpty {
                expandedCategories.formUnion(hints)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requirementFulfillmentChanged)) { _ in
            auditSnapshotStore.scheduleReloadAudit(
                collegePersistence: collegePersistence,
                majors: majors,
                minors: minors,
                academicProfile: academicProfile
            ) { hints in
                if !hints.isEmpty {
                    expandedCategories.formUnion(hints)
                }
            }
        }
    }
}

// MARK: - Academic Landscape UI Extensions

struct LandscapeDashboard: View {
    @Environment(AppContainer.self) private var appContainer

    let profile: Profile?
    let academicProfile: AcademicProfile?
    let plannerGPAFormatted: String
    let plannerCreditsEarned: Int
    let plannerCreditsRequired: Int

    private var collegePersistence: CollegePersistence { appContainer.persistence }
    @State private var majorProgramsPopover = false
    @State private var minorProgramsPopover = false

    private let majorPalette: [Color] = [Color.accentColor, .orange, .green]
    private let minorPalette: [Color] = [.teal, .purple, .indigo]

    var body: some View {
        let majors = academicProfile.map { collegePersistence.resolvedMajorNames(for: $0) }
            ?? collegePersistence.resolvedMajorNames()
        let minors = academicProfile.map { collegePersistence.resolvedMinorNames(for: $0) }
            ?? collegePersistence.resolvedMinorNames()
        let degreeLevel = academicProfile?.degreeLevel ?? collegePersistence.primaryDegreeLevel(default: "")
        let showMinorRow = DeclaredProgramDegreeMetadata.shouldShowMinorPrograms(
            degreeLevel: degreeLevel,
            minors: minors
        )

        VStack(alignment: .leading, spacing: 24) {
            landscapeProgramRow(
                rowTag: "MAJOR",
                names: majors,
                isMinor: false,
                palette: majorPalette,
                overflowOpen: $majorProgramsPopover
            )

            if showMinorRow {
                landscapeProgramRow(
                    rowTag: "MINOR",
                    names: minors,
                    isMinor: true,
                    palette: minorPalette,
                    overflowOpen: $minorProgramsPopover
                )
            }

            LandscapeTimelineCard(
                totalCredits: Double(plannerCreditsEarned),
                requiredCredits: Double(plannerCreditsRequired),
                programsBreakdown: academicProfile.map { collegePersistence.declaredProgramsCreditsBreakdown(for: $0) }
                    ?? collegePersistence.declaredProgramsCreditsBreakdown(),
                expectedGraduation: {
                    guard let s = collegePersistence.primaryExpectedGraduation()?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
                    return s
                }()
            )
            .padding(.top, 8)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
    }

    private func requirementProgress(isMinor: Bool, name: String) -> CollegePersistence.CreditsProgressSummary {
        if let academicProfile {
            if isMinor {
                return collegePersistence.minorRequirementsCreditsProgress(
                    forMinorDisplay: name,
                    academicProfile: academicProfile
                )
            }
            return collegePersistence.majorRequirementsCreditsProgress(
                forMajorDisplay: name,
                academicProfile: academicProfile
            )
        }
        if isMinor {
            return collegePersistence.minorRequirementsCreditsProgress(forMinorDisplay: name)
        }
        return collegePersistence.majorRequirementsCreditsProgress(forMajorDisplay: name)
    }

    private func landscapeProgramCardLabel(rowTag: String, index: Int, isMinor: Bool) -> String {
        if isMinor { return "\(rowTag) \(index + 1)" }
        if rowTag == "MAJOR", index == 0 { return "DEGREE" }
        return "\(rowTag) \(index + 1)"
    }

    @ViewBuilder
    private func landscapeProgramRow(
        rowTag: String,
        names: [String],
        isMinor: Bool,
        palette: [Color],
        overflowOpen: Binding<Bool>
    ) -> some View {
        let maxC = ProfileProgramLists.maxTrackColumns
        HStack(spacing: 16) {
            if names.isEmpty {
                LandscapeMajorCard(
                    type: rowTag,
                    name: String(
                        localized: isMinor
                            ? "academics.landscape.no_minors"
                            : "academics.landscape.no_majors",
                        defaultValue: isMinor ? "No minors declared" : "No majors declared"
                    ),
                    gpa: plannerGPAFormatted,
                    progress: CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
                    color: .secondary,
                    barColor: .secondary.opacity(0.35)
                )
                .frame(maxWidth: .infinity)
            } else if names.count > maxC {
                ForEach(0..<(maxC - 1), id: \.self) { idx in
                    let name = names[idx]
                    LandscapeMajorCard(
                        type: landscapeProgramCardLabel(rowTag: rowTag, index: idx, isMinor: isMinor),
                        name: name,
                        gpa: plannerGPAFormatted,
                        progress: requirementProgress(isMinor: isMinor, name: name),
                        color: palette[idx % palette.count],
                        barColor: palette[idx % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }

                let extra = Array(names.dropFirst(maxC - 1))
                Button {
                    overflowOpen.wrappedValue.toggle()
                } label: {
                    LandscapeMajorCard(
                        type: "MORE",
                        name: "+\(extra.count) more",
                        gpa: plannerGPAFormatted,
                        progress: CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
                        color: palette[(maxC - 1) % palette.count],
                        barColor: palette[(maxC - 1) % palette.count]
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: overflowOpen) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(extra, id: \.self) { line in
                                Text(line)
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(DesignSystem.Spacing.lg)
                    }
                    .frame(minWidth: 280, minHeight: 140)
                }
            } else {
                ForEach(Array(names.enumerated()), id: \.offset) { slot, name in
                    LandscapeMajorCard(
                        type: "\(rowTag) \(slot + 1)",
                        name: name,
                        gpa: plannerGPAFormatted,
                        progress: requirementProgress(isMinor: isMinor, name: name),
                        color: palette[slot % palette.count],
                        barColor: palette[slot % palette.count]
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct LandscapeMajorCard: View {
    let type: String
    let name: String
    let gpa: String
    let progress: CollegePersistence.CreditsProgressSummary
    let color: Color
    let barColor: Color

    private var creditsTowardRequirementLine: String {
        let req = progress.requiredRoundedInt
        let done = progress.completedRoundedInt
        if req <= 0 { return "Requirement credits TBD" }
        return "\(done)/\(req) cr toward requirement"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(type.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("GPA")
                            .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(gpa)
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("plan")
                            .font(DesignSystem.Fonts.main(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(name)
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48, alignment: .topLeading)
                    .help(name)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(progress.fraction > 0 ? progress.fraction : 0.0))
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [barColor.opacity(0.5), barColor]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text(String(format: "%.0f%%", progress.fraction * 100))
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requirement progress")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(creditsTowardRequirementLine)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LandscapeTimelineCard: View {
    let totalCredits: Double
    let requiredCredits: Double
    var programsBreakdown: CollegePersistence.DeclaredProgramsCreditsBreakdown?
    var expectedGraduation: String?

    private var timelineSubtitle: String {
        if programsBreakdown?.hasAdditionalPrograms == true {
            return String(
                localized: "academics.graduation.timeline.degree_only",
                defaultValue: "Degree requirement — additional majors and minors tracked separately"
            )
        }
        return String(
            localized: "academics.landscape.timeline.subtitle",
            defaultValue: "Combined progress across declared majors and minors"
        )
    }

    var body: some View {
        GroupBox {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: "graduationcap.fill")
                        .font(DesignSystem.Fonts.main(size: 20))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Graduation Timeline")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        if let expectedGraduation, !expectedGraduation.isEmpty {
                            Text(expectedGraduation.uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(timelineSubtitle)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        Text(
                            programsBreakdown?.hasAdditionalPrograms == true
                                ? String(localized: "academics.graduation.degree_credit_progress", defaultValue: "DEGREE CREDIT PROGRESS")
                                : "TOTAL CREDIT PROGRESS"
                        )
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        if requiredCredits > 0 {
                            Text("\(Int(totalCredits))")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("/ \(Int(requiredCredits)) Credits")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(totalCredits)) cr earned")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                            .frame(maxWidth: .infinity)
                        GeometryReader { geo in
                            let frac = requiredCredits > 0 ? min(1.0, totalCredits / requiredCredits) : 0.0
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: CGFloat(frac) * geo.size.width, height: 8)
                        }
                    }
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)
                    if let footnote = programsBreakdown?.optionalProgramsFootnote {
                        Text(footnote)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(DesignSystem.Spacing.sm)
        }
    }
}

struct LandscapeCurriculumCard: View {
    @Environment(AppContainer.self) private var appContainer

    let semester: PlannerSemester
    @State private var isCollapsed = false
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    private var sortedCourses: [PlannerCourse] {
        (semester.courses ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var totalSemesterCredits: Int {
        sortedCourses.reduce(0) { $0 + Int($1.credits) }
    }

    private func resolvedTitle(for course: PlannerCourse) -> String {
        let rawCode = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeNorm = rawCode.replacingOccurrences(of: " ", with: "").uppercased()
        let nameNorm = rawName.replacingOccurrences(of: " ", with: "").uppercased()

        if !rawName.isEmpty, nameNorm != codeNorm {
            return rawName
        }

        if !rawCode.isEmpty {
            if let catalog = CollegePersistence.shared.fetchCatalogCourseForCodeBroadSearch(rawCode) {
                let title = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty,
                   title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
                    return title
                }
            }

            // Also try the base code without trailing alpha section suffixes,
            // e.g. "CSE220LEC" -> "CSE220", so catalog titles still resolve.
            let strippedCode = rawCode
                .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !strippedCode.isEmpty, strippedCode.caseInsensitiveCompare(rawCode) != .orderedSame,
               let catalog = CollegePersistence.shared.fetchCatalogCourseForCodeBroadSearch(strippedCode) {
                let title = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty,
                   title.replacingOccurrences(of: " ", with: "").uppercased() != codeNorm {
                    return title
                }
            }
        }

        return "No title available"
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "calendar")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(semester.name)
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !isCollapsed {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("\(totalSemesterCredits) Total Credits")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.up.circle.fill")
                            .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                            .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(DesignSystem.Spacing.lg)

                if !isCollapsed {
                    Table(sortedCourses) {
                        TableColumn("Course") { course in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.code)
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(resolvedTitle(for: course))
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .contextMenu {
                                Button("Remove Course", role: .destructive) {
                                    collegePersistence.deleteCourse(id: course.id)
                                }
                            }
                        }
                        TableColumn("Credits") { course in
                            Text("\(Int(course.credits))")
                                .font(DesignSystem.Fonts.main(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .contextMenu {
                                    Button("Remove Course", role: .destructive) {
                                        collegePersistence.deleteCourse(id: course.id)
                                    }
                                }
                        }
                        TableColumn("Requirement") { course in
                            Text(course.status.uppercased())
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .contextMenu {
                                    Button("Remove Course", role: .destructive) {
                                        collegePersistence.deleteCourse(id: course.id)
                                    }
                                }
                        }
                        TableColumn("Status") { course in
                            HStack(spacing: 4) {
                                Image(systemName: course.isCompleted ? "checkmark.circle.fill" : "clock.fill")
                                    .contentTransition(.symbolEffect(.replace.offUp))
                                Text(course.isCompleted ? "Completed" : "Active")
                                    .contentTransition(.opacity)
                            }
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(course.isCompleted ? .green : .accentColor)
                            .animation(.spring(response: 0.28, dampingFraction: 0.80), value: course.isCompleted)
                            .padding(.vertical, 8)
                            .contextMenu {
                                Button("Remove Course", role: .destructive) {
                                    collegePersistence.deleteCourse(id: course.id)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .alternatingRowBackgrounds(.disabled)
                    .frame(minHeight: CGFloat(sortedCourses.count * 46 + 40))
                }
            }
        }
    }
}

// MARK: - Requirements breakdown parsing (titles + credit progress)

/// Shared between audit loading (first-expand) and `RequirementsBreakdownView` UI.
enum RequirementBreakdownParser {
    struct ParsedTitle: Equatable {
        var displayTitle: String
        var creditsLabel: String?
        var minCredits: Int?
        var maxCredits: Int?
    }

    /// Pulls `(6 credits)`, `(3-4 Credits)`, etc. out of the category title for a clean heading + right-column catalog label.
    static func parseTitle(_ raw: String) -> ParsedTitle {
        var work = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var minV: Int?
        var maxV: Int?
        var label: String?

        let parenRx = try? NSRegularExpression(pattern: #"(?i)\s*\((\d+)(?:\s*[-–]\s*(\d+))?\s*credits?\)"#, options: [])
        if let parenRx {
            let range = NSRange(work.startIndex..<work.endIndex, in: work)
            if let m = parenRx.firstMatch(in: work, options: [], range: range),
               let r1 = Range(m.range(at: 1), in: work),
               let lo = Int(work[r1]) {
                minV = lo
                if m.range(at: 2).location != NSNotFound,
                   let r2 = Range(m.range(at: 2), in: work),
                   let hi = Int(work[r2]), hi >= lo {
                    maxV = hi
                    label = "\(lo)–\(hi) Credits"
                } else {
                    maxV = lo
                    label = "\(lo) Credits"
                }
                work = parenRx.stringByReplacingMatches(in: work, options: [], range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if label == nil {
            let trailRx = try? NSRegularExpression(pattern: #"(?i)\s+(\d+)(?:\s*[-–]\s*(\d+))?\s*credits?\s*$"#, options: [])
            if let trailRx {
                let range = NSRange(work.startIndex..<work.endIndex, in: work)
                if let m = trailRx.firstMatch(in: work, options: [], range: range),
                   let r1 = Range(m.range(at: 1), in: work),
                   let lo = Int(work[r1]) {
                    minV = lo
                    if m.range(at: 2).location != NSNotFound,
                       let r2 = Range(m.range(at: 2), in: work),
                       let hi = Int(work[r2]), hi >= lo {
                        maxV = hi
                        label = "\(lo)–\(hi) Credits"
                    } else {
                        maxV = lo
                        label = "\(lo) Credits"
                    }
                    work = trailRx.stringByReplacingMatches(in: work, options: [], range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        work = work.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return ParsedTitle(displayTitle: work, creditsLabel: label, minCredits: minV, maxCredits: maxV)
    }

    static func creditValue(from raw: String) -> Int {
        RequirementBreakdownCredits.creditValue(from: raw)
    }

    static func sumCreditsAll(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        RequirementBreakdownCredits.sumCreditsAll(items: items)
    }

    static func sumCompletedCredits(items: [AcademicsAuditPanel.AuditItem]) -> Int {
        RequirementBreakdownCredits.sumCompletedCredits(items: items)
    }

    static func sumCompletedCredits(for category: AcademicsAuditPanel.AuditCategory) -> Int {
        RequirementBreakdownCredits.sumCompletedCredits(
            items: category.items,
            selectCount: category.selectCount,
            descriptionCredits: category.descriptionCredits,
            headerCredits: category.headerCredits
        )
    }

    static func progressTarget(for category: AcademicsAuditPanel.AuditCategory) -> Int {
        RequirementBreakdownCredits.progressTarget(for: category)
    }

    static func isCategoryDone(category: AcademicsAuditPanel.AuditCategory) -> Bool {
        RequirementBreakdownCredits.isCategoryDone(category: category)
    }

    /// Catalog-style reference lists (e.g. Comparative Politics **List**) — lighter visual tier for dense minors.
    static func isListStyleSubheader(_ displayTitle: String) -> Bool {
        displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"(?i)\blist\s*$"#, options: .regularExpression) != nil
    }
}

/// Scroll anchors for the requirements list — IDs match `ProgramCreditStatusStripRow.id`.
enum AcademicsProgramRequirementsScrollID {
    static let top = "requirements|top"

    static func forStripSelection(_ stripID: String) -> String {
        stripID == ProgramCreditStatusStripRow.allProgramsID ? top : stripID
    }

    static func forDegree(_ degree: AcademicsAuditPanel.AuditDegree) -> String {
        switch degree.kind {
        case .major:
            return "major|\(degree.rawName)"
        case .minor:
            return "minor|\(degree.rawName)"
        }
    }
}

struct RequirementsBreakdownView: View {
    var primaryMajor: String
    /// True when Profile lists at least one major or minor (used for empty-state copy).
    var hasDeclaredPrograms: Bool = false
    var auditDegrees: [AcademicsAuditPanel.AuditDegree]
    var isLoading: Bool
    @Binding var expandedCategories: Set<UUID>
    @Binding var isInspectorPresented: Bool
    @Binding var scrollToProgramID: String?

    @State private var hideCompleted: Bool = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("accessibility.reduceMotion") private var prefReduceMotion: Bool = false

    /// Specialization selections keyed by `"\(degreeKey)|\(groupKey)"`. Mirrors
    /// `AuditSpecializationStore` so the View reacts to picker changes immediately while
    /// the store handles cross-session persistence and exposes the values to
    /// credit-progress calculators outside this View.
    @State private var specializationSelections: [String: String] = [:]
    @State private var requirementSelections: [String: Set<String>] = [:]
    /// Cache keys (`degreeKey|categoryTitle`, lowercased) for requirement categories the user
    /// has tagged as "doesn't count toward the credit goal". Seeded from
    /// `AuditExcludedRequirementStore` and mutated in-place so the breakdown re-renders
    /// instantly when toggled; credit totals recompute via `.auditRequirementExclusionChanged`.
    @State private var excludedCategoryKeys: Set<String> = []
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    @Environment(AppContainer.self) private var appContainer

    private var persistence: CollegePersistence { appContainer.persistence }
    private var modalCoordinator: ModalCoordinator { appContainer.modalCoordinator }
    @State private var dropTargetCategoryID: UUID?
    /// Drives `.scrollPosition` for the requirements `List` (reliable with lazy rows).
    @State private var listScrollAnchorID: String?

    private var taggedAuditDegrees: [AcademicsAuditPanel.AuditDegree] {
        guard let target = TransferAcademicsBridge(persistence: persistence).resolveTargetSchool() else {
            return auditDegrees
        }
        let labels = TransferRequirementsSourceTagger.sourceLabelsByTargetCourseCode(
            targetSchoolID: target.id,
            persistence: persistence
        )
        return TransferRequirementsSourceTagger.applySourceTags(to: auditDegrees, labelsByCode: labels)
    }

    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    /// Composite cache key used by `specializationSelections` so it can hold selections
    /// across multiple degrees (e.g., a major and a minor that both declare picker groups).
    private func selectionCacheKey(degree: AcademicsAuditPanel.AuditDegree, groupKey: String) -> String {
        let degreeKey = degree.programURL.isEmpty ? degree.rawName : degree.programURL
        return "\(degreeKey.lowercased())|\(groupKey)"
    }

    private func requirementSelectionCacheKey(degree: AcademicsAuditPanel.AuditDegree, categoryTitle: String) -> String {
        let degreeKey = degree.programURL.isEmpty ? degree.rawName : degree.programURL
        return "\(degreeKey.lowercased())|\(categoryTitle.lowercased())"
    }

    private func degreeKey(for degree: AcademicsAuditPanel.AuditDegree) -> String {
        degree.programURL.isEmpty ? degree.rawName : degree.programURL
    }

    private func exclusionCacheKey(degree: AcademicsAuditPanel.AuditDegree, categoryTitle: String) -> String {
        "\(degreeKey(for: degree).lowercased())|\(categoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func isCategoryExcluded(
        _ category: AcademicsAuditPanel.AuditCategory,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> Bool {
        excludedCategoryKeys.contains(exclusionCacheKey(degree: degree, categoryTitle: category.title))
    }

    /// Toggle whether a requirement category counts toward the program's credit goal. Persists
    /// through `AuditExcludedRequirementStore` and notifies credit calculators to recompute.
    private func toggleCategoryExcluded(
        _ category: AcademicsAuditPanel.AuditCategory,
        in degree: AcademicsAuditPanel.AuditDegree
    ) {
        let key = exclusionCacheKey(degree: degree, categoryTitle: category.title)
        let newValue = !excludedCategoryKeys.contains(key)
        let animation: Animation = motionReduced
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.30, dampingFraction: 0.86)
        withAnimation(animation) {
            if newValue { excludedCategoryKeys.insert(key) } else { excludedCategoryKeys.remove(key) }
        }
        AuditExcludedRequirementStore.setExcluded(
            newValue,
            degreeKey: degreeKey(for: degree),
            categoryTitle: category.title
        )
        NotificationCenter.default.post(name: .auditRequirementExclusionChanged, object: nil)
    }

    private func selectedCodes(
        for category: AcademicsAuditPanel.AuditCategory,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> Set<String> {
        let cacheKey = requirementSelectionCacheKey(degree: degree, categoryTitle: category.title)
        if let cached = requirementSelections[cacheKey] { return cached }
        return AuditRequirementSelectionStore.selectedCodes(
            degreeKey: degreeKey(for: degree),
            categoryTitle: category.title
        )
    }

    private func categoryAllowsInlineCourseSelection(_ category: AcademicsAuditPanel.AuditCategory) -> Bool {
        if category.selectCount > 0 { return true }
        if category.rowKind == .chooseOne { return true }
        if category.items.contains(where: { ($0.alternativeGroupKey ?? "").isEmpty == false }) { return true }
        let title = (category.displayTitle ?? category.title).lowercased()
        if (title.contains("choose") || title.contains("select")),
           category.items.count > 1 {
            return true
        }
        return false
    }

    private func orGroupCodes(
        for item: AcademicsAuditPanel.AuditItem,
        in items: [AcademicsAuditPanel.AuditItem]
    ) -> Set<String> {
        guard let key = item.alternativeGroupKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return [] }
        return Set(
            items
                .filter { $0.alternativeGroupKey == key }
                .map { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )
    }

    private func isSelectableListedCourse(
        _ item: AcademicsAuditPanel.AuditItem,
        category: AcademicsAuditPanel.AuditCategory
    ) -> Bool {
        if item.alternativeGroupKey != nil { return true }
        if category.selectCount > 0, item.isElective { return true }
        if category.rowKind == .chooseOne, item.isElective { return true }
        let title = (category.displayTitle ?? category.title).lowercased()
        if (title.contains("choose") || title.contains("select")), item.isElective { return true }
        return false
    }

    private func isItemDimmedForSelection(
        _ item: AcademicsAuditPanel.AuditItem,
        category: AcademicsAuditPanel.AuditCategory,
        selected: Set<String>,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> Bool {
        guard categoryAllowsInlineCourseSelection(category) else { return false }
        guard isSelectableListedCourse(item, category: category) else { return false }
        let code = item.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if item.alternativeGroupKey != nil {
            let groupCodes = orGroupCodes(for: item, in: category.items)
            let pickedInGroup = selected.intersection(groupCodes)
            if pickedInGroup.isEmpty { return false }
            return !pickedInGroup.contains(code)
        }
        if selected.isEmpty { return false }
        return !selected.contains(code)
    }

    private func toggleRequirementSelection(
        item: AcademicsAuditPanel.AuditItem,
        category: AcademicsAuditPanel.AuditCategory,
        degree: AcademicsAuditPanel.AuditDegree
    ) {
        let cacheKey = requirementSelectionCacheKey(degree: degree, categoryTitle: category.title)
        let degreeKey = degreeKey(for: degree)
        let maxSelections = max(1, category.selectCount > 0 ? category.selectCount : 1)
        AuditRequirementSelectionStore.selectCourse(
            item.code,
            degreeKey: degreeKey,
            categoryTitle: category.title,
            maxSelections: maxSelections,
            orGroupKey: item.alternativeGroupKey,
            orGroupCodes: orGroupCodes(for: item, in: category.items)
        )
        requirementSelections[cacheKey] = AuditRequirementSelectionStore.selectedCodes(
            degreeKey: degreeKey,
            categoryTitle: category.title
        )
    }

    /// The real, user-pickable options in a specialization XOR group. The detector also
    /// tags the group's *parent* row (e.g. "Choose one of the following Specializations")
    /// because its title contains the "specialization" keyword — but that row is the group
    /// header, not a choice. We drop any option whose title is the parent section of its
    /// siblings so the picker, default selection, and hide logic all agree on the choices.
    private func effectiveSpecializationOptions(
        _ group: AcademicsAuditPanel.SpecializationGroup
    ) -> [AcademicsAuditPanel.AuditCategory] {
        let parentTitles = Set(
            group.options.compactMap {
                $0.parentSectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        )
        let real = group.options.filter { option in
            let title = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if parentTitles.contains(title) { return false }
            // Drop the XOR group header itself (e.g. "Choose one of the following
            // Specializations 18 credits") — it's the banner, not a selectable path.
            if isSpecializationGroupHeaderTitle(title) { return false }
            return true
        }
        return real.isEmpty ? group.options : real
    }

    /// True when a category title reads like the XOR group banner ("Choose one of the
    /// following …") rather than a concrete specialization choice.
    private func isSpecializationGroupHeaderTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return SpecializationGroupDetector.xorDescriptionPhrases.contains { lower.contains($0) }
    }

    /// Non-option rows that read like a subordinate requirement of a specialization option
    /// (e.g. "Choose two 700-800 level courses …"). Catalogs frequently flatten these so they
    /// carry no `parentSectionTitle`; their requirement kind is the reliable signal.
    private func isSpecializationSubRow(_ category: AcademicsAuditPanel.AuditCategory) -> Bool {
        switch category.rowKind {
        case .chooseOne, .ruleBucket, .distributionBucket, .prose:
            return true
        default:
            return false
        }
    }

    /// Returns the currently-chosen option title for `(degree, group)`, defaulting to the
    /// first real option when the user hasn't picked yet. The defaulting matches the
    /// contract `AuditSpecializationStore.nonSelectedOptionTitles(for:)` uses elsewhere so
    /// the audit sidebar's view-state and the credit calculator's filter stay in lockstep.
    private func chosenOptionTitle(
        for group: AcademicsAuditPanel.SpecializationGroup,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> String {
        let cacheKey = selectionCacheKey(degree: degree, groupKey: group.key)
        if let inMemory = specializationSelections[cacheKey] { return inMemory }
        let degreeKey = degree.programURL.isEmpty ? degree.rawName : degree.programURL
        if let persisted = AuditSpecializationStore.selectedOptionTitle(degreeKey: degreeKey, groupKey: group.key) {
            return persisted
        }
        return effectiveSpecializationOptions(group).first?.title ?? ""
    }

    /// Category IDs that belong to a *non-selected* specialization path and should be hidden
    /// entirely (only the chosen option's content stays visible). Ownership of sub-rows
    /// (e.g. "Choose two 700-800 level courses …") is assigned by document order: a non-option
    /// row that sits under the XOR group's parent and follows an option belongs to that
    /// option. The redundant group header row is always hidden — the picker replaces it.
    private func hiddenSpecializationCategoryIDs(
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> Set<UUID> {
        let groups = degree.specializationGroups
        guard !groups.isEmpty else { return [] }
        var hidden = Set<UUID>()
        for group in groups {
            let realOptions = effectiveSpecializationOptions(group)
            guard !realOptions.isEmpty else { continue }
            let chosen = chosenOptionTitle(for: group, in: degree)
            let realOptionTitles = Set(realOptions.map(\.title))
            let groupParents = Set(
                realOptions.compactMap {
                    $0.parentSectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
            var currentOwner: String? = nil
            var inRegion = false
            for cat in degree.categories {
                let isGroupMember = cat.specializationGroupKey == group.key
                if isGroupMember, !realOptionTitles.contains(cat.title) {
                    // Group header / parent row — replaced by the picker.
                    hidden.insert(cat.id)
                    inRegion = true
                    continue
                }
                if isGroupMember {
                    inRegion = true
                    currentOwner = cat.title
                    if cat.title != chosen { hidden.insert(cat.id) }
                    continue
                }
                // Non-option row. Attribute it to the most recent option when it is a
                // subordinate requirement of that path. Ownership is by document order
                // because catalogs flatten these rows (no `parentSectionTitle` link).
                guard inRegion, let owner = currentOwner else { continue }
                let parent = cat.parentSectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let parentLinksToGroup = !parent.isEmpty && groupParents.contains(parent)
                let subordinateByOrder = parent.isEmpty && isSpecializationSubRow(cat)
                if parentLinksToGroup || subordinateByOrder {
                    if owner != chosen { hidden.insert(cat.id) }
                } else {
                    // An unrelated top-level section — the specialization block has ended.
                    inRegion = false
                    currentOwner = nil
                }
            }
        }
        return hidden
    }

    /// Stable signature of every specialization pick in view so the `List` can animate row
    /// insert/removals when the user switches a specialization.
    private var specializationSelectionSignature: String {
        specializationSelections
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\u{1e}")
    }

    /// First category index in `degree.categories` that carries the given group key —
    /// used to decide where to inject the picker UI so it only appears once per group.
    private func isFirstAppearance(
        of groupKey: String,
        category: AcademicsAuditPanel.AuditCategory,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> Bool {
        degree.categories.first(where: { $0.specializationGroupKey == groupKey })?.id == category.id
    }

    /// Non-gray palette for requirements panel text and status rendering.
    private enum Palette {
        static let panelBackground = DesignSystem.Colors.bgMain
        static let primaryText = Color.primary
        static let secondaryText = Color.accentColor
        static let subduedText = Color.accentColor.opacity(0.75)
        static let statusNeutral = Color.orange
    }

    /// Panel title (largest) > degree section > requirement section > subsection > category row > courses.
    private enum Typography {
        static let panelTitle = Font.system(size: 18, weight: .semibold)
        static let degreeSection = Font.system(size: 15, weight: .bold)
        static let sectionHeader = Font.system(size: 14, weight: .bold)
        static let categoryTitle = Font.system(size: 12, weight: .medium)
        static let rowMeta = Font.system(size: 12, weight: .medium)
        static let body = Font.system(size: 12, weight: .regular)
        static let bodySemibold = Font.system(size: 12, weight: .semibold)
    }

    /// Aligns expanded course rows with the category title (past the disclosure chevron).
    private var categoryBodyLeadingInset: CGFloat { 22 }

    private var allCategoryIDs: Set<UUID> {
        Set(taggedAuditDegrees.flatMap { degree in
            degree.categories.map(\.id)
        })
    }

    private var firstOptionalProgramIndex: Int? {
        taggedAuditDegrees.firstIndex(where: { !$0.isGraduationRequirement })
    }

    /// The right-canvas Requirements Breakdown. Previously hidden behind the
    /// `academicsSidebarShown` toolbar toggle (the old narrow-inspector design);
    /// in the redesigned layout the breakdown IS the main canvas and is always
    /// visible. The toolbar toggle now controls the left stats sidebar instead.
    var body: some View {
        requirementsSidebar
    }
    
    private var requirementsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title row: "Requirements Breakdown" and "Hide Met" share the same line so the
            // toggle no longer pushes the title above an awkwardly wrapped subheader. The
            // outer VStack still controls vertical rhythm via `bottomPadding`-equivalent
            // spacing right below.
            HStack(alignment: .center, spacing: 12) {
                Text("Requirements Breakdown")
                    .font(Typography.panelTitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Toggle("Hide Met", isOn: $hideCompleted)
                    .toggleStyle(.switch)
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            if isLoading {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            Capsule().fill(Color.primary.opacity(0.12)).frame(width: 180, height: 16)
                            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 240, height: 12)
                            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 200, height: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 16)
                .padding(.horizontal, 24)
            } else if taggedAuditDegrees.isEmpty {
                Text(
                    hasDeclaredPrograms
                        ? String(
                            localized: "academics.requirements_breakdown.empty_declared",
                            defaultValue: "No requirement course lists matched your declared programs yet. Open Settings and run a catalog sync, or check that major and minor names in Profile match the catalog."
                        )
                        : String(
                            localized: "academics.requirements_breakdown.empty_none",
                            defaultValue: "Add a major in your Profile to see your requirements breakdown here."
                        )
                )
                    .font(Typography.body)
                    .foregroundStyle(Palette.subduedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(DesignSystem.Spacing.xl)
            } else {
                List {
                    Color.clear
                        .frame(height: 1)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .id(AcademicsProgramRequirementsScrollID.top)
                        .accessibilityHidden(true)

                    ForEach(taggedAuditDegrees.indices, id: \.self) { degreeIndex in
                        let degree = taggedAuditDegrees[degreeIndex]
                        if let firstOptional = firstOptionalProgramIndex, firstOptional == degreeIndex {
                            optionalProgramsIntroSection
                        }
                        degreeRequirementsSection(degree: degree)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 8)
                .scrollContentBackground(.hidden)
                .scrollTargetLayout()
                .scrollPosition(id: $listScrollAnchorID, anchor: .top)
                .background(Palette.panelBackground)
                .animation(nil, value: expandedCategories)
                .animation(
                    motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86),
                    value: hideCompleted
                )
                .animation(
                    motionReduced ? .easeOut(duration: 0.14) : .spring(response: 0.34, dampingFraction: 0.85),
                    value: specializationSelectionSignature
                )
                .onAppear {
                    hydrateRequirementAndSpecializationSelections()
                }
                .onChange(of: scrollToProgramID) { _, target in
                    scrollRequirements(to: target)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.panelBackground)
    }

    private func scrollRequirements(to target: String?) {
        guard let target, !target.isEmpty else { return }

        func applyScroll(animated: Bool) {
            if animated, !motionReduced {
                withAnimation(.easeInOut(duration: 0.28)) {
                    listScrollAnchorID = target
                }
            } else {
                listScrollAnchorID = target
            }
        }

        // Lazy `List` rows may not exist on the first pass — step through prior sections so
        // the target header is materialized, then land on the requested program.
        var stepIDs: [String] = [AcademicsProgramRequirementsScrollID.top]
        if target != AcademicsProgramRequirementsScrollID.top,
           let targetIndex = taggedAuditDegrees.firstIndex(where: {
               AcademicsProgramRequirementsScrollID.forDegree($0) == target
           }) {
            for degree in taggedAuditDegrees.prefix(targetIndex + 1) {
                stepIDs.append(AcademicsProgramRequirementsScrollID.forDegree(degree))
            }
        } else if target != AcademicsProgramRequirementsScrollID.top {
            stepIDs.append(target)
        }

        applyScroll(animated: false)
        for (offset, stepID) in stepIDs.enumerated() where offset > 0 {
            let delay = 0.04 * Double(offset)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                listScrollAnchorID = stepID
            }
        }

        let finishDelay = 0.04 * Double(max(stepIDs.count, 1)) + 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + finishDelay) {
            applyScroll(animated: !motionReduced)
            scrollToProgramID = nil
        }
    }

    private var optionalProgramsIntroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Additional programs (optional)")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(Palette.secondaryText)
                Text("Only your first declared major counts toward the degree credit total. Requirements below are for planning extra majors or minors.")
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.subduedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 4, trailing: 10))
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func degreeRequirementsSection(degree: AcademicsAuditPanel.AuditDegree) -> some View {
        let scrollID = AcademicsProgramRequirementsScrollID.forDegree(degree)
        Section {
            Color.clear
                .frame(height: 1)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .id(scrollID)
                .accessibilityHidden(true)

            let hiddenSpecializationIDs = hiddenSpecializationCategoryIDs(in: degree)
            ForEach(Array(degree.categories.enumerated()), id: \.element.id) { index, category in
                                let previous = index > 0 ? degree.categories[index - 1] : nil
                                let isHiddenOption = hiddenSpecializationIDs.contains(category.id)

                                if !isHiddenOption,
                                   let section = category.sectionHeader,
                                   section != previous?.sectionHeader {
                                    BreakdownTruncatingLabel(
                                        text: section,
                                        font: Typography.sectionHeader,
                                        color: degree.color,
                                        lineLimit: 2
                                    )
                                        .padding(.top, index == 0 ? 0 : 10)
                                        .padding(.bottom, 2)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 0, trailing: 10))
                                        .listRowSeparator(.hidden)
                                }

                                // Inject a picker row above the first option of each
                                // specialization group so the user can switch which path
                                // counts toward the total. The non-selected paths are hidden
                                // (below) and revealed with animation when the pick changes.
                                if let groupKey = category.specializationGroupKey,
                                   isFirstAppearance(of: groupKey, category: category, in: degree),
                                   let group = degree.specializationGroups.first(where: { $0.key == groupKey })
                                {
                                    specializationPicker(for: group, in: degree)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
                                        .listRowSeparator(.hidden)
                                }

                                if !isHiddenOption {
                                    categoryView(category: category, degree: degree)
                                        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                                        .listRowSeparator(.visible, edges: .bottom)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity
                                            )
                                        )
                                }
                            }
                        } header: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                BreakdownTruncatingLabel(
                                    text: degree.label.uppercased(),
                                    tooltip: degree.label,
                                    font: Typography.degreeSection,
                                    color: degree.color,
                                    lineLimit: 2
                                )
                                if !degree.isGraduationRequirement {
                                    Text("OPTIONAL")
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                        .foregroundStyle(Palette.subduedText)
                                        .tracking(0.5)
                                }
                            }
                            .padding(.bottom, 2)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                        }
    }

    private func hydrateRequirementAndSpecializationSelections() {
        for degree in auditDegrees {
            let degreeKey = degree.programURL.isEmpty ? degree.rawName : degree.programURL
            for group in degree.specializationGroups {
                let cacheKey = selectionCacheKey(degree: degree, groupKey: group.key)
                if specializationSelections[cacheKey] == nil {
                    if let stored = AuditSpecializationStore
                        .selectedOptionTitle(degreeKey: degreeKey, groupKey: group.key) {
                        specializationSelections[cacheKey] = stored
                    } else {
                        specializationSelections[cacheKey] = effectiveSpecializationOptions(group).first?.title
                    }
                }
            }
            for category in degree.categories where categoryAllowsInlineCourseSelection(category) {
                let cacheKey = requirementSelectionCacheKey(degree: degree, categoryTitle: category.title)
                if requirementSelections[cacheKey] == nil {
                    requirementSelections[cacheKey] = AuditRequirementSelectionStore.selectedCodes(
                        degreeKey: degreeKey,
                        categoryTitle: category.title
                    )
                }
            }
            for category in degree.categories {
                if AuditExcludedRequirementStore.isExcluded(degreeKey: degreeKey, categoryTitle: category.title) {
                    excludedCategoryKeys.insert(exclusionCacheKey(degree: degree, categoryTitle: category.title))
                }
            }
        }
    }

    /// Picker row injected at the top of each XOR specialization group. Renders the group
    /// title (e.g., "Specialization") and a Menu listing the option titles. Changing the
    /// selection writes through `AuditSpecializationStore` so downstream credit-progress
    /// calculations see the new pick on the next read.
    @ViewBuilder
    private func specializationPicker(
        for group: AcademicsAuditPanel.SpecializationGroup,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> some View {
        let cacheKey = selectionCacheKey(degree: degree, groupKey: group.key)
        let degreeKey = degree.programURL.isEmpty ? degree.rawName : degree.programURL
        let currentSelection = chosenOptionTitle(for: group, in: degree)

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose your \(group.title.lowercased())")
                    .font(Typography.rowMeta)
                    .foregroundStyle(Palette.subduedText)
                    .lineLimit(1)
                Text(currentSelection)
                    .font(Typography.bodySemibold)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .overlay(alignment: .leading) {
                        BreakdownTooltipCapture(text: currentSelection)
                    }
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(effectiveSpecializationOptions(group)) { option in
                    Button {
                        let selectionAnimation: Animation = motionReduced
                            ? .easeOut(duration: 0.12)
                            : .spring(response: 0.32, dampingFraction: 0.85)
                        withAnimation(selectionAnimation) {
                            specializationSelections[cacheKey] = option.title
                        }
                        AuditSpecializationStore.setSelectedOptionTitle(
                            option.title,
                            degreeKey: degreeKey,
                            groupKey: group.key
                        )
                        // Tell the rest of the app a spec choice changed so any open
                        // major-card / credit-progress view recomputes its totals.
                        NotificationCenter.default.post(
                            name: .auditSpecializationSelectionChanged,
                            object: nil,
                            userInfo: [
                                "degreeKey": degreeKey,
                                "groupKey": group.key,
                                "selectedTitle": option.title
                            ]
                        )
                    } label: {
                        if option.title == currentSelection {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Change")
                        .font(Typography.rowMeta)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    @ViewBuilder
    private func categoryView(
        category: AcademicsAuditPanel.AuditCategory,
        degree: AcademicsAuditPanel.AuditDegree,
        isDimmed: Bool = false
    ) -> some View {
        let items = category.items
        let parsed = RequirementBreakdownParser.parseTitle(category.displayTitle ?? category.title)
        let displayTitle = parsed.displayTitle
        let listSubheader = RequirementBreakdownParser.isListStyleSubheader(displayTitle)
        let hideRowTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let completedCredits = RequirementBreakdownParser.sumCompletedCredits(for: category)
        let progressTarget = RequirementBreakdownParser.progressTarget(for: category)
        let isExcluded = isCategoryExcluded(category, in: degree)
        let isDone = !isExcluded && RequirementBreakdownParser.isCategoryDone(category: category)
        let isExpanded = expandedCategories.contains(category.id)
        let hasProgressNumbers = progressTarget > 0 || completedCredits > 0
        let isSubsectionRollup = !hasProgressNumbers && category.selectCount > 0 && items.isEmpty
        let progressFraction: Double = {
            guard progressTarget > 0 else { return 0 }
            return min(1.0, Double(completedCredits) / Double(progressTarget))
        }()
        let trailingLabel: String? = {
            if progressTarget > 0 {
                return "\(completedCredits)/\(progressTarget) cr"
            }
            return nil
        }()
        let trailingTooltip: String = {
            var lines: [String] = [category.title]
            if let trailingLabel { lines.append(trailingLabel) }
            if progressTarget > 0 {
                lines.append(
                    String(
                        localized: "academics.requirements_breakdown.tooltip_progress",
                        defaultValue: "Progress: \(completedCredits) of \(progressTarget) credits from your courses count toward this row."
                    )
                )
            }
            return lines.joined(separator: "\n")
        }()
        // Collapsed chip preview disabled — pills below the title shifted the row on expand.
        let bodyInset = categoryBodyLeadingInset

        if !hideCompleted || !isDone {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Button(action: {
                        if isExpanded {
                            expandedCategories.remove(category.id)
                        } else {
                            expandedCategories.insert(category.id)
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 14, height: 14, alignment: .center)
                            .animation(
                                motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.80),
                                value: isExpanded
                            )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        if !hideRowTitle {
                            BreakdownTruncatingLabel(
                                text: displayTitle,
                                font: Typography.categoryTitle,
                                color: listSubheader ? Palette.secondaryText : Palette.primaryText,
                                lineLimit: listSubheader ? 2 : 1
                            )
                        }

                        if category.rowKind == .chooseOne {
                            Text("Complete one option (not both)")
                                .font(Typography.rowMeta)
                                .foregroundStyle(Palette.secondaryText)
                        } else if categoryAllowsInlineCourseSelection(category) {
                            let pickN = max(1, category.selectCount > 0 ? category.selectCount : 1)
                            Text(pickN == 1 ? "Tap a course to mark your choice" : "Tap up to \(pickN) courses")
                                .font(Typography.rowMeta)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isExcluded {
                        ExcludedRequirementBadge()
                    } else if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundStyle(AcademicsStatusPalette.completedDot)
                    }

                    Spacer(minLength: 8)

                    if isExcluded {
                        if let trailingLabel {
                            Text(trailingLabel)
                                .font(Typography.rowMeta)
                                .foregroundStyle(Palette.subduedText)
                                .strikethrough(true, color: Palette.subduedText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .help("Not counted toward the credit goal")
                        }
                    } else if !isDone && progressTarget > 0 {
                        InlineCategoryProgressBar(fraction: progressFraction)
                            .frame(width: 80)
                    }

                    if isExcluded {
                        EmptyView()
                    } else if let trailingLabel {
                        Text(trailingLabel)
                            .font(Typography.rowMeta)
                            .foregroundStyle(isDone ? Color.accentColor : Palette.secondaryText)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: true, vertical: false)
                            .help(trailingTooltip)
                    } else if isSubsectionRollup {
                        BreakdownTruncatingLabel(
                            text: String(localized: "academics.requirements_breakdown.subsection_rollup", defaultValue: "Included in main requirement"),
                            font: Typography.rowMeta,
                            color: Palette.subduedText,
                            lineLimit: 1
                        )
                    }

                    if category.allowsManualFulfillment {
                        Button {
                            let university = (
                                collegePersistence.getActiveUniversity()?.name ?? ""
                            ).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !university.isEmpty else { return }
                            modalCoordinator.activeModal = .assignRequirementCourse(
                                ModalCoordinator.RequirementCourseAssignment(
                                    universityName: university,
                                    programURL: degree.programURL,
                                    requirementCategory: category.title
                                )
                            )
                        } label: {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Search the course catalog to assign a course")
                    }
                }
                .frame(minHeight: 28)

                if isExpanded {
                    let selected = selectedCodes(for: category, in: degree)
                    let selectionEnabled = categoryAllowsInlineCourseSelection(category)
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            let selectable = selectionEnabled && isSelectableListedCourse(item, category: category)
                            let itemDimmed = isItemDimmedForSelection(
                                item,
                                category: category,
                                selected: selected,
                                in: degree
                            )
                            CourseProgressRow(
                                code: item.code,
                                title: item.title,
                                credits: item.credits,
                                grade: item.grade,
                                planProgress: item.planProgress,
                                transferSourceLabel: item.transferSourceLabel,
                                scheduledTermLabel: item.scheduledTermLabel,
                                selectionMode: selectable,
                                isSelected: selected.contains(
                                    item.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                ),
                                isDimmed: itemDimmed,
                                onSelect: selectable ? {
                                    toggleRequirementSelection(item: item, category: category, degree: degree)
                                } : nil,
                                onOpen: {
                                    modalCoordinator.activeModal = .courseDashboard(
                                        courseCode: item.code,
                                        defaultCourseName: item.title,
                                        defaultCreditsText: item.credits,
                                        courseID: nil
                                    )
                                }
                            )
                        }
                    }
                    .padding(.leading, bodyInset)
                }
            }
            .opacity(isDimmed ? 0.42 : (isExcluded ? 0.6 : 1))
            .saturation(isDimmed ? 0.6 : (isExcluded ? 0.5 : 1))
            .allowsHitTesting(!isDimmed)
            .accessibilityLabel(
                isDimmed
                    ? "\(category.title), not selected — alternative path"
                    : (isExcluded ? "\(category.title), not counted toward the credit goal" : category.title)
            )
            .contextMenu {
                Button {
                    toggleCategoryExcluded(category, in: degree)
                } label: {
                    if isExcluded {
                        Label("Count toward credit goal", systemImage: "checkmark.circle")
                    } else {
                        Label("Don't count toward credit goal", systemImage: "minus.circle")
                    }
                }
            }
            .animation(
                motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.82),
                value: isDone
            )
            .animation(
                motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.84),
                value: isDimmed
            )
            .onChange(of: isDone) { wasDone, nowDone in
                if nowDone, !wasDone {
                    _ = withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.28, dampingFraction: 0.84)) {
                        expandedCategories.insert(category.id)
                    }
                }
            }
            .onDrop(
                of: [UTType.text],
                isTargeted: category.allowsManualFulfillment
                    ? Binding(
                        get: { dropTargetCategoryID == category.id },
                        set: { targeted in
                            dropTargetCategoryID = targeted ? category.id : nil
                        }
                    )
                    : .constant(false)
            ) { providers in
                guard category.allowsManualFulfillment else { return false }
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { object, _ in
                    guard let object else { return }
                    let code = PlannerCourseDragPayload.decode(object).code
                    guard !code.isEmpty else { return }
                    Task { @MainActor in
                        let university = (
                            collegePersistence.getActiveUniversityName() ?? ""
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                        try? RequirementFulfillmentStore.assign(
                            context: collegePersistence.profileContext,
                            university: university,
                            programURL: degree.programURL,
                            requirementCategory: category.title,
                            courseCode: code
                        )
                    }
                }
                return true
            }
            .overlay {
                if dropTargetCategoryID == category.id {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
        }
    }
}

extension Notification.Name {
    /// Posted whenever the user picks a different specialization option for a degree. Listeners
    /// (chiefly the major card's credit-progress calculator) re-read
    /// `AuditSpecializationStore` and refresh their displayed totals so the Credits Earned
    /// / Total Credit Progress numbers track the chosen path.
    static let auditSpecializationSelectionChanged = Notification.Name(
        "college.audit.specializationSelectionChanged"
    )

    /// Posted whenever the user tags / untags a requirement category as not counting toward the
    /// credit goal. The credit-progress calculators re-read `AuditExcludedRequirementStore` and
    /// refresh the bottom summary strip and per-program totals.
    static let auditRequirementExclusionChanged = Notification.Name(
        "college.audit.requirementExclusionChanged"
    )
}


/// Small pill marking a requirement the user excluded from the credit goal (prerequisite
/// satisfied, waived by the school, etc.).
struct ExcludedRequirementBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "minus.circle.fill")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
            Text("Not counted")
                .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.secondary.opacity(0.14))
        )
        .help("Not counted toward the credit goal. Right-click to re-include it.")
        .accessibilityLabel("Not counted toward the credit goal")
    }
}

/// Per-course row in the Requirements Breakdown. Matches the Figma's rich layout:
/// a small status bullet → course code (accent) → full course title → letter grade
/// (accent) → credit count. The bullet color is driven by `AcademicsStatusPalette`
/// so it stays in lockstep with the semester pills and the bottom summary strip.
struct CourseProgressRow: View {
    var code: String
    var title: String
    var credits: String
    var grade: String?
    var planProgress: RequirementPlanProgress
    var transferSourceLabel: String? = nil
    var scheduledTermLabel: String? = nil
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var isDimmed: Bool = false
    var onSelect: (() -> Void)? = nil
    /// Opens the full Course Page. Used when the row isn't in selection mode.
    var onOpen: (() -> Void)? = nil

    private var trimmedScheduledTerm: String? {
        let t = (scheduledTermLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var paletteState: AcademicsStatusPalette.State {
        AcademicsStatusPalette.state(for: planProgress)
    }

    private var bulletColor: Color {
        AcademicsStatusPalette.dot(for: paletteState)
    }

    /// Normalize the catalog's credit string to something compact ("3 cr", "3-4 cr").
    /// If the catalog returns just a number we append the unit; if it's already labeled
    /// or contains a range we leave it alone modulo trimming.
    private var creditsLabel: String {
        let trimmed = credits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if lower.contains("cr") || lower.contains("credit") {
            return trimmed
        }
        return "\(trimmed) cr"
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedGrade: String? {
        let g = (grade ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? nil : g
    }

    /// Pre-baked tooltip so hovering surfaces the full code + title + grade + credits even
    /// when the title gets truncated on a narrow canvas.
    private var accessibilityTooltip: String {
        var parts: [String] = [code]
        if !trimmedTitle.isEmpty { parts.append(trimmedTitle) }
        if let g = trimmedGrade { parts.append("Grade: \(g)") }
        if !creditsLabel.isEmpty { parts.append(creditsLabel) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
                    .padding(.top, 1)
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
            } else {
                Circle()
                    .fill(bulletColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }

            Text(code)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .overlay {
                    BreakdownTooltipCapture(text: code)
                }

            if let tag = transferSourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
                Text(tag)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityLabel("Transfer source: \(tag)")
            }

            if !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        BreakdownTooltipCapture(text: trimmedTitle)
                    }
            }

            Spacer(minLength: 8)

            if let term = trimmedScheduledTerm {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                        .font(DesignSystem.Fonts.main(size: 9, weight: .semibold))
                    Text(term)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(AcademicsStatusPalette.dot(for: paletteState))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AcademicsStatusPalette.dot(for: paletteState).opacity(0.12))
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Scheduled for \(term)")
            }

            if let g = trimmedGrade {
                Text(g)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !creditsLabel.isEmpty {
                Text(creditsLabel)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .opacity(isDimmed ? 0.38 : 1)
        .saturation(isDimmed ? 0.55 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: trimmedScheduledTerm)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionMode {
                onSelect?()
            } else {
                onOpen?()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            selectionMode
                ? "\(accessibilityTooltip) — \(isSelected ? "selected" : isDimmed ? "not selected" : "tap to select")"
                : accessibilityTooltip
        )
        .accessibilityAddTraits((selectionMode || onOpen != nil) ? .isButton : [])
        .draggable(
            PlannerCourseDragPayload(code: code, title: trimmedTitle, credits: credits).encoded
        ) {
            HStack(spacing: 6) {
                Circle().fill(bulletColor).frame(width: 6, height: 6)
                Text(code)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                if !creditsLabel.isEmpty {
                    Text(creditsLabel)
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
        }
    }
}

#if os(macOS)
/// Invisible AppKit layer so truncated List labels show the full string on hover (SwiftUI `.help` is unreliable in `List`).
struct BreakdownTooltipCapture: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipHostView {
        TooltipHostView()
    }

    func updateNSView(_ nsView: TooltipHostView, context: Context) {
        nsView.toolTip = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    final class TooltipHostView: NSView {
        override var isOpaque: Bool { false }

        override func draw(_ dirtyRect: NSRect) {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }
    }
}
#else
struct BreakdownTooltipCapture: View {
    let text: String
    var body: some View { Color.clear.help(text) }
}
#endif

/// Single- or multi-line label that truncates with "…" and reveals the full text on hover.
struct BreakdownTruncatingLabel: View {
    let text: String
    var tooltip: String? = nil
    var font: Font
    var color: Color
    var lineLimit: Int = 1

    private var tooltipText: String { tooltip ?? text }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .leading) {
                BreakdownTooltipCapture(text: tooltipText)
            }
            .accessibilityLabel(tooltipText)
    }
}



struct InlineCategoryProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.7), Color.accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0.0, fraction)))))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Specialization Detection + Selection Persistence

/// Stamps `specializationGroupKey` on categories that look like options in a "choose one of
/// the following specializations" XOR group. Detection runs at audit-load time so the same
/// catalog data drives both the sidebar picker and the credit-total filter.
///
/// Heuristic order (least → most specific):
/// 1. Category description text — looks for "choose one", "select one", "choose one of the
///    following", "select one of the following" (case-insensitive).
/// 2. Category title — categories whose displayed title contains "Specialization",
///    "Concentration", "Track", or "Option" are bucketed together (catalogs frequently use
///    these labels for XOR groups even without explicit "choose one" phrasing).
///
/// When two or more categories trip the same signal, they're merged into a single group
/// keyed by the lowercase keyword (`"specialization"`, `"concentration"`, …) and presented
/// as a picker. Single hits are left alone — a lone "Technical Specialization" with no
/// sibling means there's no choice to make and grouping would just confuse the UI.
enum SpecializationGroupDetector {
    /// Keywords whose presence in a category title signals an XOR option label. Order
    /// matters: when a category title contains more than one keyword, the first match wins.
    static let xorTitleKeywords: [(keyword: String, displayTitle: String)] = [
        ("specialization", "Specialization"),
        ("concentration",  "Concentration"),
        ("track",          "Track"),
        ("pathway",        "Pathway"),
        ("emphasis",       "Emphasis"),
        ("option",         "Option")
    ]

    /// Phrases that indicate the description bracketing a set of XOR option categories.
    static let xorDescriptionPhrases: [String] = [
        "choose one of the following",
        "select one of the following",
        "select one of",
        "choose one of",
        "select one",
        "choose one"
    ]

    static func tagSpecializations(
        categories: [AcademicsAuditPanel.AuditCategory],
        groupDescriptions: [String: String]
    ) -> [AcademicsAuditPanel.AuditCategory] {
        guard !categories.isEmpty else { return categories }

        // Step 1: bucket by title keyword.
        var keywordHits: [Int: (key: String, title: String)] = [:]
        for (idx, cat) in categories.enumerated() {
            let lower = cat.title.lowercased()
            for (kw, displayTitle) in xorTitleKeywords where lower.contains(kw) {
                keywordHits[idx] = (kw, displayTitle)
                break
            }
        }

        // Step 2: surface description signals so they can override (or supplement) title hits.
        var explicitHits: Set<Int> = []
        for (idx, cat) in categories.enumerated() {
            let desc = (groupDescriptions[cat.title] ?? "").lowercased()
            if xorDescriptionPhrases.contains(where: { desc.contains($0) }) {
                explicitHits.insert(idx)
            }
        }

        var groupAssignments: [Int: String] = [:]
        var groupDisplayTitle: [String: String] = [:]
        let keywordGroupedIndices = Dictionary(grouping: keywordHits.keys) { idx in
            keywordHits[idx]?.key ?? ""
        }
        for (key, indices) in keywordGroupedIndices where indices.count >= 2 {
            // At least two siblings required — a lone "Technical Specialization" with no
            // peer isn't an XOR group and forcing a picker on it would just confuse the user.
            let display = keywordHits[indices.first ?? -1]?.title ?? "Specialization"
            for idx in indices {
                groupAssignments[idx] = key
                groupDisplayTitle[key] = display
            }
        }

        // Fallback: title heuristic didn't fire, but explicit "choose one" phrasing showed up
        // on two or more categories. Bundle them under a generic "choose-one" key.
        if groupAssignments.isEmpty && explicitHits.count >= 2 {
            let key = "choose-one"
            for idx in explicitHits {
                groupAssignments[idx] = key
            }
            groupDisplayTitle[key] = "Specialization"
        }

        guard !groupAssignments.isEmpty else { return categories }

        return categories.enumerated().map { (idx, cat) -> AcademicsAuditPanel.AuditCategory in
            guard let groupKey = groupAssignments[idx] else { return cat }
            return AcademicsAuditPanel.AuditCategory(
                title: cat.title,
                items: cat.items,
                selectCount: cat.selectCount,
                creditsRequired: cat.creditsRequired,
                catalogCreditsRequired: cat.catalogCreditsRequired,
                descriptionCredits: cat.descriptionCredits,
                headerCredits: cat.headerCredits,
                rowKind: cat.rowKind,
                parentSectionTitle: cat.parentSectionTitle,
                displayTitle: cat.displayTitle,
                sectionHeader: cat.sectionHeader,
                indentLevel: cat.indentLevel,
                allowsManualFulfillment: cat.allowsManualFulfillment,
                specializationGroupKey: groupKey,
                specializationGroupTitle: groupDisplayTitle[groupKey] ?? "Specialization"
            )
        }
    }
}

/// Tiny UserDefaults-backed store for the user's per-(degree, group) specialization picks.
/// Keyed by `(programURL or rawName, groupKey)` so a Mathematics minor's "Concentration"
/// pick never collides with a Cyber Defense, M.S. "Specialization" pick.
///
/// The store is namespaced so we can purge / migrate later without touching unrelated app
/// preferences. The audit sidebar reads/writes through this; credit-progress calculators
/// in `CollegePersistence` read through the same key when summing earned/required credits.
enum AuditSpecializationStore {
    private static let prefix = "academics.audit.specialization.v1."

    private static func key(degreeKey: String, groupKey: String) -> String {
        let degreeNorm = degreeKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(prefix)\(degreeNorm)|\(groupKey)"
    }

    /// Returns the user's chosen category title within the group, or nil if they haven't
    /// picked yet (caller should default to the first option).
    static func selectedOptionTitle(degreeKey: String, groupKey: String) -> String? {
        let stored = UserDefaults.standard.string(forKey: key(degreeKey: degreeKey, groupKey: groupKey))
        return stored?.isEmpty == false ? stored : nil
    }

    static func setSelectedOptionTitle(_ title: String, degreeKey: String, groupKey: String) {
        UserDefaults.standard.set(title, forKey: key(degreeKey: degreeKey, groupKey: groupKey))
    }

    /// Returns the set of "non-chosen" category titles for a given degree, which credit
    /// calculators use as a filter when summing earned/required credits. Pass the full
    /// degree object so the helper can resolve the default (first option) when the user
    /// hasn't picked yet.
    static func nonSelectedOptionTitles(for degree: AcademicsAuditPanel.AuditDegree) -> Set<String> {
        var out = Set<String>()
        let degreeKey = degree.programURL.isEmpty ? degree.rawName : degree.programURL
        for group in degree.specializationGroups {
            let chosen = selectedOptionTitle(degreeKey: degreeKey, groupKey: group.key)
                ?? group.options.first?.title
                ?? ""
            for option in group.options where option.title != chosen {
                out.insert(option.title)
            }
        }
        return out
    }
}

/// User-tagged requirement categories that should NOT count toward a program's credit goal —
/// e.g. a "Knowledge Courses" prerequisite the school waived because the student satisfied it
/// through prior experience / transfer. Keyed by `(degreeKey, categoryTitle)` like the
/// specialization store. The credit calculators in `CollegePersistence` read through the same
/// keys and drop these rows before summing required / earned credits.
enum AuditExcludedRequirementStore {
    private static let defaultsKey = "academics.audit.excludedCategories.v1"

    private static func normDegree(_ degreeKey: String) -> String {
        degreeKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func normCategory(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func load() -> [String: [String]] {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]]) ?? [:]
    }
    private static func save(_ dict: [String: [String]]) {
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    static func isExcluded(degreeKey: String, categoryTitle: String) -> Bool {
        let d = normDegree(degreeKey)
        guard !d.isEmpty else { return false }
        return (load()[d] ?? []).contains(normCategory(categoryTitle))
    }

    static func setExcluded(_ excluded: Bool, degreeKey: String, categoryTitle: String) {
        let d = normDegree(degreeKey)
        let c = normCategory(categoryTitle)
        guard !d.isEmpty, !c.isEmpty else { return }
        var dict = load()
        var titles = Set(dict[d] ?? [])
        if excluded { titles.insert(c) } else { titles.remove(c) }
        dict[d] = titles.isEmpty ? nil : Array(titles)
        save(dict)
    }

    /// Excluded category titles (lowercased) for any of the supplied candidate degree keys.
    /// The audit UI may persist under a program URL while a credit calculator resolves the
    /// program by display name (or vice-versa), so callers pass every key they know.
    static func excludedCategoryTitles(forAnyDegreeKey keys: [String]) -> Set<String> {
        let dict = load()
        var out = Set<String>()
        for key in keys {
            let d = normDegree(key)
            guard !d.isEmpty, let titles = dict[d] else { continue }
            out.formUnion(titles)
        }
        return out
    }
}
