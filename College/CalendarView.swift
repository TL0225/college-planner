import Foundation
import SwiftUI
import Combine
import AppKit
import CoreData
import UniformTypeIdentifiers

fileprivate func isPastEvent(start: Date?, end: Date?, allDay: Bool, now: Date = Date()) -> Bool {
    guard let end else { return false }
    if allDay {
        // Treat all-day events as past once their end has passed the start of today.
        return end <= Calendar.current.startOfDay(for: now)
    }
    return end < now
}

fileprivate struct CourseColorOverrides {
    fileprivate static let keyPrefix = "CourseColorOverride."

    static func color(for courseCode: String) -> Color? {
        let key = keyPrefix + courseCode
        guard let hex = UserDefaults.standard.string(forKey: key) else { return nil }
        return Color(hex: hex)
    }

    static func setColor(_ color: Color, for courseCode: String) {
        guard let hex = color.hexRGBString() else { return }
        let key = keyPrefix + courseCode
        UserDefaults.standard.set(hex, forKey: key)
    }

    static func clearColor(for courseCode: String) {
        let key = keyPrefix + courseCode
        UserDefaults.standard.removeObject(forKey: key)
    }
}

fileprivate func stableColor(for courseCode: String) -> Color {
    let normalized = courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if let override = CourseColorOverrides.color(for: normalized) {
        return override
    }
    let palette: [Color] = [
        DesignSystem.Colors.primary,
        DesignSystem.Colors.secondary,
        DesignSystem.Colors.accent,
        DesignSystem.Colors.success,
        DesignSystem.Colors.warning,
        DesignSystem.Colors.info
    ]
    let value = abs(normalized.unicodeScalars.reduce(0) { $0 + Int($1.value) })
    return palette[value % palette.count]
}

private enum CalendarItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [URL: CGRect] = [:]
    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Non-publishing cache for calendar item frames.
///
/// This intentionally avoids @Published to prevent SwiftUI feedback loops:
/// GeometryPreference -> @State update -> re-render -> GeometryPreference -> ...
private final class CalendarItemFrameCache: ObservableObject {
    var frames: [URL: CGRect] = [:]

    func update(with newFrames: [URL: CGRect]) {
        guard !newFrames.isEmpty else { return }

        // Round to half-point to avoid perpetual tiny diffs during animations/transitions.
        func round(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        func rounded(_ r: CGRect) -> CGRect {
            CGRect(
                x: round(r.origin.x),
                y: round(r.origin.y),
                width: round(r.size.width),
                height: round(r.size.height)
            )
        }

        let epsilon: CGFloat = 0.5
        func approxEqual(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.origin.x - b.origin.x) <= epsilon &&
            abs(a.origin.y - b.origin.y) <= epsilon &&
            abs(a.size.width - b.size.width) <= epsilon &&
            abs(a.size.height - b.size.height) <= epsilon
        }

        for (k, v) in newFrames {
            let rv = rounded(v)
            if let old = frames[k], approxEqual(old, rv) {
                continue
            }
            frames[k] = rv
        }
    }
}

private enum SearchFieldFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

private enum CalendarTopPillFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

fileprivate enum CalendarQuickAddParser {
    struct Result {
        var title: String
        var start: Date?
        var end: Date?
    }

    static func parse(_ raw: String, referenceDate: Date) -> Result {
        let working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return Result(title: "", start: nil, end: nil) }

        let calendar = Calendar.current
        let baseDay = calendar.startOfDay(for: referenceDate)

        // 1) Resolve an explicit day offset (today/tomorrow) if present.
        var dayStart = baseDay
        var consumedRanges: [NSRange] = []

        if let range = working.range(of: "tomorrow", options: [.caseInsensitive, .diacriticInsensitive]) {
            consumedRanges.append(NSRange(range, in: working))
            dayStart = calendar.date(byAdding: .day, value: 1, to: baseDay) ?? baseDay
        } else if let range = working.range(of: "today", options: [.caseInsensitive, .diacriticInsensitive]) {
            consumedRanges.append(NSRange(range, in: working))
            dayStart = baseDay
        }

        // 2) Parse a time range like "1pm-2pm" or "13:00-14:30".
        let timeRangePattern = "(?i)\\b(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\s*(?:-|to)\\s*(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\b"
        if let match = firstMatch(pattern: timeRangePattern, in: working) {
            consumedRanges.append(match.range)

            let h1 = requiredIntGroup(working, match, 1)
            let m1 = optionalIntGroup(working, match, 2) ?? 0
            let ap1 = stringGroup(working, match, 3)

            let h2 = requiredIntGroup(working, match, 4)
            let m2 = optionalIntGroup(working, match, 5) ?? 0
            let ap2 = stringGroup(working, match, 6)

            if let start = makeTime(on: dayStart, hour: h1, minute: m1, ampm: ap1),
               let end = makeTime(on: dayStart, hour: h2, minute: m2, ampm: ap2 ?? ap1) {
                let finalEnd = (end <= start) ? (calendar.date(byAdding: .hour, value: 1, to: start) ?? end) : end
                return Result(title: strip(raw: working, removing: consumedRanges), start: start, end: finalEnd)
            }
        }

        // 3) Parse a single time like "3pm" or "15:30".
        let singleTimePattern = "(?i)\\b(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\b"
        if let match = firstMatch(pattern: singleTimePattern, in: working) {
            // Avoid treating the leading number in a short title (e.g. "CS 101") as a time.
            // Heuristic: require am/pm or a colon, or a number in 1...12.
            let hasColon = (stringGroup(working, match, 2) != nil)
            let ap = stringGroup(working, match, 3)
            let hour = requiredIntGroup(working, match, 1)
            let minute = optionalIntGroup(working, match, 2) ?? 0
            if ap != nil || hasColon || (1...12).contains(hour) {
                consumedRanges.append(match.range)
                if let start = makeTime(on: dayStart, hour: hour, minute: minute, ampm: ap) {
                    let end = calendar.date(byAdding: .hour, value: 1, to: start)
                    return Result(title: strip(raw: working, removing: consumedRanges), start: start, end: end)
                }
            }
        }

        return Result(title: working, start: nil, end: nil)
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private static func requiredIntGroup(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> Int {
        Int((text as NSString).substring(with: match.range(at: index))) ?? 0
    }

    private static func optionalIntGroup(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> Int? {
        let r = match.range(at: index)
        guard r.location != NSNotFound else { return nil }
        return Int((text as NSString).substring(with: r))
    }

    private static func stringGroup(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> String? {
        let r = match.range(at: index)
        guard r.location != NSNotFound else { return nil }
        let s = (text as NSString).substring(with: r)
        return s.isEmpty ? nil : s
    }

    private static func makeTime(on dayStart: Date, hour: Int, minute: Int, ampm: String?) -> Date? {
        var h = hour
        if let ap = ampm?.lowercased() {
            if ap == "pm" && h < 12 { h += 12 }
            if ap == "am" && h == 12 { h = 0 }
        }
        guard (0...23).contains(h), (0...59).contains(minute) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: h * 60 + minute, to: dayStart)
    }

    private static func strip(raw: String, removing ranges: [NSRange]) -> String {
        guard !ranges.isEmpty else { return raw }
        let sorted = ranges.sorted { $0.location > $1.location }
        let mutable = NSMutableString(string: raw)
        for r in sorted {
            if r.location != NSNotFound, NSMaxRange(r) <= mutable.length {
                mutable.replaceCharacters(in: r, with: " ")
            }
        }
        return (mutable as String)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

fileprivate func eventDisplayColor(_ event: CalendarEventEntity, calendarManager: CalendarIntegrationManager) -> Color {
    if let id = event.id, let override = EventColorOverrides.color(for: id) {
        return override
    }

    if event.course != nil {
        return stableColor(for: event.course?.code ?? "")
    }

    if let sourceColor = calendarManager.sourceCalendarColor(for: event) {
        return sourceColor
    }

    return DesignSystem.Colors.primary
}

fileprivate enum CalendarTimeFormatters {
    static let hourLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

fileprivate func localizedHourLabel(hour: Int) -> String {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: Date())
    let date = calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
    return CalendarTimeFormatters.hourLabel.string(from: date)
}

fileprivate func localizedTimePrefix(_ date: Date) -> String {
    CalendarTimeFormatters.shortTime.string(from: date)
}

fileprivate func localizedTimeRange(_ start: Date, _ end: Date) -> String {
    "\(localizedTimePrefix(start))–\(localizedTimePrefix(end))"
}

fileprivate struct TimeRangeTooltip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
            )
            .cornerRadius(10)
    }
}

struct CalendarView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedSemesterID: UUID? = nil
    @State private var displayedMonth: Date = Date()

    var body: some View {
        CalendarShellView(
            selectedSemesterID: $selectedSemesterID,
            displayedMonth: $displayedMonth,
            onAddItem: {
                modalCoordinator.activeModal = .addCalendarItem(
                    semesterID: selectedSemesterID,
                    initialTitle: nil,
                    initialStart: nil,
                    initialEnd: nil
                )
            }
        )
        .onAppear {
            if selectedSemesterID == nil {
                selectedSemesterID = defaultSemesterID()
            }
        }
        .onChange(of: coreDataManager.semesters.count) { _, _ in
            if selectedSemesterID == nil {
                selectedSemesterID = defaultSemesterID()
            }
        }
    }

    private func defaultSemesterID() -> UUID? {
        let sorted = coreDataManager.semesters.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.seasonOrder > $1.seasonOrder
        }
        return sorted.first?.id
    }
}

private struct CalendarShellView: View {
    @Binding var selectedSemesterID: UUID?
    @Binding var displayedMonth: Date
    let onAddItem: () -> Void

    var body: some View {
        CalendarMainContent(
            selectedSemesterID: $selectedSemesterID,
            displayedMonth: $displayedMonth,
            onAddItem: onAddItem
        )
    }
}

// Calendar sidebar removed by request (Select Semester / My Courses / Upcoming Tasks).

struct CourseListItem: View {
    let code: String
    let name: String
    let color: Color
    
    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color.opacity(0.4), radius: 4)
                
                VStack(alignment: .leading) {
                    Text(code)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Text(name)
                        .font(DesignSystem.Fonts.main(size: 10))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            Image(systemName: "eye")
                .font(.system(size: 14))
                .foregroundColor(color)
        }
        .padding(12)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
        )
    }
}

struct TaskItem: View {
    let title: String
    let subtitle: String
    let time: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time)
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(color)
                .tracking(0.5)
            
            Text(title)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
            
            Text(subtitle)
                .font(DesignSystem.Fonts.main(size: 10))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            HStack {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)
                Spacer()
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2)
    }
}

private struct AgendaRow: View {
    let title: String
    let subtitle: String?
    let timeText: String
    let color: Color

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(timeText)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .tracking(0.5)

