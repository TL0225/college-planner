// AcademicsView.swift
// Feature: Academics
// Purpose: Academics module — AcademicsEntranceModifier.
// Data: CollegePersistence / repositories when applicable.

// AcademicsView.swift
// Semester Planner — the "Academics" tab (card-shell pattern aligned with Profile).

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CollegeAcademics

// MARK: - Motion Infrastructure

private enum AcademicsMotion {
    static let cardStaggerStep: Double = 0.045
    static let revealDuration: Double = 0.30
    static let reducedRevealDuration: Double = 0.10
    static let hoverDuration: Double = 0.18
}

enum AcademicsFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "academics",
                title: "Academics planning",
                criticality: .requiredBeforeReady,
                timeoutSeconds: 1.2,
                retryLimit: 1,
                run: { context, onProgress, _ in
                    LaunchBootstrapCache.fetchPlansIfNeeded()
                    onProgress(1)
                }
            )
        )
    }
}

private struct AcademicsEntranceModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 12))
            .scaleEffect(isVisible ? 1 : (reduceMotion ? 1 : 0.985), anchor: .top)
            .animation(
                reduceMotion
                    ? .easeOut(duration: AcademicsMotion.reducedRevealDuration)
                    : .spring(response: AcademicsMotion.revealDuration, dampingFraction: 0.88)
                        .delay(Double(index) * AcademicsMotion.cardStaggerStep),
                value: isVisible
            )
    }
}

