// CalendarView.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import Observation
import os
import MapKit

// Domain types and cache logic live in CalendarCacheEngine.swift
public typealias CalEvent = CalendarCalEvent
public typealias EventLayoutSegment = CalendarLayoutSegment
public typealias EventType = CalendarEventKind

public enum CalendarViewDisplayMode: String, CaseIterable, Sendable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
}

public enum CalendarSidebarPanel: String, CaseIterable, Sendable {
    case eventList = "Event List"
    case tasks = "Tasks"
}

/// Shared calendar grid cache; `@Observable` limits invalidation to views that read changed buckets.
@Observable
@MainActor
public final class CalendarEventCacheStore {
    public var dayEventsByDate: [Date: [CalEvent]] = [:]
    public var timedLayoutsByDate: [Date: [EventLayoutSegment]] = [:]

    public init() {}
}

/// Shell: holds navigation state and derives the local store fetch window so `CalendarViewContent` can use bounded fetches.
public struct CalendarView: View {
    @Binding var isCalendarPageActive: Bool
    var cacheStore: CalendarEventCacheStore

    public init(isCalendarPageActive: Binding<Bool>, cacheStore: CalendarEventCacheStore) {
        _isCalendarPageActive = isCalendarPageActive
        self.cacheStore = cacheStore
    }

    @State private var currentDate = Date()
    @State private var activeViewMode: CalendarViewDisplayMode = .month
    @SceneStorage("calendar.currentDateTS") private var storedCurrentDateTS: Double = Date().timeIntervalSince1970
    @SceneStorage("calendar.activeViewModeRaw") private var storedActiveViewModeRaw: String = CalendarViewDisplayMode.month.rawValue
    @State private var didRestoreState = false

    @Environment(\.calendarPersistence) private var collegePersistence
    @State private var isEventListSidebarShown: Bool = true
    @State private var sidebarPanel: CalendarSidebarPanel = .eventList

    @Environment(\.calendarSceneState) private var calendarSceneState

    public var body: some View {
        let cal: Calendar = {
            var c = Calendar.current
            c.firstWeekday = 1
            return c
        }()
        let fetchedWindow = CalendarCacheEngine.fetchWindow(
            currentDate: currentDate,
            mode: Self.mapFetchMode(activeViewMode),
            cal: cal
        )
        let todayStart = cal.startOfDay(for: Date())
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let windowStart = min(fetchedWindow.start, todayStart)
        let windowEnd = max(fetchedWindow.end, todayEnd)

        Group {
            CalendarViewContent(
                rangeStart: windowStart,
                rangeEnd: windowEnd,
                isCalendarPageActive: $isCalendarPageActive,
                currentDate: $currentDate,
                activeViewMode: $activeViewMode,
                cacheStore: cacheStore,
                calendarSearchText: contentCalendarSearchBinding,
                isEventListSidebarShown: contentEventListSidebarBinding,
                sidebarPanel: contentSidebarPanelBinding
            )
        }
        .onAppear {
            guard !didRestoreState else { return }
            didRestoreState = true
            currentDate = Date(timeIntervalSince1970: storedCurrentDateTS)
            if let restoredMode = CalendarViewDisplayMode(rawValue: storedActiveViewModeRaw) {
                activeViewMode = restoredMode
            }
        }
        .onChange(of: currentDate) { _, newDate in
            storedCurrentDateTS = newDate.timeIntervalSince1970
        }
        .onChange(of: activeViewMode) { _, newMode in
            storedActiveViewModeRaw = newMode.rawValue
        }
        .overlay(alignment: .topTrailing) {
            calendarSearchResultsFloatingPanel
        }
    }

    private var contentCalendarSearchBinding: Binding<String> {
        Binding(
            get: { calendarSceneState?.toolbarSearchText ?? "" },
            set: { calendarSceneState?.toolbarSearchText = $0 }
        )
    }

    private var contentEventListSidebarBinding: Binding<Bool> {
        $isEventListSidebarShown
    }

    private var contentSidebarPanelBinding: Binding<CalendarSidebarPanel> {
        $sidebarPanel
    }

    @ViewBuilder
    private var calendarSearchResultsFloatingPanel: some View {
        let searchText = calendarSceneState?.toolbarSearchText ?? ""
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCalendarPageActive, calendarSceneState?.toolbarSearchExpanded == true, !trimmed.isEmpty {
            let results = calendarSceneState?.toolbarSearchResults ?? []
            VStack(alignment: .leading, spacing: 0) {
                if results.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text("No events found")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    let shown = Array(results.prefix(6))
                    ForEach(shown) { match in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(match.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if match.id != shown.last?.id {
                            Divider().padding(.horizontal, 14)
                        }
                    }
                }
            }
            .frame(width: 300)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
            .padding(.top, 10)
            .padding(.trailing, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: trimmed)
        }
    }

    private static func mapFetchMode(_ mode: CalendarViewDisplayMode) -> CalendarFetchMode {
        switch mode {
        case .month: return .month
        case .week: return .week
        case .day: return .day
        }
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

private struct CalendarViewContent: View {
    let rangeStart: Date
    let rangeEnd: Date

    @Binding var isCalendarPageActive: Bool
    @Binding var currentDate: Date
    @Binding var activeViewMode: CalendarViewDisplayMode

        
    @Environment(\.calendarPersistence) private var collegePersistence
    @Environment(\.calendarIntegrationManager) private var calendarManager

    @Environment(\.calendarModalCoordinator) private var modalCoordinator
    @Environment(\.calendarSceneState) private var calendarSceneState
    

    var cacheStore: CalendarEventCacheStore
    @State private var toolbarHandlerToken: (any CalendarToolbarHandlerToken)?

    @SceneStorage("calendar.view.hasAnimatedIn") private var hasAnimatedIn = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    @State private var navigationDirection: Int = 1
    @State private var hourHeight: CGFloat = 60
    @State private var swipeNavProgress: CGFloat = 0  // -1...1: negative=forward, positive=backward

    @State private var cacheRebuildTask: Task<Void, Never>?
    @State private var didPrewarmEventEntities = false

    // Event List sidebar state
    @State private var sidebarDate: Date = Date()
    @State private var isFilterPopoverShown: Bool = false
    @State private var activeCalendarFilters: Set<String> = []

    @State private var toolbarCalendarSearchTask: Task<Void, Never>? = nil
    @State private var orderedSidebarEventsSnapshot: [CalEvent] = []
    @State private var uniqueCalendarNamesSnapshot: [String] = []
    @State private var filterSnapshotTask: Task<Void, Never>? = nil
    /// Driven by CalendarView's toolbar search popover (passed as binding).
    @Binding var calendarSearchText: String

    @Binding var isEventListSidebarShown: Bool
    @Binding var sidebarPanel: CalendarSidebarPanel

    init(
        rangeStart: Date,
        rangeEnd: Date,
        isCalendarPageActive: Binding<Bool>,
        currentDate: Binding<Date>,
        activeViewMode: Binding<CalendarViewDisplayMode>,
        cacheStore: CalendarEventCacheStore,
        calendarSearchText: Binding<String> = .constant(""),
        isEventListSidebarShown: Binding<Bool> = .constant(true),
        sidebarPanel: Binding<CalendarSidebarPanel> = .constant(.eventList)
    ) {
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        _isCalendarPageActive = isCalendarPageActive
        _currentDate = currentDate
        _activeViewMode = activeViewMode
        self.cacheStore = cacheStore
        _isEventListSidebarShown = isEventListSidebarShown
        _sidebarPanel = sidebarPanel
        _calendarSearchText = calendarSearchText
    }

    private var calendarToolbarInitials: String {
        Self.initialsFromProfileName(collegePersistence?.profileDisplayName)
    }

    private static func initialsFromProfileName(_ raw: String?) -> String {
        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "" }
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2,
           let a = parts[0].first,
           let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private static let performanceLog = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)

    private enum CalendarFormatters {
        static let monthHeader: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter
        }()

        static let weekHeader: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter
        }()