                Text(title)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)

                if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? DesignSystem.Colors.textLight.opacity(0.28) : Color(hex: "f1f5f9"), lineWidth: isHovered ? 1.25 : 1)
        )
        .offset(y: isHovered ? -2 : 0)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CalendarMainContent: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedSemesterID: UUID?
    @Binding var displayedMonth: Date
    let onAddItem: () -> Void

    @State private var dayChips: [Date: [CalendarChip]] = [:]
    @State private var viewMode: CalendarViewMode = .month
    @State private var calendarEvents: [CalendarEventEntity] = []
    @State private var calendarTasks: [TaskEntity] = []
    @State private var searchEventResults: [CalendarEventEntity] = []
    @State private var searchTaskResults: [TaskEntity] = []
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    @State private var monthKeyboardSelection: Date = Date()
    @State private var showsMonthKeyboardFocusIndicator: Bool = false
    @State private var courseColorOverrideRevision: Int = 0
    @State private var hoveredSearchResultURL: URL? = nil
    @State private var cachedSearchFieldFrame: CGRect? = nil

    @State private var isShowingAddHelpPopover: Bool = false

    @ScaledMetric(relativeTo: .body) private var headerControlSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var headerVerticalPadding: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var headerHorizontalPadding: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var focusCardWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var focusCardHeight: CGFloat = 72

    @State private var isCommandPalettePresented: Bool = false
    @State private var commandPaletteQuery: String = ""
    @FocusState private var isCommandPaletteFieldFocused: Bool

    @State private var isQuickAddPresented: Bool = false
    @State private var quickAddText: String = ""
    @FocusState private var isQuickAddFieldFocused: Bool

    @StateObject private var calendarItemFrameCache = CalendarItemFrameCache()
    @State private var anchoredEditorObjectID: NSManagedObjectID? = nil
    @State private var anchoredEditorAnchorURL: URL? = nil
    @State private var cachedAnchoredEditorFrame: CGRect? = nil
    @State private var anchoredEditorPreferredHeight: CGFloat = 0
    @State private var anchoredEditorUserSize: CGSize? = nil

    @State private var anchoredTaskEditorObjectID: NSManagedObjectID? = nil
    @State private var anchoredTaskEditorAnchorURL: URL? = nil
    @State private var cachedAnchoredTaskEditorFrame: CGRect? = nil
    @State private var anchoredTaskEditorPreferredHeight: CGFloat = 0
    @State private var anchoredTaskEditorUserSize: CGSize? = nil

    @State private var topInlineEditorObjectID: NSManagedObjectID? = nil
    @State private var topInlineEditorIsTask: Bool = false
    @State private var topInlineEditorPreferredHeight: CGFloat = 0

    @State private var lastMonthDragSwitch: Date = .distantPast

    @State private var monthNavigationDirection: Int = 0

    private enum CalendarSearchResultKind {
        case event
        case task
    }

    private struct CalendarSearchResult: Identifiable {
        let kind: CalendarSearchResultKind
        let id: NSManagedObjectID
        let title: String
        let subtitle: String?
        let date: Date
    }

    private enum FocusItemKind {
        case event
        case task
    }

    private struct FocusItem: Identifiable {
        let id: NSManagedObjectID
        let kind: FocusItemKind
        let title: String
        let subtitle: String?
        let date: Date
        let isAllDay: Bool
        let color: Color
    }

    private var shouldShowSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var focusItems: [FocusItem] {
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        var items: [FocusItem] = []

        for event in filteredEvents {
            guard let start = event.startDate, let end = event.endDate else { continue }
            guard end >= now, start <= horizon else { continue }
            let subtitle: String?
            if event.allDay {
                subtitle = start.formatted(date: .abbreviated, time: .omitted)
            } else {
                subtitle = localizedTimeRange(start, end)
            }
            items.append(
                FocusItem(
                    id: event.objectID,
                    kind: .event,
                    title: (event.title ?? "Event"),
                    subtitle: subtitle,
                    date: start,
                    isAllDay: event.allDay,
                    color: eventDisplayColor(event, calendarManager: calendarManager)
                )
            )
        }

        for task in filteredTasks {
            guard let dueDate = task.dueDate else { continue }
            guard dueDate >= now, dueDate <= horizon else { continue }
            items.append(
                FocusItem(
                    id: task.objectID,
                    kind: .task,
                    title: (task.title ?? "Task"),
                    subtitle: dueDate.formatted(date: .abbreviated, time: .shortened),
                    date: dueDate,
                    isAllDay: false,
                    color: DesignSystem.Colors.warning
                )
            )
        }

        return items.sorted { $0.date < $1.date }.prefix(6).map { $0 }
    }

    private var focusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(focusItems) { item in
                    FocusCard(
                        item: item,
                        width: focusCardWidth,
                        height: focusCardHeight,
                        onJump: { jumpToFocusItem(item) },
                        onPrimaryAction: { openFocusItem(item) },
                        onSecondaryAction: item.kind == .task ? { completeTaskItem(item) } : nil
                    )
                }
            }
            .padding(.horizontal, headerHorizontalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            calendarBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.bgMain)
        .coordinateSpace(name: "CalendarMainContent")
        .onPreferenceChange(CalendarItemFramePreferenceKey.self) { newFrames in
            guard !newFrames.isEmpty else { return }
            calendarItemFrameCache.update(with: newFrames)
        }
        .overlay {
            anchoredEditorsOverlay
        }
        .overlayPreferenceValue(SearchFieldFramePreferenceKey.self) { frame in
            GeometryReader { proxy in
                let containerSize = proxy.size
                let horizontalMargin: CGFloat = 8
                let estimatedPanelHeight: CGFloat = 280

                ZStack(alignment: .topLeading) {
                    if shouldShowSearchResults, let anchorFrame = frame ?? cachedSearchFieldFrame {
                        let maxPanelWidth: CGFloat = min(560, containerSize.width - (horizontalMargin * 2))
                        let desiredWidth: CGFloat = max(240, anchorFrame.width)
                        let panelWidth = max(240, min(desiredWidth, maxPanelWidth))

                        let proposedX = anchorFrame.minX
                        let x = min(max(proposedX, horizontalMargin), max(horizontalMargin, containerSize.width - panelWidth - horizontalMargin))

                        let belowY = anchorFrame.maxY + 8
                        let aboveY = anchorFrame.minY - 8 - estimatedPanelHeight
                        let opensUpward = (belowY + estimatedPanelHeight > containerSize.height) && (aboveY >= 0)
                        let y = opensUpward ? max(8, aboveY) : belowY

                        searchResultsPanel
                            .frame(width: panelWidth, alignment: .leading)
                            .offset(x: x, y: y)
                            .transition(.opacity)
                            .zIndex(1000)
                    }
                }
                .animation(.easeInOut(duration: 0.12), value: shouldShowSearchResults)
            }
        }
        .overlayPreferenceValue(CalendarTopPillFramePreferenceKey.self) { frame in
            ZStack {
                CalendarTopInlineEditorOverlay(
                    anchorFrame: frame,
                    objectID: $topInlineEditorObjectID,
                    isTask: $topInlineEditorIsTask,
                    preferredHeight: $topInlineEditorPreferredHeight
                )

                CalendarTopAddEditOverlay(anchorFrame: frame)
                    .zIndex(2400)
            }
        }
        .overlay {
            ZStack {
                if isCommandPalettePresented {
                    commandPaletteOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(4000)
                }
                if isQuickAddPresented {
                    quickAddOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(4001)
                }
            }
            .animation(.easeInOut(duration: 0.14), value: isCommandPalettePresented)
            .animation(.easeInOut(duration: 0.14), value: isQuickAddPresented)
        }
        .onPreferenceChange(SearchFieldFramePreferenceKey.self) { newFrame in
            if let newFrame {
                cachedSearchFieldFrame = newFrame
            }
        }
        .background(DesignSystem.Colors.bgMain)
        .onAppear { reloadCalendarData() }
        .onChange(of: viewMode) { _, newValue in
            reloadCalendarData()
            if newValue == .month {
                monthKeyboardSelection = Calendar.current.startOfDay(for: displayedMonth)
            }
        }
        .onChange(of: displayedMonth) { _, newValue in
            reloadCalendarData()
            if viewMode == .month {
                monthKeyboardSelection = Calendar.current.startOfDay(for: newValue)
            }
        }
        .onChange(of: selectedSemesterID) { _, _ in reloadCalendarData() }
        .onReceive(coreDataManager.objectWillChange.debounce(for: .milliseconds(75), scheduler: RunLoop.main)) { _ in
            reloadCalendarData()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            courseColorOverrideRevision &+= 1
            if viewMode == .month {
                rebuildDayChips(fromEvents: filteredEvents, tasks: filteredTasks)
            }
        }
        .onChange(of: pillCoordinator.selection) { _, newValue in
            if newValue == nil, topInlineEditorObjectID != nil {
                withAnimation(.easeInOut(duration: 0.14)) {
                    topInlineEditorObjectID = nil
                    topInlineEditorPreferredHeight = 0
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            reloadCalendarData()
        }
    }

    private struct ResizeHandleOverlay: View {
        let currentSize: CGSize
        @Binding var userSize: CGSize?
        let minSize: CGSize
        let maxSize: CGSize

        @State private var dragStartSize: CGSize? = nil

        var body: some View {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.45))
                .padding(8)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                )
                .padding(8)
                .contentShape(Rectangle())
                .help("Resize")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartSize == nil {
                                dragStartSize = userSize ?? currentSize
                            }
                            guard let start = dragStartSize else { return }

                            var newWidth = start.width + value.translation.width
                            var newHeight = start.height + value.translation.height

                            newWidth = min(max(newWidth, minSize.width), maxSize.width)
                            newHeight = min(max(newHeight, minSize.height), maxSize.height)

                            userSize = CGSize(width: newWidth, height: newHeight)
                        }
                        .onEnded { _ in
                            dragStartSize = nil
                        }
                )
        }
    }

    private struct CalendarTopInlineEditorOverlay: View {
        @EnvironmentObject private var coreDataManager: CoreDataManager

        let anchorFrame: CGRect?
        @Binding var objectID: NSManagedObjectID?
        @Binding var isTask: Bool
        @Binding var preferredHeight: CGFloat

        @State private var userSize: CGSize? = nil

        private var isPresentedBinding: Binding<Bool> {
            Binding(
                get: { objectID != nil },
                set: { presented in
                    if !presented {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            objectID = nil
                            preferredHeight = 0
                        }
                    }
                }
            )
        }

        var body: some View {
            GeometryReader { proxy in
                let containerSize = proxy.size
                let horizontalMargin: CGFloat = 12
                let verticalMargin: CGFloat = 10
                let desiredPanelWidth: CGFloat = 490
                let desiredPanelHeight: CGFloat = 720
                let gap: CGFloat = 10

                let maxAllowedWidth = max(0, containerSize.width - (horizontalMargin * 2))
                let maxAllowedHeight = max(0, containerSize.height - (verticalMargin * 2))

                ZStack(alignment: .topLeading) {
                    if objectID != nil {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.14)) {
                                    objectID = nil
                                    preferredHeight = 0
                                }
                            }
                            .zIndex(2500)
                    }

                    if let anchorFrame,
                       let objectID {
                        let panelWidth = max(420, min(userSize?.width ?? desiredPanelWidth, maxAllowedWidth))
                        let baseHeight = userSize?.height ?? (preferredHeight > 0 ? preferredHeight : desiredPanelHeight)
                        let effectivePanelHeight = min(maxAllowedHeight, max(360, baseHeight))

                        let proposedX = anchorFrame.midX - (panelWidth / 2)
                        let x = min(
                            max(horizontalMargin, proposedX),
                            max(horizontalMargin, containerSize.width - panelWidth - horizontalMargin)
                        )

                        let proposedY = anchorFrame.maxY + gap
                        let y = min(
                            max(verticalMargin, proposedY),
                            max(verticalMargin, containerSize.height - effectivePanelHeight - verticalMargin)
                        )

                        topInlineEditorPanel(objectID: objectID)
                            .frame(width: panelWidth, height: effectivePanelHeight)
                            .overlay(alignment: .bottomTrailing) {
                                ResizeHandleOverlay(
                                    currentSize: CGSize(width: panelWidth, height: effectivePanelHeight),
                                    userSize: $userSize,
                                    minSize: CGSize(width: 420, height: 360),
                                    maxSize: CGSize(width: maxAllowedWidth, height: maxAllowedHeight)
                                )
                            }
                            .offset(x: x, y: y)
                            .transition(.opacity)
                            .zIndex(2600)
                            .animation(.easeInOut(duration: 0.18), value: effectivePanelHeight)
                            .animation(.easeInOut(duration: 0.18), value: y)
                    }
                }
                .animation(.easeInOut(duration: 0.14), value: objectID != nil)
            }
        }

        private func topInlineEditorPanel(objectID: NSManagedObjectID) -> AnyView {
            if isTask {
                let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity
                guard let task else { return AnyView(EmptyView()) }
                return AnyView(
                    AddTaskOverlay(
                        isPresented: isPresentedBinding,
                        semester: task.semester,
                        taskToEdit: task,
                        presentationStyle: .anchoredPanel
                    )
                    .onPreferenceChange(AddTaskOverlayPreferredHeightKey.self) { height in
                        guard height > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            preferredHeight = height
                        }
                    }
                )
            } else {
                let event = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity
                guard let event else { return AnyView(EmptyView()) }
                return AnyView(
                    AddCalendarItemOverlay(
                        isPresented: isPresentedBinding,
                        semester: event.semester,
                        initialStartDateTime: event.startDate,
                        initialEndDateTime: event.endDate,
                        eventToEdit: event,
                        presentationStyle: .anchoredPanel
                    )
                    .onPreferenceChange(AddCalendarItemOverlayPreferredHeightKey.self) { height in
                        guard height > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            preferredHeight = height
                        }
                    }
                )
            }
        }
    }

    private struct CalendarTopAddEditOverlay: View {
        @EnvironmentObject private var coreDataManager: CoreDataManager
        @EnvironmentObject private var modalCoordinator: ModalCoordinator
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        let anchorFrame: CGRect?

        @State private var preferredHeight: CGFloat = 0
        @State private var userSize: CGSize? = nil

        private var isPresented: Bool {
            switch modalCoordinator.activeModal {
            case .addCalendarItem, .editCalendarItem:
                return true
            default:
                return false
            }
        }

        private var isPresentedBinding: Binding<Bool> {
            Binding(
                get: { isPresented },
                set: { presented in
                    if !presented {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
                            modalCoordinator.activeModal = nil
                            preferredHeight = 0
                        }
                    }
                }
            )
        }

        var body: some View {
            GeometryReader { proxy in
                let containerSize = proxy.size
                let horizontalMargin: CGFloat = 12
                let verticalMargin: CGFloat = 10
                let desiredPanelWidth: CGFloat = 400
                let desiredPanelHeight: CGFloat = 560
                let minPanelHeight: CGFloat = 240
                let gap: CGFloat = 10

                let maxAllowedWidth = max(0, containerSize.width - (horizontalMargin * 2))
                let maxAllowedHeight = max(0, containerSize.height - (verticalMargin * 2))

                ZStack(alignment: .topLeading) {
                    if isPresented, let anchorFrame {
                        let startY = max(0, anchorFrame.maxY)

                        Color.black.opacity(0.001)
                            .frame(width: containerSize.width, height: max(0, containerSize.height - startY))
                            .offset(x: 0, y: startY)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
                                    modalCoordinator.activeModal = nil
                                    preferredHeight = 0
                                }
                            }
                            .zIndex(2500)
                    }

                    if isPresented, let anchorFrame {
                        let panelWidth = max(420, min(userSize?.width ?? desiredPanelWidth, maxAllowedWidth))
                        let baseHeight = userSize?.height ?? (preferredHeight > 0 ? preferredHeight : desiredPanelHeight)
                        let effectivePanelHeight = min(maxAllowedHeight, max(minPanelHeight, baseHeight))

                        // Right-side panel: keep it pinned to the window's right edge.
                        let x = max(horizontalMargin, containerSize.width - panelWidth - horizontalMargin)

                        let proposedY = anchorFrame.maxY + gap
                        let y = min(
                            max(verticalMargin, proposedY),
                            max(verticalMargin, containerSize.height - effectivePanelHeight - verticalMargin)
                        )

                        panel
                            .frame(width: panelWidth, height: effectivePanelHeight)
                            .offset(x: x, y: y)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(2600)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: effectivePanelHeight)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: y)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isPresented)
            }
        }

        @ViewBuilder
        private var panel: some View {
            switch modalCoordinator.activeModal {
            case .addCalendarItem(let semesterID, let initialTitle, let initialStart, let initialEnd):
                AddCalendarItemOverlay(
                    isPresented: isPresentedBinding,
                    semester: {
                        guard let semesterID else { return nil }
                        return coreDataManager.semesters.first(where: { $0.id == semesterID })
                    }(),
                    initialTitle: initialTitle,
                    initialStartDateTime: initialStart,
                    initialEndDateTime: initialEnd,
                    eventToEdit: nil,
                    presentationStyle: .floatingCards
                )
                .onPreferenceChange(AddCalendarItemOverlayPreferredHeightKey.self) { height in
                    guard height > 0 else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        preferredHeight = height
                    }
                }

            case .editCalendarItem(let objectID):
                let event = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity
                if let event {
                    AddCalendarItemOverlay(
                        isPresented: isPresentedBinding,
                        semester: event.semester,
                        initialStartDateTime: event.startDate,
                        initialEndDateTime: event.endDate,
                        eventToEdit: event,
                        presentationStyle: .floatingCards
                    )
                    .onPreferenceChange(AddCalendarItemOverlayPreferredHeightKey.self) { height in
                        guard height > 0 else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            preferredHeight = height
                        }
                    }
                } else {
                    EmptyView()
                }

            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 0) {
            calendarTopBar
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: CalendarTopPillFramePreferenceKey.self,
                                value: proxy.frame(in: .named("CalendarMainContent"))
                            )
                    }
                )
                .padding(.bottom, 6)

            if !focusItems.isEmpty {
                focusStrip
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var calendarBody: some View {
        ZStack {
            switch viewMode {
            case .month:
                monthView
            case .week:
                weekView
            case .day:
                dayView
            case .agenda:
                agendaView
            }
        }
        .id(viewMode)
        .transition(.opacity.combined(with: .scale(scale: 0.99)))
    }

    private var monthView: some View {
        ZStack {
            monthGrid
                .id(monthTransitionKey(for: displayedMonth))
                .transition(monthGridTransition)
        }
    }

    private var weekView: some View {
        WeekScheduleView(
            viewContext: coreDataManager.viewContext,
            anchorDate: displayedMonth,
            semester: selectedSemester(),
            events: filteredEvents,
            tasks: filteredTasks,
            isKeyboardCaptureEnabled: !isSearchFieldFocused,
            onMoveEvent: { id, start, end in
                coreDataManager.updateCalendarEventTimes(objectID: id, startDate: start, endDate: end)
                if let event = (try? coreDataManager.viewContext.existingObject(with: id)) as? CalendarEventEntity {
                    // Never block the UI/drag interaction on sync work.
                    Task.detached(priority: .utility) { [calendarManager] in
                        calendarManager.exportEventToGoogle(event)
                    }
                }
            },
            onCreateEvent: { start, end in
                pillCoordinator.clearSelection(animated: !reduceMotion)
                pillCoordinator.suppressOutsideDismissOnce()
                modalCoordinator.activeModal = .addCalendarItem(
                    semesterID: selectedSemesterID,
                    initialTitle: nil,
                    initialStart: start,
                    initialEnd: end
                )
            },
            onEditEvent: { objectID in
                pillCoordinator.selectEvent(objectID: objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
            },
            onEditEventFromOverflow: { objectID in
                modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
            },
            onDeleteEvent: { objectID in
                let eventTitle: String
                if let event = try? coreDataManager.viewContext.existingObject(with: objectID) as? CalendarEventEntity {
                    eventTitle = event.title ?? "Event"
                    if let uuid = event.id {
                        Task.detached(priority: .utility) { [calendarManager] in
                            calendarManager.deleteEventFromGoogle(localEventID: uuid)
                        }
                    }
                } else {
                    eventTitle = "Event"
                }
                coreDataManager.deleteCalendarEvent(objectID: objectID)

                AppNotificationCenter.shared.post(
                    kind: .info,
                    title: "Event Deleted",
                    message: "\(eventTitle) removed from calendar",
                    autoDismissAfter: 3
                )
            },
            onDuplicateEvent: { objectID in
                duplicateCalendarEvent(objectID: objectID)
            },
            onMoveTaskDueDate: { objectID, newDueDate in
                guard let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity else {
                    return
                }
                coreDataManager.updateTask(
                    objectID: objectID,
                    title: task.title ?? "Task",
                    dueDate: newDueDate,
                    semester: task.semester,
                    course: task.course,
                    notes: task.notes,
                    priority: task.priority
                )
            },
            onEditTask: { objectID in
                pillCoordinator.selectTask(objectID: objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
            },
            onDeleteTask: { objectID in
                coreDataManager.deleteTask(objectID: objectID)
            }
        )
    }

    private var dayView: some View {
        DayScheduleView(
            viewContext: coreDataManager.viewContext,
            date: displayedMonth,
            semester: selectedSemester(),
            events: filteredEvents,
            tasks: filteredTasks,
            isKeyboardCaptureEnabled: !isSearchFieldFocused,
            onMoveEvent: { id, start, end in
                coreDataManager.updateCalendarEventTimes(objectID: id, startDate: start, endDate: end)
                if let event = (try? coreDataManager.viewContext.existingObject(with: id)) as? CalendarEventEntity {
                    // Never block the UI/drag interaction on sync work.
                    Task.detached(priority: .utility) { [calendarManager] in
                        calendarManager.exportEventToGoogle(event)
                    }
                }
            },
            onCreateEvent: { start, end in
                pillCoordinator.clearSelection(animated: !reduceMotion)
                pillCoordinator.suppressOutsideDismissOnce()
                modalCoordinator.activeModal = .addCalendarItem(
                    semesterID: selectedSemesterID,
                    initialTitle: nil,
                    initialStart: start,
                    initialEnd: end
                )
            },
            onEditEvent: { objectID in
                pillCoordinator.selectEvent(objectID: objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
            },
            onEditEventFromOverflow: { objectID in
                modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
            },
            onDeleteEvent: { objectID in
                let eventTitle: String
                if let event = try? coreDataManager.viewContext.existingObject(with: objectID) as? CalendarEventEntity {
                    eventTitle = event.title ?? "Event"
                    if let uuid = event.id {
                        Task.detached(priority: .utility) { [calendarManager] in
                            calendarManager.deleteEventFromGoogle(localEventID: uuid)
                        }
                    }
                } else {
                    eventTitle = "Event"
                }
                coreDataManager.deleteCalendarEvent(objectID: objectID)

                AppNotificationCenter.shared.post(
                    kind: .info,
                    title: "Event Deleted",
                    message: "\(eventTitle) removed from calendar",
                    autoDismissAfter: 3
                )
            },
            onDuplicateEvent: { objectID in
                duplicateCalendarEvent(objectID: objectID)
            },
            onMoveTaskDueDate: { objectID, newDueDate in
                guard let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity else {
                    return
                }
                coreDataManager.updateTask(
                    objectID: objectID,
                    title: task.title ?? "Task",
                    dueDate: newDueDate,
                    semester: task.semester,
                    course: task.course,
                    notes: task.notes,
                    priority: task.priority
                )
            },
            onEditTask: { objectID in
                pillCoordinator.selectTask(objectID: objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
            },
            onDeleteTask: { objectID in
                coreDataManager.deleteTask(objectID: objectID)
            }
        )
    }

    private var agendaView: some View {
        agendaList
    }

    private var anchoredEditorsOverlay: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let panelHorizontalMargin: CGFloat = 10
            let panelVerticalMargin: CGFloat = 10
            let desiredPanelWidth: CGFloat = 430
            let desiredPanelHeight: CGFloat = 680
            let gap: CGFloat = 14

            let maxAllowedWidth = max(0, containerSize.width - (panelHorizontalMargin * 2))
            let maxAllowedHeight = max(0, containerSize.height - (panelVerticalMargin * 2))

            ZStack(alignment: .topLeading) {
                if anchoredEditorObjectID != nil || anchoredTaskEditorObjectID != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                anchoredEditorObjectID = nil
                                anchoredEditorAnchorURL = nil
                                cachedAnchoredEditorFrame = nil

                                anchoredTaskEditorObjectID = nil
                                anchoredTaskEditorAnchorURL = nil
                                cachedAnchoredTaskEditorFrame = nil
                            }
                        }
                        .zIndex(1000)
                }

                if let objectID = anchoredEditorObjectID,
                   let anchorURL = anchoredEditorAnchorURL,
                   let anchorFrame = calendarItemFrameCache.frames[anchorURL] ?? cachedAnchoredEditorFrame,
                   let event = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity {

                    let panelWidth = max(420, min(anchoredEditorUserSize?.width ?? desiredPanelWidth, maxAllowedWidth))
                    let baseHeight = anchoredEditorUserSize?.height ?? (anchoredEditorPreferredHeight > 0 ? anchoredEditorPreferredHeight : desiredPanelHeight)
                    let effectivePanelHeight = min(maxAllowedHeight, max(360, baseHeight))

                    let openRight = (anchorFrame.maxX + gap + panelWidth) <= (containerSize.width - panelHorizontalMargin)
                    let proposedX = openRight ? (anchorFrame.maxX + gap) : (anchorFrame.minX - gap - panelWidth)
                    let x = min(
                        max(panelHorizontalMargin, proposedX),
                        max(panelHorizontalMargin, containerSize.width - panelWidth - panelHorizontalMargin)
                    )

                    let proposedY = anchorFrame.minY
                    let y = min(
                        max(panelVerticalMargin, proposedY),
                        max(panelVerticalMargin, containerSize.height - effectivePanelHeight - panelVerticalMargin)
                    )

                    AddCalendarItemOverlay(
                        isPresented: Binding(
                            get: { anchoredEditorObjectID != nil },
                            set: { isPresented in
                                if !isPresented {
                                    anchoredEditorObjectID = nil
                                    anchoredEditorAnchorURL = nil
                                    cachedAnchoredEditorFrame = nil
                                }
                            }
                        ),
                        semester: event.semester,
                        initialStartDateTime: event.startDate,
                        initialEndDateTime: event.endDate,
                        eventToEdit: event,
                        presentationStyle: .anchoredPanel
                    )
                    .onPreferenceChange(AddCalendarItemOverlayPreferredHeightKey.self) { height in
                        guard height > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            anchoredEditorPreferredHeight = height
                        }
                    }
                    .frame(width: panelWidth, height: effectivePanelHeight)
                    .overlay(alignment: .bottomTrailing) {
                        ResizeHandleOverlay(
                            currentSize: CGSize(width: panelWidth, height: effectivePanelHeight),
                            userSize: $anchoredEditorUserSize,
                            minSize: CGSize(width: 420, height: 360),
                            maxSize: CGSize(width: maxAllowedWidth, height: maxAllowedHeight)
                        )
                    }
                    .offset(x: x, y: y)
                    .zIndex(1100)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .animation(.easeInOut(duration: 0.18), value: effectivePanelHeight)
                    .animation(.easeInOut(duration: 0.18), value: y)
                }

                if let objectID = anchoredTaskEditorObjectID,
                   let anchorURL = anchoredTaskEditorAnchorURL,
                   let anchorFrame = calendarItemFrameCache.frames[anchorURL] ?? cachedAnchoredTaskEditorFrame,
                   let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity {

                    let panelWidth = max(420, min(anchoredTaskEditorUserSize?.width ?? desiredPanelWidth, maxAllowedWidth))
                    let baseHeight = anchoredTaskEditorUserSize?.height ?? (anchoredTaskEditorPreferredHeight > 0 ? anchoredTaskEditorPreferredHeight : desiredPanelHeight)
                    let effectivePanelHeight = min(maxAllowedHeight, max(320, baseHeight))

                    let openRight = (anchorFrame.maxX + gap + panelWidth) <= (containerSize.width - panelHorizontalMargin)
                    let proposedX = openRight ? (anchorFrame.maxX + gap) : (anchorFrame.minX - gap - panelWidth)
                    let x = min(
                        max(panelHorizontalMargin, proposedX),
                        max(panelHorizontalMargin, containerSize.width - panelWidth - panelHorizontalMargin)
                    )

                    let proposedY = anchorFrame.minY
                    let y = min(
                        max(panelVerticalMargin, proposedY),
                        max(panelVerticalMargin, containerSize.height - effectivePanelHeight - panelVerticalMargin)
                    )

                    AddTaskOverlay(
                        isPresented: Binding(
                            get: { anchoredTaskEditorObjectID != nil },
                            set: { isPresented in
                                if !isPresented {
                                    anchoredTaskEditorObjectID = nil
                                    anchoredTaskEditorAnchorURL = nil
                                    cachedAnchoredTaskEditorFrame = nil
                                }
                            }
                        ),
                        semester: task.semester,
                        taskToEdit: task,
                        presentationStyle: .anchoredPanel
                    )
                    .onPreferenceChange(AddTaskOverlayPreferredHeightKey.self) { height in
                        guard height > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            anchoredTaskEditorPreferredHeight = height
                        }
                    }
                    .frame(width: panelWidth, height: effectivePanelHeight)
                    .overlay(alignment: .bottomTrailing) {
                        ResizeHandleOverlay(
                            currentSize: CGSize(width: panelWidth, height: effectivePanelHeight),
                            userSize: $anchoredTaskEditorUserSize,
                            minSize: CGSize(width: 420, height: 320),
                            maxSize: CGSize(width: maxAllowedWidth, height: maxAllowedHeight)
                        )
                    }
                    .offset(x: x, y: y)
                    .zIndex(1100)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .animation(.easeInOut(duration: 0.18), value: effectivePanelHeight)
                    .animation(.easeInOut(duration: 0.18), value: y)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: anchoredEditorObjectID != nil)
            .animation(.easeInOut(duration: 0.12), value: anchoredTaskEditorObjectID != nil)
        }
    }

    private var calendarTopBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(topBarTitle)
                    .font(DesignSystem.Fonts.main(size: 19, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.65)
                    .layoutPriority(2)

                HStack(spacing: 6) {
                    Button(action: { moveAnchor(-1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: headerControlSize, height: headerControlSize)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(previousPeriodAccessibilityLabel)
                    .help(previousPeriodAccessibilityLabel)

                    Button(action: { moveAnchor(1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: headerControlSize, height: headerControlSize)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(nextPeriodAccessibilityLabel)
                    .help(nextPeriodAccessibilityLabel)
                }
            }

            Spacer(minLength: 8)

            searchBox

            CalendarViewModeSwitcher(selection: $viewMode)
                .frame(minWidth: 240)
                .layoutPriority(1)

            Button(action: { navigateToToday() }) {
                Label("Today", systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("t", modifiers: [.command])
            .accessibilityLabel("View today")

            Button(action: onAddItem) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Create new event")

            calendarSourcesMenu

            Button(action: { isShowingAddHelpPopover.toggle() }) {
                Image(systemName: "questionmark.circle")
                    .frame(width: headerControlSize, height: headerControlSize)
            }
            .buttonStyle(.borderless)
            .help("How to add events")
            .accessibilityLabel("Help")
            .popover(isPresented: $isShowingAddHelpPopover, arrowEdge: .top) {
                addHelpPopover
                    .padding(14)
                    .frame(width: 320)
            }
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.vertical, headerVerticalPadding)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1),
            alignment: .bottom
        )
        .overlay(calendarKeyboardShortcuts)
    }

    private var addHelpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adding events")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Text("Quick ways to create events:")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text("⌘N")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(width: 44, alignment: .leading)
                    Text("Open the Add Event form")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                }

                if viewMode == .month {
                    HStack(alignment: .top, spacing: 10) {
                        Text("Click")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .frame(width: 44, alignment: .leading)
                        Text("Click an empty day to create a 9–10am event")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                } else if viewMode == .week || viewMode == .day {
                    HStack(alignment: .top, spacing: 10) {
                        Text("Click")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .frame(width: 44, alignment: .leading)
                        Text("Click an empty time slot to create a 1-hour event")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Text("Drag")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                            .frame(width: 44, alignment: .leading)
                        Text("Click + drag to select a time range")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                }
            }
        }
        .background(DesignSystem.Colors.surface)
    }

    private var searchBox: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = isSearchFieldFocused || !trimmed.isEmpty

        return searchInputRow
            .frame(minWidth: isExpanded ? 260 : 200, maxWidth: isExpanded ? 420 : 260)
            .animation(.easeInOut(duration: 0.18), value: isExpanded)
            .zIndex(10)
    }

    private var searchInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)

            TextField("Search", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(minWidth: 120)
                .focused($isSearchFieldFocused)
                .accessibilityLabel("Search calendar")

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SearchFieldFramePreferenceKey.self, value: proxy.frame(in: .named("CalendarMainContent")))
            }
        )
    }

    private var calendarSourcesMenu: some View {
        Menu {
            let appleCalendars = calendarManager.connectedCalendars.filter { $0.source == "Apple" }
            let googleCalendars = calendarManager.connectedCalendars.filter { $0.source == "Google" }

            Section("iCloud") {
                ForEach(appleCalendars) { calendar in
                    Button {
                        calendarManager.toggleCalendarEnabled(calendar)
                    } label: {
                        Label(calendar.name, systemImage: calendarManager.isCalendarEnabled(calendar) ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Section("Google") {
                if googleCalendars.isEmpty {
                    Text("No Google calendars").foregroundColor(.secondary)
                } else {
                    ForEach(googleCalendars) { calendar in
                        Button {
                            calendarManager.toggleCalendarEnabled(calendar)
                        } label: {
                            Label(calendar.name, systemImage: calendarManager.isCalendarEnabled(calendar) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }
        } label: {
            let enabledCalendars = calendarManager.connectedCalendars.filter { calendarManager.isCalendarEnabled($0) }

            Label("\(enabledCalendars.count) Calendars", systemImage: "dot.radiowaves.left.and.right")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Calendar sources")
    }

    private struct FocusCard: View {
        let item: FocusItem
        let width: CGFloat
        let height: CGFloat
        let onJump: () -> Void
        let onPrimaryAction: () -> Void
        let onSecondaryAction: (() -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.title)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Button(action: onJump) {
                        Label("Jump", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.borderless)

                    Button(action: onPrimaryAction) {
                        Label("Open", systemImage: item.kind == .event ? "pencil" : "square.and.pencil")
                    }
                    .buttonStyle(.borderless)

                    if let onSecondaryAction {
                        Button(action: onSecondaryAction) {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: width, height: height, alignment: .leading)
            .background(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
            .cornerRadius(12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onJump)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.title)
            .accessibilityHint("Jump to date")
        }
    }

    private var searchResultsPanel: some View {
        let results = activeSearchResults

        return VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text("No results")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { item in
                            let url = item.id.uriRepresentation()
                            let isHovered = hoveredSearchResultURL == url
                            Button(action: { handleSearchResultTap(item) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: item.kind == .event ? "calendar" : "checklist")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(DesignSystem.Colors.textLight)

                                        Text(item.title)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textMain)
                                            .lineLimit(2)

                                        Spacer(minLength: 0)
                                    }

                                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignSystem.Colors.surface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isHovered ? DesignSystem.Colors.textLight.opacity(0.30) : Color.clear, lineWidth: isHovered ? 1.25 : 1)
                                )
                                .offset(y: isHovered ? -2 : 0)
                                .scaleEffect(isHovered ? 1.01 : 1)
                                .animation(.spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onHover { hovering in
                                if hovering {
                                    hoveredSearchResultURL = url
                                } else if hoveredSearchResultURL == url {
                                    hoveredSearchResultURL = nil
                                }
                            }

                            Rectangle()
                                .fill(Color(hex: "f1f5f9"))
                                .frame(height: 1)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10)
    }

    private var activeSearchResults: [CalendarSearchResult] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        func dateText(_ date: Date) -> String {
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            return df.string(from: date)
        }

        let eventResults: [CalendarSearchResult] = searchEventResults
            .filter { calendarManager.shouldDisplayEvent($0) }
            .compactMap { ev in
                guard let start = ev.startDate else { return nil }
                let title = (ev.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
                let courseText = (ev.course?.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitleParts = [courseText.isEmpty ? nil : courseText, dateText(start)].compactMap { $0 }
                return CalendarSearchResult(
                    kind: .event,
                    id: ev.objectID,
                    title: title.isEmpty ? "Event" : title,
                    subtitle: subtitleParts.joined(separator: " • "),
                    date: start
                )
            }

        let taskResults: [CalendarSearchResult] = searchTaskResults
            .compactMap { t in
                guard let due = t.dueDate else { return nil }
                let title = t.title ?? "Task"
                let courseText = (t.course?.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitleParts = [courseText.isEmpty ? nil : courseText, "Due \(dateText(due))"].compactMap { $0 }
                return CalendarSearchResult(
                    kind: .task,
                    id: t.objectID,
                    title: title,
                    subtitle: subtitleParts.joined(separator: " • "),
                    date: due
                )
            }

        return (eventResults + taskResults)
            .sorted { $0.date < $1.date }
            .prefix(10)
            .map { $0 }
    }

    private func handleSearchResultTap(_ result: CalendarSearchResult) {
        displayedMonth = result.date
        monthKeyboardSelection = Calendar.current.startOfDay(for: result.date)

        switch result.kind {
        case .event:
            presentAnchoredEditor(objectID: result.id)
        case .task:
            presentAnchoredTaskEditor(objectID: result.id)
        }
    }

    private func presentAnchoredEditor(objectID: NSManagedObjectID) {
        let url = objectID.uriRepresentation()
        anchoredTaskEditorObjectID = nil
        anchoredTaskEditorAnchorURL = nil
        cachedAnchoredTaskEditorFrame = nil

        anchoredEditorObjectID = objectID
        anchoredEditorAnchorURL = url

        if let frame = calendarItemFrameCache.frames[url] {
            cachedAnchoredEditorFrame = frame
        } else {
            // Fallback (e.g. month overflow popover) where we can't reliably anchor.
            modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
        }
    }

    private func presentAnchoredTaskEditor(objectID: NSManagedObjectID) {
        let url = objectID.uriRepresentation()
        anchoredEditorObjectID = nil
        anchoredEditorAnchorURL = nil
        cachedAnchoredEditorFrame = nil

        anchoredTaskEditorObjectID = objectID
        anchoredTaskEditorAnchorURL = url
        if let frame = calendarItemFrameCache.frames[url] {
            cachedAnchoredTaskEditorFrame = frame
        } else {
            // Fallback (e.g. month overflow popover) where we can't reliably anchor.
            modalCoordinator.activeModal = .editTask(objectID: objectID)
        }
    }

    private enum CommandPaletteItemKind {
        case command
        case event
        case task
        case course
    }

    private struct CommandPaletteItem: Identifiable {
        let kind: CommandPaletteItemKind
        let id: String
        let title: String
        let subtitle: String?
        let icon: String
        let perform: () -> Void
    }

    private func openCommandPalette(prefill: String = "") {
        commandPaletteQuery = prefill
        isCommandPalettePresented = true
        isQuickAddPresented = false
        isCommandPaletteFieldFocused = true
    }

    private func openQuickAdd(prefill: String = "") {
        quickAddText = prefill
        isQuickAddPresented = true
        isCommandPalettePresented = false
        isQuickAddFieldFocused = true
    }

    private func dismissPalettes() {
        isCommandPalettePresented = false
        isQuickAddPresented = false
        isCommandPaletteFieldFocused = false
        isQuickAddFieldFocused = false
    }

    private func defaultStartEndForCurrentContext() -> (start: Date, end: Date) {
        let cal = Calendar.current
        switch viewMode {
        case .month:
            let day = cal.startOfDay(for: monthKeyboardSelection)
            let start = cal.date(byAdding: .hour, value: 9, to: day) ?? day
            let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start
            return (start, end)
        case .week, .day, .agenda:
            let day = cal.startOfDay(for: displayedMonth)
            let start = cal.date(byAdding: .hour, value: 9, to: day) ?? day
            let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start
            return (start, end)
        }
    }

    private var commandPaletteItems: [CommandPaletteItem] {
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = query.lowercased()

        func matches(_ text: String) -> Bool {
            if lower.isEmpty { return true }
            return text.lowercased().contains(lower)
        }

        var items: [CommandPaletteItem] = []

        items.append(
            CommandPaletteItem(
                kind: .command,
                id: "cmd.today",
                title: "Go to Today",
                subtitle: "Jump to today",
                icon: "calendar.badge.clock",
                perform: {
                    displayedMonth = Date()
                    monthKeyboardSelection = Calendar.current.startOfDay(for: displayedMonth)
                    dismissPalettes()
                }
            )
        )

        items.append(
            CommandPaletteItem(
                kind: .command,
                id: "cmd.addEvent",
                title: "Create Event…",
                subtitle: "Open Add Event",
                icon: "plus",
                perform: {
                    let (start, end) = defaultStartEndForCurrentContext()
                    pillCoordinator.presentAddEvent(
                        prefill: .init(semesterID: selectedSemesterID, title: nil, start: start, end: end),
                        animated: !reduceMotion
                    )
                    dismissPalettes()
                }
            )
        )

        items.append(
            CommandPaletteItem(
                kind: .command,
                id: "cmd.quickAdd",
                title: "Quick Add…",
                subtitle: "Natural language input",
                icon: "sparkles",
                perform: {
                    dismissPalettes()
                    openQuickAdd()
                }
            )
        )

        items.append(
            CommandPaletteItem(
                kind: .command,
                id: "cmd.search",
                title: "Focus Search",
                subtitle: "Search events and tasks",
                icon: "magnifyingglass",
                perform: {
                    dismissPalettes()
                    isSearchFieldFocused = true
                }
            )
        )

        items.append(contentsOf: [
            CommandPaletteItem(kind: .command, id: "cmd.view.day", title: "Switch to Day", subtitle: nil, icon: "rectangle.split.3x1") { viewMode = .day; dismissPalettes() },
            CommandPaletteItem(kind: .command, id: "cmd.view.week", title: "Switch to Week", subtitle: nil, icon: "rectangle.split.3x1") { viewMode = .week; dismissPalettes() },
            CommandPaletteItem(kind: .command, id: "cmd.view.month", title: "Switch to Month", subtitle: nil, icon: "square.grid.3x2") { viewMode = .month; dismissPalettes() },
            CommandPaletteItem(kind: .command, id: "cmd.view.agenda", title: "Switch to Agenda", subtitle: nil, icon: "list.bullet") { viewMode = .agenda; dismissPalettes() }
        ])

        if !lower.isEmpty {
            items = items.filter { matches($0.title) || ($0.subtitle.map(matches) ?? false) }
        }

        if !lower.isEmpty {
            func dateText(_ date: Date) -> String {
                let df = DateFormatter()
                df.dateFormat = "MMM d, h:mm a"
                return df.string(from: date)
            }

            let eventHits = filteredEvents
                .filter { matches(($0.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)) }
                .prefix(8)
                .map { ev in
                    let start = ev.startDate
                    let subtitle = start.map { dateText($0) }
                    return CommandPaletteItem(
                        kind: .event,
                        id: "event.\(ev.objectID.uriRepresentation().absoluteString)",
                        title: (ev.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines),
                        subtitle: subtitle,
                        icon: "calendar",
                        perform: {
                            displayedMonth = ev.startDate ?? displayedMonth
                            presentAnchoredEditor(objectID: ev.objectID)
                            dismissPalettes()
                        }
                    )
                }

            let taskHits = filteredTasks
                .filter { matches(($0.title ?? "Task").trimmingCharacters(in: .whitespacesAndNewlines)) }
                .prefix(8)
                .map { task in
                    let due = task.dueDate
                    let subtitle = due.map { "Due \(dateText($0))" }
                    return CommandPaletteItem(
                        kind: .task,
                        id: "task.\(task.objectID.uriRepresentation().absoluteString)",
                        title: (task.title ?? "Task").trimmingCharacters(in: .whitespacesAndNewlines),
                        subtitle: subtitle,
                        icon: "checklist",
                        perform: {
                            if let due { displayedMonth = due }
                            presentAnchoredTaskEditor(objectID: task.objectID)
                            dismissPalettes()
                        }
                    )
                }

            let courseHits: [CommandPaletteItem] = (selectedSemester()?.coursesArray ?? [])
                .filter { course in
                    let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return matches(code) || matches(name)
                }
                .prefix(8)
                .map { course in
                    let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = code.isEmpty ? (name.isEmpty ? "Course" : name) : code
                    let subtitle = code.isEmpty ? nil : (name.isEmpty ? nil : name)
                    return CommandPaletteItem(
                        kind: .course,
                        id: "course.\(course.objectID.uriRepresentation().absoluteString)",
                        title: title,
                        subtitle: subtitle,
                        icon: "book",
                        perform: {
                            modalCoordinator.activeModal = .editCourse(
                                ModalCoordinator.CourseEditSelection(
                                    courseCode: code,
                                    defaultCourseName: name,
                                    defaultCreditsText: String(course.creditsInt)
                                )
                            )
                            dismissPalettes()
                        }
                    )
                }

            // Keep commands first, then results.
            items.append(contentsOf: eventHits)
            items.append(contentsOf: taskHits)
            items.append(contentsOf: courseHits)
        }

        return items
    }

    private var commandPaletteOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .ignoresSafeArea()
                .onTapGesture { dismissPalettes() }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    TextField("Search commands, events, tasks, courses", text: $commandPaletteQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .focused($isCommandPaletteFieldFocused)

                    if !commandPaletteQuery.isEmpty {
                        Button(action: { commandPaletteQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "f8fafc"))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commandPaletteItems) { item in
                            Button(action: item.perform) {
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textMain)
                                            .lineLimit(1)
                                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                .foregroundColor(DesignSystem.Colors.textLight)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Rectangle()
                                .fill(Color(hex: "f1f5f9"))
                                .frame(height: 1)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .padding(14)
            .frame(width: 560)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 18)
            .onAppear { isCommandPaletteFieldFocused = true }
            .onExitCommand { dismissPalettes() }
        }
    }

    private func submitQuickAdd() {
        let raw = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { dismissPalettes(); return }

        let parsed = CalendarQuickAddParser.parse(raw, referenceDate: Date())
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)

        let startEnd: (Date, Date) = {
            if let s = parsed.start, let e = parsed.end {
                return (s, e)
            }
            return defaultStartEndForCurrentContext()
        }()

        pillCoordinator.presentAddEvent(
            prefill: .init(
                semesterID: selectedSemesterID,
                title: title.isEmpty ? raw : title,
                start: startEnd.0,
                end: startEnd.1
            ),
            animated: !reduceMotion
        )
        dismissPalettes()
    }

    private var quickAddOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.20))
                .ignoresSafeArea()
                .onTapGesture { dismissPalettes() }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Add")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                TextField("e.g., Lunch tomorrow 1pm", text: $quickAddText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(DesignSystem.Fonts.main(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .focused($isQuickAddFieldFocused)
                    .onSubmit { submitQuickAdd() }

                Text("Press Return to open Add Event with the parsed time.")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                HStack(spacing: 10) {
                    Button("Cancel") { dismissPalettes() }
                        .buttonStyle(PlainButtonStyle())
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    Spacer(minLength: 0)

                    Button("Continue") { submitQuickAdd() }
                        .buttonStyle(PlainButtonStyle())
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.primary)
                        .cornerRadius(10)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 520)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 18)
            .onAppear { isQuickAddFieldFocused = true }
            .onExitCommand { dismissPalettes() }
        }
    }

    private var calendarKeyboardShortcuts: some View {
        Group {
            if !isSearchFieldFocused {
                Button("", action: { handleArrowKey(deltaDays: -1) })
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("", action: { handleArrowKey(deltaDays: 1) })
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("", action: { handleArrowKey(deltaDays: -7) })
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("", action: { handleArrowKey(deltaDays: 7) })
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button("", action: { performPrimaryKeyboardAction() })
                    .keyboardShortcut(.return, modifiers: [])
                Button("", action: { performPrimaryKeyboardAction() })
                    .keyboardShortcut("n", modifiers: [])
            }

            Button("", action: { moveAnchor(-1) })
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("", action: { moveAnchor(1) })
                .keyboardShortcut(.rightArrow, modifiers: [.command])

            Button("", action: { viewMode = .month })
                .keyboardShortcut("1", modifiers: [.command])
            Button("", action: { viewMode = .week })
                .keyboardShortcut("2", modifiers: [.command])
            Button("", action: { viewMode = .day })
                .keyboardShortcut("3", modifiers: [.command])
            Button("", action: { viewMode = .agenda })
                .keyboardShortcut("4", modifiers: [.command])

            Button("", action: { openCommandPalette() })
                .keyboardShortcut("k", modifiers: [.command])

            Button("", action: { openQuickAdd() })
                .keyboardShortcut("n", modifiers: [.shift])
        }
        .labelsHidden()
        .buttonStyle(PlainButtonStyle())
        .frame(width: 0, height: 0)
        .opacity(0.0)
    }

    private func handleArrowKey(deltaDays: Int) {
        let calendar = Calendar.current
        switch viewMode {
        case .month:
            showsMonthKeyboardFocusIndicator = true
            let current = Calendar.current.startOfDay(for: monthKeyboardSelection)
            let next = calendar.date(byAdding: .day, value: deltaDays, to: current) ?? current
            monthKeyboardSelection = calendar.startOfDay(for: next)

            // If selection moves outside the displayed month, follow it.
            if !isInDisplayedMonth(next) {
                monthNavigationDirection = compareMonthDirection(from: displayedMonth, to: next)
                withAnimation(.easeInOut(duration: 0.20)) {
                    displayedMonth = next
                }
            }
        case .week, .day, .agenda:
            withAnimation(.easeInOut(duration: 0.20)) {
                displayedMonth = calendar.date(byAdding: .day, value: deltaDays, to: displayedMonth) ?? displayedMonth
            }
        }
    }

    private func performPrimaryKeyboardAction() {
        switch viewMode {
        case .month:
            let day = Calendar.current.startOfDay(for: monthKeyboardSelection)
            if let firstEvent = (dayChips[day] ?? []).first(where: { $0.kind == .event }) {
                presentAnchoredEditor(objectID: firstEvent.id)
                return
            }
            let start = Calendar.current.date(byAdding: .hour, value: 9, to: day) ?? day
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            pillCoordinator.presentAddEvent(
                prefill: .init(semesterID: selectedSemesterID, title: nil, start: start, end: end),
                animated: !reduceMotion
            )
        case .week, .day, .agenda:
            let dayStart = Calendar.current.startOfDay(for: displayedMonth)
            let start = Calendar.current.date(byAdding: .hour, value: 9, to: dayStart) ?? dayStart
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            pillCoordinator.presentAddEvent(
                prefill: .init(semesterID: selectedSemesterID, title: nil, start: start, end: end),
                animated: !reduceMotion
            )
        }
    }

    private func moveAnchor(_ delta: Int) {
        let calendar = Calendar.current
        switch viewMode {
        case .month:
            navigateMonth(delta)
        case .week:
            withAnimation(.easeInOut(duration: 0.20)) {
                displayedMonth = calendar.date(byAdding: .day, value: delta * 7, to: displayedMonth) ?? displayedMonth
            }
        case .day:
            withAnimation(.easeInOut(duration: 0.20)) {
                displayedMonth = calendar.date(byAdding: .day, value: delta, to: displayedMonth) ?? displayedMonth
            }
        case .agenda:
            withAnimation(.easeInOut(duration: 0.20)) {
                displayedMonth = calendar.date(byAdding: .day, value: delta, to: displayedMonth) ?? displayedMonth
            }
        }
    }

    private func navigateMonth(_ delta: Int) {
        monthNavigationDirection = delta
        withAnimation(.easeInOut(duration: 0.22)) {
            displayedMonth = addMonths(displayedMonth, delta)
        }
    }

    private func navigateToToday() {
        let today = Date()
        monthNavigationDirection = compareMonthDirection(from: displayedMonth, to: today)
        withAnimation(.easeInOut(duration: 0.22)) {
            displayedMonth = today
        }
    }

    private func jumpToFocusItem(_ item: FocusItem) {
        monthNavigationDirection = compareMonthDirection(from: displayedMonth, to: item.date)
        withAnimation(.easeInOut(duration: 0.22)) {
            displayedMonth = item.date
            viewMode = .day
        }
    }

    private func openFocusItem(_ item: FocusItem) {
        switch item.kind {
        case .event:
            modalCoordinator.activeModal = .editCalendarItem(objectID: item.id)
        case .task:
            modalCoordinator.activeModal = .editTask(objectID: item.id)
        }
    }

    private func completeTaskItem(_ item: FocusItem) {
        guard item.kind == .task else { return }
        if let task = try? coreDataManager.viewContext.existingObject(with: item.id) as? TaskEntity {
            coreDataManager.setTaskCompleted(task, completed: true)
        }
    }

    private func monthTransitionKey(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private var monthGridTransition: AnyTransition {
        let direction = monthNavigationDirection
        let insertionEdge: Edge = (direction >= 0) ? .trailing : .leading
        let removalEdge: Edge = (direction >= 0) ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func compareMonthDirection(from: Date, to: Date) -> Int {
        let cal = Calendar.current
        let a = cal.dateComponents([.year, .month], from: from)
        let b = cal.dateComponents([.year, .month], from: to)
        let aKey = (a.year ?? 0) * 12 + (a.month ?? 0)
        let bKey = (b.year ?? 0) * 12 + (b.month ?? 0)
        if bKey > aKey { return 1 }
        if bKey < aKey { return -1 }
        return 0
    }

    private var topBarTitle: String {
        switch viewMode {
        case .month:
            return monthTitle(displayedMonth)
        case .week:
            return weekTitle(anchor: displayedMonth)
        case .day:
            return dayTitle(displayedMonth)
        case .agenda:
            return agendaTitle(anchor: displayedMonth)
        }
    }

    private var previousPeriodAccessibilityLabel: String {
        switch viewMode {
        case .month:
            return "Previous month"
        case .week:
            return "Previous week"
        case .day:
            return "Previous day"
        case .agenda:
            return "Previous day"
        }
    }

    private var nextPeriodAccessibilityLabel: String {
        switch viewMode {
        case .month:
            return "Next month"
        case .week:
            return "Next week"
        case .day:
            return "Next day"
        case .agenda:
            return "Next day"
        }
    }



    private func weekTitle(anchor: Date) -> String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor)) ?? anchor
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start

        let monthDay = DateFormatter()
        monthDay.dateFormat = "MMM d"
        let year = DateFormatter()
        year.dateFormat = "yyyy"

        if cal.component(.year, from: start) == cal.component(.year, from: end) {
            return "\(monthDay.string(from: start)) – \(monthDay.string(from: end)), \(year.string(from: end))"
        }
        return "\(monthDay.string(from: start)), \(year.string(from: start)) – \(monthDay.string(from: end)), \(year.string(from: end))"
    }

    private func dayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .textCase(.uppercase)
                }
            }
            .background(Color(hex: "f8fafc").opacity(0.5))
            .border(width: 1, edges: [.bottom], color: Color(hex: "f1f5f9"))

            // Days Grid
            GeometryReader { geometry in
                let width = geometry.size.width / 7
                let height = geometry.size.height / 6
                let grid = monthGridDates(for: displayedMonth)

                let monthSpanLaneHeight: CGFloat = 14
                let monthSpanLaneSpacing: CGFloat = 3
                let monthSpanTopOffset: CGFloat = 40

                let dropDelegate = MonthGridDropDelegate(
                    viewContext: coreDataManager.viewContext,
                    displayedMonth: $displayedMonth,
                    lastMonthDragSwitch: $lastMonthDragSwitch,
                    gridDates: grid,
                    cellWidth: width,
                    cellHeight: height,
                    gridSize: geometry.size,
                    moveEventToDay: { objectID, targetDay, withinDayMinutesHint in
                        moveEvent(objectID: objectID, toDay: targetDay, withinDayMinutesHint: withinDayMinutesHint)
                    },
                    moveTaskToDay: { objectID, targetDay, withinDayMinutesHint in
                        moveTask(objectID: objectID, toDay: targetDay, withinDayMinutesHint: withinDayMinutesHint)
                    }
                )

                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        let rowDates = Array(grid[(row * 7)..<((row * 7) + 7)])
                        let packedSpans = packMonthRecurringAllDaySpanLanes(monthRecurringAllDaySpanSeeds(forRowDates: rowDates, events: filteredEvents))
                        let laneCount = (packedSpans.map(\.lane).max() ?? -1) + 1
                        let reservedTop: CGFloat = laneCount > 0
                        ? (CGFloat(laneCount) * monthSpanLaneHeight) + (CGFloat(max(0, laneCount - 1)) * monthSpanLaneSpacing) + 6
                        : 0

                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(0..<7, id: \.self) { col in
                                    let index = row * 7 + col
                                    let date = grid[index]
                                    DayCell(
                                        date: date,
                                        isCurrentMonth: isInDisplayedMonth(date),
                                        isToday: Calendar.current.isDateInToday(date),
                                        isSelected: viewMode == .month && Calendar.current.isDate(date, inSameDayAs: monthKeyboardSelection),
                                        showsKeyboardFocusIndicator: showsMonthKeyboardFocusIndicator,
                                        width: width,
                                        height: height,
                                        chips: dayChips[Calendar.current.startOfDay(for: date)] ?? [],
                                        topOverlayReservedHeight: reservedTop,
                                        onTapEmpty: {
                                            pillCoordinator.clearSelection(animated: !reduceMotion)
                                            let dayStart = Calendar.current.startOfDay(for: date)
                                            showsMonthKeyboardFocusIndicator = false
                                            monthKeyboardSelection = dayStart
                                            let start = Calendar.current.date(byAdding: .hour, value: 9, to: dayStart) ?? dayStart
                                            let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
                                            pillCoordinator.suppressOutsideDismissOnce()
                                            modalCoordinator.activeModal = .addCalendarItem(
                                                semesterID: selectedSemesterID,
                                                initialTitle: nil,
                                                initialStart: start,
                                                initialEnd: end
                                            )
                                        },
                                        onTapChip: { chip in
                                            showsMonthKeyboardFocusIndicator = false
                                            monthKeyboardSelection = Calendar.current.startOfDay(for: date)

                                            switch chip.kind {
                                            case .event:
                                                    pillCoordinator.selectEvent(objectID: chip.id, in: coreDataManager.viewContext, animated: !reduceMotion)
                                            case .task:
                                                    pillCoordinator.selectTask(objectID: chip.id, in: coreDataManager.viewContext, animated: !reduceMotion)
                                            }
                                        }
                                    )
                                }
                            }

                            ForEach(packedSpans) { span in
                                MonthRecurringSpanBar(
                                    objectID: span.objectID,
                                    title: span.title,
                                    color: span.color,
                                    isPast: span.isPast,
                                    onSelect: {
                                        pillCoordinator.selectEvent(objectID: span.objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
                                    },
                                    onTap: {
                                        presentAnchoredEditor(objectID: span.objectID)
                                    },
                                    onDelete: {
                                        let eventTitle: String
                                        if let event = try? coreDataManager.viewContext.existingObject(with: span.objectID) as? CalendarEventEntity {
                                            eventTitle = event.title ?? "Event"
                                            if let uuid = event.id {
                                                Task.detached(priority: .utility) { [calendarManager] in
                                                    calendarManager.deleteEventFromGoogle(localEventID: uuid)
                                                }
                                            }
                                        } else {
                                            eventTitle = "Event"
                                        }
                                        coreDataManager.deleteCalendarEvent(objectID: span.objectID)
                                        
                                        AppNotificationCenter.shared.post(
                                            kind: .info,
                                            title: "Event Deleted",
                                            message: "\(eventTitle) removed from calendar",
                                            autoDismissAfter: 3
                                        )
                                    },
                                    onDuplicate: {
                                        duplicateCalendarEvent(objectID: span.objectID)
                                    }
                                )
                                .frame(width: (CGFloat((span.endIndex - span.startIndex) + 1) * width) - 8, height: monthSpanLaneHeight)
                                .offset(
                                    x: (CGFloat(span.startIndex) * width) + 4,
                                    y: monthSpanTopOffset + (CGFloat(span.lane) * (monthSpanLaneHeight + monthSpanLaneSpacing))
                                )
                            }
                        }
                        .frame(height: height)
                        .clipped()
                    }
                }
                .onDrop(of: [UTType.text.identifier], delegate: dropDelegate)
            }
        }
        .background(Color.white)
    }

    private struct MonthRecurringSpanSeed: Identifiable {
        let id: String
        let objectID: NSManagedObjectID
        let title: String
        let color: Color
        let isPast: Bool
        let startIndex: Int
        let endIndex: Int
    }

    private struct PackedMonthRecurringSpan: Identifiable {
        let id: String
        let objectID: NSManagedObjectID
        let title: String
        let color: Color
        let isPast: Bool
        let startIndex: Int
        let endIndex: Int
        let lane: Int
    }

    private func monthRecurringAllDaySpanSeeds(forRowDates rowDates: [Date], events: [CalendarEventEntity]) -> [MonthRecurringSpanSeed] {
        guard rowDates.count == 7 else { return [] }

        let cal = Calendar.current
        let rowStart = cal.startOfDay(for: rowDates[0])
        let rowEnd = cal.startOfDay(for: rowDates[6])

        var daysBySeries: [String: [Date: CalendarEventEntity]] = [:]

        for event in events {
            guard event.allDay, let startDate = event.startDate, let endDate = event.endDate else { continue }
            guard let seriesKey = calendarManager.googleRecurringSeriesKey(for: event) else { continue }

            let startDay = cal.startOfDay(for: startDate)

            // Compute inclusive last day (treat midnight end as exclusive).
            let endDayStart = cal.startOfDay(for: endDate)
            var lastDay = endDayStart
            if endDate == endDayStart && endDate > startDate {
                lastDay = cal.date(byAdding: .day, value: -1, to: endDayStart) ?? endDayStart
            }
            if lastDay < startDay { lastDay = startDay }

            if lastDay < rowStart || startDay > rowEnd { continue }

            var day = max(startDay, rowStart)
            while day <= min(lastDay, rowEnd) {
                // Keep the first instance we see for this day.
                if daysBySeries[seriesKey]?[day] == nil {
                    daysBySeries[seriesKey, default: [:]][day] = event
                }
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }

        var seeds: [MonthRecurringSpanSeed] = []

        for (seriesKey, dayMap) in daysBySeries {
            let sortedDays = dayMap.keys.sorted()
            guard var segmentStart = sortedDays.first else { continue }
            var segmentEnd = segmentStart

            func flushSegment(start: Date, end: Date) {
                guard let representative = dayMap[start] ?? dayMap[end] else { return }
                let startIndex = cal.dateComponents([.day], from: rowStart, to: start).day ?? 0
                let endIndex = cal.dateComponents([.day], from: rowStart, to: end).day ?? 0
                let title = (representative.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
                let isPast = isPastEvent(start: representative.startDate, end: representative.endDate, allDay: representative.allDay)

                let seedID = "\(seriesKey)||\(startIndex)-\(endIndex)"
                seeds.append(
                    MonthRecurringSpanSeed(
                        id: seedID,
                        objectID: representative.objectID,
                        title: title.isEmpty ? "Event" : title,
                        color: eventDisplayColor(representative, calendarManager: calendarManager),
                        isPast: isPast,
                        startIndex: max(0, min(6, startIndex)),
                        endIndex: max(0, min(6, endIndex))
                    )
                )
            }

            for day in sortedDays.dropFirst() {
                let expectedNext = cal.date(byAdding: .day, value: 1, to: segmentEnd) ?? segmentEnd
                if cal.isDate(day, inSameDayAs: expectedNext) {
                    segmentEnd = day
                } else {
                    flushSegment(start: segmentStart, end: segmentEnd)
                    segmentStart = day
                    segmentEnd = day
                }
            }
            flushSegment(start: segmentStart, end: segmentEnd)
        }

        return seeds
    }

    private func packMonthRecurringAllDaySpanLanes(_ items: [MonthRecurringSpanSeed]) -> [PackedMonthRecurringSpan] {
        let sorted = items.sorted {
            if $0.startIndex != $1.startIndex { return $0.startIndex < $1.startIndex }
            // Prefer longer spans first when starting the same day.
            return ($0.endIndex - $0.startIndex) > ($1.endIndex - $1.startIndex)
        }

        var laneEnd: [Int] = []
        var packed: [PackedMonthRecurringSpan] = []

        for item in sorted {
            var assignedLane: Int? = nil
            for (lane, end) in laneEnd.enumerated() {
                if end < item.startIndex {
                    assignedLane = lane
                    laneEnd[lane] = item.endIndex
                    break
                }
            }
            if assignedLane == nil {
                assignedLane = laneEnd.count
                laneEnd.append(item.endIndex)
            }

            let lane = assignedLane ?? 0
            packed.append(
                PackedMonthRecurringSpan(
                    id: "\(item.id)||lane:\(lane)",
                    objectID: item.objectID,
                    title: item.title,
                    color: item.color,
                    isPast: item.isPast,
                    startIndex: item.startIndex,
                    endIndex: item.endIndex,
                    lane: lane
                )
            )
        }

        return packed
    }

    private func moveEvent(objectID: NSManagedObjectID, toDay targetDay: Date, withinDayMinutesHint: Int?) {
        guard let event = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity,
              let start = event.startDate,
              let end = event.endDate
        else {
            return
        }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: targetDay)

        if event.allDay {
            let newStart = dayStart
            let newEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            coreDataManager.updateCalendarEventTimes(objectID: objectID, startDate: newStart, endDate: newEnd)
            if let updated = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity {
                Task.detached(priority: .utility) { [calendarManager] in
                    calendarManager.exportEventToGoogle(updated)
                }
            }
            return
        }

        let time = cal.dateComponents([.hour, .minute, .second], from: start)
        let duration = end.timeIntervalSince(start)

        let isSameDayMove = cal.isDate(start, inSameDayAs: targetDay)
        if isSameDayMove, let withinDayMinutesHint {
            var comps = cal.dateComponents([.year, .month, .day], from: dayStart)
            comps.hour = withinDayMinutesHint / 60
            comps.minute = withinDayMinutesHint % 60
            comps.second = 0

            let newStart = cal.date(from: comps) ?? dayStart
            let newEnd = newStart.addingTimeInterval(max(15 * 60, duration))
            coreDataManager.updateCalendarEventTimes(objectID: objectID, startDate: newStart, endDate: newEnd)
            if let updated = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity {
                Task.detached(priority: .utility) { [calendarManager] in
                    calendarManager.exportEventToGoogle(updated)
                }
            }
            return
        }

        var comps = cal.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = time.second
        let newStart = cal.date(from: comps) ?? dayStart
        let newEnd = newStart.addingTimeInterval(max(15 * 60, duration))

        coreDataManager.updateCalendarEventTimes(objectID: objectID, startDate: newStart, endDate: newEnd)
        if let updated = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity {
            Task.detached(priority: .utility) { [calendarManager] in
                calendarManager.exportEventToGoogle(updated)
            }
        }
    }

    private func moveTask(objectID: NSManagedObjectID, toDay targetDay: Date, withinDayMinutesHint: Int?) {
        guard let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity else {
            return
        }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: targetDay)

        let currentDue = task.dueDate
        let time: DateComponents = {
            if let withinDayMinutesHint {
                var comps = DateComponents()
                comps.hour = withinDayMinutesHint / 60
                comps.minute = withinDayMinutesHint % 60
                comps.second = 0
                return comps
            }
            if let currentDue {
                return cal.dateComponents([.hour, .minute, .second], from: currentDue)
            }
            return DateComponents(hour: 9, minute: 0, second: 0)
        }()

        var comps = cal.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = time.second

        let newDue = cal.date(from: comps) ?? dayStart

        coreDataManager.updateTask(
            objectID: task.objectID,
            title: task.title ?? "Task",
            dueDate: newDue,
            semester: task.semester,
            course: task.course,
            notes: task.notes,
            priority: task.priority
        )
    }

    private struct MonthGridDropDelegate: DropDelegate {
        let viewContext: NSManagedObjectContext
        @Binding var displayedMonth: Date
        @Binding var lastMonthDragSwitch: Date

        let gridDates: [Date]
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let gridSize: CGSize
        let moveEventToDay: (NSManagedObjectID, Date, Int?) -> Void
        let moveTaskToDay: (NSManagedObjectID, Date, Int?) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [UTType.text.identifier])
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            maybeAutoAdvanceMonth(location: info.location)
            return DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            guard let item = info.itemProviders(for: [UTType.text.identifier]).first else {
                return false
            }

            let location = info.location
            let target = dropTarget(at: location)
            let targetDay = target?.dayStart
            let withinDayMinutesHint = target?.withinDayMinutesHint

            item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                guard let targetDay else { return }

                let str: String? = {
                    if let s = data as? String { return s }
                    if let ns = data as? NSString { return ns as String }
                    if let d = data as? Data { return String(data: d, encoding: .utf8) }
                    return nil
                }()

                guard let urlString = str?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let uri = URL(string: urlString),
                      let coordinator = viewContext.persistentStoreCoordinator,
                      let objectID = coordinator.managedObjectID(forURIRepresentation: uri)
                else {
                    return
                }

                DispatchQueue.main.async {
                    if let _ = (try? viewContext.existingObject(with: objectID)) as? CalendarEventEntity {
                        moveEventToDay(objectID, targetDay, withinDayMinutesHint)
                    } else if let _ = (try? viewContext.existingObject(with: objectID)) as? TaskEntity {
                        moveTaskToDay(objectID, targetDay, withinDayMinutesHint)
                    }
                }
            }

            return true
        }

        private struct DropTarget {
            let dayStart: Date
            let withinDayMinutesHint: Int
        }

        private func dropTarget(at location: CGPoint) -> DropTarget? {
            guard cellWidth > 0, cellHeight > 0 else { return nil }
            let col = Int(floor(location.x / cellWidth))
            let row = Int(floor(location.y / cellHeight))
            guard col >= 0, col < 7, row >= 0, row < 6 else { return nil }

            let index = row * 7 + col
            guard index >= 0, index < gridDates.count else { return nil }

            let dayStart = Calendar.current.startOfDay(for: gridDates[index])

            // Only used when dropping *within the same day* (see `moveEvent`):
            // map Y position inside the cell to a 15-minute snapped time.
            let yInCell = max(0, min(cellHeight, location.y - CGFloat(row) * cellHeight))
            let fraction = max(0, min(0.999, yInCell / max(1, cellHeight)))
            let rawMinutes = Int(round(fraction * 24.0 * 60.0))
            let snapped = Int(round(Double(rawMinutes) / 15.0)) * 15
            let clamped = max(0, min(23 * 60 + 45, snapped))

            return DropTarget(dayStart: dayStart, withinDayMinutesHint: clamped)
        }

        private func maybeAutoAdvanceMonth(location: CGPoint) {
            // When hovering near the left/right edges while dragging, flip months.
            // Throttle so it only advances one month at a time.
            let threshold: CGFloat = 36
            let cooldown: TimeInterval = 0.55
            let now = Date()
            guard now.timeIntervalSince(lastMonthDragSwitch) >= cooldown else { return }

            if location.x <= threshold {
                lastMonthDragSwitch = now
                displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } else if location.x >= max(0, gridSize.width - threshold) {
                lastMonthDragSwitch = now
                displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            }
        }
    }

    private func selectedSemester() -> SemesterEntity? {
        guard let id = selectedSemesterID else { return nil }
        return coreDataManager.semesters.first(where: { $0.id == id })
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private func todayText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: Date())
    }

    private func addMonths(_ date: Date, _ delta: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: delta, to: date) ?? date
    }

    private func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    private func monthGridDates(for month: Date) -> [Date] {
        let calendar = Calendar.current
        let first = startOfMonth(month)

        // Align to week start (Sunday) to match headers.
        let weekday = calendar.component(.weekday, from: first) // Sunday=1
        let daysToSubtract = weekday - 1
        let gridStart = calendar.date(byAdding: .day, value: -daysToSubtract, to: first) ?? first

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    private func isInDisplayedMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let a = calendar.dateComponents([.year, .month], from: date)
        let b = calendar.dateComponents([.year, .month], from: displayedMonth)
        return a.year == b.year && a.month == b.month
    }

    private func reloadCalendarData() {
        let semester: SemesterEntity? = selectedSemester()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Always keep the visible range populated so searching doesn't hide events.
        let range = visibleRange(for: viewMode, anchor: displayedMonth)
        let rangeStart = range.start
        let rangeEnd = range.end

        calendarEvents = coreDataManager.fetchCalendarEvents(semester: semester, start: rangeStart, end: rangeEnd)
        calendarTasks = coreDataManager.fetchTasks(semester: semester, dueStart: rangeStart, dueEnd: rangeEnd, includeCompleted: false)

        // Search is only for the results panel.
        if !query.isEmpty {
            searchEventResults = coreDataManager.searchCalendarEvents(semester: semester, query: query)
            searchTaskResults = coreDataManager.searchTasks(semester: semester, query: query, includeCompleted: false)
        } else {
            searchEventResults = []
            searchTaskResults = []
        }

        if viewMode == .month {
            rebuildDayChips(fromEvents: filteredEvents, tasks: filteredTasks)
        }
    }

    private var filteredEvents: [CalendarEventEntity] {
        return calendarEvents.filter { calendarManager.shouldDisplayEvent($0) }
    }

    private var filteredTasks: [TaskEntity] {
        return calendarTasks
    }

    private func rebuildDayChips(fromEvents events: [CalendarEventEntity], tasks: [TaskEntity]) {
        var next: [Date: [CalendarChip]] = [:]

        for event in events {
            guard let startDate = event.startDate, let endDate = event.endDate else { continue }
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: startDate)

            let isRecurring = (calendarManager.googleRecurringSeriesKey(for: event) != nil)
            if event.allDay && isRecurring {
                // Month view renders recurring all-day instances as spanning bars (split at week boundaries).
                // Skip per-day chips to avoid duplicates.
                continue
            }

            // Treat end dates as exclusive when they land exactly on a day boundary.
            // This avoids showing all‑day events on the day after they end.
            let endDayStart = calendar.startOfDay(for: endDate)
            var lastDay = endDayStart
            if endDate == endDayStart && endDate > startDate {
                lastDay = calendar.date(byAdding: .day, value: -1, to: endDayStart) ?? endDayStart
            }
            if lastDay < startDay { lastDay = startDay }

            var day = startDay
            while day <= lastDay {
                let title = (event.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
                let timeText: String? = {
                    if event.allDay {
                        // Don't show "All-day" text - removed per user request
                        return nil
                    }
                    return localizedTimePrefix(startDate)
                }()
                let isPast = isPastEvent(start: startDate, end: endDate, allDay: event.allDay)
                let chip = CalendarChip(
                    id: event.objectID,
                    title: title.isEmpty ? "Event" : title,
                    timeText: timeText,
                    color: eventDisplayColor(event, calendarManager: calendarManager),
                    icon: event.course != nil ? "book.closed" : nil,
                    trailingIcon: (event.allDay && isRecurring) ? "arrow.triangle.2.circlepath" : nil,
                    kind: .event,
                    isPast: isPast
                )
                next[day, default: []].append(chip)

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }

        for task in tasks {
            guard let due = task.dueDate else { continue }
            let day = Calendar.current.startOfDay(for: due)
            let isPast = due < Date()
            let chip = CalendarChip(
                id: task.objectID,
                title: (task.title ?? "Task"),
                timeText: timePrefix(due),
                color: isPast ? DesignSystem.Colors.textLight : DesignSystem.Colors.warning,
                icon: "checklist",
                kind: .task,
                isPast: isPast
            )
            next[day, default: []].append(chip)
        }

        for (key, value) in next {
            next[key] = value.sorted {
                let aTime = ($0.timeText ?? "")
                let bTime = ($1.timeText ?? "")
                if aTime != bTime { return aTime < bTime }
                return $0.title < $1.title
            }
        }

        dayChips = next
    }

    private func agendaTitle(anchor: Date) -> String {
        let cal = Calendar.current
        let start = cal.startOfDay(for: anchor)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Schedule • \(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private var agendaList: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: displayedMonth)
        let days = (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: start) }

        let hasAnyItems: Bool = {
            for day in days {
                let dayStart = cal.startOfDay(for: day)
                let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

                if filteredEvents.contains(where: { ev in
                    guard let s = ev.startDate, let e = ev.endDate else { return false }
                    return s < dayEnd && e > dayStart
                }) {
                    return true
                }

                if filteredTasks.contains(where: { t in
                    guard let due = t.dueDate else { return false }
                    return due >= dayStart && due < dayEnd
                }) {
                    return true
                }
            }
            return false
        }()

        return ScrollView {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        pillCoordinator.clearSelection(animated: !reduceMotion)
                    }

                VStack(alignment: .leading, spacing: 16) {
                if !hasAnyItems {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No items")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("No events or tasks match this range.")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
                    )
                }
                ForEach(days, id: \.self) { day in
                    let dayStart = cal.startOfDay(for: day)
                    let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

                    let dayEvents: [CalendarEventEntity] = filteredEvents
                        .filter { ev in
                            guard let s = ev.startDate, let e = ev.endDate else { return false }
                            return s < dayEnd && e > dayStart
                        }
                        .sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }

                    let dayTasks: [TaskEntity] = filteredTasks
                        .filter { t in
                            guard let due = t.dueDate else { return false }
                            return due >= dayStart && due < dayEnd
                        }
                        .sorted { ($0.dueDate ?? Date()) < ($1.dueDate ?? Date()) }

                    if !dayEvents.isEmpty || !dayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)

                            VStack(spacing: 10) {
                                ForEach(dayEvents, id: \.objectID) { event in
                                    let baseColor = eventDisplayColor(event, calendarManager: calendarManager)
                                    let isPast = isPastEvent(start: event.startDate, end: event.endDate, allDay: event.allDay)
                                    AgendaRow(
                                        title: event.title ?? "Event",
                                        subtitle: event.location,
                                        timeText: agendaTimeText(event: event, dayStart: dayStart, dayEnd: dayEnd),
                                        color: isPast ? DesignSystem.Colors.textLight : baseColor
                                    )
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: CalendarItemFramePreferenceKey.self,
                                                value: [event.objectID.uriRepresentation(): geo.frame(in: .named("CalendarMainContent"))]
                                            )
                                        }
                                    )
                                    .onTapGesture {
                                        pillCoordinator.selectEvent(objectID: event.objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
                                    }
                                    .contextMenu {
                                        Button("Edit…") { presentAnchoredEditor(objectID: event.objectID) }
                                        Button("Duplicate") { duplicateCalendarEvent(objectID: event.objectID) }
                                        Button("Delete…", role: .destructive) {
                                            let eventTitle = event.title ?? "Event"
                                            if let uuid = event.id {
                                                Task.detached(priority: .utility) { [calendarManager] in
                                                    calendarManager.deleteEventFromGoogle(localEventID: uuid)
                                                }
                                            }
                                            coreDataManager.deleteCalendarEvent(objectID: event.objectID)
                                            
                                            AppNotificationCenter.shared.post(
                                                kind: .info,
                                                title: "Event Deleted",
                                                message: "\(eventTitle) removed from calendar",
                                                autoDismissAfter: 3
                                            )
                                        }
                                    }
                                }

                                ForEach(dayTasks, id: \.objectID) { task in
                                    let isPast = (task.dueDate ?? .distantFuture) < Date()
                                    AgendaRow(
                                        title: task.title ?? "Task",
                                        subtitle: task.course?.code,
                                        timeText: agendaTaskTimeText(task),
                                        color: isPast ? DesignSystem.Colors.textLight : DesignSystem.Colors.warning
                                    )
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: CalendarItemFramePreferenceKey.self,
                                                value: [task.objectID.uriRepresentation(): geo.frame(in: .named("CalendarMainContent"))]
                                            )
                                        }
                                    )
                                    .onTapGesture {
                                        pillCoordinator.selectTask(objectID: task.objectID, in: coreDataManager.viewContext, animated: !reduceMotion)
                                    }
                                    .contextMenu {
                                        Button("Edit…") { presentAnchoredTaskEditor(objectID: task.objectID) }
                                        Button("Delete…", role: .destructive) { coreDataManager.deleteTask(task) }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
                        )
                    }
                }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
    }

    private func agendaTimeText(event: CalendarEventEntity, dayStart: Date, dayEnd: Date) -> String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        if event.allDay { return "" }
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(end, dayEnd)
        return localizedTimeRange(clippedStart, clippedEnd)
    }

    private func agendaTaskTimeText(_ task: TaskEntity) -> String {
        guard let due = task.dueDate else { return "No due date" }
        return "Due \(localizedTimePrefix(due))"
    }

    private func duplicateCalendarEvent(objectID: NSManagedObjectID) {
        guard let existing = try? coreDataManager.viewContext.existingObject(with: objectID) as? CalendarEventEntity else {
            return
        }

        let title = (existing.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
        let start = existing.startDate ?? Date()
        let end = existing.endDate ?? (Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start)
        let allDay = existing.allDay
        let notes = existing.notes
        let location = existing.location
        let semester = existing.semester
        let course = existing.course

        _ = coreDataManager.addCalendarEvent(
            title: title.isEmpty ? "Event" : title,
            startDate: start,
            endDate: end,
            allDay: allDay,
            semester: semester,
            course: course,
            notes: notes,
            location: location
        )
    }

    private func visibleRange(for mode: CalendarViewMode, anchor: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch mode {
        case .month:
            let grid = monthGridDates(for: anchor)
            guard let start = grid.first, let end = grid.last else {
                let start = calendar.startOfDay(for: anchor)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                return (start, end)
            }
            let rangeStart = calendar.startOfDay(for: start)
            let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            return (rangeStart, rangeEnd)
        case .week:
            let start = startOfWeek(anchor)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return (start, end)
        case .day:
            let start = calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return (start, end)
        case .agenda:
            let start = calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: 14, to: start) ?? start
            return (start, end)
        }
    }

    private func startOfWeek(_ date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay) // Sunday=1
        let daysToSubtract = weekday - 1
        return calendar.date(byAdding: .day, value: -daysToSubtract, to: startOfDay) ?? startOfDay
    }

    private func timePrefix(_ date: Date) -> String {
        localizedTimePrefix(date)
    }
}

