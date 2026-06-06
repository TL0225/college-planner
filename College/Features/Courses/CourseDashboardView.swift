// CourseDashboardView.swift
import CollegeCalendar
// Feature: Courses
// Purpose: Courses module — CourseDashboardView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import SwiftData
import MapKit

/// Course dashboard page (inspired by the provided design screenshot).
///
/// Important: Dynamic fields (course name, code, tags, grade, tasks) are derived from existing app data.
struct CourseDashboardView: View {
    @Environment(AppContainer.self) private var container
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var calendarManager: CalendarIntegrationManager { container.calendarManager }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var securityManager: SecurityManager { container.securityManager }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
                @State private var plannerRefreshToken = 0
    @State private var dashboardPayload = CourseDashboardReadBridge.Payload(course: nil, tasks: [], events: [])

    private var profile: Profile? {
        _ = plannerRefreshToken
        return ProfilePlannerReadBridge.primaryProfile(collegePersistence: collegePersistence)
    }

    @Binding var activePage: AppPage

    let courseCode: String
    let defaultCourseName: String
    let defaultCreditsText: String
    let onClose: () -> Void

    @State private var isSyllabusPresented: Bool = false

    private enum TasksFilter: Equatable {
        case incomplete
        case all
    }

    @State private var tasksFilter: TasksFilter = .incomplete

    @State private var tasksCategoryFilter: String? = nil

    @State private var isTaskSearchActive: Bool = false
    @State private var taskSearchText: String = ""
    @FocusState private var taskSearchFocused: Bool

    @State private var showAllTasks: Bool = false
    @State private var isGPAPopoverPresented: Bool = false
    @State private var isCatalogSheetPresented: Bool = false
    @State private var prereqMet: Bool? = nil

    private enum Refined {
        static let pageBG = Color(hex: "F9F8F6")
        static let card = Color.white
        static let border = Color(hex: "E6E4E0")
        static let hover = Color(hex: "F2F0ED")
        static let text = Color(hex: "282725")
        static let muted = Color(hex: "757370")
        static let dim = Color(hex: "A19F9C")
        static let primary = Color(hex: "33312E")
    }

    fileprivate enum Formatters {
        static let monthDay: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "MMM d"
            return f
        }()