private struct PressableCardStyle: ButtonStyle {
    var reduceMotion: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.spring(response: 0.10, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - AcademicsView

struct AcademicsView: View {
    @Binding var activePage: AppPage
    @Binding var isInspectorPresented: Bool

    @Environment(AppContainer.self) private var appContainer
    private var persistence: CollegePersistence { appContainer.persistence }
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    private var appDataStore: AppDataStore { appContainer.appDataStore }
    private var academicMetricsStore: AcademicMetricsStore { appContainer.academicMetricsStore }
    private var auditSnapshotStore: AuditSnapshotStore { appContainer.auditSnapshotStore }
    private var modalCoordinator: ModalCoordinator { appContainer.modalCoordinator }
    private var academicsScene: AcademicsSceneState { appContainer.academicsScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    @State private var toolbarHandlerToken: ToolbarHandlerToken?

    private var profile: Profile? { ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) }

    @State private var plannerSemesters: [PlannerSemester] = []

    private var academicProfiles: [AcademicProfile] {
        AcademicProfileReadBridge.profiles()
    }

    private var selectedAcademicProfile: AcademicProfile? {
        if let id = academicsScene.selectedAcademicProfileID,
           let match = academicProfiles.first(where: { $0.id == id }) {
            return match
        }
        return academicProfiles.first
    }

    @State private var plannerCourseCount: Int = 0

    private var creditLayoutToken: String {
        let courseCount = max(
            plannerCourseCount,
            AcademicsPlannerReadBridge.semesterCourseCount(appDataStore: appDataStore)
        )
        let majors = selectedAcademicProfile.map { collegePersistence.resolvedMajorNames(for: $0) }
            ?? collegePersistence.resolvedMajorNames()
        let minors = selectedAcademicProfile.map { collegePersistence.resolvedMinorNames(for: $0) }
            ?? collegePersistence.resolvedMinorNames()
        return AuditSnapshotStore.creditLayoutToken(
            academicProfileID: selectedAcademicProfile?.id,
            majors: majors,
            minors: minors,
            semesterCourseCount: courseCount,
            specializationSelectionVersion: specializationSelectionVersion,
            metricsCreditsRequired: academicMetricsStore.snapshot?.creditsRequired
        )
    }

    /// Fixed width of the left stats column. The requirements canvas keeps the
    /// remaining space via `layoutPriority`; the column is not in a 50/50 split.
    private let leftSidebarWidth: CGFloat = 300
    @StateObject private var linker = CalendarCourseLinker.shared

    /// Tap target for the Phase B Graduation Timeline configuration sheet.
    /// `CompactGraduationTimelineCard` flips this; the sheet is mounted on this view so
    /// the modal participates in the same window lifecycle as the rest of the page.
    @State private var showGraduationSheet: Bool = false

    /// Bumped whenever the user picks a different specialization option in the audit sidebar.
    /// Major-card credit progress reads from local store each `body` render, so we need a
    /// State value that SwiftUI tracks to invalidate the cached `body` and trigger a fresh
    /// computation through `applySpecializationFilter`. Without this, the picker would
    /// update the sidebar UI immediately but the "Credits Earned" / "Total Credit Progress"
    /// numbers would stay frozen until something else in the view caused a re-render.
    @State private var specializationSelectionVersion = 0
    /// Set by the bottom program picker; `RequirementsBreakdownView` scrolls to the matching section.
    @State private var requirementsScrollTargetID: String?

    @SceneStorage("academics.view.hasAnimatedIn") private var hasAnimatedIn = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    // MARK: - Body

    var body: some View {
        let resolvedCreditsEarned = academicMetricsStore.snapshot?.completedCreditsTotal
            ?? collegePersistence.primaryCreditsEarned()
        let majors = selectedAcademicProfile.map { collegePersistence.resolvedMajorNames(for: $0) }
            ?? collegePersistence.resolvedMajorNames()
        let minors = selectedAcademicProfile.map { collegePersistence.resolvedMinorNames(for: $0) }
            ?? collegePersistence.resolvedMinorNames()
        let layout = auditSnapshotStore.creditLayout
        let breakdown = layout?.programsBreakdown
            ?? CollegePersistence.DeclaredProgramsCreditsBreakdown(
                primary: CollegePersistence.CreditsProgressSummary(completed: 0, required: 0, fraction: 0),
                additionalPrograms: []
            )
        let resolvedGraduationCreditsRequired = layout?.resolvedGraduationCreditsRequired ?? (academicMetricsStore.snapshot?.creditsRequired ?? 0)
        let buckets = layout?.buckets ?? AcademicsCreditBuckets()
        let programCreditRows = layout?.programCreditRows ?? []

        GeometryReader { proxy in
            let sidebarWidth = academicsScene.statsSidebarShown ? leftSidebarWidth : 0
            let contentWidth = max(0, proxy.size.width - sidebarWidth)

            HStack(alignment: .top, spacing: 0) {
                if academicsScene.statsSidebarShown {
                    AcademicsLeftStatsSidebar(
                        profile: profile,
                        academicProfile: selectedAcademicProfile,
                        plannerGPAFormatted: Self.formatPlannerGPA(academicMetricsStore.snapshot),
                        plannerCreditsEarned: resolvedCreditsEarned,
                        plannerCreditsRequired: resolvedGraduationCreditsRequired,
                        programsBreakdown: breakdown,
                        sapStats: collegePersistence.sapStats(),
                        majors: majors,
                        minors: minors,
                        showGraduationSheet: $showGraduationSheet
                    )
                    .frame(width: leftSidebarWidth, height: proxy.size.height, alignment: .topLeading)
                    .modifier(AcademicsEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                    Divider()
                }

                VStack(spacing: 0) {
                    AcademicsAuditPanel(
                        majors: majors,
                        minors: minors,
                        academicProfile: selectedAcademicProfile,
                        activePage: $activePage,
                        isInspectorPresented: $isInspectorPresented,
                        scrollToProgramID: $requirementsScrollTargetID
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(AcademicsEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                    AcademicsBottomSummaryStrip(
                        programs: programCreditRows,
                        onSelectProgram: { stripID in
                            requirementsScrollTargetID = AcademicsProgramRequirementsScrollID
                                .forStripSelection(stripID)
                        }
                    )
                }
                .frame(width: contentWidth, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .task(id: creditLayoutToken) {
            auditSnapshotStore.scheduleCreditLayoutRefresh(
                token: creditLayoutToken,
                collegePersistence: collegePersistence,
                academicProfile: selectedAcademicProfile,
                majors: majors,
                minors: minors,
                plannerSemesters: plannerSemesters.isEmpty
                    ? collegePersistence.semesters
                    : plannerSemesters,
                metricsCreditsRequired: academicMetricsStore.snapshot?.creditsRequired
            )
        }
        // Anchor a hidden reference so SwiftUI tracks `specializationSelectionVersion` as
        // a dependency of `body`. Whenever the audit sidebar picker bumps it, the body
        // recomputes — and the embedded `requirementProgress(...)` local store lookup picks
        // up the new specialization choice through `applySpecializationFilter`.
        .background(
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .id(specializationSelectionVersion)
        )
        .onReceive(NotificationCenter.default.publisher(for: .auditSpecializationSelectionChanged)) { _ in
            specializationSelectionVersion &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .graduationPlanChanged)) { _ in
            // Bump the same version dependency so the Graduation Timeline card and any
            // credit-progress reads pick up the new structured target / per-term caps.
            specializationSelectionVersion &+= 1
        }
        .background {
            AcademicsSemesterQueryHost(
                onSemesterCountChange: { count in
                    plannerCourseCount = count
                },
                onPlannerSemestersChange: { semesters in
                    plannerSemesters = semesters
                }
            )
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            
        }
        .sheet(isPresented: $showGraduationSheet) {
            GraduationTimelineConfigSheet(
                academicProfile: selectedAcademicProfile,
                requiredCredits: resolvedGraduationCreditsRequired,
                completedCredits: buckets.completed,
                inProgressCredits: buckets.inProgress,
                plannedCredits: buckets.planned
            )
            }
        .onAppear {
            
            collegePersistence.fetchSemesters()
            collegePersistence.fetchProfile()
            collegePersistence.reconcileDeclaredProgramDegreeMetadata()
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = toolbarDispatcher.register(owner: .academics) { action in
                handleAcademicsToolbarAction(action)
            }

            guard !hasAnimatedIn else { return }
            withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.30, dampingFraction: 0.88)) {
                hasAnimatedIn = true
            }
        }
        .onDisappear {
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
        }
    }

    private func handleAcademicsToolbarAction(_ action: ToolbarAction) {
        guard case .academics(let academicsAction) = action else { return }
        switch academicsAction {
        case .statsSidebarToggle:
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                academicsScene.statsSidebarShown.toggle()
            }
        case .addCourse:
            let activePlanSemesters = collegePersistence.getActivePlan()?.semestersArray ?? []
            let source = activePlanSemesters.isEmpty ? collegePersistence.semesters : activePlanSemesters
            let semester = AcademicTermResolver.resolveCurrentSemester(from: source)
                ?? source.first(where: { !$0.isPlanned })
                ?? source.last
            if let semesterID = semester?.id {
                modalCoordinator.activeModal = .addCatalogCourse(semesterID: semesterID)
            } else {
                modalCoordinator.activeModal = .addCatalogCourseGlobal(tagAsGenEd: false)
            }
        }
    }

    private var isCourseDashboardActive: Bool {
        if case .courseDashboard = modalCoordinator.activeModal { return true }
        return false
    }

    private static func formatPlannerGPA(_ snapshot: AcademicMetricsSnapshot?) -> String {
        guard let g = snapshot?.cumulativeGPA else { return "—" }
        return String(format: "%.2f", g)
    }

    // MARK: - Semester GPA helper

    private func semesterGPA(_ semester: PlannerSemester) -> Double? {
        func gradePoints(_ grade: String) -> Double? {
            let g = grade.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let excluded: Set<String> = ["P","PASS","S","SAT","W","WD","I","INC","AU","NG","NR"]
            if excluded.contains(g) { return nil }
            switch g {
            case "A+","A": return 4.0
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
                let stripped = g.replacingOccurrences(of: "%", with: "")
                if let pct = Double(stripped) {
                    switch pct {
                    case 93...: return 4.0
                    case 90..<93: return 3.7
                    case 87..<90: return 3.3
                    case 83..<87: return 3.0
                    case 80..<83: return 2.7
                    case 77..<80: return 2.3
                    case 73..<77: return 2.0
                    case 70..<73: return 1.7
                    case 67..<70: return 1.3
                    case 63..<67: return 1.0
                    case 60..<63: return 0.7
                    default: return 0.0
                    }
                }
                return nil
            }
        }
        var qp = 0.0; var cr = 0.0
        for c in semester.coursesArray {
            guard c.isCompleted, let g = c.grade, !g.isEmpty,
                  let pts = gradePoints(g) else { continue }
            qp += pts * Double(c.credits)
            cr += Double(c.credits)
        }
        return cr > 0 ? (qp / cr * 100).rounded() / 100 : nil
    }

    // Legacy `mainCard / cardInnerHeader / splitContent / degreeCardsSection /
    // semesterListSection / legendDot` helpers powered the old horizontal-dashboard
    // layout. They were removed when this view was restructured to the new
    // `AcademicsLeftStatsSidebar` + wide Requirements canvas in `body`. Their
    // backing helper types (`AcademicsDegreeCard`, `LandscapeDashboard`, etc.)
    // remain in this file as `private struct`s for possible reuse later.
}

// MARK: - Degree Progress Card

private struct AcademicsDegreeCard: View {
    struct BarRow {
        let label: String
        let progress: CollegePersistence.CreditsProgressSummary
        let color: Color
    }

    let badge: String
    let badgeColor: Color
    let title: String
    let circleColor: Color
    let progress: CollegePersistence.CreditsProgressSummary
    let rows: [BarRow]

    @State private var isCardHovered = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pct: Int { Int((progress.fraction * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row + progress circle
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(badge)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .tracking(0.8)
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(progress.fraction) : 0)
                        .stroke(circleColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48)
                .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)
            }

            Spacer(minLength: 0)

            // Progress bars
            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    let row = rows[i]
                    VStack(spacing: 4) {
                        HStack {
                            Text(row.label)
                                .font(DesignSystem.Fonts.main(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(
                                row.progress.requiredRoundedInt > 0
                                    ? "\(row.progress.completedRoundedInt)/\(row.progress.requiredRoundedInt) Cr"
                                    : "\(row.progress.completedRoundedInt) Cr"
                            )
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(row.color)
                                    .frame(
                                        width: appeared ? max(0, geo.size.width * CGFloat(row.progress.fraction)) : 0,
                                        height: 6
                                    )
                                    .animation(.spring(response: 0.7, dampingFraction: 0.84), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .scaleEffect(isCardHovered && !reduceMotion ? 1.015 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isCardHovered)
        .onHover { isCardHovered = $0 }
        .pointerStyle(.link)
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Semester row ↔ requirement breakdown (shared rules)

/// Progress for a single requirement course row, derived from planner courses matching that code.
enum RequirementPlanProgress: Int, Comparable, Equatable {
    /// No matching course on any semester.
    case notOnPlan = 0
    /// On a semester but not active / not finished (draft, future term, etc.).
    case planned = 1
    case inProgress = 2
    case completed = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Keeps `AcademicsCourseRow` and the requirements breakdown on the same completion rules.
enum AcademicsCourseSchedule {
    static func semesterHasEnded(_ course: PlannerCourse, asOf today: Date = Date()) -> Bool {
        guard let sem = course.semester else { return false }
        let yr = Int(sem.year)
        let month: Int
        switch sem.season.lowercased() {
        case "winter": month = 1
        case "spring": month = 5
        case "summer": month = 8
        default:       month = 12
        }
        let end = Calendar.current.date(from: DateComponents(year: yr, month: month, day: 28)) ?? .distantPast
        return end < today
    }

    /// Same string the semester card shows as status (including past-term “Completed” override).
    static func displayStatus(course: PlannerCourse, asOf today: Date = Date()) -> String {
        let status = course.status.isEmpty ? "Draft" : course.status
        if semesterHasEnded(course, asOf: today), !status.lowercased().contains("complet") {
            return "Completed"
        }
        return status
    }

    /// Counts for degree requirement math and green checkmarks — not just the `isCompleted` local store flag.
    static func countsTowardRequirementCompletion(_ course: PlannerCourse, asOf today: Date = Date()) -> Bool {
        if course.isCompleted { return true }
        let shown = displayStatus(course: course, asOf: today).lowercased()
        if shown.contains("incomplete") { return false }
        if shown.contains("complet") { return true }
        return false
    }

    static func singleCoursePlanProgress(_ course: PlannerCourse, asOf today: Date = Date()) -> RequirementPlanProgress {
        if countsTowardRequirementCompletion(course, asOf: today) { return .completed }
        let raw = course.status.lowercased()
        if raw.contains("enroll") || raw.contains("in progress") || raw.contains("registered") { return .inProgress }
        if raw.contains("waitlist") { return .inProgress }
        return .planned
    }

    static func mergeProgress(_ a: RequirementPlanProgress?, _ b: RequirementPlanProgress) -> RequirementPlanProgress {
        Swift.max(a ?? .notOnPlan, b)
    }
}

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
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
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
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(gpa)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("plan")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(name)
                    .font(.system(size: 18, weight: .bold))
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
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requirement progress")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(creditsTowardRequirementLine)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(8)
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
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Graduation Timeline")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        if let expectedGraduation, !expectedGraduation.isEmpty {
                            Text(expectedGraduation.uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(timelineSubtitle)
                        .font(.system(size: 13, weight: .medium))
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
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        if requiredCredits > 0 {
                            Text("\(Int(totalCredits))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)

                            Text("/ \(Int(requiredCredits)) Credits")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(totalCredits)) cr earned")
                                .font(.system(size: 14, weight: .bold))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(8)
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(semester.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !isCollapsed {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("\(totalSemesterCredits) Total Credits")
                                .font(.system(size: 12, weight: .bold))
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                if !isCollapsed {
                    Table(sortedCourses) {
                        TableColumn("Course") { course in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.code)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(resolvedTitle(for: course))
                                    .font(.system(size: 11, weight: .medium))
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
                                .font(.system(size: 12))
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
                                .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(course.isCompleted ? .green : .accentColor)
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
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    @Environment(AppContainer.self) private var appContainer

    private var persistence: CollegePersistence { appContainer.persistence }
    private var modalCoordinator: ModalCoordinator { appContainer.modalCoordinator }
    @State private var dropTargetCategoryID: UUID?
    /// Drives `.scrollPosition` for the requirements `List` (reliable with lazy rows).
    @State private var listScrollAnchorID: String?

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

    /// Returns the currently-chosen option title for `(degree, group)`, defaulting to the
    /// first option when the user hasn't picked yet. The defaulting matches the contract
    /// `AuditSpecializationStore.nonSelectedOptionTitles(for:)` uses elsewhere so the audit
    /// sidebar's view-state and the credit calculator's filter stay in lockstep.
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
        return group.options.first?.title ?? ""
    }

    /// True when this category is an option in a specialization XOR group AND it's not the
    /// user's current pick. The sidebar still renders these rows but dims them so the user
    /// can see what the alternative path looks like without it counting toward totals.
    private func isDimmedNonSelectedOption(
        category: AcademicsAuditPanel.AuditCategory,
        in degree: AcademicsAuditPanel.AuditDegree
    ) -> Bool {
        guard let groupKey = category.specializationGroupKey,
              let group = degree.specializationGroups.first(where: { $0.key == groupKey })
        else { return false }
        return chosenOptionTitle(for: group, in: degree) != category.title
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
        Set(auditDegrees.flatMap { degree in
            degree.categories.map(\.id)
        })
    }

    private var firstOptionalProgramIndex: Int? {
        auditDegrees.firstIndex(where: { !$0.isGraduationRequirement })
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
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)
            
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
            } else if auditDegrees.isEmpty {
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
                    .padding(24)
            } else {
                List {
                    Color.clear
                        .frame(height: 1)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .id(AcademicsProgramRequirementsScrollID.top)
                        .accessibilityHidden(true)

                    ForEach(auditDegrees.indices, id: \.self) { degreeIndex in
                        let degree = auditDegrees[degreeIndex]
                        if let firstOptional = firstOptionalProgramIndex, firstOptional == degreeIndex {
                            optionalProgramsIntroSection
                        }
                        degreeRequirementsSection(degree: degree)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 36)
                .scrollContentBackground(.hidden)
                .scrollTargetLayout()
                .scrollPosition(id: $listScrollAnchorID, anchor: .top)
                .background(Palette.panelBackground)
                .animation(nil, value: expandedCategories)
                .animation(
                    motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.86),
                    value: hideCompleted
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
           let targetIndex = auditDegrees.firstIndex(where: {
               AcademicsProgramRequirementsScrollID.forDegree($0) == target
           }) {
            for degree in auditDegrees.prefix(targetIndex + 1) {
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

            ForEach(Array(degree.categories.enumerated()), id: \.element.id) { index, category in
                                let previous = index > 0 ? degree.categories[index - 1] : nil

                                if let section = category.sectionHeader,
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
                                // counts toward the total.
                                if let groupKey = category.specializationGroupKey,
                                   isFirstAppearance(of: groupKey, category: category, in: degree),
                                   let group = degree.specializationGroups.first(where: { $0.key == groupKey })
                                {
                                    specializationPicker(for: group, in: degree)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
                                        .listRowSeparator(.hidden)
                                }

                                categoryView(
                                    category: category,
                                    degree: degree,
                                    isDimmed: isDimmedNonSelectedOption(category: category, in: degree)
                                )
                                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                                .listRowSeparator(.visible, edges: .bottom)
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
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Palette.subduedText)
                                        .tracking(0.5)
                                }
                            }
                            .padding(.bottom, 2)
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
                        specializationSelections[cacheKey] = group.options.first?.title
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
                ForEach(group.options) { option in
                    Button {
                        specializationSelections[cacheKey] = option.title
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
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(8)
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
        let isDone = RequirementBreakdownParser.isCategoryDone(category: category)
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
                            .font(.system(size: 12, weight: .bold))
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

                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AcademicsStatusPalette.completedDot)
                    }

                    Spacer(minLength: 8)

                    if !isDone && progressTarget > 0 {
                        InlineCategoryProgressBar(fraction: progressFraction)
                            .frame(width: 80)
                    }

                    if let trailingLabel {
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
                                selectionMode: selectable,
                                isSelected: selected.contains(
                                    item.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                ),
                                isDimmed: itemDimmed,
                                onSelect: selectable ? {
                                    toggleRequirementSelection(item: item, category: category, degree: degree)
                                } : nil
                            )
                        }
                    }
                    .padding(.leading, bodyInset)
                }
            }
            .opacity(isDimmed ? 0.42 : 1)
            .saturation(isDimmed ? 0.6 : 1)
            .allowsHitTesting(!isDimmed)
            .accessibilityLabel(isDimmed ? "\(category.title), not selected — alternative path" : category.title)
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
                    guard let code = object?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !code.isEmpty else { return }
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
}

/// Per-course row in the Requirements Breakdown. Matches the Figma's rich layout:
/// a small status bullet → course code (accent) → full course title → letter grade
/// (accent) → credit count. The bullet color is driven by `AcademicsStatusPalette`
/// so it stays in lockstep with the semester pills and the bottom summary strip.
private struct CourseProgressRow: View {
    var code: String
    var title: String
    var credits: String
    var grade: String?
    var planProgress: RequirementPlanProgress
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var isDimmed: Bool = false
    var onSelect: (() -> Void)? = nil

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
                    .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .overlay {
                    BreakdownTooltipCapture(text: code)
                }

            if !trimmedTitle.isEmpty {
                Text(trimmedTitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        BreakdownTooltipCapture(text: trimmedTitle)
                    }
            }

            Spacer(minLength: 8)

            if let g = trimmedGrade {
                Text(g)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !creditsLabel.isEmpty {
                Text(creditsLabel)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .opacity(isDimmed ? 0.38 : 1)
        .saturation(isDimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            selectionMode
                ? "\(accessibilityTooltip) — \(isSelected ? "selected" : isDimmed ? "not selected" : "tap to select")"
                : accessibilityTooltip
        )
        .accessibilityAddTraits(selectionMode ? .isButton : [])
    }
}

#if os(macOS)
/// Invisible AppKit layer so truncated List labels show the full string on hover (SwiftUI `.help` is unreliable in `List`).
private struct BreakdownTooltipCapture: NSViewRepresentable {
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
private struct BreakdownTooltipCapture: View {
    let text: String
    var body: some View { Color.clear.help(text) }
}
#endif

/// Single- or multi-line label that truncates with "…" and reveals the full text on hover.
private struct BreakdownTruncatingLabel: View {
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



private struct InlineCategoryProgressBar: View {
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