private struct CalendarViewModeSwitcher: View {
    @Binding var selection: CalendarViewMode

    private let modes: [(CalendarViewMode, String)] = [
        (.day, "Day"),
        (.week, "Week"),
        (.month, "Month"),
        (.agenda, "List")
    ]

    var body: some View {
        Picker("View Mode", selection: $selection) {
            ForEach(modes, id: \.0) { mode, title in
                Text(title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private enum CalendarViewMode {
    case day
    case week
    case month
    case agenda
}

private struct WeekScheduleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    let viewContext: NSManagedObjectContext
    let anchorDate: Date
    let semester: SemesterEntity?
    let events: [CalendarEventEntity]
    let tasks: [TaskEntity]
    let isKeyboardCaptureEnabled: Bool
    let onMoveEvent: (NSManagedObjectID, Date, Date) -> Void
    let onCreateEvent: (Date, Date) -> Void
    let onEditEvent: (NSManagedObjectID) -> Void
    let onEditEventFromOverflow: (NSManagedObjectID) -> Void
    let onDeleteEvent: (NSManagedObjectID) -> Void
    let onDuplicateEvent: (NSManagedObjectID) -> Void

    let onMoveTaskDueDate: (NSManagedObjectID, Date) -> Void
    let onEditTask: (NSManagedObjectID) -> Void
    let onDeleteTask: (NSManagedObjectID) -> Void

    @ScaledMetric(relativeTo: .body) private var timeGutterWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var allDayRowHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var eventPadding: CGFloat = 6
    private let snapMinutes: Int = 15

    @ScaledMetric(relativeTo: .body) private var allDayLaneHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var allDayLaneSpacing: CGFloat = 6
    @ScaledMetric(relativeTo: .body) private var allDayRowVerticalPadding: CGFloat = 6

    @State private var selection: TimeSelection? = nil
    @State private var pendingCreationRange: TimeSelection? = nil
    @State private var suppressNextTapCreate: Bool = false

    @State private var creationBloom: CreationBloom? = nil
    @State private var creationBloomPhase: CGFloat = 0

    // Hover highlights intentionally disabled.

    @State private var focusedDayIndex: Int = 0
    @State private var focusedMinute: Int = 9 * 60
    @State private var allDayOverflowPopoverDay: Date? = nil
    @State private var showsKeyboardFocusIndicator: Bool = false
    @FocusState private var isGridFocused: Bool

    private struct TimeSelection {
        let dayIndex: Int
        let startMinute: Int
        var currentMinute: Int
    }

    private struct AllDaySpan: Identifiable {
        let id: String
        let objectID: NSManagedObjectID
        let title: String
        let color: Color
        let isPast: Bool
        let startIndex: Int
        let endIndex: Int
        let badge: AllDaySpanChip.Badge
        let lane: Int
    }

    private func allDaySpanRange(for event: CalendarEventEntity) -> (startIndex: Int, endIndex: Int)? {
        guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
        let calendar = Calendar.current
        let weekStartDay = calendar.startOfDay(for: weekStart)
        let weekEndDay = calendar.date(byAdding: .day, value: 7, to: weekStartDay) ?? weekStartDay

        // Must overlap this week.
        guard startDate < weekEndDay && endDate > weekStartDay else { return nil }

        let startDay = calendar.startOfDay(for: startDate)

        // Treat end dates as exclusive when they land exactly on a day boundary.
        let endDayStart = calendar.startOfDay(for: endDate)
        var lastDay = endDayStart
        if endDate == endDayStart && endDate > startDate {
            lastDay = calendar.date(byAdding: .day, value: -1, to: endDayStart) ?? endDayStart
        }
        if lastDay < startDay { lastDay = startDay }

        let clampedStart = max(startDay, weekStartDay)
        let clampedEnd = min(lastDay, calendar.date(byAdding: .day, value: -1, to: weekEndDay) ?? lastDay)

        let startIndex = max(0, min(6, calendar.dateComponents([.day], from: weekStartDay, to: clampedStart).day ?? 0))
        let endIndex = max(0, min(6, calendar.dateComponents([.day], from: weekStartDay, to: clampedEnd).day ?? 0))
        return (min(startIndex, endIndex), max(startIndex, endIndex))
    }

    private func packAllDayLanes(_ items: [(id: String, objectID: NSManagedObjectID, title: String, color: Color, isPast: Bool, startIndex: Int, endIndex: Int, badge: AllDaySpanChip.Badge)]) -> [AllDaySpan] {
        // Place all events horizontally next to each other (all in lane 0)
        // Multi-day events will naturally stretch across days
        // Events on the same day will be positioned by their startIndex/endIndex
        return items.map { item in
            AllDaySpan(
                id: item.id,
                objectID: item.objectID,
                title: item.title,
                color: item.color,
                isPast: item.isPast,
                startIndex: item.startIndex,
                endIndex: item.endIndex,
                badge: item.badge,
                lane: 0 // All events in same horizontal lane (next to each other)
            )
        }
    }

    private func allDaySpansForWeek() -> [AllDaySpan] {
        let calendar = Calendar.current
        let weekStartDay = calendar.startOfDay(for: weekStart)
        let weekEndDay = calendar.date(byAdding: .day, value: 7, to: weekStartDay) ?? weekStartDay

        let allDayInWeek = events
            .filter { $0.allDay }
            .filter { ev in
                guard let s = ev.startDate, let e = ev.endDate else { return false }
                return s < weekEndDay && e > weekStartDay
            }

        // 1) Group recurring Google instances into segments of consecutive days.
        var usedObjectIDs = Set<NSManagedObjectID>()
        var groupedItems: [(id: String, objectID: NSManagedObjectID, title: String, color: Color, isPast: Bool, startIndex: Int, endIndex: Int, badge: AllDaySpanChip.Badge)] = []

        let groups = Dictionary(grouping: allDayInWeek) { ev in
            calendarManager.googleRecurringSeriesKey(for: ev)
        }

        for (seriesKey, seriesEvents) in groups {
            guard let seriesKey else { continue }

            // Collect all covered day indices for this series.
            var dayIndexToRepresentative: [Int: CalendarEventEntity] = [:]
            var covered: Set<Int> = []

            for ev in seriesEvents {
                guard let range = allDaySpanRange(for: ev) else { continue }
                for idx in range.startIndex...range.endIndex {
                    covered.insert(idx)
                    if dayIndexToRepresentative[idx] == nil {
                        dayIndexToRepresentative[idx] = ev
                    }
                }
            }

            let sortedIndices = covered.sorted()
            guard !sortedIndices.isEmpty else { continue }

            // Segment into consecutive runs.
            var runStart = sortedIndices[0]
            var runEnd = sortedIndices[0]
            func flushRun() {
                guard let rep = dayIndexToRepresentative[runStart] else { return }
                usedObjectIDs.insert(rep.objectID)

                let title = (rep.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
                let color = eventDisplayColor(rep, calendarManager: calendarManager)
                let isPast = isPastEvent(start: rep.startDate, end: rep.endDate, allDay: true)

                groupedItems.append(
                    (
                        id: "recurring|\(seriesKey)|\(runStart)-\(runEnd)",
                        objectID: rep.objectID,
                        title: title.isEmpty ? "Event" : title,
                        color: color,
                        isPast: isPast,
                        startIndex: runStart,
                        endIndex: runEnd,
                        badge: .recurring
                    )
                )
            }

            for idx in sortedIndices.dropFirst() {
                if idx == runEnd + 1 {
                    runEnd = idx
                } else {
                    flushRun()
                    runStart = idx
                    runEnd = idx
                }
            }
            flushRun()
        }

        // 2) Non-recurring all-day items (including multi-day) become spans.
        for ev in allDayInWeek {
            if usedObjectIDs.contains(ev.objectID) { continue }
            guard let range = allDaySpanRange(for: ev) else { continue }
            let title = (ev.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
            let color = eventDisplayColor(ev, calendarManager: calendarManager)
            let isPast = isPastEvent(start: ev.startDate, end: ev.endDate, allDay: true)
            groupedItems.append(
                (
                    id: "allday|\(ev.objectID.uriRepresentation().absoluteString)",
                    objectID: ev.objectID,
                    title: title.isEmpty ? "Event" : title,
                    color: color,
                    isPast: isPast,
                    startIndex: range.startIndex,
                    endIndex: range.endIndex,
                    badge: .allDay
                )
            )
        }

        return packAllDayLanes(groupedItems)
    }

    private struct CreationBloom: Identifiable {
        let id = UUID()
        let dayIndex: Int
        let startMinute: Int
        let endMinute: Int
    }

    private func triggerCreationBloom(dayIndex: Int, startMinute: Int, endMinute: Int) {
        guard !reduceMotion else { return }

        creationBloom = CreationBloom(
            dayIndex: dayIndex,
            startMinute: min(max(startMinute, 0), 24 * 60),
            endMinute: min(max(endMinute, 0), 24 * 60)
        )
        creationBloomPhase = 0

        withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
            creationBloomPhase = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.14)) {
                creationBloomPhase = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            if creationBloom?.dayIndex == dayIndex {
                creationBloom = nil
            }
        }
    }

    private var weekStart: Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: anchorDate)
        let weekday = calendar.component(.weekday, from: startOfDay) // Sunday=1
        let daysToSubtract = weekday - 1
        return calendar.date(byAdding: .day, value: -daysToSubtract, to: startOfDay) ?? startOfDay
    }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayRow
            Divider().overlay(Color(hex: "f1f5f9"))
            scrollGrid
        }
        .background(Color.white)
        .focusable(isKeyboardCaptureEnabled)
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onAppear {
            if isKeyboardCaptureEnabled {
                isGridFocused = true
            }
        }
        .onChange(of: isKeyboardCaptureEnabled) { _, enabled in
            if enabled {
                isGridFocused = true
            }
        }
        .onMoveCommand { direction in
            guard isKeyboardCaptureEnabled else { return }
            showsKeyboardFocusIndicator = true
            switch direction {
            case .up:
                focusedMinute = max(0, focusedMinute - snapMinutes)
            case .down:
                focusedMinute = min(24 * 60 - snapMinutes, focusedMinute + snapMinutes)
            case .left:
                focusedDayIndex = max(0, focusedDayIndex - 1)
            case .right:
                focusedDayIndex = min(6, focusedDayIndex + 1)
            default:
                break
            }
        }
        .overlay(keyboardActionCapture)
        .onChange(of: pillCoordinator.isAddEventPresented) { _, isPresented in
            if !isPresented {
                pendingCreationRange = nil
            }
        }
    }

