// SyllabusReviewView.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — SyllabusReviewView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import SwiftData

struct SyllabusReviewView: View {
    @Environment(AppContainer.self) private var container
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var securityManager: SecurityManager { container.securityManager }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
                @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    let courseCode: String
    let defaultCourseName: String
    let semesterText: String?
    let overrideEntity: CourseOverride?
    let plannedCourse: PlannerCourse?
    let onClose: () -> Void

    @StateObject private var vm = SyllabusAnalysisViewModel()

    @State private var showRawPreview = false
    @State private var didPersistGrading: Bool = false
    @State private var didPersistInstructor: Bool = false

    private enum MainTab: String, CaseIterable {
        case events = "Events"
        case professor = "Professor"
    }

    @State private var mainTab: MainTab = .events

    @State private var conflictLookup: [UUID: [ConflictEvent]] = [:]
    @State private var conflictSheetDraft: ConflictSheetDraft? = nil
    @State private var sortAscending: Bool = true
    @State private var selectedSection: SyllabusSection? = nil

    // Derived-state caches — recomputed only when dependencies change, not on every render.
    @State private var cachedSortedDraftIndices: [Int] = []
    @State private var cachedSelectedDraftCount: Int = 0
    @State private var cachedWorkloadProfile: WorkloadProfile? = nil
    @State private var conflictsRefreshTask: Task<Void, Never>? = nil
    @State private var manualLocation: String = ""

    var body: some View {
        ZStack {
            DesignSystem.Colors.bgMain
                .ignoresSafeArea()

            workspaceShell
                .padding(16)
        }
        .frame(minWidth: 980, minHeight: 680)
        .task { await startIfPossible() }
        .onChange(of: vm.phase) { _, newValue in
            guard case .ready = newValue else { return }
            persistGradingIfPossible()
            persistInstructorIfPossible()
            refreshDerivedState()
            refreshConflicts()
        }
        .onChange(of: vm.draftEvents) { _, _ in
            guard vm.phase == .ready else { return }
            refreshDerivedState()
            scheduleConflictsRefresh()
        }
        .onChange(of: sortAscending) { _, _ in
            // Re-sort without re-fetching CollegePersistence.
            cachedSortedDraftIndices = computeSortedDraftIndices()
        }
        .sheet(item: $conflictSheetDraft) { sheet in
            ConflictSheet(
                title: "Conflict Details",
                events: conflictLookup[sheet.id] ?? []
            )
            .dismissOnOutsideClickForSheet()
        }
    }

    private struct ConflictSheetDraft: Identifiable {
        let id: UUID
    }

    private func persistGradingIfPossible() {
        guard !didPersistGrading else { return }
        guard vm.phase == .ready else { return }
        guard let plannedCourse else {
            if !vm.syllabusData.grading.isEmpty {
                notifications.post(
                    kind: .info,
                    title: "Weights Not Saved",
                    message: "Add this course to a semester plan to sync grading weights into Tasks.",
                    isDismissible: true,
                    autoDismissAfter: 5
                )
            }
            return
        }

        let upserted = collegePersistence.upsertGradingCategories(for: plannedCourse, items: vm.syllabusData.grading, source: "syllabus_ai")
        didPersistGrading = true

        if !upserted.isEmpty {
            notifications.post(
                kind: .success,
                title: "Saved Course Weights",
                message: "Synced \(upserted.count) grading categories for this course.",
                isDismissible: true,
                autoDismissAfter: 3
            )
        }
    }

    private func persistInstructorIfPossible() {
        guard !didPersistInstructor else { return }
        guard vm.phase == .ready else { return }
        guard let instructor = vm.syllabusData.instructor else { return }

        let didWrite = collegePersistence.upsertCourseInstructorContact(
            courseCode: courseCode,
            professorName: instructor.name,
            email: instructor.email,
            contactMethod: instructor.contactMethod,
            officeHours: instructor.officeHours,
            overwriteExisting: false
        )

        didPersistInstructor = true

        if didWrite {
            notifications.post(
                kind: .success,
                title: "Saved Instructor Details",
                message: "Synced professor contact info into Course Details.",
                isDismissible: true,
                autoDismissAfter: 3
            )
        }
    }