        static let weekday: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "EEEE"
            return f
        }()

        static let dateTime: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        static let weekdayShort: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = "EEE"
            return f
        }()

        static let timeOnly: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateStyle = .none
            f.timeStyle = .short
            return f
        }()

        static let dateOnly: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateStyle = .medium
            f.timeStyle = .none
            return f
        }()

        static let courseCodeRegex = try? NSRegularExpression(pattern: "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4})\\b")
    }

    @State private var logisticsResolvedLocation: ResolvedLocation? = nil
    @State private var logisticsIsResolvingLocation: Bool = false
    @State private var logisticsLocationResolveError: Bool = false
    @State private var logisticsResolvedQueryKey: String = ""
    private let courseID: UUID?

    init(
        activePage: Binding<AppPage>,
        courseCode: String,
        defaultCourseName: String,
        defaultCreditsText: String,
        courseID: UUID? = nil,
        onClose: @escaping () -> Void
    ) {
        self._activePage = activePage
        self.courseCode = Self.normalizeCourseCode(courseCode)
        self.defaultCourseName = defaultCourseName
        self.defaultCreditsText = defaultCreditsText
        self.courseID = courseID
        self.onClose = onClose
    }

    private var course: PlannerCourse? { dashboardPayload.course }
    private var tasks: [PlannerTask] { dashboardPayload.tasks }
    private var events: [CalendarEvent] { dashboardPayload.events }

    private var catalogCourse: CourseCatalog? {
        collegePersistence.getCatalogCourse(code: courseCode)
            ?? collegePersistence.getCatalogCourseMatching(code: courseCode)
    }

    private var displayCourseName: String {
        let name = (course?.name ?? defaultCourseName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Course" : name
    }

    private var displayCourseTitle: String {
        let code = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { return displayCourseName }
        return "\(code): \(displayCourseName)"
    }

    private var semesterText: String? {
        (course?.semester?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tagPills: [String] {
        var pills: [String] = []

        let major = (collegePersistence.resolvedMajorNames().first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !major.isEmpty { pills.append(major) }

        let degreeLevel = collegePersistence.primaryDegreeLevel(default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !degreeLevel.isEmpty { pills.append(degreeLevel) }

        let gradingType = (course?.gradingType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !gradingType.isEmpty { pills.append(gradingType) }

        return Array(pills.prefix(3))
    }

    private var gradeText: String {
        let g = (course?.grade ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? "—" : g
    }

    private var creditsText: String {
        let c = Int(course?.credits ?? 0)
        if c > 0 { return String(c) }
        let fallback = defaultCreditsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "—" : fallback
    }

    /// Matches `AcademicsCourseRow` / `AcademicsCourseSchedule` plan progress (not task-completion %).
    private var semesterPlanProgressPercentText: String {
        guard let c = course else { return "—" }
        switch AcademicsCourseSchedule.singleCoursePlanProgress(c) {
        case .completed:
            return "100%"
        case .inProgress:
            return "50%"
        case .planned, .notOnPlan:
            return "—"
        }
    }

    private var immediateActionTask: PlannerTask? {
        let now = Date()
        return tasks.first(where: { task in
            guard !task.isCompleted else { return false }
            guard let due = task.dueDate else { return false }
            return due >= now
        })
    }

    private var immediateActionDuePillText: String? {
        guard let due = immediateActionTask?.dueDate else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dueDay = cal.startOfDay(for: due)
        let days = cal.dateComponents([.day], from: today, to: dueDay).day
        guard let days else { return nil }
        if days <= 0 { return "Due Today" }
        if days == 1 { return "Due Tomorrow" }
        return "Due in \(days) Days"
    }

    private var professorText: String {
        (course?.professor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var professorEmailText: String {
        (collegePersistence.getCourseOverride(courseCode: courseCode)?.professorEmail ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var externalURLText: String {
        (collegePersistence.getCourseOverride(courseCode: courseCode)?.externalURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var catalogDescriptionText: String {
        let raw = (catalogCourse?.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if CollegePersistence.isUnusableCatalogDescription(raw) { return "" }
        return raw
    }

    private var catalogPrerequisitesText: String { "" }

    private var catalogCorequisitesText: String { "" }

    private var catalogTypicallyOfferedText: String { "" }

    private var statusText: String {
        let status = (course?.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return status.isEmpty ? "—" : status
    }

    private var nextUpcomingEvent: CalendarEvent? {
        let now = Date()

        // Choose the earliest event that hasn't ended yet.
        // (If endDate is missing, treat startDate as the best-effort bound.)
        let upcoming = events
            .filter { e in
                if e.endDate < now { return false }
                if e.startDate < now && e.endDate <= e.startDate { return false }
                return true
            }
            .sorted { $0.startDate < $1.startDate }

        return upcoming.first
    }

    private var logisticsAnchorEvent: CalendarEvent? {
        if let nextUpcomingEvent {
            return nextUpcomingEvent
        }

        // Fallback: use the most recent course event (even if in the past)
        // so Logistics can still show a meeting pattern/location.
        return events
            .sorted { $0.startDate > $1.startDate }
            .first
    }

    private var logisticsIsHappeningNow: Bool {
        guard let e = logisticsAnchorEvent else {
            return false
        }
        let now = Date()
        return e.startDate <= now && now <= e.endDate
    }

    private var logisticsMeetingDaysText: String? {
        guard let anchor = logisticsAnchorEvent else {
            return nil
        }
        let anchorStart = anchor.startDate
        let anchorEnd = anchor.endDate

        let calendar = Calendar.current
        let now = Date()
        let lookAheadEnd = calendar.date(byAdding: .day, value: 21, to: now) ?? now

        let anchorDuration = anchorEnd.timeIntervalSince(anchorStart)
        let anchorLocation = (anchor.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func isSimilarMeeting(_ e: CalendarEvent) -> Bool {
            let s = e.startDate
            let en = e.endDate
            if s < now || s > lookAheadEnd { return false }

            let duration = en.timeIntervalSince(s)
            if abs(duration - anchorDuration) > 60 * 15 { return false }

            // If the anchor has a location, prefer meetings with the same location.
            if !anchorLocation.isEmpty {
                let loc = (e.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if loc != anchorLocation { return false }
            }
            return true
        }

        let candidates = events.filter(isSimilarMeeting)
        var weekdaySet = Set<Int>()
        for e in candidates {
            weekdaySet.insert(calendar.component(.weekday, from: e.startDate))
        }

        // Fallback: if we couldn't infer multiple meeting days, use anchor day.
        if weekdaySet.isEmpty {
            weekdaySet.insert(calendar.component(.weekday, from: anchorStart))
        }

        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1] // Mon..Sun
        // Hardcoded labels in Mon..Sun order.
        let labelByWeekday: [Int: String] = [
            1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"
        ]
        let labels = orderedWeekdays.compactMap { weekdaySet.contains($0) ? labelByWeekday[$0] : nil }
        return labels.isEmpty ? nil : labels.joined(separator: " / ")
    }

    private var logisticsMeetingTimeText: String? {
        guard let anchor = logisticsAnchorEvent else { return nil }
        let start = anchor.startDate
        let end = anchor.endDate
        let s = Formatters.timeOnly.string(from: start)
        let e = Formatters.timeOnly.string(from: end)
        return "\(s) - \(e)"
    }

    private var logisticsLocationQuery: String {
        let raw = (logisticsAnchorEvent?.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }

        // If the anchor event has no location, fall back to any known location on this course's events.
        let fallback = events
            .sorted { $0.startDate > $1.startDate }
            .compactMap { ($0.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        return fallback ?? ""
    }

    private var logisticsUniversityHintName: String {
        let active = (collegePersistence.getActiveUniversity()?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !active.isEmpty { return active }

        let profileName = (profile?.collegeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return profileName
    }

    private func logisticsQueryCandidates(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Heuristic: if the string looks like "Building, Room", prefer searching for just the building.
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let buildingOnly = parts.first ?? trimmed

        var candidates: [String] = []
        func add(_ s: String) {
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { return }
            if !candidates.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) {
                candidates.append(v)
            }
        }

        // Try building-only first; room numbers often confuse geocoding.
        add(buildingOnly)
        add(trimmed)

        let hint = logisticsUniversityHintName
        if !hint.isEmpty {
            add("\(buildingOnly), \(hint)")
            add("\(trimmed), \(hint)")
        }

        return candidates
    }

    private func resolveLogisticsLocationIfNeeded() async {
        let query = logisticsLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            logisticsResolvedLocation = nil
            logisticsLocationResolveError = false
            logisticsResolvedQueryKey = ""
            return
        }

        let queryKey = "\(query.lowercased())|\(logisticsUniversityHintName.lowercased())"
        if logisticsResolvedQueryKey == queryKey, logisticsResolvedLocation != nil {
            return
        }

        logisticsIsResolvingLocation = true
        logisticsLocationResolveError = false
        defer { logisticsIsResolvingLocation = false }

        do {
            // Optional: bias searches to the active university/campus.
            var biasRegion: MKCoordinateRegion? = nil
            let uniHint = logisticsUniversityHintName
            if !uniHint.isEmpty {
                let uniReq = MKLocalSearch.Request()
                uniReq.naturalLanguageQuery = uniHint
                let uniSearch = MKLocalSearch(request: uniReq)
                if let uniResp = try? await uniSearch.start(), let uniItem = uniResp.mapItems.first {
                    let c = uniItem.location.coordinate
                    biasRegion = MKCoordinateRegion(
                        center: c,
                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                    )
                }
            }

            let candidates = logisticsQueryCandidates(for: query)
            var foundItem: MKMapItem? = nil
            for candidate in candidates {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = candidate
                if let biasRegion {
                    request.region = biasRegion
                }

                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                if let item = response.mapItems.first {
                    foundItem = item
                    break
                }
            }

            guard let item = foundItem else {
                logisticsResolvedLocation = nil
                logisticsLocationResolveError = true
                logisticsResolvedQueryKey = queryKey
                return
            }

            let coordinate = item.location.coordinate

            let title = item.name ?? query
            let address = item.address
            let subtitle = [address?.shortAddress, address?.fullAddress]
                .compactMap { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""

            logisticsResolvedLocation = ResolvedLocation(
                id: UUID(),
                title: title,
                subtitle: subtitle,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            logisticsResolvedQueryKey = queryKey
        } catch {
            logisticsResolvedLocation = nil
            logisticsLocationResolveError = true
            logisticsResolvedQueryKey = queryKey
        }
    }

    private func presentEditCourse() {
        modalCoordinator.activeModal = .editCourse(
            ModalCoordinator.CourseEditSelection(
                courseCode: courseCode,
                defaultCourseName: defaultCourseName,
                defaultCreditsText: defaultCreditsText
            )
        )
    }

    private func presentAddCalendarItem() {
        let semesterID = course?.semester?.id
        modalCoordinator.activeModal = .addCalendarItem(
            semesterID: semesterID,
            initialTitle: courseCode.isEmpty ? displayCourseName : courseCode,
            initialStart: nil,
            initialEnd: nil
        )
    }

    private func presentAddTask() {
        modalCoordinator.courseDashboardTaskOverlay = .add(
            semesterID: course?.semester?.id,
            prefillCourseID: course?.id
        )
    }

    private func presentEditTask(taskID: UUID) {
        modalCoordinator.courseDashboardTaskOverlay = .edit(taskID: taskID)
    }

    var body: some View {
        GeometryReader { proxy in
            let sideGutter = max(24, proxy.size.width * 0.035) // ~3.5% padding each side
            let contentWidth = max(0, proxy.size.width - (sideGutter * 2))

            VStack(spacing: 0) {
                header(sideGutter: sideGutter)
                    .frame(maxWidth: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        immediateAction
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 48)

                        gridContent(availableWidth: contentWidth)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, sideGutter)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .background(DesignSystem.Colors.bgMain)
        }
        .sheet(isPresented: $isSyllabusPresented) {
            syllabusSheet
                .dismissOnOutsideClickForSheet()
        }
        .sheet(isPresented: $isCatalogSheetPresented) {
            catalogInfoSheet
                .dismissOnOutsideClickForSheet()
        }
        .overlay(alignment: .bottomTrailing) {
            floatingAddTaskButton
        }
        .onAppear { reloadDashboardPayload() }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            plannerRefreshToken &+= 1
            reloadDashboardPayload()
        }
        .onChange(of: collegePersistence.calendarDidChangeToken) { _, _ in
            reloadDashboardPayload()
        }
        .background {
            ProfilePlannerQueryHost {
                plannerRefreshToken &+= 1
                reloadDashboardPayload()
            }
        }
        .task(id: courseCode) {
            reloadDashboardPayload()
            await computePrereqCheck()
        }
        .onChange(of: activePage) { _, _ in onClose() }
    }

    private func reloadDashboardPayload() {
        dashboardPayload = CourseDashboardReadBridge.load(
            courseCode: courseCode,
            courseID: courseID
        )
    }

    private var floatingAddTaskButton: some View {
        Button(action: { presentAddTask() }) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add task")
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }

    /// Matches `DocumentsView` / shell pages: 22pt title, secondary subtitle, trailing summary chips.
    private var courseHeaderSubtitle: String {
        var parts: [String] = []
        if let s = semesterText, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(s)
        }
        let code = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty { parts.append(code) }
        return parts.joined(separator: " · ")
    }

    private var courseHeaderTagsLine: String? {
        guard !tagPills.isEmpty else { return nil }
        return tagPills.joined(separator: " · ")
    }

    private func headerStatChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            Text(value)
                .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
        )
    }

    private func header(sideGutter: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayCourseName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !courseHeaderSubtitle.isEmpty {
                    Text(courseHeaderSubtitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let tags = courseHeaderTagsLine {
                    Text(tags)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                headerStatChip(title: "Grade", value: securityManager.isUnlocked ? gradeText : "••")
                headerStatChip(title: "Credits", value: creditsText)
                headerStatChip(title: "Progress", value: semesterPlanProgressPercentText)
            }
        }
        .padding(.horizontal, sideGutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(hex: "f1f5f9"))
        }
    }

    private func gridContent(availableWidth: CGFloat) -> some View {
        let gap: CGFloat = 32
        let minTwoColumnWidth: CGFloat = 920

        return Group {
            if availableWidth < minTwoColumnWidth {
                VStack(alignment: .leading, spacing: gap) {
                    sidebar
                    tasksAndDeadlines
                }
            } else {
                let usable = max(0, availableWidth - gap)
                let proposedSidebar = usable * (4.0 / 12.0)
                let sidebarWidth = min(max(300, proposedSidebar), 460)
                let tasksWidth = max(420, usable - sidebarWidth)

                HStack(alignment: .top, spacing: gap) {
                    sidebar
                        .frame(width: sidebarWidth, alignment: .leading)

                    tasksAndDeadlines
                        .frame(width: tasksWidth, alignment: .leading)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MiniCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("LIVE GRADE")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .tracking(1)
                            Spacer()
                            Button {
                                isGPAPopoverPresented = true
                            } label: {
                                Image(systemName: "function")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $isGPAPopoverPresented) {
                                GPACalculatorPopoverView(universityID: nil)
                            }
                        }

                        Text(securityManager.isUnlocked ? gradeText : "••")
                            .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                }
                .frame(minHeight: 128)

                MiniCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text("PROFESSOR")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .tracking(1)

                            Spacer()

                            Button(action: presentEditCourse) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 10) {
                            Circle()
                                .fill(DesignSystem.Colors.textLight.opacity(0.18))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(professorText.isEmpty ? "Not set" : professorText)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .lineLimit(1)

                                if !professorEmailText.isEmpty {
                                    Button {
                                        if let url = URL(string: "mailto:\(professorEmailText)") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "envelope")
                                                .font(.system(size: 10, weight: .semibold))
                                            Text(professorEmailText)
                                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(DesignSystem.Colors.primary)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(professorText.isEmpty ? "Add in course details" : "Add email in course details")
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 128)
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RESOURCES")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .tracking(1)

                    DashboardResourceRow(
                        title: "Course Syllabus",
                        subtitle: syllabusSubtitle,
                        icon: "doc.richtext",
                        trailingIcon: "chevron.right"
                    ) {
                        isSyllabusPresented = true
                    }

                    DashboardResourceRow(
                        title: "Course Calendar",
                        subtitle: "View course events",
                        icon: "calendar",
                        trailingIcon: "chevron.right"
                    ) {
                        activePage = .calendar
                    }

                    if !externalURLText.isEmpty {
                        DashboardResourceRow(
                            title: "Course Website",
                            subtitle: externalURLText,
                            icon: "globe",
                            trailingIcon: "arrow.up.right"
                        ) {
                            if let url = URL(string: externalURLText) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }

                    if !catalogDescriptionText.isEmpty || !catalogPrerequisitesText.isEmpty {
                        DashboardResourceRow(
                            title: "View in Catalog",
                            subtitle: course?.catalogCourse?.title ?? courseCode,
                            icon: "books.vertical",
                            trailingIcon: "chevron.right"
                        ) {
                            isCatalogSheetPresented = true
                        }
                    }

                    if calendarManager.googleStatus == .connected {
                        DashboardResourceRow(
                            title: "Sync to Google Calendar",
                            subtitle: "Force a full resync",
                            icon: "arrow.triangle.2.circlepath",
                            trailingIcon: "chevron.right"
                        ) {
                            calendarManager.resyncGoogleNow()
                            notifications.post(kind: .success, title: "Sync Started", message: "Google Calendar sync is running.", isDismissible: true, autoDismissAfter: 3)
                        }
                    }

                    if !relatedDocuments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Related Documents")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .tracking(0.8)

                            ForEach(relatedDocuments.prefix(6), id: \.id) { document in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)

                                    Text(document.fileName)
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    Button {
                                        openVaultDocument(document)
                                    } label: {
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open document")

                                    Button {
                                        revealVaultDocumentInFinder(document)
                                    } label: {
                                        Image(systemName: "folder")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reveal in Finder")

                                    Button {
                                        unlinkVaultDocument(document)
                                    } label: {
                                        Image(systemName: "link.badge.minus")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Unlink from this course")
                                }
                                .padding(.vertical, 2)
                            }

                            if relatedDocuments.count > 6 {
                                Button {
                                    openDocumentsForCurrentCourse()
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("+")
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                        Text("\(relatedDocuments.count - 6) more in Documents")
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(DesignSystem.Colors.primary)
                                }
                                .buttonStyle(.plain)
                                .help("Open Documents to view all linked files")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("LOGISTICS")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .tracking(1)

                        Spacer()

                        if logisticsIsHappeningNow {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(DesignSystem.Colors.success)
                                    .frame(width: 7, height: 7)

                                Text("Happening Now")
                                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.success)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.success.opacity(0.10))
                            .cornerRadius(999)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(DesignSystem.Colors.success.opacity(0.18), lineWidth: 1)
                            )
                        } else {
                            DashboardStatusBadge(text: statusText, color: statusText == "—" ? DesignSystem.Colors.textLight : DesignSystem.Colors.success)
                        }
                    }

                    if let days = logisticsMeetingDaysText, let times = logisticsMeetingTimeText {
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DesignSystem.Colors.success.opacity(0.10))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "clock")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.success)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(days)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)

                                Text(times)
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }

                            Spacer()
                        }
                    } else {
                        Text("No scheduled class meetings yet.")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }

                    Button(action: {
                        notifications.post(kind: .info, title: "Check-in", message: "Check-in is a placeholder for now.", isDismissible: true, autoDismissAfter: 3)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Check-in to Class")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(DesignSystem.Colors.success)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    if !logisticsLocationQuery.isEmpty {
                        Group {
                            if let resolved = logisticsResolvedLocation {
                                DashboardFixedMapPreview(location: resolved)
                            } else if logisticsIsResolvingLocation {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.black.opacity(0.04))
                                    ProgressView()
                                        .scaleEffect(0.85)
                                }
                                .frame(height: 140)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            } else if logisticsLocationResolveError {
                                DashboardMapPreview(title: logisticsLocationQuery)
                            } else {
                                DashboardMapPreview(title: logisticsLocationQuery)
                            }
                        }
                        .task(id: logisticsLocationQuery.lowercased()) {
                            await resolveLogisticsLocationIfNeeded()
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WEIGHTS")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .tracking(1)

                    let grading = (course?.gradingCategories ?? []).sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }

                    if grading.isEmpty {
                        Text("Weights populate when grading is extracted from a syllabus.")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: { isSyllabusPresented = true }) {
                            Label("Analyze Syllabus", systemImage: "sparkles")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(DesignSystem.Colors.primary.opacity(0.12))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(grading.prefix(8), id: \.id) { item in
                                HStack {
                                    Text(item.name.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                        .lineLimit(1)

                                    Spacer()

                                    if let w = item.weightPercent, w > 0 {
                                        Text(String(format: "%.0f%%", w))
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.info)
                                    } else {
                                        Text("—")
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Button(action: { isSyllabusPresented = true }) {
                            Label("Re-scan Syllabus", systemImage: "sparkles")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(DesignSystem.Colors.primary.opacity(0.12))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !catalogDescriptionText.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DESCRIPTION")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .tracking(1)

                        Text(catalogDescriptionText)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !catalogPrerequisitesText.isEmpty || !catalogCorequisitesText.isEmpty || !catalogTypicallyOfferedText.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CATALOG INFO")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .tracking(1)
                            Spacer()
                            if let met = prereqMet {
                                HStack(spacing: 4) {
                                    Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text(met ? "Prerequisites Met" : "Prerequisites Unmet")
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                }
                                .foregroundColor(met ? DesignSystem.Colors.success : Color(hex: "EF4444"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((met ? DesignSystem.Colors.success : Color(hex: "EF4444")).opacity(0.10))
                                .cornerRadius(8)
                            }
                        }

                        if !catalogPrerequisitesText.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Prerequisites")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Text(catalogPrerequisitesText)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !catalogCorequisitesText.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Co-requisites")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Text(catalogCorequisitesText)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !catalogTypicallyOfferedText.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Text("Typically offered: \(catalogTypicallyOfferedText)")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }
                        }
                    }
                }
            }
        }
    }

    private var immediateAction: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Immediate Action")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(Color.white)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "DC2626"))
                        .cornerRadius(6)

                    if let pill = immediateActionDuePillText {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .semibold))
                            Text(pill)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "B91C1C"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "FAF2F2"))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "F2E4E4"), lineWidth: 1)
                        )
                    }
                }

                Text(immediateActionTitle)
                    .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                    .foregroundColor(Color(hex: "33312E"))
                    .lineLimit(2)

                Text(immediateActionSubtitle)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "757370"))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: {
                    if let t = immediateActionTask {
                        presentEditTask(taskID: t.id)
                    }
                }) {
                    Text("View Rubric")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "757370"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(DesignSystem.Colors.bgMain)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(immediateActionTask == nil)

                Button(action: {
                    if let t = immediateActionTask {
                        presentEditTask(taskID: t.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .bold))
                        Text("Submit Now")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    }
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(hex: "DC2626"))
                    .cornerRadius(12)
                    .shadow(color: Color(hex: "FECACA").opacity(0.85), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(immediateActionTask == nil)
            }
        }
        .padding(22)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 5)
    }

    private var tasksAndDeadlines: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Text("Tasks & Deadlines")
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                    .layoutPriority(1)

                    if isTaskSearchActive {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.9))

                            TextField("Search tasks & deadlines", text: $taskSearchText)
                                .textFieldStyle(.plain)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .focused($taskSearchFocused)

                            if !taskSearchText.isEmpty {
                                Button(action: { taskSearchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.65))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .trailing)))
                    } else {
                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 10) {
                        Button(action: {
                            modalCoordinator.activeModal = .addCalendarItem(
                                semesterID: course?.semester?.id,
                                initialTitle: nil,
                                initialStart: nil,
                                initialEnd: nil
                            )
                        }) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .frame(width: 32, height: 32)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add calendar event")

                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
                                isTaskSearchActive.toggle()
                            }
                            if isTaskSearchActive {
                                DispatchQueue.main.async {
                                    taskSearchFocused = true
                                }
                            } else {
                                taskSearchText = ""
                                taskSearchFocused = false
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .frame(width: 32, height: 32)
                                .background(isTaskSearchActive ? DesignSystem.Colors.primary.opacity(0.12) : DesignSystem.Colors.surface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isTaskSearchActive ? "Close search" : "Search tasks")

                        Button(action: { tasksFilter = .incomplete }) {
                            Text("Incomplete")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(tasksFilter == .incomplete ? DesignSystem.Colors.primary.opacity(0.10) : DesignSystem.Colors.surface.opacity(0.6))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .opacity(tasksFilter == .incomplete ? 1 : 0.75)
                        .accessibilityLabel("Show incomplete tasks")

                        Button(action: { tasksFilter = .all }) {
                            Text("All Tasks")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .opacity(tasksFilter == .all ? 1 : 0.75)
                        .accessibilityLabel("Show all tasks")
                    }
                    .layoutPriority(1)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.92), value: isTaskSearchActive)

                if !availableTaskCategoryFilters.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button(action: { tasksCategoryFilter = nil }) {
                                let isSelected = (tasksCategoryFilter == nil)
                                Text("All")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundColor(isSelected ? DesignSystem.Colors.textMain : DesignSystem.Colors.textMain.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? DesignSystem.Colors.primary.opacity(0.10) : DesignSystem.Colors.surface.opacity(0.6))
                                    .cornerRadius(999)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 999)
                                            .stroke(isSelected ? DesignSystem.Colors.primary.opacity(0.25) : DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            ForEach(availableTaskCategoryFilters, id: \.self) { category in
                                let isSelected = tasksCategoryFilter?.caseInsensitiveCompare(category) == .orderedSame
                                Button(action: {
                                    if isSelected {
                                        tasksCategoryFilter = nil
                                    } else {
                                        tasksCategoryFilter = category
                                    }
                                }) {
                                    Text(category)
                                        .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                        .foregroundColor(isSelected ? DesignSystem.Colors.textMain : DesignSystem.Colors.textMain.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? DesignSystem.Colors.primary.opacity(0.10) : DesignSystem.Colors.surface.opacity(0.6))
                                        .cornerRadius(999)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 999)
                                                .stroke(isSelected ? DesignSystem.Colors.primary.opacity(0.25) : DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if tasks.isEmpty && events.isEmpty {
                    Text("No tasks or course events yet.")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        if upcomingItems.isEmpty {
                            Text("No tasks match the current filters.")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(showAllTasks ? Array(upcomingItems) : Array(upcomingItems.prefix(12)), id: \.id) { item in
                                DashboardTaskRow(
                                    item: item,
                                    onEdit: {
                                        switch item.kind {
                                        case .task(let taskID):
                                            presentEditTask(taskID: taskID)
                                        case .event(let eventID):
                                            modalCoordinator.activeModal = .editCalendarItem(eventID: eventID)
                                        }
                                    }
                                )
                            }

                            if upcomingItems.count > 12 {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        showAllTasks.toggle()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Text(showAllTasks ? "Show Less" : "Show \(upcomingItems.count - 12) More")
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                        Image(systemName: showAllTasks ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundColor(DesignSystem.Colors.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var availableTaskCategoryFilters: [String] {
        let raw = tasks.compactMap { task -> String? in
            let trimmed = (task.categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Graded" : trimmed
        }

        var seen: Set<String> = []
        var unique: [String] = []
        for name in raw {
            let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(name)
        }

        return unique.sorted { $0.lowercased() < $1.lowercased() }
    }

    private var syllabusSubtitle: String {
        let overrideEntity = collegePersistence.getCourseOverride(courseCode: courseCode)
        if overrideEntity?.syllabusFileBookmarkData != nil {
            return "PDF saved"
        }
        return "No PDF saved"
    }

    private var relatedDocuments: [VaultDocument] {
        VaultReadBridge.documentsLinkedToCourse(
            courseCode: courseCode,
            collegePersistence: collegePersistence
        )
    }

    private func openVaultDocument(_ document: VaultDocument) {
        if let url = VaultDocumentAccess.urlForDocument(id: document.id, collegePersistence: collegePersistence) {
            NSWorkspace.shared.open(url)
            return
        }

        notifications.post(
            kind: .warning,
            title: "Document Unavailable",
            message: "Could not access this file from the vault.",
            isDismissible: true,
            autoDismissAfter: 3
        )
    }

    private func revealVaultDocumentInFinder(_ document: VaultDocument) {
        if let url = VaultDocumentAccess.urlForDocument(id: document.id, collegePersistence: collegePersistence) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        notifications.post(
            kind: .warning,
            title: "Document Unavailable",
            message: "Could not reveal this file in Finder.",
            isDismissible: true,
            autoDismissAfter: 3
        )
    }

    private func unlinkVaultDocument(_ document: VaultDocument) {
        collegePersistence.setVaultDocumentCourseLink(document, courseCode: nil)
        notifications.post(
            kind: .success,
            title: "Document Unlinked",
            message: "Removed course link for \(document.fileName).",
            isDismissible: true,
            autoDismissAfter: 2
        )
    }

    private func openDocumentsForCurrentCourse() {
        NotificationCenter.default.post(
            name: .plannerOpenDocumentsForCourse,
            object: nil,
            userInfo: ["courseCode": courseCode]
        )
        activePage = .documents
    }

    @MainActor
    private func computePrereqCheck() async {
        guard let catalogEntity = collegePersistence.fetchCatalogCourseForCode(courseCode) else {
            prereqMet = nil
            return
        }
        let completedCourses = ProfilePlannerReadBridge
            .allCoursesAcrossPlans(collegePersistence: collegePersistence)
            .filter(\.isCompleted)
        let validator = PrerequisiteValidator(collegePersistence: collegePersistence)
        let result = validator.validatePrerequisites(for: catalogEntity, completedCourses: completedCourses)
        prereqMet = result.met
    }

    private var catalogInfoSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(courseCode)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Text(displayCourseName)
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                    Spacer()
                    Button(action: { isCatalogSheetPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(DesignSystem.Colors.textLight.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                if !catalogDescriptionText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .textCase(.uppercase)
                            .tracking(1)
                        Text(catalogDescriptionText)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .lineSpacing(4)
                    }
                }

                if !catalogPrerequisitesText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Prerequisites")
                                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .textCase(.uppercase)
                                .tracking(1)
                            if let met = prereqMet {
                                Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(met ? DesignSystem.Colors.success : Color(hex: "EF4444"))
                            }
                        }
                        Text(catalogPrerequisitesText)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                }

                if !catalogCorequisitesText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Co-requisites")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .textCase(.uppercase)
                            .tracking(1)
                        Text(catalogCorequisitesText)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                }

                if !catalogTypicallyOfferedText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.circle")
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Text("Typically offered: \(catalogTypicallyOfferedText)")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 300)
    }

    private var syllabusSheet: some View {
        let overrideEntity = collegePersistence.getCourseOverride(courseCode: courseCode)
        let plannedCourse = course
        return SyllabusReviewView(
            courseCode: courseCode,
            defaultCourseName: displayCourseName,
            semesterText: semesterText,
            overrideEntity: overrideEntity,
            plannedCourse: plannedCourse,
            onClose: { isSyllabusPresented = false }
        )
        }

    private var immediateActionTitle: String {
        if let t = immediateActionTask {
            let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Upcoming Task" : title
        }
        return "No upcoming tasks"
    }

    private var immediateActionSubtitle: String {
        if let t = immediateActionTask, let due = t.dueDate {
            return "Due \(Formatters.dateTime.string(from: due))"
        }
        return "Add tasks or import syllabus dates to populate this card."
    }

    // MARK: - Upcoming Items

    fileprivate enum DashboardItemKind {
        case task(id: UUID)
        case event(id: UUID)
    }

    fileprivate struct DashboardItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let dateText: String
        let sortDate: Date?
        let kind: DashboardItemKind
        let badgeText: String
        let badgeColor: Color
        let isCompleted: Bool
        let isPast: Bool
        let effortText: String?
    }

    private var upcomingItems: [DashboardItem] {
        var items: [DashboardItem] = []

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let dateTimeFormatter = Formatters.dateTime

        for t in tasks {
            let taskID = t.id
            let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let due = t.dueDate
            let dueDay = due.map { calendar.startOfDay(for: $0) }
            let isPast = dueDay.map { $0 < today } ?? false

            let (badgeText, badgeColor) = taskBadge(for: t)

            let subtitle: String = {
                let rawNotes = (t.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = stripTaskMetaBlock(from: rawNotes)
                if !cleaned.isEmpty { return cleaned }
                return ""
            }()

            let dateText = due.map { dateTimeFormatter.string(from: $0) } ?? "—"
            let effortText = taskEffortText(for: t)

            items.append(
                DashboardItem(
                    id: "task:\(taskID.uuidString)",
                    title: title.isEmpty ? "Task" : title,
                    subtitle: subtitle,
                    dateText: dateText,
                    sortDate: due,
                    kind: .task(id: taskID),
                    badgeText: badgeText,
                    badgeColor: badgeColor,
                    isCompleted: t.isCompleted,
                    isPast: isPast,
                    effortText: effortText
                )
            )
        }

        for e in events {
            let eventID = e.id
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = e.startDate
            let end = e.endDate

            // Keep events that haven't ended yet.
            if end < now { continue }
            if start < now && end <= start { continue }

            let dateText = dateTimeFormatter.string(from: start)
            let startDay = calendar.startOfDay(for: start)
            let isPast = startDay < today

            let subtitle: String = {
                let raw = (e.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return raw
            }()

            items.append(
                DashboardItem(
                    id: "event:\(eventID.uuidString)",
                    title: title.isEmpty ? "Event" : title,
                    subtitle: subtitle,
                    dateText: dateText,
                    sortDate: start,
                    kind: .event(id: eventID),
                    badgeText: "Event",
                    badgeColor: DesignSystem.Colors.warning
                    ,
                    isCompleted: false,
                    isPast: isPast,
                    effortText: nil
                )
            )
        }

        // Incomplete first (soonest first). Completed last.
        items.sort { a, b in
            if a.isCompleted != b.isCompleted {
                return a.isCompleted == false
            }
            if !a.isCompleted {
                return (a.sortDate ?? .distantFuture) < (b.sortDate ?? .distantFuture)
            }
            return (a.sortDate ?? .distantPast) > (b.sortDate ?? .distantPast)
        }

        let filteredByCompletion: [DashboardItem] = {
            switch tasksFilter {
            case .all:
                return items
            case .incomplete:
                return items.filter { !$0.isCompleted }
            }
        }()

        let filteredBySearch: [DashboardItem] = {
            let q = taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return filteredByCompletion }
            let query = q.lowercased()

            func matches(_ item: DashboardItem) -> Bool {
                if item.title.lowercased().contains(query) { return true }
                if item.subtitle.lowercased().contains(query) { return true }
                if item.badgeText.lowercased().contains(query) { return true }
                return false
            }

            return filteredByCompletion.filter(matches)
        }()

        if let selectedCategory = tasksCategoryFilter?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedCategory.isEmpty {
            return filteredBySearch.filter { item in
                guard case .task = item.kind else { return false }
                return item.badgeText.caseInsensitiveCompare(selectedCategory) == .orderedSame
            }
        }

        return filteredBySearch
    }

    private func stripTaskMetaBlock(from notes: String) -> String {
        let startTag = "[CollegeTaskMeta]"
        let endTag = "[/CollegeTaskMeta]"

        guard let start = notes.range(of: startTag),
              let end = notes.range(of: endTag),
              start.lowerBound < end.lowerBound else {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let before = notes[..<start.lowerBound]
        let after = notes[end.upperBound...]
        let combined = String(before) + String(after)
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func taskEffortText(for task: PlannerTask) -> String? {
        guard let rawMinutes = task.estimatedEffortMinutes.map(Int.init), rawMinutes > 0 else { return nil }
        let total = rawMinutes
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    private func taskBadge(for task: PlannerTask) -> (text: String, color: Color) {
        let trimmed = (task.categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "Graded" : trimmed
        let raw = label.lowercased()

        func has(_ s: String) -> Bool { raw.contains(s) }

        if has("reading") {
            return (label, Color(hex: "2563EB"))
        }
        if has("quiz") || has("exam") || has("midterm") || has("final") {
            return (label, Color.black.opacity(0.35))
        }
        if has("event") {
            return (label, Color(hex: "7C3AED"))
        }
        if has("assignment") || has("homework") || has("project") || has("lab") {
            return (label, Color(hex: "EF4444"))
        }
        // Fallback: treat as graded work.
        return (label, Color(hex: "EF4444"))
    }

    // MARK: - Utils

    private static func normalizeCourseCode(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let re = Formatters.courseCodeRegex {
            let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            if let m = re.firstMatch(in: cleaned, range: nsRange), m.numberOfRanges >= 3,
               let r1 = Range(m.range(at: 1), in: cleaned),
               let r2 = Range(m.range(at: 2), in: cleaned) {
                return "\(cleaned[r1]) \(cleaned[r2])"
            }
        }

        return cleaned
    }

    private static func eventDateText(_ e: CalendarEvent) -> String {
        let start = e.startDate
        return e.allDay ? Formatters.dateOnly.string(from: start) : Formatters.dateTime.string(from: start)
    }

    private var scheduleSummaryText: String {
        guard let next = nextUpcomingEvent else { return "" }
        let start = next.startDate

        let day = Formatters.weekdayShort.string(from: start)
        let startText = Formatters.timeOnly.string(from: start)
        let endText = Formatters.timeOnly.string(from: next.endDate)
        return "\(day) • \(startText) – \(endText)"
    }
}

// MARK: - Components

private struct Card<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardBoxStyle()
    }
}

private struct MiniCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardBoxStyle(cornerRadius: 16)
    }
}

private struct SmallStatCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .tracking(1)

                Text(value)
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
            }

            Spacer(minLength: 10)

            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 160)
        .dashboardBoxStyle()
    }
}

