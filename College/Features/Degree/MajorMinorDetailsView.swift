// MajorMinorDetailsView.swift
// Feature: Degree
// Purpose: Degree module — MajorMinorDetailsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import Combine
import os
import UniformTypeIdentifiers

/// Main-panel content shown when the user clicks "View Details" for their Major.
///
/// This view intentionally matches the provided design: header (title + badge + subtitle + actions),
/// three stat cards, then requirements sections with a table-style list.
struct MajorMinorDetailsView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
#if DEBUG
    private static let perfLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "Perf.Requirements")
#endif
    private static let courseCodeRegex = try? NSRegularExpression(
        pattern: "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4})\\b"
    )
    private static let creditsRequirementRegex = try? NSRegularExpression(
        pattern: #"\((\d+(?:\.\d+)?)\s*(?:[-–]\s*(\d+(?:\.\d+)?))?\s*credits?\)"#,
        options: [.caseInsensitive]
    )
    private var collegePersistence: CollegePersistence { container.persistence }
    private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
    @State private var plannerRefreshToken = 0

    private var plans: [PlannerPlan] {
        _ = plannerRefreshToken
        return ProfilePlannerReadBridge.plans(collegePersistence: collegePersistence)
    }

    private var profile: Profile? {
        _ = plannerRefreshToken
        return ProfilePlannerReadBridge.primaryProfile(collegePersistence: collegePersistence)
    }

    enum ProgramKind {
        case major
        case minor
    }

    let majorDisplay: String
    let onBack: () -> Void
    let showsBackButton: Bool
    let embedInParentScrollView: Bool
    let programKind: ProgramKind

    @State private var isLoadingRequirements: Bool = false
    @State private var requirementsError: String? = nil
    @State private var fetchedRequirements: [CatalogDegreeRequirement] = []
    @State private var activeProgramURL: String = ""

    @State private var isGenEdDropTargeted: Bool = false
    @State private var fulfillmentDropTargetSectionID: String? = nil

    @State private var isGPACalculatorPresented: Bool = false
    @State private var removedCourseCodes: Set<String> = []
    @StateObject private var detailsViewModel = MajorDetailsViewModel()

    private var majorTitle: String {
        let s = majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { return s }
        return programKind == .minor ? "Select Minor" : "Select Major"
    }

    private var badgeText: String {
        programKind == .minor ? "MINOR" : "MAJOR"
    }

    private var accentColor: Color {
        programKind == .minor ? DesignSystem.Colors.accent : DesignSystem.Colors.info
    }

    private var majorSubtitle: String {
        // Keep this derived from the profile/department so it stays consistent with what the user selected.
        let level = collegePersistence.primaryDegreeLevel(default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeType = (collegePersistence.primaryDegreeType() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let department = (collegePersistence.primaryDepartment() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let university = (profile?.collegeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var left = ""
        if programKind == .minor {
            left = "Minor"
        } else {
            if !degreeType.isEmpty {
                // Mirror the mock's style: "Bachelor of Science" rather than "BS" where possible.
                if degreeType.uppercased() == "BS" {
                    left = "Bachelor of Science"
                } else if degreeType.uppercased() == "BA" {
                    left = "Bachelor of Arts"
                } else {
                    left = degreeType
                }
            } else if !level.isEmpty {
                left = level
            }
        }

        var right = ""
        if !university.isEmpty, !department.isEmpty,
           let school = collegePersistence.schoolForDepartment(universityName: university, departmentName: department) {
            right = school
        } else if !department.isEmpty {
            right = department
        }

        if !left.isEmpty, !right.isEmpty {
            return "\(left) • \(right)"
        }
        return [left, right].first(where: { !$0.isEmpty }) ?? ""
    }

    var body: some View {
        Group {
            if embedInParentScrollView {
                VStack(spacing: 0) {
                    header
                    contentStack
                        .padding(24)
                }
                .background(DesignSystem.Colors.bgMain)
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        contentStack
                            .padding(24)
                    }
                    .background(DesignSystem.Colors.bgMain)
                }
                .background(DesignSystem.Colors.bgMain)
            }
        }
        .task(id: requirementsTaskKey) {
            await refreshRequirementsIfNeeded()
        }
        .onChange(of: memoizedSectionsCacheKey) { _, _ in
            refreshMemoizedSectionPresentations()
        }
        .onAppear {
            refreshMemoizedSectionPresentations()
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            plannerRefreshToken &+= 1
        }
        .background {
            ProfilePlannerQueryHost {
                plannerRefreshToken &+= 1
            }
        }
    }

    private var memoizedSectionsCacheKey: String {
        [
            requirementsTaskKey,
            String(fetchedRequirements.count),
            String(removedCourseCodes.count),
            String(isLoadingRequirements),
            requirementsError ?? "",
        ].joined(separator: "|")
    }

    private func refreshMemoizedSectionPresentations() {
        let claimed = claimedCourseCodes(in: fetchedRequirements)
        let presentations = dynamicRequirementSections.map { section -> MajorDetailsViewModel.SectionPresentation in
            let baseRows = section.rowsOverride ?? buildRows(from: section.requirements)
            let rows = filterRemovedRows(
                resolvedRowsForOpenEndedSection(baseRows: baseRows, claimedCourseCodes: claimed)
            )
            let creditsRequirement = creditsRequirementForSection(title: section.title, requirements: section.requirements)
            let completedCredits = completedCreditsInRows(rows)
            let completedText = section.completedTextOverride
                ?? creditsProgressText(completedCredits: completedCredits, requirement: creditsRequirement)
            return MajorDetailsViewModel.SectionPresentation(
                id: section.id,
                accent: section.accent,
                title: section.title,
                completedText: completedText,
                rows: rows,
                isGenEdSection: section.id == "gened-manual",
                allowsFulfillmentDrop: section.allowsFulfillmentDrop,
                fulfillmentCategoryKey: section.fulfillmentCategoryKey
            )
        }
        detailsViewModel.update(presentations: presentations, cacheKey: memoizedSectionsCacheKey)
    }

    private var contentStack: some View {
        VStack(spacing: 24) {
            statsRow

            VStack(spacing: 28) {
                ForEach(detailsViewModel.presentations) { section in
                    RequirementsSection(
                        accent: section.accent,
                        title: section.title,
                        completedText: section.completedText,
                        rows: section.rows,
                        showsAddCourseButton: true,
                        showsDropTarget: section.isGenEdSection || section.allowsFulfillmentDrop,
                        dropHintText: section.isGenEdSection
                            ? "Drop to add to General Education"
                            : "Drop to assign course to this requirement",
                        onTapAddCourse: {
                            if section.isGenEdSection {
                                modalCoordinator.activeModal = .addGenEdCourse
                            } else {
                                modalCoordinator.activeModal = .addCatalogCourseGlobal(tagAsGenEd: false)
                            }
                        },
                        isDropTargeted: Binding(
                            get: {
                                if section.isGenEdSection { return isGenEdDropTargeted }
                                return fulfillmentDropTargetSectionID == section.id
                            },
                            set: { targeted in
                                if section.isGenEdSection {
                                    isGenEdDropTargeted = targeted
                                } else if targeted {
                                    fulfillmentDropTargetSectionID = section.id
                                } else if fulfillmentDropTargetSectionID == section.id {
                                    fulfillmentDropTargetSectionID = nil
                                }
                            }
                        ),
                        onDropCourseCode: { droppedCode in
                            if section.isGenEdSection {
                                handleGenEdDrop(courseCode: droppedCode)
                            } else if section.allowsFulfillmentDrop,
                                      let categoryKey = section.fulfillmentCategoryKey {
                                handleRequirementFulfillmentDrop(
                                    courseCode: droppedCode,
                                    requirementCategory: categoryKey
                                )
                            }
                        },
                        onSelectCourse: { row in
                            let normalized = normalizeCode(row.code)
                            guard !normalized.isEmpty else { return }
                            guard !normalized.hasPrefix("SELECT ") else { return }

                            modalCoordinator.activeModal = .editCourse(
                                ModalCoordinator.CourseEditSelection(
                                    courseCode: normalized,
                                    defaultCourseName: row.title,
                                    defaultCreditsText: row.credits
                                )
                            )
                        },
                        onOpenDashboard: { row in
                            let normalized = normalizeCode(row.code)
                            guard !normalized.isEmpty else { return }
                            guard !normalized.hasPrefix("SELECT ") else { return }

                            modalCoordinator.activeModal = .courseDashboard(
                                courseCode: normalized,
                                defaultCourseName: row.title,
                                defaultCreditsText: row.credits,
                                courseID: nil
                            )
                        },
                        onDeleteCourse: { code in
                            let normalized = normalizeCode(code)
                            if !normalized.isEmpty {
                                removedCourseCodes.insert(normalized)
                            }
                            deletePlannedCourseAndOverrides(for: code)
                        },
                        availableSemesters: availablePlanSemesters,
                        onChangeStatus: { code, newStatus in
                            let normalized = normalizeCode(code)
                            guard !normalized.isEmpty else { return }
                            let existing = courseOverride(for: normalized)
                            collegePersistence.upsertCourseOverride(
                                courseCode: normalized,
                                courseName: existing?.courseName,
                                credits: existing?.credits,
                                professor: existing?.professor,
                                semesterText: existing?.semesterText,
                                status: newStatus.displayString,
                                grade: existing?.grade,
                                gradingType: existing?.gradingType ?? "Standard",
                                externalURL: existing?.externalURL
                            )
                            if let course = plannedCourse(for: normalized) {
                                course.status = newStatus.displayString
                                course.isCompleted = (newStatus == .completed)
                                collegePersistence.save()
                            }
                        },
                        onChangeSemester: { row, sem in
                            let normalized = normalizeCode(row.code)
                            guard !normalized.isEmpty else { return }
                            if let sem {
                                if let course = plannedCourse(for: normalized) {
                                    course.semester = sem
                                    collegePersistence.save()
                                } else {
                                    let creditsInt = Int(row.credits.replacingOccurrences(of: ".0", with: "")) ?? 3
                                    _ = collegePersistence.addCourse(
                                        to: sem,
                                        code: normalized,
                                        name: row.title,
                                        credits: creditsInt,
                                        status: "Planned",
                                        gradingType: "Standard",
                                        professor: nil
                                    )
                                }
                                let semLabel: String = {
                                    let season = sem.season.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let year = Int(sem.year)
                                    guard !season.isEmpty, year > 0 else { return "" }
                                    return "\(season) \(year)"
                                }()
                                let existing = courseOverride(for: normalized)
                                collegePersistence.upsertCourseOverride(
                                    courseCode: normalized,
                                    courseName: existing?.courseName,
                                    credits: existing?.credits,
                                    professor: existing?.professor,
                                    semesterText: semLabel,
                                    status: existing?.status ?? "Planned",
                                    grade: existing?.grade,
                                    gradingType: existing?.gradingType ?? "Standard",
                                    externalURL: existing?.externalURL
                                )
                            } else {
                                // Unassign: detach from semester
                                if let course = plannedCourse(for: normalized) {
                                    course.semester = nil
                                    collegePersistence.save()
                                }
                                let existing = courseOverride(for: normalized)
                                collegePersistence.upsertCourseOverride(
                                    courseCode: normalized,
                                    courseName: existing?.courseName,
                                    credits: existing?.credits,
                                    professor: existing?.professor,
                                    semesterText: nil,
                                    status: existing?.status ?? "Not Planned",
                                    grade: existing?.grade,
                                    gradingType: existing?.gradingType ?? "Standard",
                                    externalURL: existing?.externalURL
                                )
                            }
                        }
                    )
                }

                if shouldShowCapstoneCard {
                    capstone
                }
            }
        }
    }

    init(
        majorDisplay: String,
        onBack: @escaping () -> Void,
        showsBackButton: Bool = true,
        embedInParentScrollView: Bool = false,
        programKind: ProgramKind = .major
    ) {
        self.majorDisplay = majorDisplay
        self.onBack = onBack
        self.showsBackButton = showsBackButton
        self.embedInParentScrollView = embedInParentScrollView
        self.programKind = programKind
    }

    private var requirementsTaskKey: String {
        let kind = (programKind == .minor) ? "minor" : "major"
        let dt = (programKind == .minor)
            ? "Minor"
            : (collegePersistence.primaryDegreeType() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let major = majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return [kind, dt, major].joined(separator: "|")
    }

    @MainActor
    private func refreshRequirementsIfNeeded() async {
#if DEBUG
        let spid = OSSignpostID(log: Self.perfLog)
        os_signpost(.begin, log: Self.perfLog, name: "RequirementsRefresh", signpostID: spid)
        defer { os_signpost(.end, log: Self.perfLog, name: "RequirementsRefresh", signpostID: spid) }
#endif
        let logger = DebugLogger.shared
        requirementsError = nil
        isLoadingRequirements = false
        
        let isMinor = (programKind == .minor)
        logger.log("[MajorDetails] Starting requirements refresh")
        logger.log("[MajorDetails] kind=\(isMinor ? "minor" : "major") display='\(majorDisplay)'")
        logger.log("[MajorDetails] Profile degreeType: '\(collegePersistence.primaryDegreeType() ?? "nil")'")

        guard let programURL = collegePersistence.resolveProgramProgramURL(programDisplay: majorDisplay, isMinor: isMinor) else {
            requirementsError = isMinor
                ? "No program URL found for the selected minor. Re-run the program import for this university."
                : "No program URL found for the selected major. Re-run the program import for this university."
            fetchedRequirements = []
            return
        }

        let degreeTypeForScrape: String = {
            if isMinor { return "Minor" }
            let dt = (collegePersistence.primaryDegreeType() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return dt.isEmpty ? "Unknown" : dt
        }()

        // Show whatever we already have cached in local store immediately.
        // Then refresh in the background and update once the refresh completes.
        let cachedRequirements = collegePersistence.getDegreeRequirements(programURL: programURL, degreeType: degreeTypeForScrape)
        if !cachedRequirements.isEmpty {
            fetchedRequirements = cachedRequirements
            activeProgramURL = programURL
            isLoadingRequirements = false
            refreshMemoizedSectionPresentations()
        } else {
            isLoadingRequirements = true
        }

        _ = await collegePersistence.refreshProgramRequirementsIfNeeded(
            programURL: programURL,
            major: majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines),
            degreeType: degreeTypeForScrape,
            force: false
        )

        if Task.isCancelled {
            isLoadingRequirements = false
            return
        }

        fetchedRequirements = collegePersistence.getDegreeRequirements(programURL: programURL, degreeType: degreeTypeForScrape)
        activeProgramURL = programURL
        logger.log("[MajorDetails] Fetched \(fetchedRequirements.count) requirement entities")

        isLoadingRequirements = false
        refreshMemoizedSectionPresentations()
        
        if fetchedRequirements.isEmpty {
            logger.log("[MajorDetails] ❌ No requirements found in local store")
            requirementsError = isMinor
                ? "No requirements were found for this minor. This program may use an unsupported layout."
                : "No requirements were found for this major. This program may use an unsupported layout."
        } else {
            logger.log("[MajorDetails] ✓ Requirements loaded successfully")
            for req in fetchedRequirements.prefix(3) {
                let parsedCourses = (req.requiredCourses ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let selectCourses = collegePersistence.decodeJSONCourseList(req.selectFromJSON)
                logger.log("[MajorDetails]   - \(req.requirementCategory) (\(req.creditsRequired) credits): required=\(parsedCourses.count) courses, select=\(selectCourses.count) courses")
                if !parsedCourses.isEmpty {
                    logger.log("[MajorDetails]     Required: \(parsedCourses.prefix(5).joined(separator: ", "))\(parsedCourses.count > 5 ? "..." : "")")
                }
                if !selectCourses.isEmpty {
                    logger.log("[MajorDetails]     Select from: \(selectCourses.prefix(5).joined(separator: ", "))\(selectCourses.count > 5 ? "..." : "")")
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            if showsBackButton {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .frame(width: 36, height: 36)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: "building.2")
                        .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(majorTitle)
                            .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        Text(badgeText)
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.15))
                            .cornerRadius(10)
                    }

                    if !majorSubtitle.isEmpty {
                        Text(majorSubtitle)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: {}) {
                    Label("Edit Major", systemImage: "pencil")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {}) {
                    Label("Degree Audit PDF", systemImage: "arrow.down.circle")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(DesignSystem.Colors.info)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .background(DesignSystem.Colors.surface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.12)),
            alignment: .bottom
        )
    }

    private var statsRow: some View {
        let fraction = creditsCompletionCardFraction(requirements: fetchedRequirements)
        let percent = Int((fraction * 100).rounded())
        let gpaSummary = collegePersistence.majorGPASummary(requirements: fetchedRequirements)
        let gpaText = gpaSummary.map { GPAFormatting.fractionText(gpa: $0.gpa) } ?? GPAFormatting.fractionText(gpa: nil)
        let gpaFraction = gpaSummary.map { min(max($0.gpa / 4.0, 0), 1) } ?? 0
        let gpaPercentText = gpaSummary.map { "\(Int(($0.gpa / 4.0 * 100).rounded()))%" } ?? "-"
        let gpaInGoodStanding = (gpaSummary?.gpa ?? 0) >= 2.0
        let allRows = allRequirementRows()
        let issues = potentialIssues(in: allRows)
        let issueCount = issues.count
        let issueSummary = potentialIssueSummaryText(issues)
        let totalCourseCount = uniqueCourseCodeCount(in: allRows)
        let issueFraction = totalCourseCount > 0 ? Double(issueCount) / Double(totalCourseCount) : 0
        let universityID = collegePersistence.getActiveUniversity()?.id
        return HStack(spacing: 16) {
            StatCard(
                title: programKind == .minor ? "Minor Completion" : "Major Completion",
                valueText: "\(percent)%",
                valueColor: accentColor,
                subtitleLeft: creditsCompletionCardSubtitleLeft(requirements: fetchedRequirements),
                subtitleRight: creditsCompletionCardSubtitleRight(requirements: fetchedRequirements),
                buttonTitle: nil,
                buttonIcon: nil,
                buttonColor: nil,
                progressFraction: fraction
            )

            StatCard(
                title: programKind == .minor ? "Minor GPA" : "Major GPA",
                valueText: gpaPercentText,
                valueColor: gpaInGoodStanding ? DesignSystem.Colors.success : DesignSystem.Colors.warning,
                subtitleLeft: gpaText,
                subtitleRight: "Min. Required: 2.0",
                pillText: gpaSummary == nil ? nil : (gpaInGoodStanding ? "Good Standing" : "Needs Attention"),
                pillColor: gpaInGoodStanding ? DesignSystem.Colors.success : DesignSystem.Colors.warning,
                buttonTitle: "GPA Calculator",
                buttonIcon: "chart.line.uptrend.xyaxis",
                buttonColor: DesignSystem.Colors.primary,
                progressFraction: gpaFraction,
                onButtonTap: {
                    isGPACalculatorPresented = true
                },
                popoverIsPresented: $isGPACalculatorPresented,
                popoverContent: {
                    AnyView(
                        GPACalculatorPopoverView(universityID: universityID)
                            )
                }
            )

            StatCard(
                title: "Potential Issues",
                valueText: "\(issueCount)",
                valueColor: issueCount > 0 ? DesignSystem.Colors.warning : DesignSystem.Colors.textLight,
                subtitleLeft: "C- or below",
                subtitleRight: issueSummary,
                buttonTitle: nil,
                buttonIcon: nil,
                buttonColor: nil,
                progressFraction: issueFraction
            )
        }
    }

    private struct DynamicRequirementSection: Identifiable {
        let id: String
        let title: String
        let accent: Color
        let requirements: [CatalogDegreeRequirement]
        var rowsOverride: [CourseRequirementRow]? = nil
        var completedTextOverride: String? = nil
        var fulfillmentCategoryKey: String? = nil
        var allowsFulfillmentDrop: Bool = false
    }

    private func normalizeCategoryKey(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func groupSectionTitle(for reqs: [CatalogDegreeRequirement]) -> String {
        if let parent = reqs.first?.parentCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !parent.isEmpty {
            return parent
        }
        return (reqs.first?.requirementCategory ?? "Requirements")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func accentColor(forCategory category: String) -> Color {
        switch classifyCategory(normalizeCategoryKey(category)) {
        case .core:
            return DesignSystem.Colors.info
        case .electives:
            return DesignSystem.Colors.secondary
        case .genEd:
            return DesignSystem.Colors.warning
        case .other:
            return DesignSystem.Colors.accent
        }
    }

    private var dynamicRequirementSections: [DynamicRequirementSection] {
        // While loading or erroring, still render a single section so the user sees feedback.
        if (isLoadingRequirements && fetchedRequirements.isEmpty) || (requirementsError != nil && fetchedRequirements.isEmpty) {
            return [
                DynamicRequirementSection(
                    id: "requirements",
                    title: "Requirements",
                    accent: DesignSystem.Colors.info,
                    requirements: []
                )
            ]
        }

        var byKey: [String: [CatalogDegreeRequirement]] = [:]
        var orderedKeys: [String] = []

        for r in fetchedRequirements {
            let display = r.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = (r.parentCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let groupTitle = parent.isEmpty ? display : parent
            let key = normalizeCategoryKey(groupTitle)
            guard !key.isEmpty else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                orderedKeys.append(key)
            }
            byKey[key, default: []].append(r)
        }

        // Deterministic ordering: if local store fetch is alphabetical, preserve it; otherwise keep encounter order.
        // (We don't have a stored section order yet.)
        var sections: [DynamicRequirementSection] = orderedKeys.compactMap { key in
            guard var reqs = byKey[key], !reqs.isEmpty else { return nil }
            reqs.sort { $0.sectionOrder < $1.sectionOrder }
            let title = groupSectionTitle(for: reqs)
            let allowsDrop = reqs.contains { req in
                let kind = College.RequirementKind(rawValue: req.requirementKind ?? "")
                    ?? RequirementProgressEngine.inferredKind(from: req)
                return kind == .distributionBucket || kind == .ruleBucket || kind == .chooseOne
            }
            return DynamicRequirementSection(
                id: key,
                title: title.isEmpty ? "Requirements" : title,
                accent: accentColor(forCategory: title),
                requirements: reqs,
                fulfillmentCategoryKey: allowsDrop ? (reqs.first?.requirementCategory ?? title) : nil,
                allowsFulfillmentDrop: allowsDrop
            )
        }

        let hasDistributionBuckets = fetchedRequirements.contains {
            RequirementProgressEngine.inferredKind(from: $0) == .distributionBucket
        }
        let degreeLevel = collegePersistence.primaryDegreeLevel(default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isUndergrad = degreeLevel.lowercased().contains("under")

        // General Education applies only to Undergraduate Majors and should appear after other requirement sections.
        if programKind == .major, isUndergrad, !hasDistributionBuckets {
            sections.append(
                DynamicRequirementSection(
                    id: "gened-manual",
                    title: genEdTitleWithCredits(),
                    accent: DesignSystem.Colors.warning,
                    requirements: [],
                    rowsOverride: genEdRows(),
                    completedTextOverride: genEdProgressText()
                )
            )
        }

        return sections
    }

    private func genEdStatus(for course: PlannerCourse) -> RequirementStatus {
        if course.isCompleted { return .completed }
        let s = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "In Progress" || s == "In-Progress" { return .inProgress }
        if s == "Dropped" { return .dropped }
        return .planned
    }

    private func genEdRows() -> [CourseRequirementRow] {
        let courses = genEdCourses()
        if courses.isEmpty {
            return [
                .init(code: "", title: "No GenEd courses assigned.", credits: "-", grade: "-", semester: "-", status: .planned)
            ]
        }

        return courses.map { course in
            let code = normalizeCode(course.code)
            let catalogTitle = collegePersistence.getCatalogCourse(code: code)?.title
            let title = (course.name.isEmpty ? (catalogTitle ?? "") : course.name).trimmingCharacters(in: .whitespacesAndNewlines)
            let grade = (course.grade ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(
                code: code,
                title: title.isEmpty ? "Course" : title,
                credits: formatCredits(course.credits),
                grade: grade.isEmpty ? "-" : grade,
                semester: semesterText(for: course),
                status: genEdStatus(for: course)
            )
        }
    }

    private func genEdProgressText() -> String {
        let courses = genEdCourses()
        let completed = courses.filter { $0.isCompleted }.reduce(0.0) { $0 + Double($1.credits) }
        let total = genEdTotalCredits()
        let doneText = formatCreditsTotal(completed)
        let totalText = formatCreditsTotal(total)
        return "\(doneText) of \(totalText) credits completed"
    }

    private func genEdCourses() -> [PlannerCourse] {
        allPlannedCourses().filter { $0.countsTowardGenEd }
    }

    private func genEdTotalCredits() -> Double {
        genEdCourses().reduce(0.0) { $0 + Double($1.credits) }
    }

    private func formatCreditsTotal(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0001 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", value)
    }

    private func genEdTitleWithCredits() -> String {
        let creditsText = formatCreditsTotal(genEdTotalCredits())
        return "General Education (\(creditsText) Credits)"
    }


    private func handleGenEdDrop(courseCode: String) {
        let code = normalizeCode(courseCode)
        guard !code.isEmpty else { return }

        if let existing = plannedCourse(for: code) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                existing.countsTowardGenEd = true
            }
            collegePersistence.save()
            return
        }

        guard let catalogCourse = collegePersistence.getCatalogCourse(code: code) else {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Course Not Found",
                message: "Could not find \(code) in the active university catalog.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            collegePersistence.addOrTagGenEdCourse(from: catalogCourse)
        }

    }

    private func handleRequirementFulfillmentDrop(courseCode: String, requirementCategory: String) {
        let code = normalizeCode(courseCode)
        let category = requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !category.isEmpty, !activeProgramURL.isEmpty else { return }
        let university = (profile?.collegeName ?? collegePersistence.getActiveUniversity()?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try? RequirementFulfillmentStore.assign(
            context: collegePersistence.profileContext,
            university: university,
            programURL: activeProgramURL,
            requirementCategory: category,
            courseCode: code
        )
        refreshMemoizedSectionPresentations()
    }

    private var shouldShowCapstoneCard: Bool {
        let cats = fetchedRequirements.map { $0.requirementCategory.lowercased() }
        return cats.contains(where: { c in
            c.contains("capstone") || c.contains("senior project") || c.contains("thesis") || c.contains("culminat")
        })
    }

    private var capstone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 6, height: 28)
                Text("Capstone Project")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(DesignSystem.Colors.accent.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "graduationcap")
                                .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.accent)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Senior Capstone Experience")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        HStack(spacing: 8) {
                            Text("Not Started")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DesignSystem.Colors.textLight.opacity(0.12))
                                .cornerRadius(8)

                            Text("• 3 Credits Required")
                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }

                        Text("All students must complete a capstone project that integrates knowledge from their core and elective courses. This can be fulfilled through an approved capstone course or an independent study.")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: {}) {
                            Label("View Approved Capstone Options", systemImage: "magnifyingglass")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(DesignSystem.Colors.accent.opacity(0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()
                }
            }
            .padding(18)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DesignSystem.Colors.accent.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private enum CategoryAccentKind {
        case core
        case electives
        case genEd
        case other
    }

    private func classifyCategory(_ lowercasedCategory: String) -> CategoryAccentKind {
        if lowercasedCategory.contains("elective") { return .electives }
        if lowercasedCategory.contains("general education") { return .genEd }
        if lowercasedCategory.contains("gen ed") { return .genEd }
        if lowercasedCategory.contains("gen-ed") { return .genEd }
        if lowercasedCategory.contains("core curriculum") { return .genEd }
        if lowercasedCategory.contains("ub curriculum") { return .genEd }
        if lowercasedCategory.contains("breadth") { return .genEd }

        if lowercasedCategory.contains("core") { return .core }
        if lowercasedCategory.contains("foundation") { return .core }
        if lowercasedCategory.contains("required") { return .core }

        return .other
    }

    private func normalizeCode(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        // Canonicalize common catalog variants:
        // - "CSE410LEC" / "CSE 410LEC" / "CSE 410" -> "CSE 410"
        // - "MTH-131LR" -> "MTH 131"
        if let re = Self.courseCodeRegex {
            let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            if let m = re.firstMatch(in: cleaned, range: nsRange), m.numberOfRanges >= 3,
               let r1 = Range(m.range(at: 1), in: cleaned),
               let r2 = Range(m.range(at: 2), in: cleaned) {
                return "\(cleaned[r1]) \(cleaned[r2])"
            }
        }

        return cleaned
    }

    private func allPlannedCourses() -> [PlannerCourse] {
        plans.flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
    }

    private var availablePlanSemesters: [PlannerSemester] {
        var result = [PlannerSemester]()
        for plan in plans { result.append(contentsOf: plan.semestersArray) }
        return result.sorted(by: {
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.seasonOrder < $1.seasonOrder
        })
    }

    private func plannedCourse(for code: String) -> PlannerCourse? {
        let needle = normalizeCode(code)
        guard !needle.isEmpty else { return nil }
        return allPlannedCourses().first(where: { normalizeCode($0.code) == needle })
    }

    private func courseOverride(for code: String) -> CourseOverride? {
        let needle = normalizeCode(code)
        guard !needle.isEmpty else { return nil }
        return collegePersistence.getCourseOverride(courseCode: needle)
    }

    private func deletePlannedCourseAndOverrides(for rawCode: String) {
        let code = normalizeCode(rawCode)
        guard !code.isEmpty else { return }

        // Remove any planned course enrollments for this code (across plans/semesters).
        let matches = allPlannedCourses().filter { normalizeCode($0.code) == code }
        for c in matches {
            collegePersistence.deleteCourse(id: c.id)
        }
        collegePersistence.deleteCourseOverride(courseCode: code)
    }

    private func semesterText(for course: PlannerCourse) -> String {
        guard let semester = course.semester else { return "-" }
        let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        guard !season.isEmpty, year > 0 else { return "-" }
        return "\(season) \(year)"
    }

    private func formatCredits(_ value: Int16) -> String {
        String(format: "%.1f", Double(value))
    }

    private func statusForCourse(code: String) -> RequirementStatus {
        let needle = normalizeCode(code)
        if let overrideEntity = courseOverride(for: needle) {
            let s = (overrideEntity.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if s == "Completed" { return .completed }
            if s == "In Progress" || s == "In-Progress" { return .inProgress }
            if s == "Dropped" { return .dropped }
            if s == "Planned" { return .planned }
            if s == "Not Planned" { return .notPlanned }
        }

        if let planned = plannedCourse(for: needle) {
            if planned.isCompleted { return .completed }
            let s = planned.status.trimmingCharacters(in: .whitespacesAndNewlines)
            if s == "In Progress" || s == "In-Progress" { return .inProgress }
            if s == "Dropped" { return .dropped }
            if s == "Not Planned" { return .notPlanned }
            return .planned
        }

        return .notPlanned
    }

    private func statusForSelect(selectFrom: [String], selectCount: Int) -> RequirementStatus {
        let normalized = Set(selectFrom.map(normalizeCode))
        let courses = allPlannedCourses()
        let completed = courses.filter { c in
            normalized.contains(normalizeCode(c.code)) && c.isCompleted
        }
        if completed.count >= selectCount { return .completed }
        let anyPlanned = courses.contains { c in
            normalized.contains(normalizeCode(c.code))
        }
        return anyPlanned ? .inProgress : .notPlanned
    }

    private func requirementUnitsTotalAndDone(for requirements: [CatalogDegreeRequirement]) -> (total: Int, done: Int) {
        var total = 0
        var done = 0

        for req in requirements {
            let selectCount = Int(req.selectCount)
            if selectCount > 0 {
                total += selectCount

                var selectCodes: [String] = {
                    if let selectDetailedJSON = req.selectFromDetailedJSON,
                       let selectDetailed = collegePersistence.decodeDetailedCourseList(selectDetailedJSON),
                       !selectDetailed.isEmpty {
                        return selectDetailed.map { $0.code }
                    }
                    return collegePersistence.decodeJSONCourseList(req.selectFromJSON)
                }()

                // Some scrapes store select-from options in requiredCourses*; fall back to those.
                if selectCodes.isEmpty,
                   let detailedJSON = req.requiredCoursesDetailedJSON,
                   let detailedCourses = collegePersistence.decodeDetailedCourseList(detailedJSON),
                   !detailedCourses.isEmpty {
                    selectCodes = detailedCourses.map { $0.code }
                }
                if selectCodes.isEmpty {
                    let requiredCodes: [String] = (req.requiredCourses ?? "")
                        .split(separator: ",")
                        .map { normalizeCode(String($0)) }
                        .filter { !$0.isEmpty }
                    if !requiredCodes.isEmpty {
                        selectCodes = requiredCodes
                    }
                }

                let normalized = Set(selectCodes.map(normalizeCode)).filter { !$0.isEmpty }
                let completedCount = normalized.filter { statusForCourse(code: $0) == .completed }.count
                done += min(completedCount, selectCount)
                continue
            }

            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailedCourses = collegePersistence.decodeDetailedCourseList(detailedJSON),
               !detailedCourses.isEmpty {
                let codes = detailedCourses
                    .map { normalizeCode($0.code) }
                    .filter { !$0.isEmpty } // ignore subsection header rows (code == "")
                total += codes.count
                done += codes.filter { statusForCourse(code: $0) == .completed }.count
                continue
            }

            let requiredCodes: [String] = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { normalizeCode(String($0)) }
                .filter { !$0.isEmpty }
            if !requiredCodes.isEmpty {
                total += requiredCodes.count
                done += requiredCodes.filter { statusForCourse(code: $0) == .completed }.count
                continue
            }

        }

        return (total: total, done: done)
    }

    private func buildRows(from requirements: [CatalogDegreeRequirement]) -> [CourseRequirementRow] {
        if isLoadingRequirements {
            return [
                .init(code: "", title: "Fetching catalog requirements…", credits: "-", grade: "-", semester: "-", status: .planned)
            ]
        }
        if let requirementsError {
            return [
                .init(code: "", title: requirementsError, credits: "-", grade: "-", semester: "-", status: .planned)
            ]
        }

        var rows: [CourseRequirementRow] = []

        func makeSubheaderRow(_ title: String) -> CourseRequirementRow {
            .init(code: "", title: title, credits: "", grade: "", semester: "", status: .planned)
        }

        func makeCourseRow(code rawCode: String, title preferredTitle: String?, credits preferredCredits: String?) -> CourseRequirementRow {
            let code = normalizeCode(rawCode)
            let catalog = collegePersistence.getCatalogCourse(code: code)
            let planned = plannedCourse(for: code)
            let overrideEntity = courseOverride(for: code)
            let title = preferredTitle ?? catalog?.title ?? planned?.name ?? ""
            let credits = preferredCredits
                ?? catalog.map { String(format: "%.1f", Double($0.credits)) }
                ?? planned.map { formatCredits($0.credits) }
                ?? "-"
            let grade = (planned?.grade ?? overrideEntity?.grade ?? "-")
            let semester = planned.map(semesterText(for:)) ?? (overrideEntity?.semesterText ?? "-")

            return .init(
                code: code,
                title: title.isEmpty ? "Course" : title,
                credits: credits,
                grade: grade.isEmpty ? "-" : grade,
                semester: semester,
                status: statusForCourse(code: code)
            )
        }

        for req in requirements {
            let kind = College.RequirementKind(rawValue: req.requirementKind ?? "")
                ?? RequirementProgressEngine.inferredKind(from: req)
            let categoryKey = req.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)

            if kind == .distributionBucket || kind == .ruleBucket || kind == .chooseOne {
                let bucketTitle = (req.displayTitle ?? categoryKey).trimmingCharacters(in: .whitespacesAndNewlines)
                if !bucketTitle.isEmpty {
                    rows.append(makeSubheaderRow(bucketTitle))
                }
                let university = (profile?.collegeName ?? collegePersistence.getActiveUniversity()?.name ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let assigned = RequirementFulfillmentStore.assignments(
                    context: collegePersistence.profileContext,
                    university: university,
                    programURL: activeProgramURL,
                    requirementCategory: categoryKey
                )
                for assignment in assigned {
                    let code = normalizeCode(assignment.courseCode)
                    guard !code.isEmpty else { continue }
                    rows.append(makeCourseRow(code: code, title: nil, credits: nil))
                }
            }

            // Try to use detailed course info first (new format)
            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailedCourses = collegePersistence.decodeDetailedCourseList(detailedJSON),
               !detailedCourses.isEmpty {
                for detail in detailedCourses {
                    let normalized = normalizeCode(detail.code)
                    if normalized.isEmpty {
                        let title = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty {
                            rows.append(makeSubheaderRow(title))
                        }
                        continue
                    }
                    rows.append(makeCourseRow(code: normalized, title: detail.title, credits: detail.credits))
                }
                continue
            }
            
            // Fallback to legacy format (course codes only)
            let requiredCodes: [String] = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { normalizeCode(String($0)) }
                .filter { !$0.isEmpty }

            if !requiredCodes.isEmpty {
                for code in requiredCodes {
                    rows.append(makeCourseRow(code: code, title: nil, credits: nil))
                }
                continue
            }

            // Handle select-from courses (new detailed format)
            if let selectDetailedJSON = req.selectFromDetailedJSON,
               let selectDetailed = collegePersistence.decodeDetailedCourseList(selectDetailedJSON),
               !selectDetailed.isEmpty,
               Int(req.selectCount) > 0 {
                for detail in selectDetailed {
                    rows.append(makeCourseRow(code: detail.code, title: detail.title, credits: detail.credits))
                }
                continue
            }
            
            // Fallback to legacy select-from format
            let selectFrom = collegePersistence.decodeJSONCourseList(req.selectFromJSON)
            let selectCount = Int(req.selectCount)
            if !selectFrom.isEmpty, selectCount > 0 {
                for code in selectFrom {
                    rows.append(makeCourseRow(code: code, title: nil, credits: nil))
                }
            }
        }

        if rows.isEmpty {
            rows.append(.init(code: "", title: "No requirements found.", credits: "-", grade: "-", semester: "-", status: .planned))
        }

        return rows
    }

    // MARK: - Credits-based progress + open-ended sections

    private struct CreditsRequirement {
        let min: Double
        let max: Double?

        var displayText: String {
            if let max {
                return "\(format(min))–\(format(max))"
            }
            return format(min)
        }

        private func format(_ value: Double) -> String {
            let rounded = value.rounded()
            if abs(value - rounded) < 0.0001 {
                return String(Int(rounded))
            }
            return String(format: "%.1f", value)
        }
    }

    private func creditsRequirementForSection(title: String, requirements: [CatalogDegreeRequirement]) -> CreditsRequirement {
        if let parsed = parseCreditsRequirementFromTitle(title) {
            return parsed
        }

        let fallback: Double = {
            if let firstNonZero = requirements.first(where: { $0.creditsRequired > 0 }) {
                return Double(firstNonZero.creditsRequired)
            }
            return 0
        }()

        return CreditsRequirement(min: fallback, max: nil)
    }

    private func parseCreditsRequirementFromTitle(_ title: String) -> CreditsRequirement? {
        guard let re = Self.creditsRequirementRegex else { return nil }
        let ns = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let m = re.firstMatch(in: title, options: [], range: ns) else { return nil }

        func capture(_ idx: Int) -> String? {
            guard m.numberOfRanges > idx else { return nil }
            let r = m.range(at: idx)
            guard r.location != NSNotFound, let rr = Range(r, in: title) else { return nil }
            return String(title[rr])
        }

        guard let a = capture(1), let min = Double(a) else { return nil }
        let max = capture(2).flatMap(Double.init)
        return CreditsRequirement(min: min, max: max)
    }

    private func completedCreditsInRows(_ rows: [CourseRequirementRow]) -> Double {
        rows.reduce(0.0) { partial, row in
            let code = row.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return partial }
            guard row.status == .completed else { return partial }

            let t = row.credits.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t != "-" else { return partial }
            return partial + (Double(t) ?? 0)
        }
    }

    private func creditsProgressText(completedCredits: Double, requirement: CreditsRequirement) -> String {
        let doneText = formatCreditsTotal(completedCredits)
        return "\(doneText) of \(requirement.displayText) credits completed"
    }

    private func creditsCompletionCardFraction(requirements: [CatalogDegreeRequirement]) -> Double {
        let summary = creditsCompletionSummary(requirements: requirements)
        guard summary.requiredMin > 0 else { return 0 }
        return min(max(summary.completed / summary.requiredMin, 0), 1)
    }

    private func creditsCompletionCardSubtitleLeft(requirements: [CatalogDegreeRequirement]) -> String {
        let summary = creditsCompletionSummary(requirements: requirements)
        let doneText = formatCreditsTotal(summary.completed)
        return "\(doneText) of \(summary.requiredDisplay) credits completed"
    }

    private func creditsCompletionCardSubtitleRight(requirements: [CatalogDegreeRequirement]) -> String {
        let summary = creditsCompletionSummary(requirements: requirements)
        let remainingText = summary.remainingDisplay
        return "\(remainingText) credits remaining"
    }

    private func creditsCompletionSummary(requirements: [CatalogDegreeRequirement]) -> (completed: Double, requiredMin: Double, requiredMax: Double?, requiredDisplay: String, remainingDisplay: String) {
        let summary = collegePersistence.creditsProgressSummary(requirements: requirements)
        let completed = summary.completed
        let requiredMin = summary.required

        func creditsText(_ value: Double) -> String { formatCreditsTotal(value) }

        let requiredDisplay = creditsText(requiredMin)
        let remainingDisplay = creditsText(max(requiredMin - completed, 0))

        return (
            completed: completed,
            requiredMin: requiredMin,
            requiredMax: nil,
            requiredDisplay: requiredDisplay,
            remainingDisplay: remainingDisplay
        )
    }

    private func claimedCourseCodes(in requirements: [CatalogDegreeRequirement]) -> Set<String> {
        var out = Set<String>()

        for req in requirements {
            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailed = collegePersistence.decodeDetailedCourseList(detailedJSON) {
                for d in detailed {
                    let code = normalizeCode(d.code)
                    if !code.isEmpty { out.insert(code) }
                }
            }

            let requiredCodes: [String] = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { normalizeCode(String($0)) }
                .filter { !$0.isEmpty }
            requiredCodes.forEach { out.insert($0) }

            if let selectDetailedJSON = req.selectFromDetailedJSON,
               let selectDetailed = collegePersistence.decodeDetailedCourseList(selectDetailedJSON) {
                for d in selectDetailed {
                    let code = normalizeCode(d.code)
                    if !code.isEmpty { out.insert(code) }
                }
            }

            let selectFrom = collegePersistence.decodeJSONCourseList(req.selectFromJSON)
            selectFrom.forEach { out.insert(normalizeCode($0)) }
        }

        let university = (profile?.collegeName ?? collegePersistence.getActiveUniversity()?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !activeProgramURL.isEmpty {
            out.formUnion(
                RequirementFulfillmentStore.allAssignedCodes(
                    context: collegePersistence.profileContext,
                    university: university,
                    programURL: activeProgramURL
                )
            )
        }

        return out
    }

    private func resolvedRowsForOpenEndedSection(baseRows: [CourseRequirementRow], claimedCourseCodes: Set<String>) -> [CourseRequirementRow] {
        // If the scraper produced no course rows for this section, treat it as open-ended.
        if baseRows.count == 1,
           baseRows.first?.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
           baseRows.first?.title.trimmingCharacters(in: .whitespacesAndNewlines) == "No requirements found." {
            let unclaimed = allPlannedCourses().filter { c in
                let code = normalizeCode(c.code)
                guard !code.isEmpty else { return false }
                guard !claimedCourseCodes.contains(code) else { return false }
                return c.countsTowardGenEd == false
            }

            if unclaimed.isEmpty {
                // Render a friendlier placeholder message in the table.
                return [
                    .init(code: "", title: "You can take whatever classes you want!", credits: "", grade: "", semester: "", status: .planned)
                ]
            }

            return unclaimed.map { course in
                let code = normalizeCode(course.code)
                let catalogTitle = collegePersistence.getCatalogCourse(code: code)?.title
                let title = (course.name.isEmpty ? (catalogTitle ?? "") : course.name).trimmingCharacters(in: .whitespacesAndNewlines)
                let grade = (course.grade ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)
                return .init(
                    code: code,
                    title: title.isEmpty ? "Course" : title,
                    credits: formatCredits(course.credits),
                    grade: grade.isEmpty ? "-" : grade,
                    semester: semesterText(for: course),
                    status: genEdStatus(for: course)
                )
            }
        }

        // Replace the old generic placeholder with the new friendly one.
        if baseRows.count == 1,
           baseRows.first?.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
           baseRows.first?.title.trimmingCharacters(in: .whitespacesAndNewlines) == "No requirements found." {
            return [
                .init(code: "", title: "You can take whatever classes you want!", credits: "", grade: "", semester: "", status: .planned)
            ]
        }

        return baseRows
    }

    private func filterRemovedRows(_ rows: [CourseRequirementRow]) -> [CourseRequirementRow] {
        rows.filter { row in
            let raw = row.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return true }
            guard !raw.uppercased().hasPrefix("SELECT ") else { return true }
            let code = normalizeCode(raw)
            return !removedCourseCodes.contains(code)
        }
    }

    private struct PotentialIssue {
        let code: String
        let grade: String
    }

    private func allRequirementRows() -> [CourseRequirementRow] {
        let claimed = claimedCourseCodes(in: fetchedRequirements)
        return dynamicRequirementSections.flatMap { section in
            let baseRows = section.rowsOverride ?? buildRows(from: section.requirements)
            let rows = resolvedRowsForOpenEndedSection(baseRows: baseRows, claimedCourseCodes: claimed)
            return filterRemovedRows(rows)
        }
    }

    private func uniqueCourseCodeCount(in rows: [CourseRequirementRow]) -> Int {
        var codes = Set<String>()
        for row in rows {
            let raw = row.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            guard !raw.uppercased().hasPrefix("SELECT ") else { continue }
            let code = normalizeCode(raw)
            if !code.isEmpty { codes.insert(code) }
        }
        return codes.count
    }

    private func potentialIssues(in rows: [CourseRequirementRow]) -> [PotentialIssue] {
        var seen = Set<String>()
        var out: [PotentialIssue] = []
        for row in rows {
            let raw = row.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            guard !raw.uppercased().hasPrefix("SELECT ") else { continue }
            let code = normalizeCode(raw)
            guard !code.isEmpty, !seen.contains(code) else { continue }
            seen.insert(code)

            let grade = row.grade.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isCMinusOrBelow(grade) else { continue }
            out.append(.init(code: code, grade: grade))
        }
        return out
    }

    private func potentialIssueSummaryText(_ issues: [PotentialIssue]) -> String {
        guard !issues.isEmpty else { return "None" }
        if issues.count <= 2 {
            let details = issues.map { "\($0.code) (\($0.grade))" }.joined(separator: ", ")
            return "C- or below: \(details)"
        }
        return "C- or below: \(issues.count) courses"
    }

    private func isCMinusOrBelow(_ rawGrade: String) -> Bool {
        guard let points = gradePoints(for: rawGrade) else { return false }
        return points <= 1.7
    }

    private func gradePoints(for rawGrade: String) -> Double? {
        let g = rawGrade
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !g.isEmpty else { return nil }

        switch g {
        case "A+", "A": return 4.0
        case "A-": return 3.7
        case "B+": return 3.3
        case "B": return 3.0
        case "B-": return 2.7
        case "C+": return 2.3
        case "C": return 2.0
        case "C-": return 1.7
        case "D+": return 1.3
        case "D": return 1.0
        case "D-": return 0.7
        case "F": return 0.0
        default:
            return nil
        }
    }
}

private struct StatCard: View {
    let title: String
    let valueText: String
    let valueColor: Color
    let subtitleLeft: String
    let subtitleRight: String?
    var pillText: String? = nil
    var pillColor: Color? = nil
    let buttonTitle: String?
    let buttonIcon: String?
    let buttonColor: Color?
    var progressFraction: Double = 0.35

    var onButtonTap: (() -> Void)? = nil
    var popoverIsPresented: Binding<Bool>? = nil
    var popoverContent: (() -> AnyView)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
                Text(valueText)
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(valueColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(DesignSystem.Colors.textLight.opacity(0.10))
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 999)
                        .fill(valueColor.opacity(0.9))
                        .frame(width: geo.size.width * min(max(progressFraction, 0), 1), height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text(subtitleLeft)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                Spacer()

                if let subtitleRight {
                    Text(subtitleRight)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }

            if let pillText, let pillColor {
                Text(pillText)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(pillColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pillColor.opacity(0.12))
                    .cornerRadius(8)
            }

            Group {
                if let buttonTitle, let buttonIcon, let buttonColor {
                    if let popoverIsPresented, let popoverContent {
                    Button(action: {
                        onButtonTap?()
                        popoverIsPresented.wrappedValue = true
                    }) {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(buttonColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(buttonColor.opacity(0.12))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: popoverIsPresented, arrowEdge: .leading) {
                        popoverContent()
                    }
                    } else {
                    Button(action: {
                        onButtonTap?()
                    }) {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(buttonColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(buttonColor.opacity(0.12))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(DesignSystem.Colors.textLight.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct RequirementsSection: View {
    let accent: Color
    let title: String
    let completedText: String
    let rows: [CourseRequirementRow]
    let showsAddCourseButton: Bool
    let showsDropTarget: Bool
    let dropHintText: String
    let onTapAddCourse: () -> Void
    @Binding var isDropTargeted: Bool
    let onDropCourseCode: (String) -> Void
    let onSelectCourse: (CourseRequirementRow) -> Void
    let onOpenDashboard: (CourseRequirementRow) -> Void
    let onDeleteCourse: (String) -> Void
    let availableSemesters: [PlannerSemester]
    let onChangeStatus: (String, RequirementStatus) -> Void
    let onChangeSemester: (CourseRequirementRow, PlannerSemester?) -> Void

    @State private var statusFilter: RequirementStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(accent)
                        .frame(width: 6, height: 28)
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                }

                Spacer()

                Text(completedText)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(999)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
                    )

                if showsAddCourseButton {
                    Button(action: onTapAddCourse) {
                        Label("Add Course", systemImage: "plus")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.surface)
                            .cornerRadius(999)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Menu {
                    Button("All") { statusFilter = nil }
                    Divider()
                    Button("Not Planned") { statusFilter = .notPlanned }
                    Button("Planned") { statusFilter = .planned }
                    Button("In-Progress") { statusFilter = .inProgress }
                    Button("Completed") { statusFilter = .completed }
                    Button("Dropped") { statusFilter = .dropped }
                } label: {
                    Label("Filter by Status", systemImage: "line.3.horizontal.decrease.circle")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(999)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            VStack(spacing: 0) {
                RequirementsHeaderRow()
                ForEach(rows.filter { row in
                    guard let statusFilter else { return true }
                    // Always keep subsection header rows visible regardless of filtering.
                    if row.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                    return row.status == statusFilter
                }) { row in
                    if row.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       row.title.trimmingCharacters(in: .whitespacesAndNewlines) != "No requirements found." {
                        RequirementsSubheaderRow(title: row.title)
                        Divider().opacity(0.2)
                    } else {
                        RequirementsDataRow(
                            row: row,
                            availableSemesters: availableSemesters,
                            onSelect: { onSelectCourse(row) },
                            onOpenDashboard: { onOpenDashboard(row) },
                            onDelete: {
                                let code = row.code.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !code.isEmpty else { return }
                                onDeleteCourse(code)
                            },
                            onChangeStatus: { newStatus in
                                onChangeStatus(row.code, newStatus)
                            },
                            onChangeSemester: { sem in
                                onChangeSemester(row, sem)
                            }
                        )
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(DesignSystem.Colors.surface)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DesignSystem.Colors.textLight.opacity(0.10), lineWidth: 1)
            )
            .overlay(
                Group {
                    if showsDropTarget, isDropTargeted {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(accent.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                            .overlay(
                                VStack {
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundColor(accent)
                                        Text(dropHintText)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textMain)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(DesignSystem.Colors.surface)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
                                    )
                                    .padding(.bottom, 12)
                                }
                            )
                            .transition(.opacity)
                    }
                }
            )
            .onDrop(of: [UTType.text], isTargeted: showsDropTarget ? $isDropTargeted : .constant(false)) { providers in
                guard showsDropTarget else { return false }
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                    let dropped: String? = {
                        if let s = item as? String { return s }
                        if let data = item as? Data { return String(data: data, encoding: .utf8) }
                        if let ns = item as? NSString { return String(ns) }
                        return nil
                    }()
                    guard let dropped else { return }
                    DispatchQueue.main.async {
                        onDropCourseCode(dropped)
                    }
                }
                return true
            }
        }
    }
}


private struct RequirementsHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("COURSE CODE").frame(width: 110, alignment: .leading)
            Text("COURSE TITLE").frame(maxWidth: .infinity, alignment: .leading)
            Text("CREDITS").frame(width: 70, alignment: .center)
            Text("GRADE").frame(width: 60, alignment: .center)
            Text("SEMESTER").frame(width: 110, alignment: .center)
            Text("STATUS").frame(width: 110, alignment: .trailing)
            Text("").frame(width: 56, alignment: .trailing)
        }
        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
        .foregroundColor(DesignSystem.Colors.textLight)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.textLight.opacity(0.05))
    }
}

private struct RequirementsDataRow: View {
    let row: CourseRequirementRow
    let availableSemesters: [PlannerSemester]
    let onSelect: () -> Void
    let onOpenDashboard: () -> Void
    let onDelete: () -> Void
    let onChangeStatus: (RequirementStatus) -> Void
    let onChangeSemester: (PlannerSemester?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                if isCMinusOrBelow(row.grade) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.warning)
                }
                Text(row.code)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
            }
            .frame(width: 110, alignment: .leading)

            Text(row.title)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.credits)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(width: 70, alignment: .center)

            Text(row.grade)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(row.status == .completed ? DesignSystem.Colors.success : DesignSystem.Colors.textLight)
                .frame(width: 60, alignment: .center)

            // SEMESTER — interactive menu
            Menu {
                if availableSemesters.isEmpty {
                    Text("No semesters in your plan")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                } else {
                    ForEach(availableSemesters, id: \.id) { sem in
                        let label = semesterLabel(sem)
                        Button(action: { onChangeSemester(sem) }) {
                            if row.semester == label {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                    Divider()
                }
                Button(role: .destructive, action: { onChangeSemester(nil) }) {
                    Label("Unassign", systemImage: "xmark.circle")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(row.semester)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Fonts.main(size: 9, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.5))
                }
                .frame(width: 110, alignment: .center)
            }
            .buttonStyle(.plain)

            // STATUS — interactive menu
            Menu {
                ForEach(RequirementStatus.allCases, id: \.displayString) { s in
                    Button(action: { onChangeStatus(s) }) {
                        if row.status == s {
                            Label(s.displayString, systemImage: "checkmark")
                        } else {
                            Label(s.displayString, systemImage: s.sfSymbol)
                        }
                    }
                }
            } label: {
                StatusPill(status: row.status)
            }
            .buttonStyle(.plain)
            .frame(width: 110, alignment: .trailing)

            HStack(spacing: 8) {
                Button(action: onOpenDashboard) {
                    Image(systemName: "arrow.up.right.square")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open course dashboard")

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.error)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from your plan/overrides (so you can replace it)")
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private func semesterLabel(_ sem: PlannerSemester) -> String {
        let season = sem.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(sem.year)
        guard !season.isEmpty, year > 0 else { return "Unknown Semester" }
        return "\(season) \(year)"
    }

    private func isCMinusOrBelow(_ rawGrade: String) -> Bool {
        let g = rawGrade
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        switch g {
        case "C-", "D+", "D", "D-", "F":
            return true
        default:
            return false
        }
    }
}

private struct RequirementsSubheaderRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.textLight.opacity(0.035))
    }
}