    private var workspaceShell: some View {
        GeometryReader { proxy in
            let maxWidth: CGFloat = 1200
            let height = max(620, proxy.size.height * 0.90)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 390)

                Divider()

                mainPanel
            }
            .frame(width: min(maxWidth, proxy.size.width), height: height)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.10), radius: 26, x: 0, y: 16)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COURSE ANALYSIS")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.primary.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(DesignSystem.Colors.primary.opacity(0.10), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 999))

                    Text(defaultCourseName.isEmpty ? "Course" : defaultCourseName)
                        .font(DesignSystem.Fonts.main(size: 26, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sidebarSubtitle)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }

                VStack(spacing: 12) {
                    if let sections = vm.syllabusData.sections, !sections.isEmpty {
                        sectionPickerCard(sections: sections)
                    } else {
                        InfoCard(
                            icon: "mappin.and.ellipse",
                            title: inferredLocationTitle ?? "Location not detected",
                            subtitle: inferredLocationSubtitle
                        )
                    }
                }

                gradingBreakdown

                workloadIntensity
            }
            .padding(22)
        }
        .background(sidebarBackground)
    }

    private var mainPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                mainHeader
                mainContent
            }

            if mainTab == .events {
                Button {
                    addSelectedEvents()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Import Events")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.leading, 18)
                    .padding(.trailing, 20)
                    .background(DesignSystem.Colors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
                    .shadow(color: DesignSystem.Colors.primary.opacity(0.25), radius: 18, x: 0, y: 10)
                }
                .buttonStyle(.plain)
                .padding(18)
                .disabled(vm.phase != .ready || selectedDraftCount == 0)
            }
        }
    }

    private var mainHeader: some View {
        HStack(spacing: 12) {
            if mainTab == .events {
                SelectionCircle(isOn: Binding(
                    get: { selectedDraftCount == vm.draftEvents.count && vm.draftEvents.isEmpty == false },
                    set: { newValue in setAllSelected(newValue) }
                ))
                .padding(.leading, 18)
            } else {
                Spacer().frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mainTab == .events ? "Event Review" : "Professor")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                HStack(spacing: 8) {
                    if mainTab == .events {
                        Text("\(selectedDraftCount) items selected")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)

                        Text("•")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight.opacity(0.4))

                        Text("\(vm.draftEvents.count) detected events")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    } else {
                        Text("Instructor contact details")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                }
            }

            Spacer()

            Picker("", selection: $mainTab) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Menu {
                Button {
                    sortAscending = true
                } label: {
                    Label("Oldest First", systemImage: sortAscending ? "checkmark" : "arrow.up")
                }
                Button {
                    sortAscending = false
                } label: {
                    Label("Newest First", systemImage: sortAscending ? "arrow.down" : "checkmark")
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle"
                      + (sortAscending ? "" : ".fill"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(sortAscending ? DesignSystem.Colors.textLight : DesignSystem.Colors.primary)
                    .padding(10)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke((sortAscending ? DesignSystem.Colors.textLight : DesignSystem.Colors.primary).opacity(0.20), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(mainTab != .events)
            .opacity(mainTab == .events ? 1.0 : 0.4)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(10)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignSystem.Colors.textLight.opacity(0.20), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
        }
        .padding(.vertical, 14)
        .background(
            DesignSystem.Colors.surface.opacity(0.95)
        )
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.textLight.opacity(0.12))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        switch vm.phase {
        case .idle, .extracting:
            CenteredPhaseView(title: "Extracting PDF text…")

        case .downloadingModel(let progress, let detail):
            CenteredDownloadView(progress: progress, detail: detail)

        case .analyzing:
            CenteredPhaseView(title: "Analyzing with on-device AI…")

        case .failed(let message):
            failedView(message: message)

        case .ready:
            if mainTab == .events {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedDraftIndices, id: \.self) { index in
                            let id = vm.draftEvents[index].id
                            EventReviewRow(
                                event: $vm.draftEvents[index],
                                conflictCount: conflictLookup[id]?.count ?? 0,
                                onViewConflict: { conflictSheetDraft = ConflictSheetDraft(id: id) }
                            )
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 84)
                }
                .background(DesignSystem.Colors.bgMain.opacity(0.20))
            } else {
                professorPanel
                    .background(DesignSystem.Colors.bgMain.opacity(0.20))
            }
        }
    }

    // Thin accessors — body reads the cached @State, avoiding per-render O(n log n) work.
    private var sortedDraftIndices: [Int] { cachedSortedDraftIndices }

    private func computeSortedDraftIndices() -> [Int] {
        vm.draftEvents.indices.sorted { lhs, rhs in
            let l = vm.draftEvents[lhs]
            let r = vm.draftEvents[rhs]
            if l.startDate != r.startDate {
                return sortAscending ? l.startDate < r.startDate : l.startDate > r.startDate
            }
            if l.endDate != r.endDate {
                return sortAscending ? l.endDate < r.endDate : l.endDate > r.endDate
            }
            let cmp = l.title.localizedCaseInsensitiveCompare(r.title)
            return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    private var professorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let instructor = vm.syllabusData.instructor

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Professor")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        professorRow(label: "Name", value: instructor?.name)
                        professorRow(label: "Email", value: instructor?.email)
                        professorRow(label: "Contact", value: instructor?.contactMethod)
                        professorRow(label: "Office Hours", value: instructor?.officeHours)

                        if instructor == nil {
                            Text("No instructor contact details were detected in this syllabus.")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sync")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        Text("These fields automatically sync into Course Details when detected.")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)

                        Button("Sync Now") {
                            didPersistInstructor = false
                            persistInstructorIfPossible()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.primary)
                        .disabled(vm.syllabusData.instructor == nil)
                        .opacity(vm.syllabusData.instructor == nil ? 0.4 : 1.0)
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(18)
        }
    }

    private func professorRow(label: String, value: String?) -> some View {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(width: 90, alignment: .leading)

            Text(trimmed.isEmpty ? "—" : trimmed)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Couldn’t analyze syllabus")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
            }

            Text(message)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)

            Button(showRawPreview ? "Hide Extracted Text" : "Show Extracted Text") {
                showRawPreview.toggle()
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignSystem.Colors.primary)

            if showRawPreview {
                ScrollView {
                    Text(vm.extractedPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(12)
                }
                .frame(height: 240)
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.bgMain.opacity(0.20))
    }

    private var gradingBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                    Text("Grading Breakdown")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                }
                Spacer()
            }

            HStack(spacing: 0) {
                Text("ITEM")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("WEIGHT")
                    .frame(width: 56, alignment: .trailing)
            }
            .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
            .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
            .padding(.horizontal, 2)

            if vm.phase != .ready {
                Text("Waiting for analysis…")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.vertical, 8)
            } else if vm.syllabusData.grading.isEmpty {
                Text("No grading breakdown detected.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.syllabusData.grading) { item in
                        GradingRow(item: item)

                        if item.id != vm.syllabusData.grading.last?.id {
                            Rectangle()
                                .fill(DesignSystem.Colors.textLight.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var workloadIntensity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                Text("Workload Intensity")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
            }

            if let profile = workloadProfile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PEAK STRESS")
                                .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            Text(profile.peakText)
                                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                        }

                        Spacer()

                        Text(profile.levelText)
                            .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                            .foregroundColor(profile.levelColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(profile.levelColor.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    SparkAreaChart(values: profile.weeklyCounts)
                        .frame(height: 64)

                    HStack {
                        Text("Week 1")
                        Spacer()
                        Text("Peak")
                        Spacer()
                        Text("Finals")
                    }
                    .font(DesignSystem.Fonts.main(size: 9, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
                }
                .padding(12)
                .background(DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text(vm.phase == .ready ? "Not enough dated items to estimate workload." : "Waiting for analysis…")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.vertical, 6)
            }
        }
    }

    private var sidebarBackground: some View {
        DesignSystem.Colors.surface
            .opacity(0.55)
    }

    private var sidebarSubtitle: String {
        let code = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let sem = (semesterText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty, !sem.isEmpty { return "\(code) • \(sem)" }
        if !code.isEmpty { return code }
        return sem.isEmpty ? "" : sem
    }

    private var inferredLocationTitle: String? {
        nil
    }

    private var inferredLocationSubtitle: String? {
        "Add a class meeting event with a location to show this here."
    }

    @ViewBuilder
    private func sectionPickerCard(sections: [SyllabusSection]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
                Text("Your Section")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
            }

            // Section picker menu
            Menu {
                Button("None — keep all-day") {
                    selectedSection = nil
                    vm.clearSectionTimes()
                }
                Divider()
                ForEach(sections) { section in
                    Button {
                        selectedSection = section
                        vm.applySection(section, manualLocation: manualLocation.isEmpty ? nil : manualLocation)
                    } label: {
                        HStack {
                            Text(section.label)
                            if let days = section.meetingDays, !days.isEmpty {
                                Text("· " + days.map(\.shortLabel).joined(separator: " "))
                                    .foregroundColor(.secondary)
                            }
                            if let start = section.startTime, let end = section.endTime {
                                Text("· \(formatTime(start))–\(formatTime(end))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedSection?.label ?? "Select your section…")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(selectedSection == nil
                            ? DesignSystem.Colors.textLight
                            : DesignSystem.Colors.textMain)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(DesignSystem.Colors.bgMain)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignSystem.Colors.primary.opacity(selectedSection != nil ? 0.5 : 0.18), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)

            if let sel = selectedSection {
                // Show detected location, or allow manual override
                let detectedLoc = sel.location ?? ""
                VStack(alignment: .leading, spacing: 4) {
                    Text("Building / Room")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    TextField(detectedLoc.isEmpty ? "e.g. Norton 112" : detectedLoc,
                              text: $manualLocation)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(DesignSystem.Colors.bgMain)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: manualLocation) { _, newValue in
                            vm.updateSectionLocation(newValue.isEmpty ? nil : newValue)
                        }
                }
                if let days = sel.meetingDays, !days.isEmpty,
                   let start = sel.startTime, let end = sel.endTime {
                    Text("\(days.map(\.shortLabel).joined(separator: " · ")) · \(formatTime(start))–\(formatTime(end))")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            } else {
                Text("Pick your section to add meeting times to calendar events.")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// Formats a 24h "HH:mm" string to a short 12h label like "10:00 AM".
    private func formatTime(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return hhmm }
        let period = h < 12 ? "AM" : "PM"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return m == 0 ? "\(h12) \(period)" : String(format: "%d:%02d %@", h12, m, period)
    }

    private var selectedDraftCount: Int { cachedSelectedDraftCount }

    private func computeSelectedDraftCount() -> Int {
        vm.draftEvents.filter(\.include).count
    }

    private func setAllSelected(_ selected: Bool) {
        for i in vm.draftEvents.indices {
            vm.draftEvents[i].include = selected
        }
    }

    private func refreshConflicts() {
        guard vm.phase == .ready else { return }
        guard let semester = plannedCourse?.semester else {
            conflictLookup = [:]
            return
        }
        guard !vm.draftEvents.isEmpty else {
            conflictLookup = [:]
            return
        }

        let minStart = vm.draftEvents.map(\.startDate).min() ?? Date()
        let maxEnd = vm.draftEvents.map(\.endDate).max() ?? minStart
        let existing = collegePersistence.fetchCalendarEvents(semester: semester, start: minStart, end: maxEnd)

        var next: [UUID: [ConflictEvent]] = [:]
        for draft in vm.draftEvents {
            // Only check time-based conflicts; skip all-day events.
            guard !draft.allDay else { continue }
            let overlaps = existing.compactMap { e -> ConflictEvent? in
                // Skip if the existing event is all-day — no time conflict possible.
                guard !e.allDay else { return nil }
                guard e.startDate < draft.endDate, e.endDate > draft.startDate else { return nil }
                return ConflictEvent(
                    id: e.id,
                    title: e.title,
                    start: e.startDate,
                    end: e.endDate,
                    location: e.location
                )
            }
            if !overlaps.isEmpty {
                next[draft.id] = overlaps
            }
        }

        conflictLookup = next
    }

    private struct WorkloadProfile {
        let weeklyCounts: [Int]
        let peakText: String
        let levelText: String
        let levelColor: Color
    }

    private var workloadProfile: WorkloadProfile? { cachedWorkloadProfile }

    private var computedWorkloadProfile: WorkloadProfile? {
        guard vm.phase == .ready else { return nil }
        let events = vm.draftEvents
        guard events.count >= 3 else { return nil }

        let sorted = events.sorted(by: { $0.startDate < $1.startDate })
        guard let first = sorted.first?.startDate else { return nil }

        // Week index is relative to earliest event, so we can display "Week 8-9" style.
        func startOfWeek(_ date: Date) -> Date {
            let cal = calendar
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return cal.date(from: comps) ?? cal.startOfDay(for: date)
        }

        let base = startOfWeek(first)
        var countsByWeek: [Int: Int] = [:]
        var maxWeek = 1

        for ev in sorted {
            let wkStart = startOfWeek(ev.startDate)
            let diff = calendar.dateComponents([.weekOfYear], from: base, to: wkStart).weekOfYear ?? 0
            let idx = max(1, diff + 1)
            countsByWeek[idx, default: 0] += 1
            maxWeek = max(maxWeek, idx)
        }

        let weeklyCounts = (1...maxWeek).map { countsByWeek[$0, default: 0] }
        guard let maxCount = weeklyCounts.max(), maxCount > 0 else { return nil }

        let peakWeeks = weeklyCounts.enumerated().filter { $0.element == maxCount }.map { $0.offset + 1 }
        let peakText: String
        if let firstPeak = peakWeeks.first, let lastPeak = peakWeeks.last, firstPeak != lastPeak {
            peakText = "Week \(firstPeak)-\(lastPeak)"
        } else {
            peakText = "Week \(peakWeeks.first ?? 1)"
        }

        let level: (String, Color)
        if maxCount >= 6 {
            level = ("HIGH", DesignSystem.Colors.warning)
        } else if maxCount >= 4 {
            level = ("MED", DesignSystem.Colors.info)
        } else {
            level = ("LOW", DesignSystem.Colors.success)
        }

        return WorkloadProfile(
            weeklyCounts: weeklyCounts,
            peakText: peakText,
            levelText: level.0,
            levelColor: level.1
        )
    }

    /// Recomputes all derived state that depends on draftEvents / sortAscending / phase.
    private func refreshDerivedState() {
        cachedSortedDraftIndices = computeSortedDraftIndices()
        cachedSelectedDraftCount = computeSelectedDraftCount()
        cachedWorkloadProfile    = computedWorkloadProfile
    }

    /// Debounced wrapper — avoids a CollegePersistence fetch + O(n²) scan on every single checkbox toggle.
    private func scheduleConflictsRefresh() {
        conflictsRefreshTask?.cancel()
        conflictsRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            refreshConflicts()
        }
    }

    private func startIfPossible() async {
        // Fast path: restore from per-course cache without touching the PDF.
        if vm.tryApplyCachedForCourse(
            courseCode: courseCode,
            semesterText: semesterText,
            calendar: calendar,
            timeZone: timeZone
        ) { return }

        guard let overrideEntity else {
            vm.setFailed("No syllabus is saved for this course yet.")
            return
        }
        guard let encrypted = overrideEntity.syllabusFileBookmarkData,
              let bookmark = securityManager.decryptBlobFromStorage(encrypted) else {
            vm.setFailed("Could not access the saved syllabus PDF.")
            return
        }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            vm.setFailed("Could not resolve the syllabus file bookmark.")
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        await vm.analyzeSyllabus(
            pdfURL: url,
            courseCode: courseCode,
            courseName: defaultCourseName,
            semesterText: semesterText,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private func addSelectedEvents() {
        // Ensure we have a CourseEntity to attach to.
        let course = plannedCourse
        if course == nil {
            // Best-effort: course isn’t in planner, so we can’t guarantee referential integrity.
            notifications.post(
                kind: .error,
                title: "Course Not Scheduled",
                message: "Add this course to a semester plan before importing syllabus dates.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        let semester = course?.semester

        let selected = vm.draftEvents.filter(\.include)
        if selected.isEmpty { return }

        let courseUUIDString = course?.id.uuidString

        var created: [UUID] = []
        for ev in selected {
            // Deduplicate: skip if an event with the same title and start time already exists.
            let expectedTitle = "\(courseCode): \(ev.title)"
            let expectedStart: Date = {
                if ev.allDay { return calendar.startOfDay(for: ev.startDate) }
                return ev.startDate
            }()
            let alreadyExists: Bool = {
                var descriptor = FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate { event in
                        event.title == expectedTitle && event.startDate == expectedStart
                    }
                )
                descriptor.fetchLimit = 1
                let ctx = AppDataStore.shared.profileContext
                return ((try? ctx.fetch(descriptor))?.isEmpty == false)
            }()
            if alreadyExists { continue }
            var notes = ev.notes
            if let courseUUIDString {
                let tag = "\n\n[course_uuid]=\(courseUUIDString)\n[source]=syllabus_pdf"
                notes = (notes ?? "") + tag
            }

            // For all-day events, store start/end using exclusive end-date semantics
            // (end = start of day after the selected end date).
            let startDate: Date
            let endDate: Date
            if ev.allDay {
                let startDay = calendar.startOfDay(for: ev.startDate)
                let endDayInclusive = calendar.startOfDay(for: ev.endDate)
                let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDayInclusive) ?? endDayInclusive
                startDate = startDay
                endDate = max(endExclusive, startDay.addingTimeInterval(60 * 60 * 24))
            } else {
                startDate = ev.startDate
                endDate = ev.endDate
            }

            let eventID = collegePersistence.addCalendarEvent(
                title: "\(courseCode): \(ev.title)",
                startDate: startDate,
                endDate: endDate,
                allDay: ev.allDay,
                semester: semester,
                course: course,
                notes: notes,
                location: ev.location
            )
            created.append(eventID)
        }

        for eventID in created {
            if let swiftEvent = try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: eventID) {
                calendarManager.exportEventToAppleCalendar(swiftEvent, calendarName: courseCode)
            } else if let entity = collegePersistence.calendarEventEntity(id: eventID) {
                calendarManager.exportEventToAppleCalendar(entity, calendarName: courseCode)
            }
        }

        notifications.post(
            kind: .success,
            title: "Added to Calendar",
            message: "Imported \(created.count) syllabus events.",
            isDismissible: true,
            autoDismissAfter: 4
        )

        onClose()
    }
}

private struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignSystem.Colors.textLight.opacity(0.14), lineWidth: 1)
            )
    }
}

private struct ConflictEvent: Identifiable, Hashable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let location: String?
}

private struct InfoCard: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignSystem.Colors.primary.opacity(0.10))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DesignSystem.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SelectionCircle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isOn ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
}