private struct StatsStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let icon: String
        let iconColor: Color
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "A19F9C"))
                            .textCase(.uppercase)
                            .tracking(1)

                        Text(item.value)
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .foregroundColor(Color(hex: "33312E"))
                    }

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .fill(item.iconColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: item.icon)
                            .foregroundColor(item.iconColor)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if idx < items.count - 1 {
                    Rectangle()
                        .fill(Color(hex: "F2F0ED"))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E6E4E0"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DashboardMapPreview: View {
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    DesignSystem.Colors.textLight.opacity(0.12),
                    DesignSystem.Colors.textLight.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)
                Text("Campus")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            .padding(10)
            .background(DesignSystem.Colors.surface.opacity(0.92))
            .cornerRadius(12)
            .padding(10)
        }
        .frame(height: 86)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignSystem.Colors.textLight.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct DashboardFixedMapPreview: View {
    let location: ResolvedLocation

    @State private var position: MapCameraPosition

    init(location: ResolvedLocation) {
        self.location = location
        _position = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $position, interactionModes: []) {
                Annotation(location.title, coordinate: location.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "EF4444"))
                        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(location.title)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)
                if !location.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(location.subtitle)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(DesignSystem.Colors.surface.opacity(0.92))
            .cornerRadius(12)
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DashboardStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .cornerRadius(999)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(color.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct DashboardResourceRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let trailingIcon: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)

                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }

                Spacer()

                Image(systemName: trailingIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.6))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)

            Spacer()

            Text(value)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
        }
    }
}