enum RequirementStatus: CaseIterable {
    case notPlanned
    case completed
    case inProgress
    case planned
    case dropped

    var displayString: String {
        switch self {
        case .notPlanned: return "Not Planned"
        case .completed:  return "Completed"
        case .inProgress: return "In Progress"
        case .planned:    return "Planned"
        case .dropped:    return "Dropped"
        }
    }

    var sfSymbol: String {
        switch self {
        case .notPlanned: return "circle"
        case .completed:  return "checkmark.circle.fill"
        case .inProgress: return "clock.fill"
        case .planned:    return "circle.dotted"
        case .dropped:    return "minus.circle.fill"
        }
    }
}

struct CourseRequirementRow: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let credits: String
    let grade: String
    let semester: String
    let status: RequirementStatus
}

@MainActor
final class MajorDetailsViewModel: ObservableObject {
    struct SectionPresentation: Identifiable {
        let id: String
        let accent: Color
        let title: String
        let completedText: String
        let rows: [CourseRequirementRow]
        let isGenEdSection: Bool
        var allowsFulfillmentDrop: Bool = false
        var fulfillmentCategoryKey: String? = nil
    }

    @Published private(set) var presentations: [SectionPresentation] = []
    private var cacheKey = ""

    func update(presentations: [SectionPresentation], cacheKey: String) {
        guard self.cacheKey != cacheKey else { return }
        self.cacheKey = cacheKey
        self.presentations = presentations
    }
}