        static let dayHeader: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter
        }()

        static let today: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter
        }()

        static let weekday: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter
        }()

        static let currentTime: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter
        }()

        static let shortTime: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }()
    }
    
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }
    
    private var headerDateString: String {
        switch activeViewMode {
        case .month:
            return CalendarFormatters.monthHeader.string(from: currentDate).uppercased()
        case .week:
            return CalendarFormatters.weekHeader.string(from: currentDate).uppercased()
        case .day:
            return CalendarFormatters.dayHeader.string(from: currentDate).uppercased()
        }
    }
    
    private func shiftDate(by value: Int) {
        navigationDirection = value >= 0 ? 1 : -1
        switch activeViewMode {
        case .month:
            currentDate = calendar.date(byAdding: .month, value: value, to: currentDate) ?? currentDate
        case .week:
            currentDate = calendar.date(byAdding: .weekOfYear, value: value, to: currentDate) ?? currentDate
        case .day:
            currentDate = calendar.date(byAdding: .day, value: value, to: currentDate) ?? currentDate
        }
    }
    
    private var sidebarDateString: String {
        if calendar.isDateInToday(sidebarDate) {
            return "TODAY • " + CalendarFormatters.today.string(from: sidebarDate).uppercased()
        } else if calendar.isDateInTomorrow(sidebarDate) {
            return "TOMORROW • " + CalendarFormatters.today.string(from: sidebarDate).uppercased()
        }
        return CalendarFormatters.today.string(from: sidebarDate).uppercased()
    }

    private func scheduleFilterSnapshotRefresh() {
        filterSnapshotTask?.cancel()
        let day = normalizeDay(sidebarDate)
        let filters = activeCalendarFilters
        let eventsForDay = cacheStore.dayEventsByDate[day] ?? []
        let viewDayKeys = getDaysForCurrentView().map { normalizeDay($0) }
        let viewDayEvents = viewDayKeys.map { cacheStore.dayEventsByDate[$0] ?? [] }
        let todayEvents = cacheStore.dayEventsByDate[normalizeDay(Date())] ?? []
        let referenceInstant = Date().timeIntervalSince1970

        filterSnapshotTask = Task {
            let names = await Task.detached(priority: .userInitiated) {
                CalendarSidebarSnapshotBuilder.uniqueCalendarNames(
                    viewDayEvents: viewDayEvents,
                    todayEvents: todayEvents
                )
            }.value
            let ordered = await Task.detached(priority: .userInitiated) {
                CalendarSidebarSnapshotBuilder.orderedSidebarEvents(
                    events: eventsForDay,
                    filters: filters,
                    referenceInstant: referenceInstant
                )
            }.value
            guard !Task.isCancelled else { return }
            uniqueCalendarNamesSnapshot = names
            orderedSidebarEventsSnapshot = ordered
        }
    }

    private var orderedSidebarTasks: [CalendarPlannerTaskSummary] {
        CalendarPlannerBridge.sidebarTasks(
            sidebarDate: sidebarDate,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: calendar,
            
        )
    }

    private func calendarNameForEvent(_ event: CalEvent) -> String {
        let code = courseCode(for: event.title)
        if code != "SCHEDULED" { return code }
        switch event.type {
        case .extracurricular, .club: return "Extracurricular"
        case .deadline: return "Tasks"
        case .personal: return "Personal"
        case .management: return "Management"
        default: return "Academic"
        }
    }

    private func entity(for event: CalEvent) -> CalendarStoredEvent? {
        guard let eventID = event.calendarEventID else { return nil }
        return collegePersistence?.calendarEventEntity(id: eventID)
    }

    @MainActor
    private func scheduleToolbarCalendarSearch(_ query: String) {
        toolbarCalendarSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            calendarSceneState?.toolbarSearchResults = []
            return
        }
        toolbarCalendarSearchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