private struct CenteredPhaseView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain.opacity(0.20))
    }
}

private struct CenteredDownloadView: View {
    let progress: Double
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: progress)
                .frame(width: 420)

            Text(detail)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Text("This runs locally on your Mac once downloaded.")
                .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain.opacity(0.20))
    }
}

private struct GradingRow: View {
    let item: SyllabusGradingItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(DesignSystem.Colors.textLight.opacity(0.35))
                .frame(width: 7, height: 7)

            Text(item.name)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.weightPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct EventReviewRow: View {
    @Binding var event: SyllabusAnalysisViewModel.DraftSyllabusEvent
    let conflictCount: Int
    let onViewConflict: () -> Void

    @State private var isHovering: Bool = false

    private var rowBorder: Color {
        if conflictCount > 0 {
            return DesignSystem.Colors.error.opacity(isHovering ? 0.55 : 0.35)
        }
        return DesignSystem.Colors.textLight.opacity(isHovering ? 0.25 : 0.18)
    }

    private var rowBackground: Color {
        if conflictCount > 0 {
            return DesignSystem.Colors.error.opacity(0.05)
        }
        return DesignSystem.Colors.surface
    }

    private var kindBadge: (String, Color) {
        let raw = event.kind.rawValue.uppercased()
        switch event.kind {
        case .reading:
            return (raw, Color.blue)
        case .quiz:
            return (raw, Color.orange)
        case .exam, .midterm, .final:
            return (raw, DesignSystem.Colors.error)
        case .assignment, .homework, .project, .lab:
            return (raw, DesignSystem.Colors.warning)
        case .other:
            let t = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = t.lowercased()
            let badgeText: String
            // "Week N" events: show the topic from notes as the badge.
            let isWeekTitle = t.range(of: #"^Week \d+$"#, options: .regularExpression) != nil
            if isWeekTitle, let topic = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty {
                let maxLen = 22
                badgeText = topic.count > maxLen ? (String(topic.prefix(maxLen - 1)) + "…") : topic
            } else if t.isEmpty || lower == "other" || lower == "syllabus date" {
                badgeText = "TOPIC"
            } else {
                let maxLen = 22
                badgeText = t.count > maxLen ? (String(t.prefix(maxLen - 1)) + "…") : t
            }
            return (badgeText.uppercased(), DesignSystem.Colors.textLight)
        default:
            return (raw, DesignSystem.Colors.textLight)
        }
    }

    private func symbolName() -> String {
        switch event.kind {
        case .reading:
            return "book"
        case .quiz:
            return "questionmark.circle"
        case .exam, .midterm, .final:
            return "pencil.and.ruler"
        case .assignment, .homework, .project:
            return "doc.text"
        case .lab:
            return "testtube.2"
        case .discussion, .presentation:
            return "person.2"
        case .other:
            return "lightbulb"
        }
    }

    private var dateText: String {
        DateFormatters.monthDayYear.string(from: event.startDate)
    }

    private var timeText: String? {
        guard !event.allDay else { return nil }
        return DateFormatters.timeOnly.string(from: event.startDate)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SelectionCircle(isOn: $event.include)
                .padding(.top, 18)

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.primary.opacity(isHovering ? 0.18 : 0.12))
                    Image(systemName: symbolName())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .frame(width: 44, height: 44)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(event.title)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .lineLimit(1)

                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.primary.opacity(0.55))
                            .help("View in syllabus")

                        Text(kindBadge.0)
                            .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                            .foregroundColor(kindBadge.1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(kindBadge.1.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(kindBadge.1.opacity(0.10), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        if conflictCount > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("CONFLICT DETECTED")
                                    .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                            }
                            .foregroundColor(DesignSystem.Colors.error)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DesignSystem.Colors.error.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 14) {
                        Label(dateText, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)

                        if let t = timeText {
                            Label(t, systemImage: "clock")
                                .labelStyle(.titleAndIcon)
                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }

                        let locLabel = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                        Label(locLabel.flatMap { $0.isEmpty ? nil : $0 } ?? "—", systemImage: "mappin")
                            .labelStyle(.titleAndIcon)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                            .foregroundColor(locLabel.flatMap { $0.isEmpty ? nil : $0 } != nil
                                ? DesignSystem.Colors.textMain
                                : DesignSystem.Colors.textLight)

                        Spacer(minLength: 0)
                    }

                    if conflictCount > 0 {
                        Button {
                            onViewConflict()
                        } label: {
                            Label("View Conflict", systemImage: "eye")
                                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.error)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(DesignSystem.Colors.error.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(DesignSystem.Colors.error.opacity(0.20), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .opacity(isHovering ? 1 : 0)
                    .padding(.top, 12)
            }
            .padding(14)
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(isHovering ? 0.08 : 0.04), radius: isHovering ? 14 : 6, x: 0, y: isHovering ? 8 : 3)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                event.include.toggle()
            }
        }
    }
}