private struct StatusPill: View {
    let status: RequirementStatus

    private var style: (text: String, color: Color, icon: String) {
        switch status {
        case .notPlanned:
            return ("Not Planned", DesignSystem.Colors.textLight, "circle")
        case .completed:
            return ("Completed", DesignSystem.Colors.success, "checkmark.circle.fill")
        case .inProgress:
            return ("In-Progress", DesignSystem.Colors.warning, "clock.fill")
        case .planned:
            return ("Planned", DesignSystem.Colors.info, "circle")
        case .dropped:
            return ("Dropped", DesignSystem.Colors.textLight, "minus.circle.fill")
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: style.icon)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
            Text(style.text)
                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
        }
        .foregroundColor(style.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(style.color.opacity(0.12))
        .cornerRadius(999)
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(style.color.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct ElectiveCardDone: View {
    let code: String
    let title: String
    let grade: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DesignSystem.Colors.secondary.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.secondary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(code)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                Text("Done (\(grade))")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.success.opacity(0.12))
                    .cornerRadius(999)
            }

            Spacer()
        }
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DesignSystem.Colors.textLight.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct ElectiveCardNeeded: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DesignSystem.Colors.textLight.opacity(0.08))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "plus")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Select Elective")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                Text("3–4 Credits Required")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                Text("Needed")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.textLight.opacity(0.10))
                    .cornerRadius(999)
            }

            Spacer()
        }
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.18))
        )
    }
}