private struct DashboardTaskRow: View {
    let item: CourseDashboardView.DashboardItem
    let onEdit: () -> Void

    private var accentColor: Color {
        if item.isCompleted { return DesignSystem.Colors.textLight.opacity(0.55) }
        if item.isPast { return Color(hex: "EF4444") }
        return DesignSystem.Colors.textLight
    }

    private var dueLabelText: String {
        if item.isCompleted { return "DONE" }
        return item.isPast ? "PAST" : "DUE DATE"
    }

    private var dueDateBlock: (date: String, weekday: String) {
        let now = Date()

        let fmtDate = CourseDashboardView.Formatters.monthDay
        let fmtWeekday = CourseDashboardView.Formatters.weekday

        let referenceDate: Date? = {
            switch item.kind {
            case .task(let taskID):
                guard let task = try? AppDataStore.shared.calendarRepository.fetchPlannerTask(id: taskID) else { return item.sortDate }
                return task.dueDate ?? item.sortDate
            case .event:
                return item.sortDate
            }
        }()

        if let d = referenceDate {
            return (fmtDate.string(from: d), fmtWeekday.string(from: d))
        }
        // Fallback: show today's context.
        return (fmtDate.string(from: now), fmtWeekday.string(from: now))
    }

    private var isTaskRow: Bool {
        if case .task = item.kind { return true }
        return false
    }