    private var keyboardActionCapture: some View {
        Group {
            if isKeyboardCaptureEnabled {
                Button(action: performPrimaryKeyboardAction) { EmptyView() }
                    .keyboardShortcut(.return, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                Button(action: performCreateAtFocusedSlot) { EmptyView() }
                    .keyboardShortcut("n", modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                Button(action: performDeleteAtFocusedSlot) { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                Button(action: performDeleteAtFocusedSlot) { EmptyView() }
                    .keyboardShortcut(.deleteForward, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeGutterWidth, height: headerHeight)

            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(isToday ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                        .textCase(.uppercase)

                    ZStack {
                        if isToday {
                            Circle()
                                .fill(DesignSystem.Colors.primary)
                                .frame(width: 28, height: 28)
                        }
                        Text(day.formatted(.dateTime.day()))
                            .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                            .foregroundColor(isToday ? .white : DesignSystem.Colors.textMain)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: headerHeight + 8)
                .padding(.vertical, 4)
            }
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(hex: "e2e8f0"))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var allDayRow: some View {
        let spans = allDaySpansForWeek()
        let laneCount = max(1, (spans.map { $0.lane }.max() ?? 0) + 1)
        let effectiveHeight = max(
            allDayRowHeight,
            (allDayRowVerticalPadding * 2) + (CGFloat(laneCount) * allDayLaneHeight) + (CGFloat(max(0, laneCount - 1)) * allDayLaneSpacing)
        )

        return GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - timeGutterWidth)
            let dayWidth = contentWidth / 7

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    Text("all-day")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .frame(width: timeGutterWidth, alignment: .trailing)
                        .padding(.trailing, 10)
                        .frame(height: effectiveHeight)

                    ForEach(0..<7, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: effectiveHeight)
                    }
                }

                ForEach(spans) { span in
                    let dayCount = max(1, (span.endIndex - span.startIndex) + 1)
                    let barX = timeGutterWidth + CGFloat(span.startIndex) * dayWidth + 6
                    let barWidth = max(56, (CGFloat(dayCount) * dayWidth) - 12)
                    let y = allDayRowVerticalPadding + (CGFloat(span.lane) * (allDayLaneHeight + allDayLaneSpacing))

                    AllDaySpanChip(
                        objectID: span.objectID,
                        title: span.title,
                        badge: span.badge,
                        color: span.color,
                        isPast: span.isPast,
                        pixelsPerDay: max(44, dayWidth),
                        onSelect: { suppressNextTapCreate = true },
                        onTap: { suppressNextTapCreate = true },
                        onMoveDays: { dayDelta in
                            guard dayDelta != 0 else { return }
                            guard let ev = (events.first { $0.objectID == span.objectID }) else { return }
                            guard let start = ev.startDate, let end = ev.endDate else { return }
                            let cal = Calendar.current
                            let movedStart = cal.date(byAdding: .day, value: dayDelta, to: start) ?? start
                            let movedEnd = cal.date(byAdding: .day, value: dayDelta, to: end) ?? end
                            onMoveEvent(span.objectID, movedStart, movedEnd)
                        },
                        onDelete: { onDeleteEvent(span.objectID) },
                        onDuplicate: { onDuplicateEvent(span.objectID) }
                    )
                    .frame(width: barWidth, height: allDayLaneHeight, alignment: .leading)
                    .offset(x: barX, y: y)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CalendarItemFramePreferenceKey.self,
                                value: [span.objectID.uriRepresentation(): geo.frame(in: .named("CalendarMainContent"))]
                            )
                        }
                    )
                }
            }
        .frame(height: effectiveHeight)
    }
        .frame(height: effectiveHeight)
    }

    private var scrollGrid: some View {
        ScrollView(.vertical) {
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let contentWidth = max(0, totalWidth - timeGutterWidth)
                let dayWidth = contentWidth / 7
                let minuteHeight = hourHeight / 60
                let totalHeight = hourHeight * 24

                let dropDelegate = WeekTimeGridDropDelegate(
                    viewContext: viewContext,
                    days: days,
                    timeGutterWidth: timeGutterWidth,
                    dayWidth: dayWidth,
                    minuteHeight: minuteHeight,
                    snapMinutes: snapMinutes,
                    onMoveEvent: onMoveEvent,
                    onMoveTaskDueDate: onMoveTaskDueDate
                )

                let content = ZStack(alignment: .topLeading) {
                    gridBackground(dayWidth: dayWidth, totalHeight: totalHeight)
                    gridInteractionLayer(totalWidth: totalWidth, dayWidth: dayWidth, minuteHeight: minuteHeight, totalHeight: totalHeight)

                    nowIndicatorWeek(dayWidth: dayWidth, minuteHeight: minuteHeight)

                    if let selection {
                        let start = max(0, min(selection.startMinute, selection.currentMinute))
                        let end = min(24 * 60, max(selection.startMinute, selection.currentMinute))
                        let minEnd = min(24 * 60, start + 30)
                        let finalEnd = max(end, minEnd)

                        let selectedDay = days[min(max(selection.dayIndex, 0), days.count - 1)]
                        let selectedDayStart = Calendar.current.startOfDay(for: selectedDay)
                        let startDate = Calendar.current.date(byAdding: .minute, value: start, to: selectedDayStart) ?? selectedDayStart
                        let endDate = Calendar.current.date(byAdding: .minute, value: finalEnd, to: selectedDayStart) ?? startDate

                        let x = timeGutterWidth + CGFloat(selection.dayIndex) * dayWidth + eventPadding
                        let y = CGFloat(start) * minuteHeight
                        let w = max(0, dayWidth - eventPadding * 2)
                        let h = max(20, CGFloat(finalEnd - start) * minuteHeight)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.primary.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DesignSystem.Colors.primary.opacity(0.18), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .position(x: x + w / 2, y: y + h / 2)

                        TimeRangeTooltip(
                            text: localizedTimeRange(startDate, endDate),
                            color: DesignSystem.Colors.primary
                        )
                        .position(x: x + w / 2, y: max(14, y - 12))
                    }

                    if pillCoordinator.isAddEventPresented, let pending = pendingCreationRange {
                        let start = max(0, min(pending.startMinute, pending.currentMinute))
                        let end = min(24 * 60, max(pending.startMinute, pending.currentMinute))
                        let minEnd = min(24 * 60, start + 30)
                        let finalEnd = max(end, minEnd)

                        let x = timeGutterWidth + CGFloat(pending.dayIndex) * dayWidth + eventPadding
                        let y = CGFloat(start) * minuteHeight
                        let w = max(0, dayWidth - eventPadding * 2)
                        let h = max(20, CGFloat(finalEnd - start) * minuteHeight)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.primary.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DesignSystem.Colors.primary.opacity(0.24), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .position(x: x + w / 2, y: y + h / 2)
                            .allowsHitTesting(false)
                    }

                    if let bloom = creationBloom {
                        let start = max(0, min(bloom.startMinute, bloom.endMinute))
                        let end = min(24 * 60, max(bloom.startMinute, bloom.endMinute))
                        let minEnd = min(24 * 60, start + 30)
                        let finalEnd = max(end, minEnd)

                        let x = timeGutterWidth + CGFloat(min(max(bloom.dayIndex, 0), 6)) * dayWidth + eventPadding
                        let y = CGFloat(start) * minuteHeight
                        let w = max(0, dayWidth - eventPadding * 2)
                        let h = max(20, CGFloat(finalEnd - start) * minuteHeight)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.primary.opacity(0.18 * creationBloomPhase))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DesignSystem.Colors.primary.opacity(0.30 * creationBloomPhase), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .position(x: x + w / 2, y: y + h / 2)
                            .scaleEffect(0.90 + 0.12 * creationBloomPhase)
                            .opacity(creationBloomPhase)
                            .allowsHitTesting(false)
                    }

                    if isKeyboardCaptureEnabled && showsKeyboardFocusIndicator {
                        focusedSlotHighlight(dayWidth: dayWidth, minuteHeight: minuteHeight)
                    }

                    ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, day in
                        let laidOut = layoutTimedBlocks(for: day)
                        ForEach(laidOut, id: \.id) { item in
                            let x = timeGutterWidth + CGFloat(dayIndex) * dayWidth + eventPadding + item.xOffset(dayWidth: dayWidth, padding: eventPadding)
                            let y = CGFloat(item.startMinutes) * minuteHeight + 2
                            let h = max(CGFloat(item.durationMinutes) * minuteHeight - 4, 20)
                            Group {
                                switch item.kind {
                                case .event:
                                    EventBlockView(
                                        item: item,
                                        color: item.color,
                                        width: item.width(dayWidth: dayWidth, padding: eventPadding),
                                        height: h,
                                        currentDayIndex: dayIndex,
                                        dayCount: days.count,
                                        reduceMotion: reduceMotion,
                                        onHoverChanged: nil,
                                        onSelect: {
                                            suppressNextTapCreate = true
                                        },
                                        onTap: {
                                            suppressNextTapCreate = true
                                        },
                                        onDelete: {
                                            if reduceMotion {
                                                onDeleteEvent(item.id)
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.14)) {
                                                    onDeleteEvent(item.id)
                                                }
                                            }
                                        },
                                        onDuplicate: {
                                            onDuplicateEvent(item.id)
                                        },
                                        onMove: { dayDelta, minutesDelta in
                                            guard let start = item.originalStart, let end = item.originalEnd else { return }
                                            let calendar = Calendar.current
                                            let movedStart = calendar.date(byAdding: .day, value: dayDelta, to: start) ?? start
                                            let movedEnd = calendar.date(byAdding: .day, value: dayDelta, to: end) ?? end

                                            let snapped = (minutesDelta / snapMinutes) * snapMinutes
                                            let finalStart = calendar.date(byAdding: .minute, value: snapped, to: movedStart) ?? movedStart
                                            let finalEnd = calendar.date(byAdding: .minute, value: snapped, to: movedEnd) ?? movedEnd
                                            if reduceMotion {
                                                onMoveEvent(item.id, finalStart, finalEnd)
                                            } else {
                                                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                    onMoveEvent(item.id, finalStart, finalEnd)
                                                }
                                            }
                                        },
                                        onResize: { minutesDelta in
                                            guard let start = item.originalStart, let end = item.originalEnd else { return }
                                            let calendar = Calendar.current
                                            let snapped = (minutesDelta / snapMinutes) * snapMinutes
                                            let proposedEnd = calendar.date(byAdding: .minute, value: snapped, to: end) ?? end
                                            let minimumEnd = calendar.date(byAdding: .minute, value: snapMinutes, to: start) ?? start
                                            let finalEnd = max(proposedEnd, minimumEnd)
                                            if reduceMotion {
                                                onMoveEvent(item.id, start, finalEnd)
                                            } else {
                                                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                    onMoveEvent(item.id, start, finalEnd)
                                                }
                                            }
                                        },
                                        dayWidth: dayWidth,
                                        minuteHeight: minuteHeight,
                                        snapMinutes: snapMinutes,
                                        allowDayShift: true
                                    )
                                case .task:
                                    TaskBlockView(
                                        item: item,
                                        width: item.width(dayWidth: dayWidth, padding: eventPadding),
                                        height: h,
                                        currentDayIndex: dayIndex,
                                        dayCount: days.count,
                                        reduceMotion: reduceMotion,
                                        onHoverChanged: nil,
                                        onSelect: {
                                            suppressNextTapCreate = true
                                        },
                                        onTap: {
                                            suppressNextTapCreate = true
                                        },
                                        onDelete: {
                                            if reduceMotion {
                                                onDeleteTask(item.id)
                                            } else {
                                                withAnimation(.easeInOut(duration: 0.14)) {
                                                    onDeleteTask(item.id)
                                                }
                                            }
                                        },
                                        onMove: { dayDelta, minutesDelta in
                                            guard let start = item.originalStart else { return }
                                            let calendar = Calendar.current
                                            let movedStart = calendar.date(byAdding: .day, value: dayDelta, to: start) ?? start

                                            let snapped = (minutesDelta / snapMinutes) * snapMinutes
                                            let finalStart = calendar.date(byAdding: .minute, value: snapped, to: movedStart) ?? movedStart
                                            if reduceMotion {
                                                onMoveTaskDueDate(item.id, finalStart)
                                            } else {
                                                withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                    onMoveTaskDueDate(item.id, finalStart)
                                                }
                                            }
                                        },
                                        dayWidth: dayWidth,
                                        minuteHeight: minuteHeight,
                                        snapMinutes: snapMinutes,
                                        allowDayShift: true
                                    )
                                }
                            }
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: CalendarItemFramePreferenceKey.self,
                                            value: [item.id.uriRepresentation(): proxy.frame(in: .named("CalendarMainContent"))]
                                        )
                                }
                            )
                            .position(x: x + item.width(dayWidth: dayWidth, padding: eventPadding) / 2, y: y + h / 2)
                        }
                    }
                }

                content
                    .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
                    .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.14), value: events.count + tasks.count)
                    .onDrop(of: [UTType.text.identifier], delegate: dropDelegate)
            }
            .frame(minHeight: hourHeight * 24)
        }
    }

    private struct WeekTimeGridDropDelegate: DropDelegate {
        let viewContext: NSManagedObjectContext
        let days: [Date]
        let timeGutterWidth: CGFloat
        let dayWidth: CGFloat
        let minuteHeight: CGFloat
        let snapMinutes: Int
        let onMoveEvent: (NSManagedObjectID, Date, Date) -> Void
        let onMoveTaskDueDate: (NSManagedObjectID, Date) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [UTType.text.identifier])
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            guard let provider = info.itemProviders(for: [UTType.text.identifier]).first else {
                return false
            }

            let location = info.location
            let rawDay = Int(floor((location.x - timeGutterWidth) / max(dayWidth, 1)))
            let dayIndex = min(6, max(0, rawDay))

            let rawMinute = min(24 * 60, max(0, Int(round(location.y / max(minuteHeight, 0.0001)))))
            let snappedMinute = (rawMinute / max(snapMinutes, 1)) * max(snapMinutes, 1)

            let targetDay = days[min(max(dayIndex, 0), days.count - 1)]
            let dayStart = Calendar.current.startOfDay(for: targetDay)
            let startDate = Calendar.current.date(byAdding: .minute, value: snappedMinute, to: dayStart) ?? dayStart

            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                let str: String? = {
                    if let s = data as? String { return s }
                    if let ns = data as? NSString { return ns as String }
                    if let d = data as? Data { return String(data: d, encoding: .utf8) }
                    return nil
                }()

                guard let urlString = str?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let uri = URL(string: urlString),
                      let coordinator = viewContext.persistentStoreCoordinator,
                      let objectID = coordinator.managedObjectID(forURIRepresentation: uri)
                else {
                    return
                }

                DispatchQueue.main.async {
                    if let event = (try? viewContext.existingObject(with: objectID)) as? CalendarEventEntity,
                       let originalStart = event.startDate,
                       let originalEnd = event.endDate {
                        let duration = max(15 * 60, originalEnd.timeIntervalSince(originalStart))
                        let endDate = startDate.addingTimeInterval(duration)
                        onMoveEvent(objectID, startDate, endDate)
                    } else if let _ = (try? viewContext.existingObject(with: objectID)) as? TaskEntity {
                        onMoveTaskDueDate(objectID, startDate)
                    }
                }
            }

            return true
        }
    }

    private func gridInteractionLayer(totalWidth: CGFloat, dayWidth: CGFloat, minuteHeight: CGFloat, totalHeight: CGFloat) -> some View {
        Color.clear
            .frame(width: totalWidth, height: totalHeight)
            .contentShape(Rectangle())
            .gesture(selectionGesture(dayWidth: dayWidth, minuteHeight: minuteHeight))
            .simultaneousGesture(tapToCreateGesture(dayWidth: dayWidth, minuteHeight: minuteHeight))
    }

    private func focusedSlotHighlight(dayWidth: CGFloat, minuteHeight: CGFloat) -> some View {
        let safeDayIndex = min(max(focusedDayIndex, 0), 6)
        let slotMinutes = min(max(focusedMinute, 0), 24 * 60 - 30)

        let x = timeGutterWidth + CGFloat(safeDayIndex) * dayWidth + eventPadding
        let y = CGFloat(slotMinutes) * minuteHeight
        let w = max(0, dayWidth - eventPadding * 2)
        let h = CGFloat(30) * minuteHeight

        return RoundedRectangle(cornerRadius: 10)
            .stroke(DesignSystem.Colors.primary.opacity(0.7), lineWidth: 2)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    private func performPrimaryKeyboardAction() {
        showsKeyboardFocusIndicator = true
        if let item = laidOutItemAtFocusedSlot() {
            switch item.kind {
            case .event:
                onEditEvent(item.id)
            case .task:
                onEditTask(item.id)
            }
            return
        }
        performCreateAtFocusedSlot()
    }

    private func performDeleteAtFocusedSlot() {
        showsKeyboardFocusIndicator = true
        guard let item = laidOutItemAtFocusedSlot() else { return }
        switch item.kind {
        case .event:
            onDeleteEvent(item.id)
        case .task:
            onDeleteTask(item.id)
        }
    }

    private func performCreateAtFocusedSlot() {
        showsKeyboardFocusIndicator = true
        let safeDayIndex = min(max(focusedDayIndex, 0), 6)
        let day = days[safeDayIndex]
        let dayStart = Calendar.current.startOfDay(for: day)

        let startMinute = min(max(focusedMinute, 0), 24 * 60 - 1)
        let start = Calendar.current.date(byAdding: .minute, value: startMinute, to: dayStart) ?? dayStart
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        onCreateEvent(start, end)
    }

    private func laidOutItemAtFocusedSlot() -> LaidOutEvent? {
        let safeDayIndex = min(max(focusedDayIndex, 0), 6)
        let day = days[safeDayIndex]

        let slotStart = min(max(focusedMinute, 0), 24 * 60)
        let slotEnd = min(24 * 60, slotStart + snapMinutes)

        return layoutTimedBlocks(for: day)
            .filter { $0.startMinutes < slotEnd && ($0.startMinutes + $0.durationMinutes) > slotStart }
            .sorted { $0.startMinutes < $1.startMinutes }
            .first
    }

    private func selectionGesture(dayWidth: CGFloat, minuteHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let x = value.location.x
                let y = value.location.y

                let rawDay = Int(floor((x - timeGutterWidth) / max(dayWidth, 1)))
                let dayIndex = min(6, max(0, rawDay))

                let minute = min(24 * 60, max(0, Int(round(y / max(minuteHeight, 0.0001)))))
                let snappedMinute = (minute / snapMinutes) * snapMinutes

                if selection == nil {
                    selection = TimeSelection(dayIndex: dayIndex, startMinute: snappedMinute, currentMinute: snappedMinute)
                } else {
                    // Lock selection to initial day column to keep UX predictable.
                    selection?.currentMinute = snappedMinute
                }
            }
            .onEnded { _ in
                guard let selection else { return }

                let startMinute = min(selection.startMinute, selection.currentMinute)
                let endMinuteRaw = max(selection.startMinute, selection.currentMinute)
                let endMinute = max(endMinuteRaw, startMinute + 30)

                let day = days[min(max(selection.dayIndex, 0), days.count - 1)]
                let dayStart = Calendar.current.startOfDay(for: day)

                let start = Calendar.current.date(byAdding: .minute, value: startMinute, to: dayStart) ?? dayStart
                let end = Calendar.current.date(byAdding: .minute, value: min(endMinute, 24 * 60), to: dayStart) ?? start

                triggerCreationBloom(dayIndex: selection.dayIndex, startMinute: startMinute, endMinute: endMinute)
                pendingCreationRange = TimeSelection(dayIndex: selection.dayIndex, startMinute: startMinute, currentMinute: endMinute)
                self.selection = nil
                onCreateEvent(start, end)
            }
    }

    private func tapToCreateGesture(dayWidth: CGFloat, minuteHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                if suppressNextTapCreate {
                    suppressNextTapCreate = false
                    return
                }

                let moved = abs(value.translation.width) + abs(value.translation.height)
                let predicted = abs(value.predictedEndTranslation.width) + abs(value.predictedEndTranslation.height)
                guard moved < 6, predicted < 18 else { return }

                // Tapping the grid again while the add-menu is open should dismiss it.
                if pillCoordinator.isAddEventPresented {
                    pillCoordinator.dismissAddEvent(animated: !reduceMotion)
                    return
                }

                let x = value.location.x
                let y = value.location.y

                let rawDay = Int(floor((x - timeGutterWidth) / max(dayWidth, 1)))
                let dayIndex = min(6, max(0, rawDay))

                let minute = min(24 * 60, max(0, Int(round(y / max(minuteHeight, 0.0001)))))
                let snappedMinute = (minute / snapMinutes) * snapMinutes

                let day = days[min(max(dayIndex, 0), days.count - 1)]
                let dayStart = Calendar.current.startOfDay(for: day)
                let start = Calendar.current.date(byAdding: .minute, value: snappedMinute, to: dayStart) ?? dayStart
                let end = Calendar.current.date(byAdding: .minute, value: 60, to: start) ?? start

                triggerCreationBloom(dayIndex: dayIndex, startMinute: snappedMinute, endMinute: snappedMinute + 60)
                pendingCreationRange = TimeSelection(dayIndex: dayIndex, startMinute: snappedMinute, currentMinute: snappedMinute + 60)
                onCreateEvent(start, end)
            }
    }

    private func nowIndicatorWeek(dayWidth: CGFloat, minuteHeight: CGFloat) -> some View {
        TimelineView(.periodic(from: Date(), by: 60)) { timeline in
            let now = timeline.date
            let calendar = Calendar.current

            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, day in
                    if calendar.isDateInToday(day) {
                        let dayStart = calendar.startOfDay(for: day)
                        let minutes = max(0, min(24 * 60, Int(now.timeIntervalSince(dayStart) / 60)))
                        let y = CGFloat(minutes) * minuteHeight
                        let x0 = timeGutterWidth + CGFloat(dayIndex) * dayWidth

                        Rectangle()
                            .fill(DesignSystem.Colors.error)
                            .frame(width: max(0, dayWidth), height: 1.5)
                            .offset(x: x0, y: y)

                        Circle()
                            .fill(DesignSystem.Colors.error)
                            .frame(width: 6, height: 6)
                            .offset(x: x0 - 3, y: y - 2.25)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func gridBackground(dayWidth: CGFloat, totalHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Vertical day separators
            ForEach(0...7, id: \.self) { i in
                Rectangle()
                    .fill(Color(hex: "e2e8f0"))
                    .frame(width: 1)
                    .offset(x: timeGutterWidth + CGFloat(i) * dayWidth, y: 0)
            }

            // Horizontal hour lines + time gutter labels
            ForEach(0...24, id: \.self) { hour in
                let y = CGFloat(hour) * hourHeight
                Rectangle()
                    .fill(Color(hex: "e2e8f0"))
                    .frame(height: 1)
                    .offset(x: 0, y: y)

                if hour < 24 && hour != 0 {
                    Text(timeLabel(for: hour))
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .frame(width: timeGutterWidth - 12, alignment: .trailing)
                        .offset(x: 0, y: y - 7)
                }
            }
        }
    }

    private func timeLabel(for hour: Int) -> String {
        localizedHourLabel(hour: hour)
    }

    private func allDayEvents(for day: Date) -> [CalendarEventEntity] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return events
            .filter { $0.allDay }
            .filter { event in
                guard let start = event.startDate, let end = event.endDate else { return false }
                return start < dayEnd && end > dayStart
            }
            .sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
    }

    private func layoutTimedBlocks(for day: Date) -> [LaidOutEvent] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var sources: [LaidOutEventSource] = []

        let timedEvents = events
            .filter { !$0.allDay }
            .compactMap { event -> LaidOutEventSource? in
                guard let start = event.startDate, let end = event.endDate else { return nil }
                guard start < dayEnd && end > dayStart else { return nil }

                let continuesBefore = start < dayStart
                let continuesAfter = end > dayEnd

                let clippedStart = max(start, dayStart)
                let clippedEnd = min(end, dayEnd)
                let startMinutes = max(0, Int(clippedStart.timeIntervalSince(dayStart) / 60))
                let endMinutes = max(0, Int(clippedEnd.timeIntervalSince(dayStart) / 60))

                let color: Color = eventDisplayColor(event, calendarManager: calendarManager)

                return LaidOutEventSource(
                    id: event.objectID,
                    title: event.title ?? "Event",
                    location: event.location,
                    startMinutes: startMinutes,
                    endMinutes: max(endMinutes, startMinutes + 10),
                    continuesBefore: continuesBefore,
                    continuesAfter: continuesAfter,
                    originalStart: start,
                    originalEnd: end,
                    displayStart: clippedStart,
                    displayEnd: clippedEnd,
                    color: color,
                    kind: .event
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }

        sources.append(contentsOf: timedEvents)

        let defaultTaskDurationMinutes = 60
        let timedTasks = tasks
            .compactMap { task -> LaidOutEventSource? in
                guard let start = task.dueDate else { return nil }
                guard start >= dayStart && start < dayEnd else { return nil }

                let end = Calendar.current.date(byAdding: .minute, value: defaultTaskDurationMinutes, to: start) ?? start
                let clippedStart = max(start, dayStart)
                let clippedEnd = min(end, dayEnd)
                let startMinutes = max(0, Int(clippedStart.timeIntervalSince(dayStart) / 60))
                let endMinutes = max(0, Int(clippedEnd.timeIntervalSince(dayStart) / 60))

                return LaidOutEventSource(
                    id: task.objectID,
                    title: (task.title ?? "Task"),
                    location: task.course?.code,
                    startMinutes: startMinutes,
                    endMinutes: max(endMinutes, startMinutes + 10),
                    continuesBefore: false,
                    continuesAfter: end > dayEnd,
                    originalStart: start,
                    originalEnd: end,
                    displayStart: clippedStart,
                    displayEnd: clippedEnd,
                    color: DesignSystem.Colors.warning,
                    kind: .task
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }

        sources.append(contentsOf: timedTasks)

        return layoutOverlappingTimedEvents(sources: sources.sorted { $0.startMinutes < $1.startMinutes })
    }

    private func stableColor(for courseCode: String) -> Color {
        let normalized = courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let override = CourseColorOverrides.color(for: normalized) {
            return override
        }
        let palette: [Color] = [
            DesignSystem.Colors.primary,
            DesignSystem.Colors.secondary,
            DesignSystem.Colors.accent,
            DesignSystem.Colors.success,
            DesignSystem.Colors.warning,
            DesignSystem.Colors.info
        ]
        let value = abs(normalized.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        return palette[value % palette.count]
    }

    // Overlap layout lives in shared helper at file scope.
}

private struct DayScheduleView: View {
    let viewContext: NSManagedObjectContext
    let date: Date
    let semester: SemesterEntity?
    let events: [CalendarEventEntity]
    let tasks: [TaskEntity]
    let isKeyboardCaptureEnabled: Bool
    let onMoveEvent: (NSManagedObjectID, Date, Date) -> Void
    let onCreateEvent: (Date, Date) -> Void
    let onEditEvent: (NSManagedObjectID) -> Void
    let onEditEventFromOverflow: (NSManagedObjectID) -> Void
    let onDeleteEvent: (NSManagedObjectID) -> Void
    let onDuplicateEvent: (NSManagedObjectID) -> Void

    let onMoveTaskDueDate: (NSManagedObjectID, Date) -> Void
    let onEditTask: (NSManagedObjectID) -> Void
    let onDeleteTask: (NSManagedObjectID) -> Void

    var body: some View {
        SingleDayScheduleView(viewContext: viewContext, date: date, semester: semester, events: events, tasks: tasks, isKeyboardCaptureEnabled: isKeyboardCaptureEnabled, onMoveEvent: onMoveEvent, onCreateEvent: onCreateEvent, onEditEvent: onEditEvent, onEditEventFromOverflow: onEditEventFromOverflow, onDeleteEvent: onDeleteEvent, onDuplicateEvent: onDuplicateEvent, onMoveTaskDueDate: onMoveTaskDueDate, onEditTask: onEditTask, onDeleteTask: onDeleteTask)
    }
}

private struct SingleDayScheduleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    let viewContext: NSManagedObjectContext
    let date: Date
    let semester: SemesterEntity?
    let events: [CalendarEventEntity]
    let tasks: [TaskEntity]
    let isKeyboardCaptureEnabled: Bool
    let onMoveEvent: (NSManagedObjectID, Date, Date) -> Void
    let onCreateEvent: (Date, Date) -> Void
    let onEditEvent: (NSManagedObjectID) -> Void
    let onEditEventFromOverflow: (NSManagedObjectID) -> Void
    let onDeleteEvent: (NSManagedObjectID) -> Void
    let onDuplicateEvent: (NSManagedObjectID) -> Void

    let onMoveTaskDueDate: (NSManagedObjectID, Date) -> Void
    let onEditTask: (NSManagedObjectID) -> Void
    let onDeleteTask: (NSManagedObjectID) -> Void

    @ScaledMetric(relativeTo: .body) private var timeGutterWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var hourHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var allDayRowHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var eventPadding: CGFloat = 6
    private let snapMinutes: Int = 15

    @State private var selection: IntRangeSelection? = nil
    @State private var pendingCreationRange: IntRangeSelection? = nil
    @State private var suppressNextTapCreate: Bool = false

    @State private var creationBloom: CreationBloom? = nil
    @State private var creationBloomPhase: CGFloat = 0

    // Hover highlights intentionally disabled.

    @State private var focusedMinute: Int = 9 * 60
    @State private var isAllDayOverflowPresented: Bool = false
    @State private var showsKeyboardFocusIndicator: Bool = false
    @FocusState private var isGridFocused: Bool

    private struct IntRangeSelection {
        let startMinute: Int
        var currentMinute: Int
    }

    private struct CreationBloom: Identifiable {
        let id = UUID()
        let startMinute: Int
        let endMinute: Int
    }

    private func triggerCreationBloom(startMinute: Int, endMinute: Int) {
        guard !reduceMotion else { return }

        creationBloom = CreationBloom(
            startMinute: min(max(startMinute, 0), 24 * 60),
            endMinute: min(max(endMinute, 0), 24 * 60)
        )
        creationBloomPhase = 0

        withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
            creationBloomPhase = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.14)) {
                creationBloomPhase = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            creationBloom = nil
        }
    }

    private var day: Date {
        Calendar.current.startOfDay(for: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayRow
            Divider().overlay(Color(hex: "f1f5f9"))
            scrollGrid
        }
        .background(Color.white)
        .focusable(isKeyboardCaptureEnabled)
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onAppear {
            if isKeyboardCaptureEnabled {
                isGridFocused = true
            }
        }
        .onChange(of: isKeyboardCaptureEnabled) { _, enabled in
            if enabled {
                isGridFocused = true
            }
        }
        .onMoveCommand { direction in
            guard isKeyboardCaptureEnabled else { return }
            showsKeyboardFocusIndicator = true
            switch direction {
            case .up:
                focusedMinute = max(0, focusedMinute - snapMinutes)
            case .down:
                focusedMinute = min(24 * 60 - snapMinutes, focusedMinute + snapMinutes)
            default:
                break
            }
        }
        .overlay(keyboardActionCapture)
        .onChange(of: pillCoordinator.isAddEventPresented) { _, isPresented in
            if !isPresented {
                pendingCreationRange = nil
            }
        }
    }

    private var keyboardActionCapture: some View {
        Group {
            if isKeyboardCaptureEnabled {
                Button(action: performPrimaryKeyboardAction) { EmptyView() }
                    .keyboardShortcut(.return, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                Button(action: performCreateAtFocusedSlot) { EmptyView() }
                    .keyboardShortcut("n", modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                Button(action: performDeleteAtFocusedSlot) { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)

                Button(action: performDeleteAtFocusedSlot) { EmptyView() }
                    .keyboardShortcut(.deleteForward, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeGutterWidth, height: headerHeight)

            let isToday = Calendar.current.isDateInToday(day)
            HStack(spacing: 8) {
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                    .foregroundColor(isToday ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                
                Text(day.formatted(.dateTime.month().day()))
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(isToday ? .white : DesignSystem.Colors.textMain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isToday ? Capsule().fill(DesignSystem.Colors.primary) : nil
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: headerHeight + 8)
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(hex: "e2e8f0"))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var allDayRow: some View {
        let items = allDayEvents(for: day)
        return GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - timeGutterWidth)
            let visibleLimit = 3
            let overflow = max(0, items.count - visibleLimit)

            HStack(spacing: 0) {
                Text("all-day")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: timeGutterWidth, alignment: .trailing)
                    .padding(.trailing, 10)
                    .frame(height: allDayRowHeight)

                HStack(spacing: 6) {
                    ForEach(items.prefix(visibleLimit), id: \.objectID) { event in
                        let isPast = isPastEvent(start: event.startDate, end: event.endDate, allDay: true)
                        let badge: AllDaySpanChip.Badge = (calendarManager.googleRecurringSeriesKey(for: event) != nil) ? .recurring : .allDay
                        AllDaySpanChip(
                            objectID: event.objectID,
                            title: event.title ?? "Event",
                            badge: badge,
                            color: eventDisplayColor(event, calendarManager: calendarManager),
                            isPast: isPast,
                            pixelsPerDay: max(90, contentWidth),
                            onSelect: {
                                suppressNextTapCreate = true
                            },
                            onTap: {
                                suppressNextTapCreate = true
                            },
                            onMoveDays: { dayDelta in
                                guard dayDelta != 0, let start = event.startDate, let end = event.endDate else { return }
                                let calendar = Calendar.current
                                let movedStart = calendar.date(byAdding: .day, value: dayDelta, to: start) ?? start
                                let movedEnd = calendar.date(byAdding: .day, value: dayDelta, to: end) ?? end
                                onMoveEvent(event.objectID, movedStart, movedEnd)
                            },
                            onDelete: {
                                onDeleteEvent(event.objectID)
                            },
                            onDuplicate: {
                                onDuplicateEvent(event.objectID)
                            }
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: CalendarItemFramePreferenceKey.self,
                                    value: [event.objectID.uriRepresentation(): geo.frame(in: .named("CalendarMainContent"))]
                                )
                            }
                        )
                    }
                    if overflow > 0 {
                        Button("+\(overflow)") {
                            isAllDayOverflowPresented = true
                        }
                        .buttonStyle(PlainButtonStyle())
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                        .cornerRadius(8)
                        .popover(isPresented: $isAllDayOverflowPresented, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(day.formatted(.dateTime.weekday(.wide).month().day()))
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(items, id: \.objectID) { event in
                                        Button {
                                            suppressNextTapCreate = true
                                            isAllDayOverflowPresented = false
                                            onEditEventFromOverflow(event.objectID)
                                        } label: {
                                            HStack(spacing: 10) {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill((event.course != nil) ? stableColor(for: event.course?.code ?? "") : DesignSystem.Colors.primary)
                                                    .frame(width: 6, height: 18)

                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(event.title ?? "Event")
                                                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                                        .foregroundColor(DesignSystem.Colors.textMain)
                                                    if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        Text(location)
                                                            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                                                            .foregroundColor(DesignSystem.Colors.textLight)
                                                    }
                                                }
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 8)
                                            .background(DesignSystem.Colors.surface)
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .contextMenu {
                                            Button("Edit…") {
                                                suppressNextTapCreate = true
                                                isAllDayOverflowPresented = false
                                                onEditEventFromOverflow(event.objectID)
                                            }
                                            Button("Duplicate") {
                                                isAllDayOverflowPresented = false
                                                onDuplicateEvent(event.objectID)
                                            }
                                            Button("Delete…", role: .destructive) {
                                                isAllDayOverflowPresented = false
                                                onDeleteEvent(event.objectID)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(14)
                            .frame(minWidth: 320)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: allDayRowHeight)
            }
        }
        .frame(height: allDayRowHeight)
    }

    private var scrollGrid: some View {
        ScrollView(.vertical) {
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let minuteHeight = hourHeight / 60
                let totalHeight = hourHeight * 24
                let dayWidth = max(0, totalWidth - timeGutterWidth)

                ZStack(alignment: .topLeading) {
                    gridBackground(dayWidth: dayWidth, totalHeight: totalHeight)
                    gridInteractionLayer(totalWidth: totalWidth, minuteHeight: minuteHeight, totalHeight: totalHeight)

                    nowIndicatorDay(minuteHeight: minuteHeight, dayWidth: dayWidth)

                    if let selection {
                        let start = max(0, min(selection.startMinute, selection.currentMinute))
                        let end = min(24 * 60, max(selection.startMinute, selection.currentMinute))
                        let minEnd = min(24 * 60, start + 30)
                        let finalEnd = max(end, minEnd)

                        let dayStart = Calendar.current.startOfDay(for: day)
                        let startDate = Calendar.current.date(byAdding: .minute, value: start, to: dayStart) ?? dayStart
                        let endDate = Calendar.current.date(byAdding: .minute, value: finalEnd, to: dayStart) ?? startDate

                        let x = timeGutterWidth + eventPadding
                        let y = CGFloat(start) * minuteHeight
                        let w = max(0, dayWidth - eventPadding * 2)
                        let h = max(20, CGFloat(finalEnd - start) * minuteHeight)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.primary.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DesignSystem.Colors.primary.opacity(0.18), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .position(x: x + w / 2, y: y + h / 2)

                        TimeRangeTooltip(
                            text: localizedTimeRange(startDate, endDate),
                            color: DesignSystem.Colors.primary
                        )
                        .position(x: x + w / 2, y: max(14, y - 12))
                    }

                    if pillCoordinator.isAddEventPresented, let pending = pendingCreationRange {
                        let start = max(0, min(pending.startMinute, pending.currentMinute))
                        let end = min(24 * 60, max(pending.startMinute, pending.currentMinute))
                        let minEnd = min(24 * 60, start + 30)
                        let finalEnd = max(end, minEnd)

                        let x = timeGutterWidth + eventPadding
                        let y = CGFloat(start) * minuteHeight
                        let w = max(0, dayWidth - eventPadding * 2)
                        let h = max(20, CGFloat(finalEnd - start) * minuteHeight)

                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.primary.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DesignSystem.Colors.primary.opacity(0.24), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .position(x: x + w / 2, y: y + h / 2)
                            .allowsHitTesting(false)
                    }

                    if let bloom = creationBloom {
                        let start = max(0, min(bloom.startMinute, bloom.endMinute))
                        let end = min(24 * 60, max(bloom.startMinute, bloom.endMinute))
                        let minEnd = min(24 * 60, start + 30)
                        let finalEnd = max(end, minEnd)

                        let x = timeGutterWidth + eventPadding
                        let y = CGFloat(start) * minuteHeight
                        let w = max(0, dayWidth - eventPadding * 2)
                        let h = max(20, CGFloat(finalEnd - start) * minuteHeight)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.primary.opacity(0.18 * creationBloomPhase))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(DesignSystem.Colors.primary.opacity(0.30 * creationBloomPhase), lineWidth: 1)
                            )
                            .frame(width: w, height: h)
                            .position(x: x + w / 2, y: y + h / 2)
                            .scaleEffect(0.90 + 0.12 * creationBloomPhase)
                            .opacity(creationBloomPhase)
                            .allowsHitTesting(false)
                    }

                    if isKeyboardCaptureEnabled && showsKeyboardFocusIndicator {
                        focusedSlotHighlight(dayWidth: dayWidth, minuteHeight: minuteHeight)
                    }

                    let laidOut = layoutTimedBlocks(for: day)
                    ForEach(laidOut, id: \.id) { item in
                        let x = timeGutterWidth + eventPadding + item.xOffset(dayWidth: dayWidth, padding: eventPadding)
                        let y = CGFloat(item.startMinutes) * minuteHeight + 2
                        let h = max(CGFloat(item.durationMinutes) * minuteHeight - 4, 20)

                        Group {
                            switch item.kind {
                            case .event:
                                EventBlockView(
                                    item: item,
                                    color: item.color,
                                    width: item.width(dayWidth: dayWidth, padding: eventPadding),
                                    height: h,
                                    currentDayIndex: 0,
                                    dayCount: 1,
                                    reduceMotion: reduceMotion,
                                    onHoverChanged: nil,
                                    onSelect: {
                                        suppressNextTapCreate = true
                                    },
                                    onTap: {
                                        suppressNextTapCreate = true
                                    },
                                    onDelete: {
                                        if reduceMotion {
                                            onDeleteEvent(item.id)
                                        } else {
                                            withAnimation(.easeInOut(duration: 0.14)) {
                                                onDeleteEvent(item.id)
                                            }
                                        }
                                    },
                                    onDuplicate: {
                                        onDuplicateEvent(item.id)
                                    },
                                    onMove: { _, minutesDelta in
                                        guard let start = item.originalStart, let end = item.originalEnd else { return }
                                        let snapped = (minutesDelta / snapMinutes) * snapMinutes
                                        let calendar = Calendar.current
                                        let finalStart = calendar.date(byAdding: .minute, value: snapped, to: start) ?? start
                                        let finalEnd = calendar.date(byAdding: .minute, value: snapped, to: end) ?? end
                                        if reduceMotion {
                                            onMoveEvent(item.id, finalStart, finalEnd)
                                        } else {
                                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                onMoveEvent(item.id, finalStart, finalEnd)
                                            }
                                        }
                                    },
                                    onResize: { minutesDelta in
                                        guard let start = item.originalStart, let end = item.originalEnd else { return }
                                        let calendar = Calendar.current
                                        let snapped = (minutesDelta / snapMinutes) * snapMinutes
                                        let proposedEnd = calendar.date(byAdding: .minute, value: snapped, to: end) ?? end
                                        let minimumEnd = calendar.date(byAdding: .minute, value: snapMinutes, to: start) ?? start
                                        let finalEnd = max(proposedEnd, minimumEnd)
                                        if reduceMotion {
                                            onMoveEvent(item.id, start, finalEnd)
                                        } else {
                                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                onMoveEvent(item.id, start, finalEnd)
                                            }
                                        }
                                    },
                                    dayWidth: dayWidth,
                                    minuteHeight: minuteHeight,
                                    snapMinutes: snapMinutes,
                                    allowDayShift: false
                                )
                            case .task:
                                TaskBlockView(
                                    item: item,
                                    width: item.width(dayWidth: dayWidth, padding: eventPadding),
                                    height: h,
                                    currentDayIndex: 0,
                                    dayCount: 1,
                                    reduceMotion: reduceMotion,
                                    onHoverChanged: nil,
                                    onSelect: {
                                        suppressNextTapCreate = true
                                    },
                                    onTap: {
                                        suppressNextTapCreate = true
                                    },
                                    onDelete: {
                                        if reduceMotion {
                                            onDeleteTask(item.id)
                                        } else {
                                            withAnimation(.easeInOut(duration: 0.14)) {
                                                onDeleteTask(item.id)
                                            }
                                        }
                                    },
                                    onMove: { _, minutesDelta in
                                        guard let start = item.originalStart else { return }
                                        let snapped = (minutesDelta / snapMinutes) * snapMinutes
                                        let calendar = Calendar.current
                                        let finalStart = calendar.date(byAdding: .minute, value: snapped, to: start) ?? start
                                        if reduceMotion {
                                            onMoveTaskDueDate(item.id, finalStart)
                                        } else {
                                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                                onMoveTaskDueDate(item.id, finalStart)
                                            }
                                        }
                                    },
                                    dayWidth: dayWidth,
                                    minuteHeight: minuteHeight,
                                    snapMinutes: snapMinutes,
                                    allowDayShift: false
                                )
                            }
                        }
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(
                                        key: CalendarItemFramePreferenceKey.self,
                                        value: [item.id.uriRepresentation(): proxy.frame(in: .named("CalendarMainContent"))]
                                    )
                            }
                        )
                        .position(x: x + item.width(dayWidth: dayWidth, padding: eventPadding) / 2, y: y + h / 2)
                    }
                }
                .frame(width: totalWidth, height: totalHeight)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: events.count + tasks.count)
                .onDrop(
                    of: [UTType.text.identifier],
                    delegate: DayTimeGridDropDelegate(
                        viewContext: viewContext,
                        day: day,
                        timeGutterWidth: timeGutterWidth,
                        minuteHeight: minuteHeight,
                        snapMinutes: snapMinutes,
                        onMoveEvent: onMoveEvent,
                        onMoveTaskDueDate: onMoveTaskDueDate
                    )
                )
            }
            .frame(height: hourHeight * 24)
        }
    }

    private struct DayTimeGridDropDelegate: DropDelegate {
        let viewContext: NSManagedObjectContext
        let day: Date
        let timeGutterWidth: CGFloat
        let minuteHeight: CGFloat
        let snapMinutes: Int
        let onMoveEvent: (NSManagedObjectID, Date, Date) -> Void
        let onMoveTaskDueDate: (NSManagedObjectID, Date) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [UTType.text.identifier])
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            guard let provider = info.itemProviders(for: [UTType.text.identifier]).first else {
                return false
            }

            let location = info.location
            // Ignore X; only use Y to set the time.
            let rawMinute = min(24 * 60, max(0, Int(round(location.y / max(minuteHeight, 0.0001)))))
            let snappedMinute = (rawMinute / max(snapMinutes, 1)) * max(snapMinutes, 1)

            let dayStart = Calendar.current.startOfDay(for: day)
            let startDate = Calendar.current.date(byAdding: .minute, value: snappedMinute, to: dayStart) ?? dayStart

            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                let str: String? = {
                    if let s = data as? String { return s }
                    if let ns = data as? NSString { return ns as String }
                    if let d = data as? Data { return String(data: d, encoding: .utf8) }
                    return nil
                }()

                guard let urlString = str?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let uri = URL(string: urlString),
                      let coordinator = viewContext.persistentStoreCoordinator,
                      let objectID = coordinator.managedObjectID(forURIRepresentation: uri)
                else {
                    return
                }

                DispatchQueue.main.async {
                    if let event = (try? viewContext.existingObject(with: objectID)) as? CalendarEventEntity,
                       let originalStart = event.startDate,
                       let originalEnd = event.endDate {
                        let duration = max(15 * 60, originalEnd.timeIntervalSince(originalStart))
                        let endDate = startDate.addingTimeInterval(duration)
                        onMoveEvent(objectID, startDate, endDate)
                    } else if let _ = (try? viewContext.existingObject(with: objectID)) as? TaskEntity {
                        onMoveTaskDueDate(objectID, startDate)
                    }
                }
            }

            return true
        }
    }

    private func gridInteractionLayer(totalWidth: CGFloat, minuteHeight: CGFloat, totalHeight: CGFloat) -> some View {
        Color.clear
            .frame(width: totalWidth, height: totalHeight)
            .contentShape(Rectangle())
            .gesture(selectionGesture(minuteHeight: minuteHeight))
            .simultaneousGesture(tapToCreateGesture(minuteHeight: minuteHeight))
    }

    private func focusedSlotHighlight(dayWidth: CGFloat, minuteHeight: CGFloat) -> some View {
        let slotMinutes = min(max(focusedMinute, 0), 24 * 60 - 30)
        let x = timeGutterWidth + eventPadding
        let y = CGFloat(slotMinutes) * minuteHeight
        let w = max(0, dayWidth - eventPadding * 2)
        let h = CGFloat(30) * minuteHeight

        return RoundedRectangle(cornerRadius: 10)
            .stroke(DesignSystem.Colors.primary.opacity(0.7), lineWidth: 2)
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    private func performPrimaryKeyboardAction() {
        showsKeyboardFocusIndicator = true
        if let item = laidOutItemAtFocusedSlot() {
            switch item.kind {
            case .event:
                onEditEvent(item.id)
            case .task:
                onEditTask(item.id)
            }
            return
        }
        performCreateAtFocusedSlot()
    }

    private func performDeleteAtFocusedSlot() {
        showsKeyboardFocusIndicator = true
        guard let item = laidOutItemAtFocusedSlot() else { return }
        switch item.kind {
        case .event:
            onDeleteEvent(item.id)
        case .task:
            onDeleteTask(item.id)
        }
    }

    private func performCreateAtFocusedSlot() {
        showsKeyboardFocusIndicator = true
        let dayStart = Calendar.current.startOfDay(for: day)
        let startMinute = min(max(focusedMinute, 0), 24 * 60 - 1)
        let start = Calendar.current.date(byAdding: .minute, value: startMinute, to: dayStart) ?? dayStart
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        onCreateEvent(start, end)
    }

    private func laidOutItemAtFocusedSlot() -> LaidOutEvent? {
        let slotStart = min(max(focusedMinute, 0), 24 * 60)
        let slotEnd = min(24 * 60, slotStart + snapMinutes)

        return layoutTimedBlocks(for: day)
            .filter { $0.startMinutes < slotEnd && ($0.startMinutes + $0.durationMinutes) > slotStart }
            .sorted { $0.startMinutes < $1.startMinutes }
            .first
    }

    private func selectionGesture(minuteHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let minute = min(24 * 60, max(0, Int(round(value.location.y / max(minuteHeight, 0.0001)))))
                let snappedMinute = (minute / snapMinutes) * snapMinutes
                if selection == nil {
                    selection = IntRangeSelection(startMinute: snappedMinute, currentMinute: snappedMinute)
                } else {
                    selection?.currentMinute = snappedMinute
                }
            }
            .onEnded { _ in
                guard let selection else { return }

                let startMinute = min(selection.startMinute, selection.currentMinute)
                let endMinuteRaw = max(selection.startMinute, selection.currentMinute)
                let endMinute = max(endMinuteRaw, startMinute + 30)

                let dayStart = Calendar.current.startOfDay(for: day)
                let start = Calendar.current.date(byAdding: .minute, value: startMinute, to: dayStart) ?? dayStart
                let end = Calendar.current.date(byAdding: .minute, value: min(endMinute, 24 * 60), to: dayStart) ?? start

                triggerCreationBloom(startMinute: startMinute, endMinute: endMinute)
                pendingCreationRange = IntRangeSelection(startMinute: startMinute, currentMinute: endMinute)
                self.selection = nil
                onCreateEvent(start, end)
            }
    }

    private func tapToCreateGesture(minuteHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                if suppressNextTapCreate {
                    suppressNextTapCreate = false
                    return
                }

                let moved = abs(value.translation.width) + abs(value.translation.height)
                let predicted = abs(value.predictedEndTranslation.width) + abs(value.predictedEndTranslation.height)
                guard moved < 6, predicted < 18 else { return }

                // Tapping the grid again while the add-menu is open should dismiss it.
                if pillCoordinator.isAddEventPresented {
                    pillCoordinator.dismissAddEvent(animated: !reduceMotion)
                    return
                }

                let y = value.location.y
                let minute = min(24 * 60, max(0, Int(round(y / max(minuteHeight, 0.0001)))))
                let snappedMinute = (minute / snapMinutes) * snapMinutes

                let dayStart = Calendar.current.startOfDay(for: day)
                let start = Calendar.current.date(byAdding: .minute, value: snappedMinute, to: dayStart) ?? dayStart
                let end = Calendar.current.date(byAdding: .minute, value: 60, to: start) ?? start

                triggerCreationBloom(startMinute: snappedMinute, endMinute: snappedMinute + 60)
                pendingCreationRange = IntRangeSelection(startMinute: snappedMinute, currentMinute: snappedMinute + 60)
                onCreateEvent(start, end)
            }
    }

    private func nowIndicatorDay(minuteHeight: CGFloat, dayWidth: CGFloat) -> some View {
        TimelineView(.periodic(from: Date(), by: 60)) { timeline in
            let now = timeline.date
            let calendar = Calendar.current
            if calendar.isDateInToday(day) {
                let dayStart = calendar.startOfDay(for: day)
                let minutes = max(0, min(24 * 60, Int(now.timeIntervalSince(dayStart) / 60)))
                let y = CGFloat(minutes) * minuteHeight

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(DesignSystem.Colors.error)
                        .frame(width: timeGutterWidth + max(0, dayWidth), height: 1.5)
                        .offset(x: 0, y: y)
                    Circle()
                        .fill(DesignSystem.Colors.error)
                        .frame(width: 6, height: 6)
                        .offset(x: timeGutterWidth - 3, y: y - 2.25)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func gridBackground(dayWidth: CGFloat, totalHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: timeGutterWidth + dayWidth, height: totalHeight)

            Rectangle()
                .fill(Color(hex: "e2e8f0"))
                .frame(width: 1)
                .offset(x: timeGutterWidth, y: 0)

            ForEach(0...24, id: \.self) { hour in
                let y = CGFloat(hour) * hourHeight
                Rectangle()
                    .fill(Color(hex: "e2e8f0"))
                    .frame(height: 1)
                    .offset(x: 0, y: y)

                if hour < 24 && hour != 0 {
                    Text(timeLabel(for: hour))
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .frame(width: timeGutterWidth - 12, alignment: .trailing)
                        .offset(x: 0, y: y - 7)
                }
            }
        }
    }

    private func timeLabel(for hour: Int) -> String {
        localizedHourLabel(hour: hour)
    }

    private func allDayEvents(for day: Date) -> [CalendarEventEntity] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return events
            .filter { $0.allDay }
            .filter { event in
                guard let start = event.startDate, let end = event.endDate else { return false }
                return start < dayEnd && end > dayStart
            }
            .sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
    }

    private func layoutTimedBlocks(for day: Date) -> [LaidOutEvent] {
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var sources: [LaidOutEventSource] = []

        let timedEvents = events
            .filter { !$0.allDay }
            .compactMap { event -> LaidOutEventSource? in
                guard let start = event.startDate, let end = event.endDate else { return nil }
                guard start < dayEnd && end > dayStart else { return nil }

                let continuesBefore = start < dayStart
                let continuesAfter = end > dayEnd

                let clippedStart = max(start, dayStart)
                let clippedEnd = min(end, dayEnd)
                let startMinutes = max(0, Int(clippedStart.timeIntervalSince(dayStart) / 60))
                let endMinutes = max(0, Int(clippedEnd.timeIntervalSince(dayStart) / 60))

                let color: Color = eventDisplayColor(event, calendarManager: calendarManager)

                return LaidOutEventSource(
                    id: event.objectID,
                    title: event.title ?? "Event",
                    location: event.location,
                    startMinutes: startMinutes,
                    endMinutes: max(endMinutes, startMinutes + 10),
                    continuesBefore: continuesBefore,
                    continuesAfter: continuesAfter,
                    originalStart: start,
                    originalEnd: end,
                    displayStart: clippedStart,
                    displayEnd: clippedEnd,
                    color: color,
                    kind: .event
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }

        sources.append(contentsOf: timedEvents)

        let defaultTaskDurationMinutes = 60
        let timedTasks = tasks
            .compactMap { task -> LaidOutEventSource? in
                guard let start = task.dueDate else { return nil }
                guard start >= dayStart && start < dayEnd else { return nil }

                let end = Calendar.current.date(byAdding: .minute, value: defaultTaskDurationMinutes, to: start) ?? start
                let clippedStart = max(start, dayStart)
                let clippedEnd = min(end, dayEnd)
                let startMinutes = max(0, Int(clippedStart.timeIntervalSince(dayStart) / 60))
                let endMinutes = max(0, Int(clippedEnd.timeIntervalSince(dayStart) / 60))

                return LaidOutEventSource(
                    id: task.objectID,
                    title: (task.title ?? "Task"),
                    location: task.course?.code,
                    startMinutes: startMinutes,
                    endMinutes: max(endMinutes, startMinutes + 10),
                    continuesBefore: false,
                    continuesAfter: end > dayEnd,
                    originalStart: start,
                    originalEnd: end,
                    displayStart: clippedStart,
                    displayEnd: clippedEnd,
                    color: DesignSystem.Colors.warning,
                    kind: .task
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }

        sources.append(contentsOf: timedTasks)

        return layoutOverlappingTimedEvents(sources: sources.sorted { $0.startMinutes < $1.startMinutes })
    }

    private func stableColor(for courseCode: String) -> Color {
        let normalized = courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let override = CourseColorOverrides.color(for: normalized) {
            return override
        }
        let palette: [Color] = [
            DesignSystem.Colors.primary,
            DesignSystem.Colors.secondary,
            DesignSystem.Colors.accent,
            DesignSystem.Colors.success,
            DesignSystem.Colors.warning,
            DesignSystem.Colors.info
        ]
        let value = abs(normalized.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        return palette[value % palette.count]
    }

    // Overlap layout lives in shared helper at file scope.
}

private enum CalendarBlockKind {
    case event
    case task
}

private struct LaidOutEventSource {
    let id: NSManagedObjectID
    let title: String
    let location: String?
    let startMinutes: Int
    let endMinutes: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
    let originalStart: Date
    let originalEnd: Date
    let displayStart: Date
    let displayEnd: Date
    let color: Color
    let kind: CalendarBlockKind
}

private struct LaidOutEvent {
    let id: NSManagedObjectID
    let title: String
    let location: String?
    let startMinutes: Int
    let durationMinutes: Int
    let column: Int
    var columnCount: Int
    let continuesBefore: Bool
    let continuesAfter: Bool
    let originalStart: Date?
    let originalEnd: Date?
    let displayStart: Date?
    let displayEnd: Date?
    let color: Color
    let kind: CalendarBlockKind

    func width(dayWidth: CGFloat, padding: CGFloat) -> CGFloat {
        let available = max(0, dayWidth - padding * 2)
        return available / CGFloat(max(columnCount, 1))
    }

    func xOffset(dayWidth: CGFloat, padding: CGFloat) -> CGFloat {
        width(dayWidth: dayWidth, padding: padding) * CGFloat(column)
    }
}

fileprivate func layoutOverlappingTimedEvents(sources: [LaidOutEventSource]) -> [LaidOutEvent] {
    // Interval layout: assign columns by first-fit; set columnCount to max columns in each collision group.
    // Shorter events are indented by placing them in higher column numbers.
    var result: [LaidOutEvent] = []
    var active: [(source: LaidOutEventSource, column: Int)] = []
    var group: [LaidOutEventSource] = []
    var groupMaxColumns: Int = 1

    func flushGroup() {
        guard !group.isEmpty else { return }
        
        // Sort group by duration (longest first) - longest events stay in column 0, shorter events get indented (higher columns)
        let sortedByDuration = group.sorted { ($0.endMinutes - $0.startMinutes) > ($1.endMinutes - $1.startMinutes) }
        
        // Create mapping: source -> new column based on duration (shorter = higher column = more indented)
        var sourceToNewColumn: [NSManagedObjectID: Int] = [:]
        var durationToColumn: [Int: Int] = [:]
        var currentColumn = 0
        
        for source in sortedByDuration {
            let duration = source.endMinutes - source.startMinutes
            // Assign column based on unique durations (longest duration gets column 0, next longest gets 1, etc.)
            if durationToColumn[duration] == nil {
                durationToColumn[duration] = currentColumn
                currentColumn += 1
            }
            sourceToNewColumn[source.id] = durationToColumn[duration] ?? 0
        }
        
        // Update result with new column assignments (shorter events indented)
        for i in result.indices {
            if let source = group.first(where: { $0.id == result[i].id }),
               let newCol = sourceToNewColumn[source.id] {
                result[i] = LaidOutEvent(
                    id: result[i].id,
                    title: result[i].title,
                    location: result[i].location,
                    startMinutes: result[i].startMinutes,
                    durationMinutes: result[i].durationMinutes,
                    column: newCol,
                    columnCount: groupMaxColumns,
                    continuesBefore: result[i].continuesBefore,
                    continuesAfter: result[i].continuesAfter,
                    originalStart: result[i].originalStart,
                    originalEnd: result[i].originalEnd,
                    displayStart: result[i].displayStart,
                    displayEnd: result[i].displayEnd,
                    color: result[i].color,
                    kind: result[i].kind
                )
            } else {
                // Update columnCount for all items in group
                result[i] = LaidOutEvent(
                    id: result[i].id,
                    title: result[i].title,
                    location: result[i].location,
                    startMinutes: result[i].startMinutes,
                    durationMinutes: result[i].durationMinutes,
                    column: result[i].column,
                    columnCount: groupMaxColumns,
                    continuesBefore: result[i].continuesBefore,
                    continuesAfter: result[i].continuesAfter,
                    originalStart: result[i].originalStart,
                    originalEnd: result[i].originalEnd,
                    displayStart: result[i].displayStart,
                    displayEnd: result[i].displayEnd,
                    color: result[i].color,
                    kind: result[i].kind
                )
            }
        }
        
        group.removeAll()
        groupMaxColumns = 1
    }

    for source in sources {
        active.removeAll { item in
            item.source.endMinutes <= source.startMinutes
        }

        if active.isEmpty {
            flushGroup()
        }

        let used = Set(active.map { $0.column })
        var col = 0
        while used.contains(col) { col += 1 }

        active.append((source, col))
        group.append(source)

        let maxColumnIndex = active.map { $0.column }.max() ?? 0
        groupMaxColumns = max(groupMaxColumns, maxColumnIndex + 1)

        result.append(
            LaidOutEvent(
                id: source.id,
                title: source.title,
                location: source.location,
                startMinutes: source.startMinutes,
                durationMinutes: max(10, source.endMinutes - source.startMinutes),
                column: col,
                columnCount: 1,
                continuesBefore: source.continuesBefore,
                continuesAfter: source.continuesAfter,
                originalStart: source.originalStart,
                originalEnd: source.originalEnd,
                displayStart: source.displayStart,
                displayEnd: source.displayEnd,
                color: source.color,
                kind: source.kind
            )
        )
    }

    flushGroup()
    return result
}

private struct EventBlockView: View {
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var modalCoordinator: ModalCoordinator

    let item: LaidOutEvent
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let currentDayIndex: Int
    let dayCount: Int
    let reduceMotion: Bool
    let onHoverChanged: ((Bool) -> Void)?
    let onSelect: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onMove: (_ dayDelta: Int, _ minutesDelta: Int) -> Void
    let onResize: (_ minutesDelta: Int) -> Void
    let dayWidth: CGFloat
    let minuteHeight: CGFloat
    let snapMinutes: Int
    let allowDayShift: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var resizeOffset: CGSize = .zero

    @State private var isHovered: Bool = false

    private static func rubberBand(_ delta: CGFloat, bandLength: CGFloat) -> CGFloat {
        guard bandLength > 0 else { return 0 }
        return (bandLength * delta) / (bandLength + abs(delta))
    }

    private var dayDeltaBounds: ClosedRange<Int> {
        guard allowDayShift else { return 0...0 }
        let minDelta = -max(0, currentDayIndex)
        let maxDelta = max(0, (dayCount - 1) - currentDayIndex)
        return minDelta...maxDelta
    }

    private var minutesDeltaBounds: ClosedRange<Int> {
        let duration = min(24 * 60, max(max(snapMinutes, 1), item.durationMinutes))
        let minDelta = -max(0, item.startMinutes)
        let maxDelta = max(0, (24 * 60 - duration) - item.startMinutes)
        return minDelta...maxDelta
    }

    private var snappedDragMinutesDelta: Int {
        let raw = Int(round(dragOffset.height / max(minuteHeight, 0.0001)))
        let snapped = (raw / max(snapMinutes, 1)) * snapMinutes
        return min(max(snapped, minutesDeltaBounds.lowerBound), minutesDeltaBounds.upperBound)
    }

    private var snappedResizeMinutesDelta: Int {
        let raw = Int(round(resizeOffset.height / max(minuteHeight, 0.0001)))
        return (raw / max(snapMinutes, 1)) * snapMinutes
    }

    private var snappedDayDelta: Int {
        guard allowDayShift else { return 0 }
        let raw = Int(round(dragOffset.width / max(dayWidth, 1)))
        return min(max(raw, dayDeltaBounds.lowerBound), dayDeltaBounds.upperBound)
    }

    private var destinationOffset: CGSize {
        CGSize(
            width: CGFloat(snappedDayDelta) * dayWidth,
            height: CGFloat(snappedDragMinutesDelta) * minuteHeight
        )
    }

    private var dragTimePreview: String? {
        guard abs(dragOffset.width) + abs(dragOffset.height) > 1 else { return nil }
        guard let start = item.originalStart, let end = item.originalEnd else { return nil }

        let calendar = Calendar.current
        let movedStartDay = calendar.date(byAdding: .day, value: snappedDayDelta, to: start) ?? start
        let movedEndDay = calendar.date(byAdding: .day, value: snappedDayDelta, to: end) ?? end
        let movedStart = calendar.date(byAdding: .minute, value: snappedDragMinutesDelta, to: movedStartDay) ?? movedStartDay
        let movedEnd = calendar.date(byAdding: .minute, value: snappedDragMinutesDelta, to: movedEndDay) ?? movedEndDay
        return localizedTimeRange(movedStart, movedEnd)
    }

    private var resizeTimePreview: String? {
        guard abs(resizeOffset.height) > 1 else { return nil }
        guard let start = item.originalStart, let end = item.originalEnd else { return nil }

        let calendar = Calendar.current
        let proposedEnd = calendar.date(byAdding: .minute, value: snappedResizeMinutesDelta, to: end) ?? end
        let minimumEnd = calendar.date(byAdding: .minute, value: max(snapMinutes, 1), to: start) ?? start
        let finalEnd = max(proposedEnd, minimumEnd)
        return localizedTimeRange(start, finalEnd)
    }

    var body: some View {
        let isPast = isPastEvent(start: item.originalStart, end: item.originalEnd, allDay: false)
        let effectiveColor: Color = isPast ? DesignSystem.Colors.textLight : color
        let isInteracting = abs(dragOffset.width) + abs(dragOffset.height) + abs(resizeOffset.width) + abs(resizeOffset.height) > 1
        let hoverLift = (isHovered && !isInteracting) ? -2.0 : 0.0

        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .lineLimit(1)
            if let start = item.displayStart, let end = item.displayEnd {
                Text(localizedTimeRange(start, end))
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(effectiveColor.opacity(0.25), lineWidth: 1)
                )
        )
        .overlay(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(effectiveColor)
                    .frame(width: 3)
                Spacer(minLength: 0)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((isHovered && !isInteracting) ? effectiveColor.opacity(0.30) : effectiveColor.opacity(0.18), lineWidth: (isHovered && !isInteracting) ? 1.25 : 1)
        )
        .overlay {
            if abs(dragOffset.width) + abs(dragOffset.height) > 1 {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        effectiveColor.opacity(0.30),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [4, 3])
                    )
                    .background(effectiveColor.opacity(0.04))
                    .cornerRadius(10)
                    .offset(
                        x: destinationOffset.width - dragOffset.width,
                        y: destinationOffset.height - dragOffset.height
                    )
                    .allowsHitTesting(false)
                    .opacity(reduceMotion ? 0 : 1)
            }
        }
        .overlay(alignment: .leading) {
            VStack(spacing: 0) {
                if item.continuesBefore {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .padding(.top, 6)
                } else {
                    Color.clear.frame(height: 0)
                }

                Spacer(minLength: 0)

                if item.continuesAfter {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .padding(.bottom, 20)
                }
            }
            .frame(width: 18)
        }
        .overlay(alignment: .bottom) {
            ZStack {
                Capsule()
                    .fill(effectiveColor.opacity(isHovered ? 0.75 : 0.35))
                    .frame(width: 24, height: isHovered ? 4 : 3)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        resizeOffset = value.translation
                    }
                    .onEnded { value in
                        let minutesDelta = Int(round(value.translation.height / max(minuteHeight, 0.0001)))
                        onResize(minutesDelta)

                        if reduceMotion {
                            resizeOffset = .zero
                        } else {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                resizeOffset = .zero
                            }
                        }
                    }
            )
        }
        .overlay(alignment: .topTrailing) {
            if let preview = resizeTimePreview {
                TimeRangeTooltip(text: preview, color: effectiveColor)
                    .padding(6)
            } else if let preview = dragTimePreview {
                TimeRangeTooltip(text: preview, color: effectiveColor)
                    .padding(6)
            }
        }
        .cornerRadius(10)
        .offset(x: dragOffset.width, y: dragOffset.height + hoverLift)
        .scaleEffect((isHovered && !isInteracting) ? 1.01 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged?(hovering)
        }
        .highPriorityGesture(
            TapGesture(count: 1)
                .onEnded {
                    onSelect()
                    pillCoordinator.selectEvent(objectID: item.id, animated: !reduceMotion)
                }
        )
        .onTapGesture(count: 2) {
            onTap()
            modalCoordinator.activeModal = .editCalendarItem(objectID: item.id)
        }
        .contextMenu {
            Button("Edit…") {
                onTap()
                modalCoordinator.activeModal = .editCalendarItem(objectID: item.id)
            }
            Button("Duplicate") { onDuplicate() }
            Button("Delete…", role: .destructive) { onDelete() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let rawX = value.translation.width
                    let rawY = value.translation.height

                    let minDayX = CGFloat(dayDeltaBounds.lowerBound) * dayWidth
                    let maxDayX = CGFloat(dayDeltaBounds.upperBound) * dayWidth
                    let clampedX = min(max(rawX, minDayX), maxDayX)
                    let overshootX = rawX - clampedX
                    let bandedX = clampedX + Self.rubberBand(overshootX, bandLength: 56)

                    let minMinY = CGFloat(minutesDeltaBounds.lowerBound) * minuteHeight
                    let maxMinY = CGFloat(minutesDeltaBounds.upperBound) * minuteHeight
                    let clampedY = min(max(rawY, minMinY), maxMinY)
                    let overshootY = rawY - clampedY
                    let bandedY = clampedY + Self.rubberBand(overshootY, bandLength: 96)

                    dragOffset = CGSize(width: bandedX, height: bandedY)
                }
                .onEnded { value in
                    let rawDayDelta = Int(round(value.translation.width / max(dayWidth, 1)))
                    let rawMinutesDelta = Int(round(value.translation.height / max(minuteHeight, 0.0001)))
                    let snappedMinutesDelta = (rawMinutesDelta / max(snapMinutes, 1)) * snapMinutes

                    let clampedDayDelta = min(max(rawDayDelta, dayDeltaBounds.lowerBound), dayDeltaBounds.upperBound)
                    let clampedMinutesDelta = min(max(snappedMinutesDelta, minutesDeltaBounds.lowerBound), minutesDeltaBounds.upperBound)

                    onMove(clampedDayDelta, clampedMinutesDelta)

                    if reduceMotion {
                        dragOffset = .zero
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }
}

private struct TaskBlockView: View {
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var modalCoordinator: ModalCoordinator

    let item: LaidOutEvent
    let width: CGFloat
    let height: CGFloat
    let currentDayIndex: Int
    let dayCount: Int
    let reduceMotion: Bool
    let onHoverChanged: ((Bool) -> Void)?
    let onSelect: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onMove: (_ dayDelta: Int, _ minutesDelta: Int) -> Void
    let dayWidth: CGFloat
    let minuteHeight: CGFloat
    let snapMinutes: Int
    let allowDayShift: Bool

    @State private var dragOffset: CGSize = .zero
    @State private var isHovered: Bool = false

    private static func rubberBand(_ delta: CGFloat, bandLength: CGFloat) -> CGFloat {
        guard bandLength > 0 else { return 0 }
        return (bandLength * delta) / (bandLength + abs(delta))
    }

    private var dayDeltaBounds: ClosedRange<Int> {
        guard allowDayShift else { return 0...0 }
        let minDelta = -max(0, currentDayIndex)
        let maxDelta = max(0, (dayCount - 1) - currentDayIndex)
        return minDelta...maxDelta
    }

    private var minutesDeltaBounds: ClosedRange<Int> {
        let duration = min(24 * 60, max(max(snapMinutes, 1), item.durationMinutes))
        let minDelta = -max(0, item.startMinutes)
        let maxDelta = max(0, (24 * 60 - duration) - item.startMinutes)
        return minDelta...maxDelta
    }

    private var snappedDragMinutesDelta: Int {
        let raw = Int(round(dragOffset.height / max(minuteHeight, 0.0001)))
        let snapped = (raw / max(snapMinutes, 1)) * snapMinutes
        return min(max(snapped, minutesDeltaBounds.lowerBound), minutesDeltaBounds.upperBound)
    }

    private var snappedDayDelta: Int {
        guard allowDayShift else { return 0 }
        let raw = Int(round(dragOffset.width / max(dayWidth, 1)))
        return min(max(raw, dayDeltaBounds.lowerBound), dayDeltaBounds.upperBound)
    }

    private var destinationOffset: CGSize {
        CGSize(
            width: CGFloat(snappedDayDelta) * dayWidth,
            height: CGFloat(snappedDragMinutesDelta) * minuteHeight
        )
    }

    private var dragTimePreview: String? {
        guard abs(dragOffset.width) + abs(dragOffset.height) > 1 else { return nil }
        guard let start = item.originalStart, let end = item.originalEnd else { return nil }

        let calendar = Calendar.current
        let movedStartDay = calendar.date(byAdding: .day, value: snappedDayDelta, to: start) ?? start
        let movedEndDay = calendar.date(byAdding: .day, value: snappedDayDelta, to: end) ?? end
        let movedStart = calendar.date(byAdding: .minute, value: snappedDragMinutesDelta, to: movedStartDay) ?? movedStartDay
        let movedEnd = calendar.date(byAdding: .minute, value: snappedDragMinutesDelta, to: movedEndDay) ?? movedEndDay
        return localizedTimeRange(movedStart, movedEnd)
    }

    var body: some View {
        let isPast = (item.originalEnd ?? item.originalStart ?? Date()) < Date()
        let baseColor: Color = DesignSystem.Colors.warning
        let effectiveColor: Color = isPast ? DesignSystem.Colors.textLight : baseColor
        let isInteracting = abs(dragOffset.width) + abs(dragOffset.height) > 1
        let hoverLift = (isHovered && !isInteracting) ? -2.0 : 0.0

        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                .foregroundColor(effectiveColor)
                .lineLimit(1)

            if let start = item.displayStart, let end = item.displayEnd {
                Text(localizedTimeRange(start, end))
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(effectiveColor.opacity(0.25), lineWidth: 1)
                )
        )
        .overlay(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(effectiveColor)
                    .frame(width: 3)
                Spacer(minLength: 0)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((isHovered && !isInteracting) ? effectiveColor.opacity(0.30) : effectiveColor.opacity(0.18), lineWidth: (isHovered && !isInteracting) ? 1.25 : 1)
        )
        .overlay {
            if abs(dragOffset.width) + abs(dragOffset.height) > 1 {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        effectiveColor.opacity(0.30),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [4, 3])
                    )
                    .background(effectiveColor.opacity(0.03))
                    .cornerRadius(10)
                    .offset(
                        x: destinationOffset.width - dragOffset.width,
                        y: destinationOffset.height - dragOffset.height
                    )
                    .allowsHitTesting(false)
                    .opacity(reduceMotion ? 0 : 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let preview = dragTimePreview {
                TimeRangeTooltip(text: preview, color: effectiveColor)
                    .padding(6)
            }
        }
        .cornerRadius(10)
        .offset(x: dragOffset.width, y: dragOffset.height + hoverLift)
        .scaleEffect((isHovered && !isInteracting) ? 1.01 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged?(hovering)
        }
        .highPriorityGesture(
            TapGesture(count: 1)
                .onEnded {
                    onSelect()
                    pillCoordinator.selectTask(objectID: item.id, animated: !reduceMotion)
                }
        )
        .onTapGesture(count: 2) {
            onTap()
            modalCoordinator.activeModal = .editTask(objectID: item.id)
        }
        .contextMenu {
            Button("Edit…") {
                onTap()
                modalCoordinator.activeModal = .editTask(objectID: item.id)
            }
            Button("Delete…", role: .destructive) { onDelete() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let rawX = value.translation.width
                    let rawY = value.translation.height

                    let minDayX = CGFloat(dayDeltaBounds.lowerBound) * dayWidth
                    let maxDayX = CGFloat(dayDeltaBounds.upperBound) * dayWidth
                    let clampedX = min(max(rawX, minDayX), maxDayX)
                    let overshootX = rawX - clampedX
                    let bandedX = clampedX + Self.rubberBand(overshootX, bandLength: 56)

                    let minMinY = CGFloat(minutesDeltaBounds.lowerBound) * minuteHeight
                    let maxMinY = CGFloat(minutesDeltaBounds.upperBound) * minuteHeight
                    let clampedY = min(max(rawY, minMinY), maxMinY)
                    let overshootY = rawY - clampedY
                    let bandedY = clampedY + Self.rubberBand(overshootY, bandLength: 96)

                    dragOffset = CGSize(width: bandedX, height: bandedY)
                }
                .onEnded { value in
                    let rawDayDelta = Int(round(value.translation.width / max(dayWidth, 1)))
                    let rawMinutesDelta = Int(round(value.translation.height / max(minuteHeight, 0.0001)))
                    let snappedMinutesDelta = (rawMinutesDelta / max(snapMinutes, 1)) * snapMinutes

                    let clampedDayDelta = min(max(rawDayDelta, dayDeltaBounds.lowerBound), dayDeltaBounds.upperBound)
                    let clampedMinutesDelta = min(max(snappedMinutesDelta, minutesDeltaBounds.lowerBound), minutesDeltaBounds.upperBound)

                    onMove(clampedDayDelta, clampedMinutesDelta)

                    if reduceMotion {
                        dragOffset = .zero
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }
}

struct CalendarChip: Identifiable {
    enum Kind {
        case event
        case task
    }

    let id: NSManagedObjectID
    let title: String
    let timeText: String?
    let color: Color
    var icon: String? = nil
    var trailingIcon: String? = nil
    let kind: Kind
    let isPast: Bool
}

struct DayCell: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    let date: Date
    let isCurrentMonth: Bool
    var isToday: Bool = false
    var isSelected: Bool = false
    var showsKeyboardFocusIndicator: Bool = false
    let width: CGFloat
    let height: CGFloat
    var chips: [CalendarChip] = []
    var topOverlayReservedHeight: CGFloat = 0
    var isBreak: Bool = false
    var onTapEmpty: (() -> Void)? = nil
    var onTapChip: ((CalendarChip) -> Void)? = nil

    @State private var suppressNextEmptyTap: Bool = false
    @State private var pendingDeleteChip: CalendarChip? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var showOverflowPopover: Bool = false
    @State private var hoveredChipURL: URL? = nil
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if suppressNextEmptyTap {
                        suppressNextEmptyTap = false
                        return
                    }
                    onTapEmpty?()
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isToday {
                        Text(dayNumber(date))
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(DesignSystem.Colors.primary)
                            .clipShape(Circle())
                            .shadow(radius: 2)

                        Text("TODAY")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                    } else {
                        Text(dayNumber(date))
                            .font(DesignSystem.Fonts.main(size: 14, weight: isCurrentMonth ? .bold : .semibold))
                            .foregroundColor(isCurrentMonth ? DesignSystem.Colors.textMain : DesignSystem.Colors.textLight.opacity(0.5))
                    }
                    Spacer()
                }
                .padding(8)

                if isBreak {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("BREAK")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            Spacer()
                        }
                        Spacer()
                    }
                    .background(
                        Stripes(config: StripesConfig(background: .clear, foreground: Color(hex: "cbd5e1").opacity(0.2), degrees: 45, barWidth: 10, barSpacing: 10))
                    )
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(Color(hex: "e2e8f0"))
                    )
                    .padding(4)
                } else {
                    let visibleLimit = 4
                    let overflowCount = max(0, chips.count - visibleLimit)
                    let visibleChips = Array(chips.prefix(visibleLimit))

                    VStack(spacing: 4) {
                        ForEach(visibleChips) { chip in
                            let url = chip.id.uriRepresentation()
                            let isHovered = hoveredChipURL == url
                            let effectiveColor = chip.isPast ? DesignSystem.Colors.textLight : chip.color
                            HStack(spacing: 4) {
                                if let icon = chip.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 10))
                                }
                                Text(chip.title)
                                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if let trailingIcon = chip.trailingIcon {
                                    Image(systemName: trailingIcon)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                        .rotationEffect(.degrees(18))
                                        .accessibilityLabel("Recurring")
                                } else if let timeText = chip.timeText, !timeText.isEmpty {
                                    Text(timeText)
                                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(effectiveColor.opacity(isHovered ? 0.14 : 0.10))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(effectiveColor.opacity(isHovered ? 0.35 : 0.20), lineWidth: isHovered ? 1.25 : 1)
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: CalendarItemFramePreferenceKey.self,
                                        value: [url: geo.frame(in: .named("CalendarMainContent"))]
                                    )
                                }
                            )
                            .offset(y: isHovered ? -2 : 0)
                            .scaleEffect(isHovered ? 1.01 : 1)
                            .animation(.spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
                            .onHover { hovering in
                                if hovering {
                                    hoveredChipURL = url
                                } else if hoveredChipURL == url {
                                    hoveredChipURL = nil
                                }
                            }
                            .onTapGesture {
                                suppressNextEmptyTap = true
                                onTapChip?(chip)
                            }
                            .onDrag {
                                return NSItemProvider(object: url.absoluteString as NSString)
                            }
                            .contextMenu {
                                switch chip.kind {
                                case .event:
                                    Button("Edit…") {
                                        onTapChip?(chip)
                                    }
                                    Button("Delete…", role: .destructive) {
                                        pendingDeleteChip = chip
                                        showDeleteConfirmation = true
                                    }
                                case .task:
                                    Button("Delete…", role: .destructive) {
                                        pendingDeleteChip = chip
                                        showDeleteConfirmation = true
                                    }
                                }
                            }
                        }

                        if overflowCount > 0 {
                            Button(action: {
                                suppressNextEmptyTap = true
                                showOverflowPopover = true
                            }) {
                                Text("+\(overflowCount) more")
                                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(DesignSystem.Colors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                    )
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .popover(isPresented: $showOverflowPopover) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textMain)

                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(chips) { chip in
                                                let url = chip.id.uriRepresentation()
                                                let isHovered = hoveredChipURL == url
                                                let effectiveColor = chip.isPast ? DesignSystem.Colors.textLight : chip.color
                                                Button(action: {
                                                    showOverflowPopover = false
                                                    onTapChip?(chip)
                                                }) {
                                                    HStack(spacing: 8) {
                                                        Circle()
                                                            .fill(effectiveColor)
                                                            .frame(width: 8, height: 8)
                                                        if let icon = chip.icon {
                                                            Image(systemName: icon)
                                                                .font(.system(size: 11, weight: .semibold))
                                                                .foregroundColor(DesignSystem.Colors.textMain)
                                                        }
                                                        Text(chip.title)
                                                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                                            .foregroundColor(DesignSystem.Colors.textMain)
                                                            .lineLimit(2)
                                                        Spacer(minLength: 0)

                                                        if let timeText = chip.timeText, !timeText.isEmpty {
                                                            Text(timeText)
                                                                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                                                .foregroundColor(DesignSystem.Colors.textMain)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                    .padding(.vertical, 6)
                                                    .padding(.horizontal, 10)
                                                    .background(DesignSystem.Colors.surface)
                                                    .cornerRadius(10)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(isHovered ? DesignSystem.Colors.textLight.opacity(0.28) : Color(hex: "f1f5f9"), lineWidth: isHovered ? 1.25 : 1)
                                                    )
                                                    .offset(y: isHovered ? -2 : 0)
                                                    .scaleEffect(isHovered ? 1.01 : 1)
                                                    .animation(.spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                .onHover { hovering in
                                                    if hovering {
                                                        hoveredChipURL = url
                                                    } else if hoveredChipURL == url {
                                                        hoveredChipURL = nil
                                                    }
                                                }
                                                .disabled(false)
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                                .frame(width: 360, height: 360)
                            }
                        }
                    }
                    .padding(.top, topOverlayReservedHeight)
                    .padding(.horizontal, 4)
                }

                Spacer()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .background(isToday ? DesignSystem.Colors.primary.opacity(0.05) : (isCurrentMonth ? Color.white : Color(hex: "f8fafc").opacity(0.3)))
        .overlay(
            Rectangle()
                .stroke(DesignSystem.Colors.primary.opacity(0.35), lineWidth: (isSelected && !isToday && showsKeyboardFocusIndicator) ? 2 : 0)
        )
        .border(width: 0.5, edges: [.trailing, .bottom], color: Color(hex: "f1f5f9"))
        .confirmationDialog(
            "Delete Item?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let chip = pendingDeleteChip else { return }
                switch chip.kind {
                case .event:
                    let eventTitle: String
                    if let event = try? coreDataManager.viewContext.existingObject(with: chip.id) as? CalendarEventEntity {
                        eventTitle = event.title ?? "Event"
                        if let uuid = event.id {
                            Task.detached(priority: .utility) { [calendarManager] in
                                calendarManager.deleteEventFromGoogle(localEventID: uuid)
                            }
                        }
                    } else {
                        eventTitle = "Event"
                    }
                    coreDataManager.deleteCalendarEvent(objectID: chip.id)
                    
                    AppNotificationCenter.shared.post(
                        kind: .info,
                        title: "Event Deleted",
                        message: "\(eventTitle) removed from calendar",
                        autoDismissAfter: 3
                    )
                case .task:
                    coreDataManager.deleteTask(objectID: chip.id)
                }
                pendingDeleteChip = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteChip = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func dayNumber(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }
}

fileprivate struct MouseLocationTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMove = onMove
    }

    fileprivate final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [
                .activeInKeyWindow,
                .inVisibleRect,
                .mouseMoved,
                .mouseEnteredAndExited
            ]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            let local = convert(event.locationInWindow, from: nil)
            let yFromTop = bounds.height - local.y
            onMove?(CGPoint(x: local.x, y: yFromTop))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onMove?(nil)
        }
    }
}