private struct DateFormatters {
    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let monthDayYearTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

private struct SparkAreaChart: View {
    let values: [Int]

    private var normalized: [CGFloat] {
        let maxV = max(values.max() ?? 0, 1)
        return values.map { CGFloat($0) / CGFloat(maxV) }
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let pts = normalized

            ZStack {
                if pts.count >= 2 {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        for i in pts.indices {
                            let x = w * CGFloat(i) / CGFloat(max(pts.count - 1, 1))
                            let y = h - (h * pts[i])
                            if i == 0 {
                                p.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                p.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [DesignSystem.Colors.primary.opacity(0.22), DesignSystem.Colors.primary.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { p in
                        for i in pts.indices {
                            let x = w * CGFloat(i) / CGFloat(max(pts.count - 1, 1))
                            let y = h - (h * pts[i])
                            if i == 0 {
                                p.move(to: CGPoint(x: x, y: y))
                            } else {
                                p.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(DesignSystem.Colors.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else {
                    Rectangle()
                        .fill(DesignSystem.Colors.primary.opacity(0.08))
                }
            }
        }
    }
}

private struct ConflictSheet: View {
    let title: String
    let events: [ConflictEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            if events.isEmpty {
                Text("No conflicts found.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(events) { e in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(e.title)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .lineLimit(2)

                                Text("\(DateFormatters.monthDayYearTime.string(from: e.start)) → \(DateFormatters.monthDayYearTime.string(from: e.end))")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textLight)

                                if let loc = e.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(loc)
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }
                            }
                            .padding(12)
                            .background(DesignSystem.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 360)
        .background(DesignSystem.Colors.bgMain)
    }
}