let formatted = await CalendarReadAccess.search!.searchOffMain(query: trimmed, limit: 50)
            guard !Task.isCancelled else { return }
            calendarSceneState?.toolbarSearchResults = formatted
        }
    }

    private func normalizeDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func scheduleCacheRebuild(delay: TimeInterval = 0.05) {
        cacheRebuildTask?.cancel()
        cacheRebuildTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await rebuildCachesAsync()
        }
    }

    private func prewarmEventEntitiesIfNeeded() {
        guard !didPrewarmEventEntities else { return }
        guard let calendarManager else { return }
        let snapshots = CalendarReadAccess.reader!.eventSnapshots(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendarManager: calendarManager
        )
        let ids = snapshots.compactMap(\.calendarEventID)
        guard !ids.isEmpty else { return }

        didPrewarmEventEntities = true
        for id in ids {
            _ = collegePersistence?.calendarEventEntity(id: id)
        }
    }

    @MainActor
    private func rebuildCachesAsync() async {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "CalendarCacheRebuild", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "CalendarCacheRebuild", signpostID: signpostID) }

        guard let calendarManager else { return }
        let resolvedEvents = await CalendarReadAccess.reader!.eventSnapshotsOffMain(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendarManager: calendarManager
        )
        let tasks = await CalendarReadAccess.reader!.taskSnapshotsOffMain(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )

        var cal = Calendar.current
        cal.firstWeekday = 1
        let tzId = TimeZone.current.identifier
        let firstWeekday = cal.firstWeekday

        let result = await Task.detached(priority: .userInitiated) {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: tzId) ?? .current
            c.firstWeekday = firstWeekday
            return CalendarCacheEngine.buildCaches(events: resolvedEvents, tasks: tasks, calendar: c)
        }.value

        cacheStore.dayEventsByDate = result.dayEventsByDate
        cacheStore.timedLayoutsByDate = result.timedLayoutsByDate
    }
    
    private func getDaysForCurrentView() -> [Date] {
        switch activeViewMode {
        case .month:
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate) else { return [] }
            guard let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else { return [] }
            guard let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1) else { return [] }
            
            let start = monthFirstWeek.start
            let end = monthLastWeek.end
            
            var dates: [Date] = []
            var d = start
            while d < end {
                dates.append(d)
                if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                    d = next
                } else {
                    break
                }
            }
            return dates
            
        case .week:
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: currentDate) else { return [] }
            var dates: [Date] = []
            var d = weekInterval.start
            while d < weekInterval.end {
                dates.append(d)
                if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                    d = next
                } else {
                    break
                }
            }
            return dates
            
        case .day:
            return [calendar.startOfDay(for: currentDate)]
        }
    }
    
    private func getEvents(for date: Date) -> [CalEvent] {
        cacheStore.dayEventsByDate[normalizeDay(date)] ?? []
    }

    private func timedLayouts(for date: Date) -> [EventLayoutSegment] {
        cacheStore.timedLayoutsByDate[normalizeDay(date)] ?? []
    }
    
    private func isEventPassed(_ event: CalEvent, referenceDate: Date = Date()) -> Bool {
        if event.isAllDay {
            guard let end = event.endDate else { return false }
            return end < calendar.startOfDay(for: referenceDate)
        }

        let end = event.endDate ?? event.startDate
        guard let end else { return false }
        return end < referenceDate
    }

    var body: some View {
        calendarReactiveHandlers(calendarRootLayout)
    }

    @ViewBuilder
    private var calendarRootLayout: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                calendarMainScroll(proxy: proxy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            if isEventListSidebarShown {
                Group {
                    if sidebarPanel == .eventList {
                        academicEventsSidebar
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        tasksSidebar
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .id(sidebarPanel)
                    .frame(width: 296)
                    .layoutPriority(0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isEventListSidebarShown)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: sidebarPanel)
        .sheet(isPresented: isAddCalendarSheetPresented) {
            CalendarOverlayAccess.builder?.addCalendarItemOverlay(
                isPresented: isAddCalendarSheetPresented,
                semesterID: addCalendarSheetSemester?.id,
                initialTitle: addCalendarSheetTitle,
                initialStart: addCalendarSheetStart,
                initialEnd: addCalendarSheetEnd,
                eventID: nil,
                style: .anchoredPanel
            )
            .frame(minWidth: 920, idealWidth: 1040, minHeight: 640, idealHeight: 760)
            .presentationBackground(.thinMaterial)
            
        }
        .sheet(isPresented: isEditCalendarSheetPresented) {
            CalendarOverlayAccess.builder?.addCalendarItemOverlay(
                isPresented: isEditCalendarSheetPresented,
                semesterID: editCalendarSheetEvent?.semesterID,
                initialTitle: editCalendarSheetEvent?.title,
                initialStart: editCalendarSheetEvent?.startDate,
                initialEnd: editCalendarSheetEvent?.endDate,
                eventID: editCalendarSheetEvent?.id,
                style: .anchoredPanel
            )
            .frame(minWidth: 920, idealWidth: 1040, minHeight: 640, idealHeight: 760)
            .presentationBackground(.thinMaterial)
            
        }
        .opacity(hasAnimatedIn ? 1 : 0)
        .offset(y: hasAnimatedIn ? 0 : (motionReduced ? 0 : 12))
        .animation(
            motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.30, dampingFraction: 0.88),
            value: hasAnimatedIn
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

    private func cancelCalendarBackgroundTasks() {
        cacheRebuildTask?.cancel()
        cacheRebuildTask = nil
        toolbarCalendarSearchTask?.cancel()
        toolbarCalendarSearchTask = nil
        filterSnapshotTask?.cancel()
        filterSnapshotTask = nil
    }

    private func handleCalendarAppear() {
        
        scheduleCacheRebuild(delay: 0)
        prewarmEventEntitiesIfNeeded()
        syncToolbarState()
        registerCalendarToolbarHandler()
        guard !hasAnimatedIn else { return }
        withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.30, dampingFraction: 0.88)) {
            hasAnimatedIn = true
        }
    }

    private func registerCalendarToolbarHandler() {
        toolbarHandlerToken?.invalidate()
        calendarSceneState?.toolbarHandler = { [self] action in
            handleCalendarToolbarAction(action)
        }
        toolbarHandlerToken = CalendarToolbarAccess.dispatcher?.registerCalendarHandler { action in
            calendarSceneState?.toolbarHandler?(action)
        }
    }

    @ViewBuilder
    private func calendarReactiveHandlers<Content: View>(_ content: Content) -> some View {
        calendarFilterHandlers(calendarToolbarHandlers(calendarCacheHandlers(content)))
    }

    @ViewBuilder
    private func calendarCacheHandlers<Content: View>(_ content: Content) -> some View {
        content
            .background { Color.clear.frame(width: 0, height: 0) }
            .onAppear { handleCalendarAppear() }
            .onChange(of: collegePersistence?.calendarDidChangeToken ?? 0) { _, _ in
                scheduleCacheRebuild()
            }
            .onChange(of: calendarManager?.calendarVisibilityToken ?? 0) { _, _ in
                scheduleCacheRebuild(delay: 0)
            }
    }

    @ViewBuilder
    private func calendarToolbarHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: headerDateString) { _, text in
                calendarSceneState?.headerDate = text
            }
            .onChange(of: activeViewMode) { _, mode in
                calendarSceneState?.viewMode = mode
            }
            .onChange(of: isEventListSidebarShown) { _, shown in
                calendarSceneState?.sidebarShown = shown
            }
            .onChange(of: sidebarPanel) { _, panel in
                calendarSceneState?.sidebarPanel = panel
            }
            .onChange(of: calendarToolbarInitials) { _, initials in
                calendarSceneState?.profileInitials = initials
            }
            .onChange(of: calendarSearchText) { _, query in
                scheduleToolbarCalendarSearch(query)
            }
    }

    @ViewBuilder
    private func calendarFilterHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onAppear { scheduleFilterSnapshotRefresh() }
            .onChange(of: sidebarDate) { _, _ in scheduleFilterSnapshotRefresh() }
            .onChange(of: activeCalendarFilters) { _, _ in scheduleFilterSnapshotRefresh() }
            .onChange(of: activeViewMode) { _, _ in scheduleFilterSnapshotRefresh() }
            .onChange(of: currentDate) { _, _ in scheduleFilterSnapshotRefresh() }
            .onChange(of: cacheStore.dayEventsByDate.count) { _, _ in scheduleFilterSnapshotRefresh() }
            .onDisappear {
                cancelCalendarBackgroundTasks()
                toolbarHandlerToken?.invalidate()
                toolbarHandlerToken = nil
                calendarSceneState?.toolbarHandler = nil
            }
    }

    private func syncToolbarState() {
        calendarSceneState?.headerDate = headerDateString
        calendarSceneState?.viewMode = activeViewMode
        calendarSceneState?.sidebarShown = isEventListSidebarShown
        calendarSceneState?.sidebarPanel = sidebarPanel
        calendarSceneState?.profileInitials = calendarToolbarInitials
    }

    private func handleCalendarToolbarAction(_ action: CalendarToolbarAction) {
        switch action {
        case .previous:
            shiftDate(by: -1)
        case .next:
            shiftDate(by: 1)
        case .modeChange(let mode):
            activeViewMode = mode
        case .sidebarToggle:
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                isEventListSidebarShown.toggle()
            }
        case .sidebarPanelChange(let panel):
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                sidebarPanel = panel
                if !isEventListSidebarShown {
                    isEventListSidebarShown = true
                }
            }
        }
    }


    private func calendarMainScroll(proxy: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            mainCalendarContent
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(560, proxy.size.height - 48))
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var isAddCalendarSheetPresented: Binding<Bool> {
        Binding(
            get: { modalCoordinator?.isAddCalendarItemPresented ?? false },
            set: { modalCoordinator?.isAddCalendarItemPresented = $0 }
        )
    }

    private var isEditCalendarSheetPresented: Binding<Bool> {
        Binding(
            get: { modalCoordinator?.isEditCalendarItemPresented ?? false },
            set: { modalCoordinator?.isEditCalendarItemPresented = $0 }
        )
    }

    private var addCalendarSheetSemester: CalendarSemesterRecord? {
        guard let semesterID = modalCoordinator?.addCalendarItemSemesterID else { return nil }
        return collegePersistence?.semester(id: semesterID)
    }

    private var addCalendarSheetTitle: String? {
        return modalCoordinator?.addCalendarItemInitialTitle
    }

    private var addCalendarSheetStart: Date? {
        return modalCoordinator?.addCalendarItemInitialStart
    }

    private var addCalendarSheetEnd: Date? {
        return modalCoordinator?.addCalendarItemInitialEnd
    }

    private var editCalendarSheetEvent: CalendarStoredEvent? {
        guard let eventID = modalCoordinator?.editCalendarItemID else { return nil }
        return collegePersistence?.calendarEventEntity(id: eventID)
    }

    private func presentAddEventFromSidebar() {
        let start = defaultSidebarStartDate()
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        modalCoordinator?.presentAddCalendarItem(semesterID: nil, title: nil, start: start, end: end
        )
    }

    private func presentAddTaskFromSidebar() {
        modalCoordinator?.presentAddTask(semesterID: nil, prefillCourseID: nil)
    }

    private func defaultSidebarStartDate() -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(sidebarDate) {
            return Date().addingTimeInterval(300)
        }

        var components = cal.dateComponents([.year, .month, .day], from: sidebarDate)
        components.hour = 10
        components.minute = 0
        return cal.date(from: components) ?? sidebarDate
    }

    @ViewBuilder
    private var mainCalendarContent: some View {
        VStack(spacing: 0) {
            if activeViewMode == .month {
                monthGridView
                    .id(currentDate)
                    .transition(navigationDirection >= 0
                        ? .push(from: .trailing)
                        : .push(from: .leading))
            } else {
                timeGridView
                    .id(currentDate)
                    .transition(navigationDirection >= 0
                        ? .push(from: .trailing)
                        : .push(from: .leading))
            }
        }
        .id(activeViewMode)
        .transition(.opacity.animation(motionReduced ? .easeOut(duration: 0.08) : .easeInOut(duration: 0.22)))
        .frame(maxWidth: .infinity, alignment: .top)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        .gesture(
            motionReduced ? nil :
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let direction = value.translation.width < 0 ? 1 : -1
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                        shiftDate(by: direction)
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: currentDate)
        // Two-finger trackpad swipe: installs an NSEvent monitor for phase-tracked scroll events.
        .background(
            TrackpadSwipeCapture(
                onNavigateForward: {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { shiftDate(by: 1) }
                },
                onNavigateBackward: {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { shiftDate(by: -1) }
                },
                onProgress: { p in
                    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.75)) {
                        swipeNavProgress = p
                    }
                },
                disabled: motionReduced || !isCalendarPageActive
            )
            .allowsHitTesting(false)
        )
        .overlay { calendarSwipeHint }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Subtle circular pill that appears mid-swipe to confirm the gesture direction before navigation fires.
    @ViewBuilder
    private var calendarSwipeHint: some View {
        let abs = abs(swipeNavProgress)
        if abs > 0.25 {
            let isBackward = swipeNavProgress > 0
            let opacity = min(1.0, (abs - 0.25) / 0.75)
            let scale   = 0.55 + 0.45 * min(1.0, abs)
            Image(systemName: isBackward ? "chevron.left" : "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .opacity(opacity)
                .scaleEffect(scale)
                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.7), value: swipeNavProgress)
        }
    }

    private var monthGridView: some View {
        let days = getDaysForCurrentView()
        return VStack(spacing: 0) {
            // Header Row (Days)
            HStack(spacing: 0) {
                let headers = days.prefix(7).map { $0 }
                ForEach(headers, id: \.timeIntervalSince1970) { date in
                    let dayString = CalendarFormatters.weekday.string(from: date).uppercased()
                    Text(dayString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            
            Divider().background(Color.primary.opacity(0.08))

            let rows = max(1, days.count / 7)
            
            if !days.isEmpty {
                ForEach(0..<rows, id: \.self) { rowIndex in
                    let startIdx = rowIndex * 7
                    let endIdx = min(startIdx + 7, days.count)
                    let rowDays = (startIdx..<endIdx).map { colIndex -> (Int, [CalEvent]?, Bool) in
                        let date = days[colIndex]
                        let dayNum = calendar.component(.day, from: date)
                        let evs = getEvents(for: date)
                        let isCurrent = calendar.isDateInToday(date)
                        return (dayNum, evs.isEmpty ? nil : evs, isCurrent)
                    }
                    
                    MonthCalendarRow(days: rowDays, isLast: rowIndex == rows - 1)
                }
            }
        }
    }
    
    // Y-Axis Time Grid
    private var timeGridView: some View {
        VStack(spacing: 0) {
            // Headers and all-day shelf
            let days = getDaysForCurrentView()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Time column header spacer
                    Spacer().frame(width: 58)
                    ForEach(days, id: \.self) { date in
                        dayHeaderColumn(for: date)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                }
                .padding(.vertical, 8)

                HStack(spacing: 0) {
                    // Time column header spacer
                    Spacer().frame(width: 58)
                    ForEach(days, id: \.self) { date in
                        allDayEventsColumn(for: date)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)
            }
            .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
            // Removed custom overlay border lines to let whitespace dictate.
            
            // Time Grid Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // Hour markers and grid lines
                        VStack(spacing: 0) {
                            ForEach(0...24, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(hourString(for: hour))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Color.secondary.opacity(0.55))
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 8)
                                        .offset(y: -6)

                                    Rectangle()
                                        .fill(Color.primary.opacity(0.06))
                                        .frame(height: 0.5)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                }
                                .frame(height: hourHeight)
                                .id(hour)
                            }
                        }
                    

                    // Events
                    HStack(spacing: 0) {
                        Spacer().frame(width: 58)
                        ForEach(days, id: \.self) { date in
                            let layouts = timedLayouts(for: date)
                            GeometryReader { geo in
                                ZStack(alignment: .topLeading) {
                                    ForEach(layouts) { layout in
                                        let event = layout.event
                                        let columnWidth = (geo.size.width - 8) / CGFloat(layout.columnCount)
                                        let gap: CGFloat = layout.columnCount > 1 ? 3 : 0
                                        let eventWidth = columnWidth - gap
                                        let eventX = CGFloat(layout.columnIndex) * columnWidth
                                        
                                        TimeEventBlock(event: event, eventWidth: eventWidth)
                                            .frame(width: eventWidth, height: height(for: event))
                                            .offset(x: eventX + gap/2, y: offset(for: event))
                                    }

                                    if let firstDay = days.first,
                                       calendar.isDate(date, inSameDayAs: firstDay) {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(width: 0.5, height: 24 * hourHeight)
                                            .offset(x: 0, y: 0)
                                    }

                                    Rectangle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 0.5, height: 24 * hourHeight)
                                        .offset(x: max(0, geo.size.width - 0.5), y: 0)
                                    
                                    // Current Time Indicator
                                    if calendar.isDateInToday(date) {
                                        TimelineView(.animation(minimumInterval: 60)) { context in
                                            let now = context.date
                                            let c = calendar.dateComponents([.hour, .minute], from: now)
                                            let currentOffset = (CGFloat(c.hour ?? 0) * 60.0 + CGFloat(c.minute ?? 0)) * (hourHeight / 60.0)

                                            if currentOffset > 0 {
                                                ZStack(alignment: .leading) {
                                                    Rectangle()
                                                        .fill(Color.red)
                                                        .frame(width: geo.size.width, height: 1)
                                                    Circle()
                                                        .fill(Color.red)
                                                        .frame(width: 6, height: 6)
                                                        .offset(x: -3)
                                                }
                                                .offset(y: currentOffset - 3)
                                                .allowsHitTesting(false)
                                                .zIndex(1)
                                                .transition(.opacity)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Current time label in the left time column.
                    if days.contains(where: { calendar.isDateInToday($0) }) {
                        TimelineView(.animation(minimumInterval: 60)) { context in
                            let now = context.date
                            let c = calendar.dateComponents([.hour, .minute], from: now)
                            let currentOffset = (CGFloat(c.hour ?? 0) * 60.0 + CGFloat(c.minute ?? 0)) * (hourHeight / 60.0)

                            if currentOffset > 0 {
                                HStack(spacing: 0) {
                                    Text(currentTimeString(for: now))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.red)
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 8)
                                    Spacer(minLength: 0)
                                }
                                .offset(y: currentOffset - 10)
                                .allowsHitTesting(false)
                                .zIndex(2)
                            }
                        }
                    }
                }
                .frame(height: 24 * hourHeight) // 24 hours * hourHeight
                .padding(.bottom, 80) // Prevent 11:59PM cutoff
            } // Close ScrollView
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(8, anchor: .top)
                }
            }
            } // Close ScrollViewReader
        }
        .gesture(
            motionReduced ? nil :
            MagnifyGesture()
                .onChanged { value in
                    let proposed = 60.0 * value.magnification
                    hourHeight = min(max(proposed, 36), 120)
                }
                .onEnded { value in
                    withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.82)) {
                        let proposed = 60.0 * value.magnification
                        hourHeight = min(max(proposed, 36), 120)
                    }
                }
        )
    }

    @ViewBuilder
    private func dayHeaderColumn(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)

        VStack(spacing: 4) {
            Text(dayHeader(for: date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isToday ? .accentColor : .secondary)

            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(Circle())
        }
    }

    @ViewBuilder
    private func allDayEventsColumn(for date: Date) -> some View {
        let allDay = getEvents(for: date).filter { $0.isAllDay }

        if !allDay.isEmpty {
            VStack(spacing: 4) {
                ForEach(allDay) { event in
                    let isInfo = isInformationalAllDay(event)
                    Text(event.title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isInfo ? .accentColor : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)
                        .background(isInfo ? Color.accentColor.opacity(0.15) : Color.red.opacity(0.8))
                        .cornerRadius(4)
                }
            }
            .padding(6)
            .background(DesignSystem.Colors.glassCardBase.opacity(0.8))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
            )
            .padding(.horizontal, 4)
        } else {
            // Keep a stable all-day shelf height even when a day has no all-day events.
            Color.clear
                .frame(height: 10)
        }
    }

    private func hourString(for hour: Int) -> String {
        let normalizedHour = (hour == 0 || hour == 24) ? 12 : (hour > 12 ? hour - 12 : hour)
        let suffix = (hour == 24) ? "AM" : ((hour >= 12) ? "PM" : "AM")
        return "\(normalizedHour) \(suffix)"
    }

    private func currentTimeString(for date: Date) -> String {
        CalendarFormatters.currentTime.string(from: date)
    }

    private func isInformationalAllDay(_ event: CalEvent) -> Bool {
        event.type == .classEvent || event.type == .management || event.type == .computerScience
    }
    
    private func dayHeader(for date: Date) -> String {
        CalendarFormatters.weekday.string(from: date).uppercased()
    }

    private func offset(for event: CalEvent) -> CGFloat {
        guard let start = event.startDate else { return 0 }
        let c = calendar.dateComponents([.hour, .minute], from: start)
        let totalMinutes = CGFloat(c.hour ?? 0) * 60.0 + CGFloat(c.minute ?? 0)
        return totalMinutes * (hourHeight / 60.0)
    }
    
    private func height(for event: CalEvent) -> CGFloat {
        guard let start = event.startDate, let end = event.endDate else { return hourHeight }
        let duration = end.timeIntervalSince(start) / 60.0
        return max(24, CGFloat(duration) * (hourHeight / 60.0))
    }

    /// Right sidebar: column title is pinned to the **top** of the sidebar (not vertically centered).
    private var academicEventsSidebar: some View {
        let now = Date()

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event List")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(sidebarDateString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Button {
                    isFilterPopoverShown.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundColor(activeCalendarFilters.isEmpty ? Color.secondary.opacity(0.55) : .accentColor)
                        .font(.system(size: 15, weight: .medium))
                        .padding(6)
                        .background(
                            activeCalendarFilters.isEmpty
                                ? Color.clear
                                : Color.accentColor.opacity(0.1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isFilterPopoverShown, arrowEdge: .top) {
                    CalendarFilterPopoverContent(
                        sidebarDate: $sidebarDate,
                        activeCalendarFilters: $activeCalendarFilters,
                        availableCalendars: uniqueCalendarNamesSnapshot
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if orderedSidebarEventsSnapshot.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("No events")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        ForEach(orderedSidebarEventsSnapshot) { event in
                            let isPast = isEventPassed(event, referenceDate: now)
                            let timeString: String = {
                                if event.isAllDay { return "All-Day" }
                                guard let start = event.startDate else { return "" }
                                return CalendarFormatters.shortTime.string(from: start)
                            }()
                            let matchedEntity = entity(for: event)
                            let pillColor = eventColor(for: event.type)
                            let calendarTint = matchedEntity.flatMap { calendarManager?.sourceCalendarColor(for: $0) } ?? pillColor.base
                            let calName = calendarNameForEvent(event)

                            SideEventCard(
                                badge: courseCode(for: event.title),
                                badgeColor: calendarTint.opacity(0.85),
                                time: timeString,
                                title: event.title,
                                calendarName: calName,
                                iconColor: calendarTint,
                                isAllDay: event.isAllDay,
                                isPast: isPast,
                                entity: matchedEntity
                            )
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.6)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.96, anchor: .top)
                                    .offset(y: phase.isIdentity ? 0 : 6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollBounceBehavior(.basedOnSize)

            Button(action: {
                presentAddEventFromSidebar()
            }) {
                Text("Add Event")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(PressableCardStyle(reduceMotion: motionReduced))
            .pointerStyle(.link)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .sensoryFeedback(.impact(weight: .light), trigger: isAddCalendarSheetPresented.wrappedValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
        .sensoryFeedback(.selection, trigger: sidebarDate)
    }

    private var tasksSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(sidebarDateString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    if orderedSidebarTasks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("No tasks")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        ForEach(orderedSidebarTasks) { task in
                            SideTaskCard(
                                title: task.title,
                                dueDate: task.dueDate
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollBounceBehavior(.basedOnSize)

            Button(action: {
                presentAddTaskFromSidebar()
            }) {
                Text("Add Task")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(PressableCardStyle(reduceMotion: motionReduced))
            .pointerStyle(.link)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color.clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }
    
    private func courseCode(for title: String) -> String {
        let parts = title.components(separatedBy: " ")
        if parts.count >= 2 {
            let first = parts[0]
            if first == first.uppercased() && first.count <= 4 {
                return "\(first) \(parts[1])".uppercased()
            }
        }
        return "SCHEDULED"
    }

    private func eventColor(for type: EventType) -> (base: Color, text: Color) {
        switch type {
        case .deadline: return (.red, .red.opacity(0.8))
        case .lecture, .classEvent: return (.accentColor, .accentColor.opacity(0.8))
        case .lab: return (.purple, .purple.opacity(0.8))
        case .extracurricular, .club: return (.green, .green.opacity(0.8))
        default: return (.secondary, .secondary)
        }
    }
}

// Block for Time Grid
fileprivate struct TimeEventBlock: View {
    let event: CalEvent
    let eventWidth: CGFloat

    @Environment(\.calendarPersistence) private var collegePersistence
    @Environment(\.calendarIntegrationManager) private var calendarManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false
    @GestureState private var isPressed = false
    @State private var selectedEntity: CalendarStoredEvent?
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(baseColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11, weight: .bold))
                    .minimumScaleFactor(0.75)
                    .foregroundColor(textColor)

                GeometryReader { geo in
                    if geo.size.height > 25 && eventWidth >= 100 {
                        Text(timeString)
                            .lineLimit(1)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(textColor.opacity(0.8))
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .background(
            ZStack {
                DesignSystem.Colors.glassCardBase
                baseColor.opacity(isHovering ? 0.25 : 0.15)
            }
        )
        .padding(.trailing, 2)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(baseColor.opacity(0.3), lineWidth: 0.5)
        )
        .clipped()
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.10, dampingFraction: 0.72), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($isPressed) { _, state, _ in state = true }
        )
        .pointerStyle(.link)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
        .onTapGesture {
            selectedEntity = resolvedEntity
            showDetail = selectedEntity != nil
        }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            if let selectedEntity {
                EventDetailPopoverContent(entity: selectedEntity)
            } else {
                Text("Event unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
        }
    }

    private var resolvedEntity: CalendarStoredEvent? {
        guard let eventID = event.calendarEventID else { return nil }
        return collegePersistence?.calendarEventEntity(id: eventID)
    }

    private var baseColor: Color {
        if let entity = resolvedEntity,
           let color = calendarManager?.sourceCalendarColor(for: entity) {
            return color
        }

        switch event.type {
        case .lecture: return .accentColor
        case .lab: return .purple
        case .deadline: return .red
        case .extracurricular: return .green
        case .management: return Color.orange
        case .computerScience: return Color.blue
        default: return .indigo
        }
    }

    private var textColor: Color { .primary }

    private var timeString: String {
        guard let s = event.startDate, let e = event.endDate else { return "" }
        return "\(Self.timeFormatter.string(from: s)) - \(Self.timeFormatter.string(from: e))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

fileprivate struct MonthCalendarRow: View {
    let days: [(Int, [CalEvent]?, Bool)]
    let isLast: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<days.count, id: \.self) { index in
                    let day = days[index]
                    MonthCalendarCell(dayNumber: day.0, events: day.1 ?? [], isCurrentDay: day.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if index < days.count - 1 {
                        Divider().background(Color.primary.opacity(0.08))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            if !isLast {
                Divider().background(Color.primary.opacity(0.08))
            }
        }
    }
}

fileprivate struct MonthCalendarCell: View {
    let dayNumber: Int
    let events: [CalEvent]
    let isCurrentDay: Bool

    @State private var isHovered = false

    // Tuned to the current day header + pill styling so overflow appears only when needed.
    private let headerApproxHeight: CGFloat = 36
    private let eventRowApproxHeight: CGFloat = 18
    private let moreLabelApproxHeight: CGFloat = 16
    
    var body: some View {
        GeometryReader { geo in
            let availableEventHeight = max(0, geo.size.height - headerApproxHeight)
            let rawCapacity = Int(floor(availableEventHeight / eventRowApproxHeight))
            let eventCapacity = max(0, rawCapacity)
            let hasOverflow = events.count > eventCapacity
            let adjustedCapacity: Int = {
                guard hasOverflow else { return eventCapacity }
                if availableEventHeight < moreLabelApproxHeight { return 0 }
                let withMore = Int(floor((availableEventHeight - moreLabelApproxHeight) / eventRowApproxHeight))
                return max(0, withMore)
            }()
            let displayedEvents = Array(events.prefix(adjustedCapacity))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isCurrentDay {
                        Text("\(dayNumber)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .shadow(color: Color.accentColor.opacity(isHovered ? 0.5 : 0), radius: 6)
                    } else {
                        Text("\(dayNumber)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(events.isEmpty ? Color.secondary.opacity(0.55) : Color.primary.opacity(0.8))
                            .frame(width: 24, height: 24)
                            .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                            .clipShape(Circle())
                            .padding(.leading, 2)
                            .padding(.top, 2)
                    }
                    Spacer()
                }
                .padding(.top, 6)
                .padding(.horizontal, 6)
                .animation(.easeInOut(duration: 0.15), value: isHovered)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(displayedEvents) { event in
                        EventPill(event: event)
                    }

                    if events.count > adjustedCapacity {
                        Text("+ \(events.count - adjustedCapacity) more")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 6)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 6)

                Spacer(minLength: 0)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            }
        }
    }
}

fileprivate struct EventPill: View {
    let event: CalEvent

    @Environment(\.calendarPersistence) private var collegePersistence
    @Environment(\.calendarIntegrationManager) private var calendarManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var selectedEntity: CalendarStoredEvent?
    @State private var showDetail = false

    var body: some View {
        Button(action: {
            selectedEntity = resolvedEntity
            showDetail = selectedEntity != nil
        }) {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(baseColor)
                    .frame(width: 3)

                if event.isImportant {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8))
                } else if event.type == .lecture || event.type == .classEvent {
                    Image(systemName: "book.fill")
                        .font(.system(size: 8))
                } else if event.type == .lab {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 8))
                }

                Text(event.title)
                    .font(.system(size: 9, weight: event.isImportant ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(textColor)
            .padding(.trailing, 6)
            .frame(height: 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(baseColor.opacity(isHovering ? 0.3 : 0.15))
            .cornerRadius(4)
            .clipped()
        }
        .buttonStyle(PressableCardStyle(reduceMotion: reduceMotion))
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .popover(isPresented: $showDetail, arrowEdge: .trailing) {
            if let selectedEntity {
                EventDetailPopoverContent(entity: selectedEntity)
            } else {
                Text("Event unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
        }
    }

    private var resolvedEntity: CalendarStoredEvent? {
        guard let eventID = event.calendarEventID else { return nil }
        return collegePersistence?.calendarEventEntity(id: eventID)
    }

    private var baseColor: Color {
        if let entity = resolvedEntity,
           let color = calendarManager?.sourceCalendarColor(for: entity) {
            return color
        }

        switch event.type {
        case .deadline: return .red
        case .lecture, .classEvent: return .accentColor
        case .lab: return .purple
        case .extracurricular, .club: return .green
        default: return .secondary
        }
    }

    private var textColor: Color {
        if let entity = resolvedEntity,
           calendarManager?.sourceCalendarColor(for: entity) != nil {
            return baseColor.opacity(0.9)
        }

        switch event.type {
        case .deadline: return .red.opacity(0.8)
        case .lecture, .classEvent: return .accentColor.opacity(0.8)
        case .lab: return .purple.opacity(0.8)
        case .extracurricular, .club: return .green.opacity(0.8)
        default: return .secondary
        }
    }
}


fileprivate struct SideEventCard: View {
    let badge: String
    let badgeColor: Color
    let time: String
    let title: String
    let calendarName: String
    let iconColor: Color
    let isAllDay: Bool
    let isPast: Bool
    let entity: CalendarStoredEvent?

    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var showDetail = false

    private var mutedTextColor: Color { .secondary.opacity(0.6) }
    private var strikeColor: Color { .secondary.opacity(0.45) }

    var body: some View {
        let liveBadgeColor = isPast ? mutedTextColor : badgeColor
        let liveAllDayColor = isPast ? mutedTextColor : Color.accentColor.opacity(0.8)
        let liveTimeColor = isPast ? mutedTextColor : Color.secondary.opacity(0.55)
        let liveTitleColor = isPast ? mutedTextColor : Color.primary
        let liveMetaColor = isPast ? mutedTextColor : Color.secondary
        let liveIconColor = isPast ? mutedTextColor : iconColor.opacity(0.8)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(liveBadgeColor)
                    .strikethrough(isPast, color: strikeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(liveBadgeColor.opacity(0.45), lineWidth: 1)
                    )

                if isAllDay {
                    Text("ALL-DAY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(liveAllDayColor)
                        .strikethrough(isPast, color: strikeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(isPast ? 0.25 : 0.45), lineWidth: 1)
                        )
                }

                Spacer()

                Text(time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(liveTimeColor)
                    .strikethrough(isPast, color: strikeColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(liveTitleColor)
                    .strikethrough(isPast, color: strikeColor)

                HStack(spacing: 4) {
                    Image(systemName: isAllDay ? "calendar" : "clock")
                        .font(.system(size: 11))
                        .foregroundColor(liveIconColor)
                    Text(calendarName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(liveMetaColor)
                        .strikethrough(isPast, color: strikeColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(20)
        .background(DesignSystem.Colors.glassCardBase.background(.thinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(isHovering ? 0.13 : 0.05),
            radius: isHovering ? 18 : 8,
            y: isHovering ? 5 : 2
        )
        .scaleEffect(isHovering ? 1.025 : 1.0)
        .offset(y: isHovering ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isHovering)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .onTapGesture {
            if entity != nil { showDetail = true }
        }
        .popover(isPresented: $showDetail, arrowEdge: .leading) {
            if let entity {
                EventDetailPopoverContent(entity: entity)
            }
        }
        .cursor(.pointingHand)
    }
}

fileprivate struct SideTaskCard: View {
    let title: String
    let dueDate: Date?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TASK")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                    )

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: "checklist")
                        .font(.system(size: 10, weight: .semibold))
                    Text(dueTimeText)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isHovering)
    }

    private var dueTimeText: String {
        guard let dueDate else { return "No Due Time" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: dueDate)
    }
}

// MARK: - Event Detail Popover

private struct EventDetailPopoverContent: View {
    let entity: CalendarStoredEvent

    @Environment(\.dismiss) private var dismiss
    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { true },
            set: { isPresented in
                if !isPresented {
                    dismiss()
                }
            }
        )
    }

    var body: some View {
        CalendarOverlayAccess.builder?.addCalendarItemOverlay(
            isPresented: isPresentedBinding,
            semesterID: entity.semesterID,
            initialTitle: entity.title,
            initialStart: entity.startDate,
            initialEnd: entity.endDate,
            eventID: entity.id,
            style: .anchoredPanel
        )
        .frame(width: 507)
        .frame(minHeight: 333, idealHeight: 373, maxHeight: 413)
        .background(Color.clear)
    }
}

// MARK: - Calendar Filter Popover

private struct CalendarFilterPopoverContent: View {
    @Binding var sidebarDate: Date
    @Binding var activeCalendarFilters: Set<String>
    let availableCalendars: [String]

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Filter Events")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            // Day picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Day")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    dayChip("Today", date: Date())
                    dayChip("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
                }
                .padding(.horizontal, 16)

                DatePicker("", selection: $sidebarDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }

            Divider()
                .padding(.vertical, 4)

            // Calendar filter
            if !availableCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(availableCalendars, id: \.self) { calName in
                        let isActive = activeCalendarFilters.contains(calName)
                        HStack {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(isActive ? .accentColor : Color.secondary.opacity(0.55))
                                .contentTransition(.symbolEffect(.replace.offUp))
                                .animation(.spring(response: 0.26, dampingFraction: 0.80), value: isActive)
                            Text(calName)
                                .font(.system(size: 13))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                                if isActive {
                                    activeCalendarFilters.remove(calName)
                                } else {
                                    activeCalendarFilters.insert(calName)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 12)
            }

            if !activeCalendarFilters.isEmpty || !Calendar.current.isDateInToday(sidebarDate) {
                Divider()
                Button {
                    sidebarDate = Date()
                    activeCalendarFilters = []
                } label: {
                    HStack {
                        Spacer()
                        Text("Clear Filters")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func dayChip(_ label: String, date: Date) -> some View {
        let isSelected = Calendar.current.isDate(sidebarDate, inSameDayAs: date)
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { sidebarDate = date }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)))
                .clipShape(Capsule())
                .animation(.spring(response: 0.26, dampingFraction: 0.80), value: isSelected)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

fileprivate extension View {
    func border(_ color: Color, width: CGFloat, edges: [Edge]) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }

    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        // Keep API compatibility for existing call sites without mutating NSCursor stack.
        self
    }
}


// MARK: – Trackpad Swipe Navigation

/// An invisible NSViewRepresentable that installs a local NSEvent monitor for phase-tracked
/// scroll wheel events. When the user performs a two-finger horizontal swipe on the trackpad,
/// horizontal delta accumulates until a threshold is reached, then the appropriate navigation
/// callback fires. All events are returned unmodified so the enclosing ScrollView continues
/// to work normally.
///
/// Thread-safety: NSEvent.addLocalMonitorForEvents fires on the main thread, and all
/// callbacks are dispatched via DispatchQueue.main.async, so Coordinator access is
/// effectively single-threaded.
@available(macOS 14, *)
private struct TrackpadSwipeCapture: NSViewRepresentable {
    let onNavigateForward:  () -> Void   // swipe left  → next period
    let onNavigateBackward: () -> Void   // swipe right → previous period
    let onProgress: (CGFloat) -> Void    // -1...1: negative=forward, positive=backward
    let disabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        context.coordinator.install(
            onForward: onNavigateForward,
            onBackward: onNavigateBackward,
            onProgress: onProgress,
            disabled: disabled
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            onForward: onNavigateForward,
            onBackward: onNavigateBackward,
            onProgress: onProgress,
            disabled: disabled
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    // MARK: Coordinator

    // @unchecked Sendable: NSEvent monitor fires on the main thread;
    // all callback invocations are safe single-threaded accesses.
    final class Coordinator: @unchecked Sendable {
        private var onForward:  (() -> Void)?
        private var onBackward: (() -> Void)?
        private var onProgress: ((CGFloat) -> Void)?
        private var isDisabled = true

        private var token: Any?
        private var accumX: CGFloat = 0
        private var fired  = false

        // Direction lock: determined on first significant delta each gesture.
        private var isTrackingHorizontal = false
        private var directionLocked      = false

        /// Horizontal delta required to trigger navigation.
        private let kThreshold: CGFloat = 80
        /// Horizontal delta before the visual hint begins appearing.
        private let kHintStart: CGFloat = 18
        /// Minimum combined delta before the axis is locked in.
        private let kAxisLockThreshold: CGFloat = 5

        func install(
            onForward: @escaping () -> Void,
            onBackward: @escaping () -> Void,
            onProgress: @escaping (CGFloat) -> Void,
            disabled: Bool
        ) {
            update(onForward: onForward, onBackward: onBackward, onProgress: onProgress, disabled: disabled)
            guard token == nil else { return }
            // Returns nil to suppress horizontal-swipe events so the vertical
            // ScrollView doesn't bounce while we're handling a horizontal gesture.
            token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self else { return event }
                let suppress = self.processScrollEvent(event)
                return suppress ? nil : event
            }
        }

        func update(
            onForward: @escaping () -> Void,
            onBackward: @escaping () -> Void,
            onProgress: @escaping (CGFloat) -> Void,
            disabled: Bool
        ) {
            self.onForward = onForward
            self.onBackward = onBackward
            self.onProgress = onProgress
            isDisabled = disabled
        }

        func teardown() {
            if let t = token { NSEvent.removeMonitor(t) }
            token = nil
        }

        /// Returns true when the event should be suppressed (not forwarded to the ScrollView).
        @discardableResult
        private func processScrollEvent(_ event: NSEvent) -> Bool {
            // Non-phase-tracked events (old mouse wheels, momentum) — pass through.
            guard !isDisabled, event.phase != [] else { return false }

            switch event.phase {
            case .began:
                accumX = 0
                fired  = false
                isTrackingHorizontal = false
                directionLocked      = false
                send(progress: 0)
                return false   // always let the .began event through

            case .changed:
                // Lock the scroll axis on the first significant movement.
                if !directionLocked {
                    let dx = abs(event.scrollingDeltaX)
                    let dy = abs(event.scrollingDeltaY)
                    if dx + dy >= kAxisLockThreshold {
                        isTrackingHorizontal = dx > dy
                        directionLocked = true
                    }
                }

                guard isTrackingHorizontal else { return false }
                guard !fired else { return true }   // still suppress during cool-down

                accumX += event.scrollingDeltaX
                if abs(accumX) > kHintStart {
                    let clamped = max(-1, min(1, accumX / kThreshold))
                    send(progress: clamped)
                }
                if accumX > kThreshold {
                    fired = true; send(progress: 0); fire(onBackward)
                } else if accumX < -kThreshold {
                    fired = true; send(progress: 0); fire(onForward)
                }
                return true   // suppress: keep ScrollView still during horizontal swipe

            case .ended, .cancelled:
                let wasH = isTrackingHorizontal
                accumX = 0; fired = false
                isTrackingHorizontal = false; directionLocked = false
                send(progress: 0)
                return wasH   // suppress the ending event if we owned this gesture

            default:
                return false
            }
        }

        // NSEvent monitor runs on the main thread, so direct invocation is safe.
        private func send(progress: CGFloat) { onProgress?(progress) }
        private func fire(_ action: (() -> Void)?) { action?() }
    }
}

fileprivate struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = rect.width, h: CGFloat = rect.height
            switch edge {
            case .top:    h = width
            case .bottom: y = rect.maxY - width; h = width
            case .leading:  w = width
            case .trailing: x = rect.maxX - width; w = width
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}

// MARK: - Sidebar filter snapshots (built off the view body)

private enum CalendarSidebarSnapshotBuilder {
    static func calendarName(for event: CalEvent) -> String {
        let code = courseCode(for: event.title)
        if code != "SCHEDULED" { return code }
        switch event.type {
        case .extracurricular, .club: return "Extracurricular"
        case .deadline: return "Tasks"
        case .personal: return "Personal"
        case .management: return "Management"
        default: return "Academic"
        }
    }

    private static func courseCode(for title: String) -> String {
        let parts = title.components(separatedBy: " ")
        if parts.count >= 2 {
            let first = parts[0]
            if first == first.uppercased() && first.count <= 4 {
                return "\(first) \(parts[1])".uppercased()
            }
        }
        return "SCHEDULED"
    }

    static func uniqueCalendarNames(
        viewDayEvents: [[CalEvent]],
        todayEvents: [CalEvent]
    ) -> [String] {
        var names = Set<String>()
        for events in viewDayEvents {
            for event in events {
                names.insert(calendarName(for: event))
            }
        }
        for event in todayEvents {
            names.insert(calendarName(for: event))
        }
        return names.sorted()
    }

    static func orderedSidebarEvents(
        events: [CalEvent],
        filters: Set<String>,
        referenceInstant: TimeInterval
    ) -> [CalEvent] {
        var content = events
        if !filters.isEmpty {
            content = content.filter { filters.contains(calendarName(for: $0)) }
        }
        let referenceDate = Date(timeIntervalSince1970: referenceInstant)
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return content.sorted { lhs, rhs in
            let lhsPassed = isEventPassed(lhs, referenceDate: referenceDate, calendar: calendar)
            let rhsPassed = isEventPassed(rhs, referenceDate: referenceDate, calendar: calendar)
            if lhsPassed != rhsPassed { return !lhsPassed && rhsPassed }
            if let lhsStart = lhs.startDate, let rhsStart = rhs.startDate { return lhsStart < rhsStart }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func isEventPassed(
        _ event: CalEvent,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        if event.isAllDay {
            guard let end = event.endDate else { return false }
            return end < calendar.startOfDay(for: referenceDate)
        }
        let end = event.endDate ?? event.startDate
        guard let end else { return false }
        return end < referenceDate
    }
}