// Helper for borders
extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }

            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }

            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }

            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addPath(Path(CGRect(x: x, y: y, width: w, height: h)))
        }
        return path
    }
}

// Helper for Stripes
struct StripesConfig {
    var background: Color
    var foreground: Color
    var degrees: Double
    var barWidth: CGFloat
    var barSpacing: CGFloat
}

struct Stripes: View {
    var config: StripesConfig

    var body: some View {
        GeometryReader { geometry in
            let longSide = max(geometry.size.width, geometry.size.height)
            let itemWidth = config.barWidth + config.barSpacing
            let items = Int(2 * longSide / itemWidth)
            
            HStack(spacing: config.barSpacing) {
                ForEach(0..<items, id: \.self) { _ in
                    Rectangle()
                        .fill(config.foreground)
                        .frame(width: config.barWidth, height: 2 * longSide)
                }
            }
            .frame(width: 2 * longSide, height: 2 * longSide)
            .rotationEffect(Angle(degrees: config.degrees))
            .offset(x: -longSide / 2, y: -longSide / 2)
            .background(config.background)
            .clipped()
        }
    }
}

fileprivate struct AllDaySpanChip: View {
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var modalCoordinator: ModalCoordinator

    enum Badge: Equatable {
        case allDay
        case recurring
    }

    let objectID: NSManagedObjectID
    let title: String
    let badge: Badge
    let color: Color
    let isPast: Bool
    let pixelsPerDay: CGFloat
    let onSelect: () -> Void
    let onTap: () -> Void
    let onMoveDays: (Int) -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @GestureState private var dragOffset: CGSize = .zero
    @State private var isHovered: Bool = false

    var body: some View {
        let effectiveColor: Color = isPast ? DesignSystem.Colors.textLight : color
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .lineLimit(1)
            Group {
                switch badge {
                case .allDay:
                    EmptyView()
                case .recurring:
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .rotationEffect(.degrees(18))
                        .accessibilityLabel("Recurring")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(effectiveColor.opacity(isHovered ? 0.14 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(effectiveColor.opacity(isHovered ? 0.30 : 0.18), lineWidth: isHovered ? 1.25 : 1)
        )
        .cornerRadius(8)
        .offset(x: dragOffset.width, y: isHovered ? -2 : 0)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .highPriorityGesture(
            TapGesture(count: 1)
                .onEnded {
                    onSelect()
                    pillCoordinator.selectEvent(objectID: objectID)
                }
        )
        .onTapGesture(count: 2) {
            onTap()
            modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
        }
        .contextMenu {
            Button("Edit…") {
                onTap()
                modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
            }
            Button("Duplicate") { onDuplicate() }
            Button("Delete…", role: .destructive) { onDelete() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let step = max(40, pixelsPerDay)
                    let delta = Int(round(value.translation.width / step))
                    onMoveDays(delta)
                }
        )
    }
}

fileprivate struct MonthRecurringSpanBar: View {
    @EnvironmentObject private var pillCoordinator: PillCoordinator
    @EnvironmentObject private var modalCoordinator: ModalCoordinator

    let objectID: NSManagedObjectID
    let title: String
    let color: Color
    let isPast: Bool
    let onSelect: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        let effectiveColor: Color = isPast ? DesignSystem.Colors.textLight : color

        HStack(spacing: 6) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .rotationEffect(.degrees(18))
                .accessibilityLabel("Recurring")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(effectiveColor.opacity(isHovered ? 0.14 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(effectiveColor.opacity(isHovered ? 0.30 : 0.18), lineWidth: isHovered ? 1.25 : 1)
        )
        .cornerRadius(7)
        .offset(y: isHovered ? -1 : 0)
        .animation(.spring(response: 0.20, dampingFraction: 0.76), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .highPriorityGesture(
            TapGesture(count: 1)
                .onEnded {
                    onSelect()
                    pillCoordinator.selectEvent(objectID: objectID)
                }
        )
        .onTapGesture(count: 2) {
            onTap()
            modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
        }
        .contextMenu {
            Button("Edit…") {
                onTap()
                modalCoordinator.activeModal = .editCalendarItem(objectID: objectID)
            }
            Button("Duplicate") { onDuplicate() }
            Button("Delete…", role: .destructive) { onDelete() }
        }
    }
}