    private var taskWeightText: String? {
        guard case .task(let taskID) = item.kind,
              let task = try? AppDataStore.shared.calendarRepository.fetchPlannerTask(id: taskID),
              let w = task.weightPercent, w > 0 else { return nil }
        return w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))% weight" : String(format: "%.1f%% weight", w)
    }

    private func toggleCompleted() {
        guard case .task(let taskID) = item.kind,
              let task = try? AppDataStore.shared.calendarRepository.fetchPlannerTask(id: taskID) else {
            return
        }
        try? AppDataStore.shared.calendarRepository.setPlannerTaskCompleted(id: taskID, completed: !task.isCompleted)
        CollegePersistence.shared.notifyCalendarDidChange()
        CollegePersistence.shared.bumpProfileRevision()
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    toggleCompleted()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(item.isCompleted ? Color.black.opacity(0.06) : Color.clear)
                            )
                            .frame(width: 20, height: 20)

                        if item.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.black.opacity(0.40))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isTaskRow)
                .opacity(isTaskRow ? 1 : 0.35)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.badgeText)
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(item.badgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.badgeColor.opacity(0.12))
                            .cornerRadius(6)

                        Spacer(minLength: 0)

                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .frame(width: 28, height: 28)
                                .background(DesignSystem.Colors.surface.opacity(item.isCompleted ? 0.6 : 1.0))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(hex: "E6E4E0"), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit")
                    }

                    Text(item.title)
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain.opacity(item.isCompleted ? 0.38 : 1))
                        .strikethrough(item.isCompleted, color: DesignSystem.Colors.textLight.opacity(0.55))
                        .lineLimit(1)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight.opacity(item.isCompleted ? 0.28 : 1))
                            .lineLimit(2)
                    }

                    if item.effortText != nil || taskWeightText != nil {
                        HStack(spacing: 6) {
                            if let weight = taskWeightText {
                                HStack(spacing: 4) {
                                    Image(systemName: "percent")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.info.opacity(item.isCompleted ? 0.28 : 0.8))
                                    Text(weight)
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.info.opacity(item.isCompleted ? 0.28 : 1))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(DesignSystem.Colors.info.opacity(0.08))
                                .cornerRadius(999)
                                .overlay(RoundedRectangle(cornerRadius: 999).stroke(DesignSystem.Colors.info.opacity(0.18), lineWidth: 1))
                            }
                            Spacer()
                            if let effort = item.effortText, !effort.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight.opacity(item.isCompleted ? 0.28 : 0.7))
                                    Text(effort)
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textLight.opacity(item.isCompleted ? 0.28 : 0.85))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(hex: "F9F8F6"))
                                .cornerRadius(999)
                                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color(hex: "E6E4E0"), lineWidth: 1))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 4) {
                Text(dueLabelText)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(accentColor.opacity(item.isCompleted ? 0.45 : 1))
                    .kerning(0.6)

                Text(dueDateBlock.date)
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(accentColor.opacity(item.isCompleted ? 0.38 : 1))

                Text(dueDateBlock.weekday)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(item.isCompleted ? 0.28 : 1))
            }
            .frame(width: 128)
            .padding(.vertical, 16)
            .background(Color(hex: "F9F8F6").opacity(0.35))
            .overlay(
                Rectangle()
                    .fill(Color(hex: "E6E4E0"))
                    .frame(width: 1),
                alignment: .leading
            )
        }
        .background(item.isCompleted ? Color(hex: "F2F0ED").opacity(0.55) : Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E6E4E0"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
        .opacity(item.isCompleted ? 0.65 : 1)
    }
}

private extension View {
    func dashboardBoxStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.10),
                radius: 12,
                x: 0,
                y: 5
            )
    }
}
