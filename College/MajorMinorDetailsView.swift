import SwiftUI
import UniformTypeIdentifiers

/// Main-panel content shown when the user clicks "View Details" for their Major.
///
/// This view intentionally matches the provided design: header (title + badge + subtitle + actions),
/// three stat cards, then requirements sections with a table-style list.
struct MajorMinorDetailsView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator

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
    @State private var fetchedRequirements: [DegreeRequirementEntity] = []

    @State private var isGenEdDropTargeted: Bool = false

    @State private var isGPACalculatorPresented: Bool = false

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
        let level = (coreDataManager.profile?.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeType = (coreDataManager.profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let department = (coreDataManager.profile?.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let university = (coreDataManager.profile?.collegeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

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
           let school = coreDataManager.schoolForDepartment(universityName: university, departmentName: department) {
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
    }

    private var contentStack: some View {
        VStack(spacing: 24) {
            statsRow

            VStack(spacing: 28) {
                ForEach(dynamicRequirementSections) { section in
                    let rows = section.rowsOverride ?? buildRows(from: section.requirements)
                    let completedText = section.completedTextOverride ?? progressText(for: section.requirements)

                    let isGenEdSection = (section.id == "gened-manual")

                    RequirementsSection(
                        accent: section.accent,
                        title: section.title,
                        completedText: completedText,
                        rows: rows,
                        showsAddCourseButton: true,
                        showsDropTarget: isGenEdSection,
                        dropHintText: "Drop to add to General Education",
                        onTapAddCourse: {
                            if isGenEdSection {
                                modalCoordinator.activeModal = .addGenEdCourse
                            } else {
                                modalCoordinator.activeModal = .addCatalogCourseGlobal(tagAsGenEd: false)
                            }
                        },
                        isDropTargeted: isGenEdSection ? $isGenEdDropTargeted : .constant(false),
                        onDropCourseCode: { droppedCode in
                            guard isGenEdSection else { return }
                            handleGenEdDrop(courseCode: droppedCode)
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
            : (coreDataManager.profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let major = majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        return [kind, dt, major].joined(separator: "|")
    }

    @MainActor
    private func refreshRequirementsIfNeeded() async {
        let logger = DebugLogger.shared
        requirementsError = nil
        isLoadingRequirements = true

        defer { isLoadingRequirements = false }
        
        let isMinor = (programKind == .minor)
        logger.log("[MajorDetails] Starting requirements refresh")
        logger.log("[MajorDetails] kind=\(isMinor ? "minor" : "major") display='\(majorDisplay)'")
        logger.log("[MajorDetails] Profile degreeType: '\(coreDataManager.profile?.degreeType ?? "nil")'")

        guard let programURL = coreDataManager.resolveProgramProgramURL(programDisplay: majorDisplay, isMinor: isMinor) else {
            requirementsError = isMinor
                ? "No program URL found for the selected minor. Re-run the program import for this university."
                : "No program URL found for the selected major. Re-run the program import for this university."
            fetchedRequirements = []
            return
        }

        let degreeTypeForScrape: String = {
            if isMinor { return "Minor" }
            let dt = (coreDataManager.profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return dt.isEmpty ? "Unknown" : dt
        }()

        await coreDataManager.refreshProgramRequirementsIfNeeded(
            programURL: programURL,
            major: majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines),
            degreeType: degreeTypeForScrape,
            force: false
        )

        fetchedRequirements = coreDataManager.getDegreeRequirements(programURL: programURL, degreeType: degreeTypeForScrape)
        logger.log("[MajorDetails] Fetched \(fetchedRequirements.count) requirement entities")
        
        if fetchedRequirements.isEmpty {
            logger.log("[MajorDetails] ❌ No requirements found in Core Data")
            requirementsError = isMinor
                ? "No requirements were found for this minor. This program may use an unsupported layout."
                : "No requirements were found for this major. This program may use an unsupported layout."
        } else {
            logger.log("[MajorDetails] ✓ Requirements loaded successfully")
            for req in fetchedRequirements.prefix(3) {
                let parsedCourses = (req.requiredCourses ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let selectCourses = coreDataManager.decodeJSONCourseList(req.selectFromJSON)
                logger.log("[MajorDetails]   - \(req.requirementCategory ?? "?") (\(req.creditsRequired) credits): required=\(parsedCourses.count) courses, select=\(selectCourses.count) courses")
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
                        .font(.system(size: 14, weight: .bold))
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
                        .font(.system(size: 22, weight: .bold))
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
        let progress = coreDataManager.courseProgressSummary(requirements: fetchedRequirements)
        let percent = Int((progress.fraction * 100).rounded())
        let gpaSummary = coreDataManager.majorGPASummary(requirements: fetchedRequirements)
        let gpaText = gpaSummary.map { String(format: "%.2f", $0.gpa) } ?? "-"
        let universityID = coreDataManager.getActiveUniversity()?.id
        return HStack(spacing: 16) {
            StatCard(
                title: programKind == .minor ? "Minor Completion" : "Major Completion",
                valueText: "\(percent)%",
                valueColor: accentColor,
                subtitleLeft: "\(progress.done) / \(progress.total) Courses Completed",
                subtitleRight: "\(progress.remaining) Courses Remaining",
                buttonTitle: "View Progress Timeline",
                buttonIcon: "chart.bar",
                buttonColor: accentColor,
                progressFraction: progress.fraction
            )

            StatCard(
                title: programKind == .minor ? "Minor GPA" : "Major GPA",
                valueText: gpaText,
                valueColor: DesignSystem.Colors.success,
                subtitleLeft: "Min. Required: 2.0",
                subtitleRight: nil,
                pillText: "Good Standing",
                pillColor: DesignSystem.Colors.success,
                buttonTitle: "GPA Calculator",
                buttonIcon: "chart.line.uptrend.xyaxis",
                buttonColor: DesignSystem.Colors.primary,
                onButtonTap: {
                    isGPACalculatorPresented = true
                },
                popoverIsPresented: $isGPACalculatorPresented,
                popoverContent: {
                    AnyView(
                        GPACalculatorPopoverView(universityID: universityID)
                            .environmentObject(coreDataManager)
                    )
                }
            )

            StatCard(
                title: "Potential Issues",
                valueText: "2",
                valueColor: DesignSystem.Colors.warning,
                subtitleLeft: "Warnings",
                subtitleRight: "Unmet prereqs, low grades",
                buttonTitle: "Review Bottlenecks",
                buttonIcon: "exclamationmark.triangle",
                buttonColor: DesignSystem.Colors.warning
            )
        }
    }

    private struct DynamicRequirementSection: Identifiable {
        let id: String
        let title: String
        let accent: Color
        let requirements: [DegreeRequirementEntity]
        var rowsOverride: [CourseRequirementRow]? = nil
        var completedTextOverride: String? = nil
    }

    private func normalizeCategoryKey(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
        if isLoadingRequirements || (requirementsError != nil && fetchedRequirements.isEmpty) {
            return [
                DynamicRequirementSection(
                    id: "requirements",
                    title: "Requirements",
                    accent: DesignSystem.Colors.info,
                    requirements: []
                )
            ]
        }

        var byKey: [String: [DegreeRequirementEntity]] = [:]
        var orderedKeys: [String] = []

        for r in fetchedRequirements {
            let display = (r.requirementCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeCategoryKey(display)
            guard !key.isEmpty else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                orderedKeys.append(key)
            }
            byKey[key, default: []].append(r)
        }

        // Deterministic ordering: if Core Data fetch is alphabetical, preserve it; otherwise keep encounter order.
        // (We don't have a stored section order yet.)
        var sections: [DynamicRequirementSection] = orderedKeys.compactMap { key in
            guard var reqs = byKey[key], !reqs.isEmpty else { return nil }
            reqs.sort { $0.sectionOrder < $1.sectionOrder }
            let title = (reqs.first?.requirementCategory ?? "Requirements").trimmingCharacters(in: .whitespacesAndNewlines)
            return DynamicRequirementSection(
                id: key,
                title: title.isEmpty ? "Requirements" : title,
                accent: accentColor(forCategory: title),
                requirements: reqs
            )
        }

        let degreeLevel = (coreDataManager.profile?.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isUndergrad = degreeLevel.lowercased().contains("under")

        // General Education applies only to Undergraduate Majors and should appear after other requirement sections.
        if programKind == .major, isUndergrad {
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

    private func genEdStatus(for course: CourseEntity) -> RequirementStatus {
        if course.isCompleted { return .completed }
        let s = (course.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            let code = normalizeCode(course.code ?? "")
            let catalogTitle = coreDataManager.getCatalogCourse(code: code)?.title
            let title = (course.name ?? catalogTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        let assigned = courses.count
        let completed = courses.filter { $0.isCompleted }.count
        return "\(completed) of \(assigned) Completed"
    }

    private func genEdCourses() -> [CourseEntity] {
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
            coreDataManager.save()
            NotificationCenter.default.post(name: .catalogCourseDropCompleted, object: nil)
            return
        }

        guard let catalogCourse = coreDataManager.getCatalogCourse(code: code) else {
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
            coreDataManager.addOrTagGenEdCourse(from: catalogCourse)
        }

        NotificationCenter.default.post(name: .catalogCourseDropCompleted, object: nil)
    }

    private var shouldShowCapstoneCard: Bool {
        let cats = fetchedRequirements.compactMap { ($0.requirementCategory ?? "").lowercased() }
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
                                .font(.system(size: 20, weight: .bold))
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

    private enum RequirementKind {
        case core
        case electives
        case genEd
        case other
    }

    private func classifyCategory(_ lowercasedCategory: String) -> RequirementKind {
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
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func allPlannedCourses() -> [CourseEntity] {
        coreDataManager.plans.flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
    }

    private func plannedCourse(for code: String) -> CourseEntity? {
        let needle = normalizeCode(code)
        guard !needle.isEmpty else { return nil }
        return allPlannedCourses().first(where: { normalizeCode($0.code ?? "") == needle })
    }

    private func courseOverride(for code: String) -> CourseOverrideEntity? {
        let needle = normalizeCode(code)
        guard !needle.isEmpty else { return nil }
        return coreDataManager.getCourseOverride(courseCode: needle)
    }

    private func semesterText(for course: CourseEntity) -> String {
        guard let semester = course.semester else { return "-" }
        let season = (semester.season ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            let s = (planned.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
            normalized.contains(normalizeCode(c.code ?? "")) && c.isCompleted
        }
        if completed.count >= selectCount { return .completed }
        let anyPlanned = courses.contains { c in
            normalized.contains(normalizeCode(c.code ?? ""))
        }
        return anyPlanned ? .inProgress : .notPlanned
    }

    private func requirementUnitsTotalAndDone(for requirements: [DegreeRequirementEntity]) -> (total: Int, done: Int) {
        var total = 0
        var done = 0

        for req in requirements {
            let selectCount = Int(req.selectCount)
            if selectCount > 0 {
                total += selectCount

                var selectCodes: [String] = {
                    if let selectDetailedJSON = req.selectFromDetailedJSON,
                       let selectDetailed = coreDataManager.decodeDetailedCourseList(selectDetailedJSON),
                       !selectDetailed.isEmpty {
                        return selectDetailed.map { $0.code }
                    }
                    return coreDataManager.decodeJSONCourseList(req.selectFromJSON)
                }()

                // Some scrapes store select-from options in requiredCourses*; fall back to those.
                if selectCodes.isEmpty,
                   let detailedJSON = req.requiredCoursesDetailedJSON,
                   let detailedCourses = coreDataManager.decodeDetailedCourseList(detailedJSON),
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
               let detailedCourses = coreDataManager.decodeDetailedCourseList(detailedJSON),
               !detailedCourses.isEmpty {
                total += detailedCourses.count
                done += detailedCourses.filter { statusForCourse(code: $0.code) == .completed }.count
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

    private func buildRows(from requirements: [DegreeRequirementEntity]) -> [CourseRequirementRow] {
        if isLoadingRequirements {
            return [
                .init(code: "", title: "Loading requirements…", credits: "-", grade: "-", semester: "-", status: .planned)
            ]
        }
        if let requirementsError {
            return [
                .init(code: "", title: requirementsError, credits: "-", grade: "-", semester: "-", status: .planned)
            ]
        }

        var rows: [CourseRequirementRow] = []

        func makeCourseRow(code rawCode: String, title preferredTitle: String?, credits preferredCredits: String?) -> CourseRequirementRow {
            let code = normalizeCode(rawCode)
            let catalog = coreDataManager.getCatalogCourse(code: code)
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
            // Try to use detailed course info first (new format)
            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailedCourses = coreDataManager.decodeDetailedCourseList(detailedJSON),
               !detailedCourses.isEmpty {
                for detail in detailedCourses {
                    rows.append(makeCourseRow(code: detail.code, title: detail.title, credits: detail.credits))
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
               let selectDetailed = coreDataManager.decodeDetailedCourseList(selectDetailedJSON),
               !selectDetailed.isEmpty,
               Int(req.selectCount) > 0 {
                for detail in selectDetailed {
                    rows.append(makeCourseRow(code: detail.code, title: detail.title, credits: detail.credits))
                }
                continue
            }
            
            // Fallback to legacy select-from format
            let selectFrom = coreDataManager.decodeJSONCourseList(req.selectFromJSON)
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

    private func progressText(for requirements: [DegreeRequirementEntity]) -> String {
        if isLoadingRequirements { return "Loading…" }
        if requirements.isEmpty { return "0 Completed" }

        let (total, done) = requirementUnitsTotalAndDone(for: requirements)
        if total <= 0 { return "0 Completed" }
        return "\(done) of \(total) Completed"
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
    let buttonTitle: String
    let buttonIcon: String
    let buttonColor: Color
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
                    return row.status == statusFilter
                }) { row in
                    RequirementsDataRow(row: row, onSelect: { onSelectCourse(row) })
                    Divider().opacity(0.4)
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
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(row.code)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
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

            Text(row.semester)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(width: 110, alignment: .center)

            StatusPill(status: row.status)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private enum RequirementStatus {
    case notPlanned
    case completed
    case inProgress
    case planned
    case dropped
}

private struct CourseRequirementRow: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let credits: String
    let grade: String
    let semester: String
    let status: RequirementStatus
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
                .font(.system(size: 12, weight: .bold))
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
                        .font(.system(size: 14, weight: .bold))
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
                        .font(.system(size: 14, weight: .bold))
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
