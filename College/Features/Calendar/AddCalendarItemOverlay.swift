// AddCalendarItemOverlay.swift
import CollegeCalendar
// Feature: Calendar
// Purpose: Calendar module — AddCalendarItemOverlay.
// Data: CollegePersistence / repositories when applicable.

import CollegePlatform
import SwiftUI
import SwiftData
import MapKit
import AppKit
import Contacts
import ContactsUI
import UniformTypeIdentifiers

/// Full-screen modal used by the Calendar page to add a new event.
struct AddCalendarItemOverlay: View {
    @Environment(AppContainer.self) private var container
    var calendarManager: CalendarIntegrationManager { container.calendarManager }
    var locationPermissionService: LocationPermissionService { container.locationPermissionService }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
            private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
    @AppStorage("calDefaultReminderMinutes") private var defaultReminderMinutes: Int = 15
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    enum PresentationStyle {
        case fullScreenOverlay
        case anchoredPanel
        case inspectorSidebar
        case dynamicIsland
        case bottomSheet
    }

    var isInspectorEmbedded: Bool {
        presentationStyle == .inspectorSidebar
    }

    var usesCompactEditorLayout: Bool {
        presentationStyle == .anchoredPanel || presentationStyle == .inspectorSidebar
    }

    @Binding var isPresented: Bool
    let semester: PlannerSemester?
    let initialTitle: String?
    let initialStartDateTime: Date?
    let initialEndDateTime: Date?
    let eventToEdit: CalendarEvent?
    let presentationStyle: PresentationStyle
    /// Called on every title/time/color change — drives the live ghost preview block.
    var onLiveUpdate: ((String, Date, Date, Color) -> Void)? = nil

    @State var title: String = ""
    @State private var mainCardHeight: CGFloat = 0
    @State var startDateTime: Date = Date()
    @State var endDateTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State var allDay: Bool = false

    @State var location: String = ""
    @State var descriptionText: String = ""
    @State var isExpanded: Bool = true

    @State private var descriptionEditorMeasuredHeight: CGFloat = 18

    @State var isShowingLocationPicker: Bool = false
    @StateObject var locationSearchService = MapLocationSearchService()
    @State var resolvedLocation: ResolvedLocation? = nil
    @State var locationSuggestions: [ResolvedLocation] = []
    @State private var pendingLocationSuggestionWorkItem: DispatchWorkItem? = nil
    @State var highlightedLocationSuggestionIndex: Int = 0

    @State var travelTimeEnabled: Bool = false
    @State private var travelTransport: TravelTransport = TravelTimeStore.loadLastTransport()
    @State var travelTimeMinutes: Int? = nil
    @State var travelEstimateMinutes: Int? = nil
    @State var isEstimatingTravel: Bool = false
    
    @State var selectedGuests: [CNContact] = []
    @State var guestResponseByEmail: [String: String] = [:]
    @State var guestInviteSyncFailed: Bool = false
    @State var contactPickerDelegate: Any? = nil // Holds strong reference to the delegate

    @AppStorage(CalendarOverlapPolicy.storageKey) var overlapPolicyRaw: String = CalendarOverlapPolicy.warn.rawValue

    @State var selectedCourseID: UUID? = nil
    @State var selectedGoogleCalendarID: String? = nil
    @State var selectedAppleCalendarID: String? = nil
    @State var showInspectorOnboardingTips: Bool = CalendarInspectorOnboarding.shouldShowTips
    @State var linkedAttachmentIDs: [UUID] = []

    enum EventColorChoice: Equatable {
        case preset(Int)
        case custom
    }

    static let presetEventColors: [Color] = [
        DesignSystem.Colors.primary,
        DesignSystem.Colors.success,
        DesignSystem.Colors.secondary,
        DesignSystem.Colors.warning,
        DesignSystem.Colors.error
    ]

    @State var eventColorChoice: EventColorChoice = .preset(0)
    @State var customColor: Color = DesignSystem.Colors.primary
    @State private var customHexInput: String = ""
    @State var isShowingHexPopover: Bool = false
    @State var isShowingFileImporter: Bool = false
    @State var isColorOverridden: Bool = false
    @State var alertLeadMinutes: [Int] = [15]
    @State var recurrenceRule: String = "none"
    @State private var recurrenceInterval: Int = 1
    @State private var recurrenceWeekdays: Set<Int> = []
    @State private var recurrenceHasEndDate: Bool = false
    @State private var recurrenceEndDate: Date = Date()
    @State var hasAutoAdjustedEndTime: Bool = false

    private var isEditingEvent: Bool {
        eventToEdit != nil
    }
    
    // Legacy font properties
    private var sectionTitleFontSize: CGFloat { isEditingEvent ? 12 : 13 }
    private var titleFieldFontSize: CGFloat { isEditingEvent ? 15 : 18 }
    private var standardFieldFontSize: CGFloat { isEditingEvent ? 13 : 14 }

    @State private var pendingAutosaveWorkItem: DispatchWorkItem? = nil
    @State private var showAdvancedDynamicIslandFields: Bool = false
    @State private var shouldReturnToCoursePanelAfterCatalog: Bool = false
    // @State private var isNotesPresented: Bool = false - Replaced by activeBottomPanel

    enum LocationInputFocus: Hashable {
        case bottomSheet
        case anchoredPanel
    }

    @FocusState var focusedLocationInput: LocationInputFocus?

    enum ActiveBottomPanel: Equatable {
        case none
        case alerts
        case recurrence
        case course
        case notes
        case files
    }
    
    @State var activeBottomPanel: ActiveBottomPanel = .none
    @State var recentFileImports: [URL] = [] // Track files for the current session UI
    
    struct Snapshot: Equatable {
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let location: String
        let notes: String
        let courseID: UUID?
        let colorHex: String?
        let recurrenceRule: String
        let recurrenceInterval: Int
        let recurrenceWeekdays: Set<Int>
        let recurrenceHasEndDate: Bool
        let recurrenceEndDate: Date
    }

    private struct ExternalPrefill: Equatable {
        let title: String?
        let start: Date?
        let end: Date?
    }

    private struct RecurrenceSettings: Codable, Equatable {
        let frequency: String
        let interval: Int
        let weekdays: [Int]
        let endDate: Date?

        static let none = RecurrenceSettings(frequency: "none", interval: 1, weekdays: [], endDate: nil)
    }

    private let initialSnapshot: Snapshot
    private let initialTravelSettings: TravelTimeSettings
    private enum CourseColorOverrides {
        private static let keyPrefix = "CourseColorOverride."

        static func color(for courseCode: String) -> Color? {
            let key = keyPrefix + courseCode
            guard let hex = UserDefaults.standard.string(forKey: key) else { return nil }
            return Color(hex: hex)
        }
    }

    private static func stableColor(for courseCode: String) -> Color {
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

    static func defaultEventColor(for course: PlannerCourse?) -> Color {
        guard let course else { return DesignSystem.Colors.primary }
        return stableColor(for: course.code)
    }

    private static func normalizedHex(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .filter { $0.isHexDigit }
            .lowercased()
    }

    private static func isValidHexRGB(_ raw: String) -> Bool {
        let hex = normalizedHex(raw)
        return hex.count == 6
    }

    private static func color(fromHexInput raw: String) -> Color? {
        let hex = normalizedHex(raw)
        guard hex.count == 6 else { return nil }
        return Color(hex: hex)
    }

    func setDisplayedColor(_ color: Color, forceChoice: EventColorChoice? = nil) {
        customColor = color
        customHexInput = color.hexRGBString() ?? customHexInput

        if let forceChoice {
            eventColorChoice = forceChoice
            return
        }

        if let hex = color.hexRGBString(),
           let presetIndex = AddCalendarItemOverlay.presetEventColors.firstIndex(where: { $0.hexRGBString() == hex }) {
            eventColorChoice = .preset(presetIndex)
        } else {
            eventColorChoice = .custom
        }
    }

    func applySelectedColor(_ color: Color, choice: EventColorChoice) {
        isColorOverridden = true
        setDisplayedColor(color, forceChoice: choice)
    }

    private var courses: [PlannerCourse] { semester?.coursesArray ?? [] }

    var allCourses: [PlannerCourse] {
        let merged = collegePersistence.semesters
            .flatMap { $0.coursesArray }
            .reduce(into: [UUID: PlannerCourse]()) { partialResult, course in
                partialResult[course.id] = course
            }
        return merged.values.sorted {
            let lhsCode = $0.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsCode = $1.code.trimmingCharacters(in: .whitespacesAndNewlines)
            if lhsCode != rhsCode {
                return lhsCode.localizedCaseInsensitiveCompare(rhsCode) == .orderedAscending
            }
            let lhsName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsName = $1.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    init(
        isPresented: Binding<Bool>,
        semester: PlannerSemester?,
        initialTitle: String? = nil,
        initialStartDateTime: Date? = nil,
        initialEndDateTime: Date? = nil,
        eventToEdit: CalendarEvent? = nil,
        presentationStyle: PresentationStyle = .fullScreenOverlay,
        onLiveUpdate: ((String, Date, Date, Color) -> Void)? = nil
    ) {
        _isPresented = isPresented
        self.semester = semester
        self.initialTitle = initialTitle
        self.initialStartDateTime = initialStartDateTime
        self.initialEndDateTime = initialEndDateTime
        self.eventToEdit = eventToEdit
        self.presentationStyle = presentationStyle
        self.onLiveUpdate = onLiveUpdate

        _isExpanded = State(initialValue: presentationStyle == .bottomSheet ? false : true)

        if let eventToEdit {
            let existingStart = initialStartDateTime ?? eventToEdit.startDate
            let existingEnd = initialEndDateTime ?? eventToEdit.endDate

            _title = State(initialValue: eventToEdit.title)
            _startDateTime = State(initialValue: existingStart)
            _endDateTime = State(initialValue: existingEnd)
            _allDay = State(initialValue: eventToEdit.allDay)
            _location = State(initialValue: eventToEdit.location ?? "")
            _descriptionText = State(initialValue: eventToEdit.notes ?? "")
            _selectedCourseID = State(initialValue: eventToEdit.course?.id)
            let recurrenceSettings = CalendarRecurrenceRuleCodec.recurrenceSettings(fromStoredRule: eventToEdit.recurrenceRule)
            let existingRecurrence = recurrenceSettings.frequency
            _recurrenceRule = State(initialValue: existingRecurrence)
            _recurrenceInterval = State(initialValue: recurrenceSettings.interval)
            _recurrenceWeekdays = State(initialValue: Set(recurrenceSettings.weekdays))
            _recurrenceHasEndDate = State(initialValue: recurrenceSettings.endDate != nil)
            _recurrenceEndDate = State(initialValue: recurrenceSettings.endDate ?? existingEnd)

            let modelColorHex = eventToEdit.customColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
            let legacyOverrideHex = EventColorOverrides.color(for: eventToEdit.id)?.hexRGBString()
            let initialOverrideHex = (modelColorHex?.isEmpty == false ? modelColorHex : nil) ?? legacyOverrideHex
            _isColorOverridden = State(initialValue: initialOverrideHex != nil)
            let initialDisplayColor: Color
            if let hex = initialOverrideHex {
                initialDisplayColor = Color(hex: hex)
            } else {
                initialDisplayColor = AddCalendarItemOverlay.defaultEventColor(for: eventToEdit.course)
            }

            let initialHex = initialDisplayColor.hexRGBString() ?? (initialOverrideHex ?? "")
            _customColor = State(initialValue: initialDisplayColor)
            _customHexInput = State(initialValue: initialHex)
            if let presetIndex = AddCalendarItemOverlay.presetEventColors.firstIndex(where: { $0.hexRGBString() == initialHex }) {
                _eventColorChoice = State(initialValue: .preset(presetIndex))
            } else {
                _eventColorChoice = State(initialValue: .custom)
            }

            initialSnapshot = Snapshot(
                title: eventToEdit.title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: existingStart,
                end: existingEnd,
                allDay: eventToEdit.allDay,
                location: (eventToEdit.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                notes: (eventToEdit.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                courseID: eventToEdit.course?.id,
                colorHex: initialOverrideHex,
                recurrenceRule: existingRecurrence,
                recurrenceInterval: recurrenceSettings.interval,
                recurrenceWeekdays: Set(recurrenceSettings.weekdays),
                recurrenceHasEndDate: recurrenceSettings.endDate != nil,
                recurrenceEndDate: recurrenceSettings.endDate ?? existingEnd
            )

            let storedTravel = TravelTimeStore.loadOverride(eventID: eventToEdit.id)
            let defaultTransport = storedTravel?.transport ?? TravelTimeStore.loadLastTransport()
            initialTravelSettings = storedTravel ?? TravelTimeSettings(
                enabled: false,
                transport: defaultTransport,
                minutes: nil,
                resolvedLocation: nil
            )

            _travelTimeEnabled = State(initialValue: initialTravelSettings.enabled)
            _travelTransport = State(initialValue: initialTravelSettings.transport)
            _travelTimeMinutes = State(initialValue: initialTravelSettings.minutes)
            _resolvedLocation = State(initialValue: initialTravelSettings.resolvedLocation)
        } else {
            let trimmedTitle = (initialTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            _title = State(initialValue: trimmedTitle)

            let start = initialStartDateTime ?? Date()
            let endDefault = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            let end = initialEndDateTime ?? endDefault
            _startDateTime = State(initialValue: start)
            _endDateTime = State(initialValue: end)

            let initialColor = AddCalendarItemOverlay.presetEventColors.first ?? DesignSystem.Colors.primary
            let initialHex = initialColor.hexRGBString() ?? ""
            _customColor = State(initialValue: initialColor)
            _customHexInput = State(initialValue: initialHex)
            _eventColorChoice = State(initialValue: .preset(0))
            _isColorOverridden = State(initialValue: true)
            _recurrenceRule = State(initialValue: "none")
            _recurrenceInterval = State(initialValue: 1)
            _recurrenceWeekdays = State(initialValue: [])
            _recurrenceHasEndDate = State(initialValue: false)
            _recurrenceEndDate = State(initialValue: end)

            initialSnapshot = Snapshot(
                title: trimmedTitle,
                start: start,
                end: end,
                allDay: false,
                location: "",
                notes: "",
                courseID: nil,
                colorHex: initialHex,
                recurrenceRule: "none",
                recurrenceInterval: 1,
                recurrenceWeekdays: [],
                recurrenceHasEndDate: false,
                recurrenceEndDate: end
            )

            let defaultTransport = TravelTimeStore.loadLastTransport()
            initialTravelSettings = TravelTimeSettings(
                enabled: false,
                transport: defaultTransport,
                minutes: nil,
                resolvedLocation: nil
            )

            _travelTimeEnabled = State(initialValue: false)
            _travelTransport = State(initialValue: defaultTransport)
            _travelTimeMinutes = State(initialValue: nil)
            _resolvedLocation = State(initialValue: nil)
        }
    }

    var travelTimeMinuteOptions: [Int] {
        [5, 10, 15, 20, 30, 45, 60, 90, 120]
    }

    func roundedToNearestFive(_ minutes: Int) -> Int {
        max(0, Int((Double(minutes) / 5.0).rounded() * 5.0))
    }

    func distanceText(for option: ResolvedLocation) -> String? {
        guard let origin = locationPermissionService.lastLocation else { return nil }
        let meters = CLLocation(latitude: option.latitude, longitude: option.longitude).distance(from: origin)
        guard meters.isFinite else { return nil }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    func applyLocationSuggestion(_ option: ResolvedLocation) {
        resolvedLocation = option
        location = option.displayName
        locationSuggestions = []
        recomputeTravelEstimateIfPossible()
    }

    private func scheduleLocationSuggestionsRefresh() {
        pendingLocationSuggestionWorkItem?.cancel()

        let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            locationSuggestions = []
            highlightedLocationSuggestionIndex = 0
            return
        }

        locationSearchService.query = query
        let work = DispatchWorkItem { [query] in
            Task { @MainActor in
                let resolved = await locationSearchService.resolveTopCompletions(
                    limit: 6,
                    near: locationPermissionService.lastLocation
                )
                let latestQuery = location.trimmingCharacters(in: .whitespacesAndNewlines)
                guard latestQuery.caseInsensitiveCompare(query) == .orderedSame else { return }
                locationSuggestions = resolved
                highlightedLocationSuggestionIndex = 0
            }
        }
        pendingLocationSuggestionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func moveLocationSuggestionSelection(by delta: Int) {
        guard !locationSuggestions.isEmpty else { return }
        let maxIndex = locationSuggestions.count - 1
        highlightedLocationSuggestionIndex = min(max(highlightedLocationSuggestionIndex + delta, 0), maxIndex)
    }

    private func applyHighlightedLocationSuggestionIfPossible() {
        guard !locationSuggestions.isEmpty else { return }
        let index = min(max(highlightedLocationSuggestionIndex, 0), locationSuggestions.count - 1)
        applyLocationSuggestion(locationSuggestions[index])
    }

    static let recurrenceOptions: [String] = ["none", "daily", "weekly", "monthly", "yearly"]

    private static func normalizedRecurrenceRule(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if recurrenceOptions.contains(value) {
            return value
        }
        return "none"
    }

    private static func recurrenceSettings(from raw: String?) -> RecurrenceSettings {
        let decoded = CalendarRecurrenceRuleCodec.recurrenceSettings(fromStoredRule: raw)
        return RecurrenceSettings(
            frequency: decoded.frequency,
            interval: decoded.interval,
            weekdays: decoded.weekdays,
            endDate: decoded.endDate
        )
    }

    private static func recurrencePayloadString(from settings: RecurrenceSettings) -> String? {
        let frequency = normalizedRecurrenceRule(settings.frequency)
        if frequency == "none" {
            return nil
        }
        let normalized = RecurrenceSettings(
            frequency: frequency,
            interval: max(1, settings.interval),
            weekdays: Array(Set(settings.weekdays.filter { (1...7).contains($0) })).sorted(),
            endDate: settings.endDate
        )
        guard let data = try? JSONEncoder().encode(normalized),
              let json = String(data: data, encoding: .utf8) else {
            return frequency
        }
        return json
    }

    var recurrenceSummaryLabel: String {
        let frequency = recurrenceLabel(for: recurrenceRule)
        if recurrenceRule == "none" {
            return frequency
        }
        let everyPart = recurrenceInterval <= 1 ? frequency : "Every \(recurrenceInterval) \(frequency.lowercased())"
        if recurrenceRule == "weekly", !recurrenceWeekdays.isEmpty {
            let symbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let days = recurrenceWeekdays.sorted().map { symbols[max(0, min(6, $0 - 1))] }.joined(separator: ",")
            return "\(everyPart) (\(days))"
        }
        return everyPart
    }

    func recurrenceLabel(for rule: String) -> String {
        switch Self.normalizedRecurrenceRule(rule) {
        case "daily":
            return "Daily"
        case "weekly":
            return "Weekly"
        case "monthly":
            return "Monthly"
        case "yearly":
            return "Yearly"
        default:
            return "Does not repeat"
        }
    }

    func setRecurrenceRule(_ value: String) {
        recurrenceRule = Self.normalizedRecurrenceRule(value)
        if recurrenceRule == "none" {
            recurrenceInterval = 1
            recurrenceWeekdays = []
            recurrenceHasEndDate = false
        } else {
            recurrenceInterval = max(1, recurrenceInterval)
        }
    }

    private var recurrenceSettingsFromState: RecurrenceSettings {
        if recurrenceRule == "none" {
            return .none
        }
        return RecurrenceSettings(
            frequency: recurrenceRule,
            interval: max(1, recurrenceInterval),
            weekdays: Array(recurrenceWeekdays).sorted(),
            endDate: recurrenceHasEndDate ? recurrenceEndDate : nil
        )
    }

    func openCourseSearchOrBuilder() {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeBottomPanel = .course
        }
    }

    func courseDisplayLabel(_ course: PlannerCourse?) -> String {
        guard let course else { return "No course" }
        let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty && !name.isEmpty { return "\(code) - \(name)" }
        if !code.isEmpty { return code }
        if !name.isEmpty { return name }
        return "Course"
    }

    private func openCourseBuilderModal() {
        shouldReturnToCoursePanelAfterCatalog = true
        let targetSemester: PlannerSemester?
        if let semester {
            targetSemester = semester
        } else {
            if let existing = collegePersistence.semesters.first {
                targetSemester = existing
            } else {
                let today = Date()
                let month = Calendar.current.component(.month, from: today)
                let year = Calendar.current.component(.year, from: today)
                let season: String
                switch month {
                case 1...5:
                    season = "Spring"
                case 6...8:
                    season = "Summer"
                default:
                    season = "Fall"
                }
                let created = collegePersistence.findOrCreateSemester(season: season, year: year)
                collegePersistence.saveCalendarChanges()
                targetSemester = created
            }
        }
        guard let targetSemester else {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeBottomPanel = .course
            }
            AppNotificationCenter.shared.post(
                kind: .info,
                title: "No Semester Found",
                message: "Create a semester first, or use the course panel below to add a course.",
                autoDismissAfter: 3
            )
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            activeBottomPanel = .none
        }
        modalCoordinator.activeModal = .addCatalogCourse(semesterID: targetSemester.id)
    }

    private func handleModalCoordinatorChange(oldValue: ModalCoordinator.ActiveModal?, newValue: ModalCoordinator.ActiveModal?) {
        if shouldReturnToCoursePanelAfterCatalog, oldValue != nil, newValue == nil {
            shouldReturnToCoursePanelAfterCatalog = false
            withAnimation(.easeInOut(duration: 0.2)) {
                activeBottomPanel = .course
            }
        }
    }

    var selectedCourseSummaryLabel: String {
        guard let course = selectedCourse() else { return "No course" }
        let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty { return code }
        let name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Course" : name
    }

    func recomputeTravelEstimateIfPossible() {
        guard travelTimeEnabled else {
            travelEstimateMinutes = nil
            return
        }
        guard let destination = resolvedLocation else {
            travelEstimateMinutes = nil
            return
        }
        guard locationPermissionService.status == .authorized,
              let origin = locationPermissionService.lastLocation else {
            travelEstimateMinutes = nil
            if locationPermissionService.status != .authorized {
                AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Travel Time Unavailable",
                    message: "Enable Location Services to estimate travel time",
                    autoDismissAfter: 4
                )
            }
            return
        }

        isEstimatingTravel = true
        let originCoordinate = origin.coordinate
        let destinationCoordinate = destination.coordinate
        let transportType = travelTransport.directionsType
        let destinationName = destination.displayName

        Task { @MainActor in
            let etaSeconds = await LocationETAService.calculateETASeconds(
                origin: originCoordinate,
                destination: destinationCoordinate,
                transportType: transportType
            )

            isEstimatingTravel = false
            guard let etaSeconds else {
                travelEstimateMinutes = nil
                AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Travel Time Unavailable",
                    message: "Could not calculate travel time to \(destinationName)",
                    autoDismissAfter: 4
                )
                return
            }

            let minutes = max(1, Int((etaSeconds / 60.0).rounded()))
            travelEstimateMinutes = minutes
            if travelTimeMinutes == nil {
                travelTimeMinutes = roundedToNearestFive(minutes)
            }
            
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Travel Time",
                message: "Estimated \(minutes) minute\(minutes == 1 ? "" : "s") to \(destinationName)",
                autoDismissAfter: 3
            )
        }
    }

    func selectedCourse() -> PlannerCourse? {
        guard let id = selectedCourseID else { return nil }
        return collegePersistence.fetchCourse(id: id)
    }

    private func createCourseFromEditor(code: String, name: String) -> PlannerCourse? {
        let activeSemester = semester ?? collegePersistence.semesters.first
        guard let activeSemester else { return nil }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty || !trimmedName.isEmpty else { return nil }

        let normalizedCode = trimmedCode.isEmpty ? "NEW100" : trimmedCode.uppercased()
        let normalizedName = trimmedName.isEmpty ? normalizedCode : trimmedName
        return collegePersistence.addCourse(
            to: activeSemester,
            code: normalizedCode,
            name: normalizedName,
            credits: 3,
            status: "Planned",
            gradingType: "Letter Grade",
            professor: nil
        )
    }

    private func unlinkSelectedCourseFromEvent() {
        selectedCourseID = nil
        if !isColorOverridden {
            setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: nil))
        }
        scheduleAutosaveIfEditing()
    }

    private func removeSelectedCourseFromPlanner() {
        guard let course = selectedCourse() else { return }
        selectedCourseID = nil
        collegePersistence.deleteCourse(id: course.id)
        if !isColorOverridden {
            setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: nil))
        }
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedEndDate() -> Date {
        let calendar = Calendar.current
        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
        return max(endDateTime, minimumEnd)
    }

    var supportedAlertOffsets: [Int] {
        [0, 5, 10, 15, 30, 60, 120, 1440]
    }

    private func normalizeAlertLeadMinutes(_ raw: [Int]) -> [Int] {
        Array(Set(raw.filter { $0 >= 0 })).sorted()
    }

    private static func remindersDefaultsKey(eventID: UUID) -> String {
        "calendar.event.reminders.\(eventID.uuidString)"
    }

    private func loadAlertLeadMinutesFromEvent() -> [Int] {
        guard let eventID = eventToEdit?.id,
              let raw = UserDefaults.standard.string(forKey: Self.remindersDefaultsKey(eventID: eventID)),
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return [defaultReminderMinutes]
        }

        if let array = json as? [Int] {
            let normalized = normalizeAlertLeadMinutes(array)
            return normalized.isEmpty ? [defaultReminderMinutes] : normalized
        }

        if let dict = json as? [String: Any],
           let overrides = dict["overrides"] as? [[String: Any]] {
            let minutes = overrides.compactMap { $0["minutes"] as? Int }
            let normalized = normalizeAlertLeadMinutes(minutes)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return [defaultReminderMinutes]
    }

    func toggleAlertOffset(_ minutes: Int) {
        if alertLeadMinutes.contains(minutes) {
            alertLeadMinutes.removeAll { $0 == minutes }
        } else {
            alertLeadMinutes.append(minutes)
        }
        alertLeadMinutes = normalizeAlertLeadMinutes(alertLeadMinutes)
    }

    private func addCustomAlertOffset(_ minutes: Int) {
        let normalized = max(0, min(minutes, 10080))
        if !alertLeadMinutes.contains(normalized) {
            alertLeadMinutes.append(normalized)
            alertLeadMinutes = normalizeAlertLeadMinutes(alertLeadMinutes)
        }
    }

    var reminderScheduleMinutes: [Int] {
        let normalized = normalizeAlertLeadMinutes(alertLeadMinutes)
        return normalized.isEmpty ? [] : normalized
    }

    func reminderSummaryText(_ values: [Int]? = nil) -> String {
        let source = values ?? reminderScheduleMinutes
        guard !source.isEmpty else { return "None" }
        if source.count == 1 {
            let minutes = source[0]
            if minutes == 0 { return "At time of event" }
            if minutes < 60 { return "\(minutes) mins before" }
            if minutes == 60 { return "1 hour before" }
            if minutes == 1440 { return "1 day before" }
            if minutes < 1440 { return "\(minutes / 60) hours before" }
            return "\(minutes) mins before"
        }
        return "\(source.count) alerts"
    }

    private func persistReminderPayloadIfNeeded(for event: CalendarEvent) {
        let key = Self.remindersDefaultsKey(eventID: event.id)
        let payload = reminderScheduleMinutes
        if payload.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: key)
    }

    private func enforceDateRangeConsistency(changedByStart: Bool) {
        let calendar = Calendar.current
        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime

        if allDay {
            hasAutoAdjustedEndTime = false
            return
        }

        let previousEnd = endDateTime
        if changedByStart {
            if endDateTime < minimumEnd {
                endDateTime = minimumEnd
                hasAutoAdjustedEndTime = true
            } else {
                hasAutoAdjustedEndTime = false
            }
            return
        }

        if endDateTime < minimumEnd {
            endDateTime = minimumEnd
        }
        hasAutoAdjustedEndTime = previousEnd < minimumEnd
    }

    private var currentSnapshot: Snapshot {
        let hex = isColorOverridden ? customColor.hexRGBString() : nil
        return Snapshot(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            start: startDateTime,
            end: endDateTime,
            allDay: allDay,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            courseID: selectedCourseID,
            colorHex: hex,
            recurrenceRule: recurrenceRule,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekdays: recurrenceWeekdays,
            recurrenceHasEndDate: recurrenceHasEndDate,
            recurrenceEndDate: recurrenceEndDate
        )
    }

    private func requestDismiss() {
        if eventToEdit != nil {
            pendingAutosaveWorkItem?.cancel()
            applySnapshotToStore(initialSnapshot)
        }
        isPresented = false
    }

    func requestDismissAnimated() {
        if reduceMotion {
            requestDismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            requestDismiss()
        }
    }

    func deleteEventNow() {
        guard let eventToEdit else { return }
        pendingAutosaveWorkItem?.cancel()

        let eventTitle = eventToEdit.title
        let localID = eventToEdit.id

        Task { @MainActor in
            do {
                try await CalendarEventWritePipeline.shared.delete(eventID: localID)
                EventColorOverrides.clearColor(for: localID)
                TravelTimeStore.clearOverride(eventID: localID)
                AppNotificationCenter.shared.post(
                    kind: .info,
                    title: "Event Deleted",
                    message: "\(eventTitle) removed from calendar",
                    autoDismissAfter: 3
                )
                isPresented = false
            } catch {
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Delete Failed",
                    message: error.localizedDescription,
                    autoDismissAfter: 4
                )
            }
        }
    }

    private func applyColorToModel(eventID: UUID?, hex: String?) {
        guard let eventID else { return }
        try? AppDataStore.shared.calendarRepository.patchCalendarEventColor(
            id: eventID,
            customColorHex: hex
        )
        if let hex, !hex.isEmpty {
            EventColorOverrides.setColor(Color(hex: hex), for: eventID)
        } else {
            EventColorOverrides.clearColor(for: eventID)
        }
    }

    private func applyColorOverride(eventID: UUID?, snapshot: Snapshot) {
        applyColorToModel(eventID: eventID, hex: snapshot.colorHex)
    }

    private func applyCurrentColorOverride(eventID: UUID?) {
        guard let eventID else { return }
        if isColorOverridden, let hex = customColor.hexRGBString() {
            applyColorToModel(eventID: eventID, hex: hex)
        } else {
            applyColorToModel(eventID: eventID, hex: nil)
        }
    }

    func persistTravelSettingsIfEditing() {
        guard let eventToEdit else { return }
        persistTravelSettings(eventID: eventToEdit.id)
    }

    private func encodedGuestsJSON() -> String? {
        let records = selectedGuests.map { contact -> CalendarEventGuestsCodec.GuestRecord in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
            let email = contact.emailAddresses.first.map { $0.value as String }
            let rsvp = email.flatMap { guestResponseByEmail[$0.lowercased()] }
            return CalendarEventGuestsCodec.GuestRecord(name: name, email: email, responseStatus: rsvp)
        }
        return CalendarEventGuestsCodec.encode(records: records)
    }

    private func writeOptionsForSave() -> CalendarEventWriteOptions {
        let googleID = resolvedGoogleCalendarIDForExport()
        let appleName = calendarManager.connectedCalendars
            .first { $0.remoteID == selectedAppleCalendarID }?.name
        return CalendarEventWriteOptions(
            exportGoogleCalendarID: googleID,
            exportAppleCalendarName: appleName,
            reminderLeadMinutes: reminderScheduleMinutes
        )
    }

    func retryGuestInviteSync() {
        guard let eventToEdit else { return }
        guard !selectedGuests.isEmpty else { return }
        let options = writeOptionsForSave()
        Task { @MainActor in
            let exportResult = await CalendarSyncExportBridge.exportAfterWriteAndReport(
                eventID: eventToEdit.id,
                options: options
            )
            guestInviteSyncFailed = exportResult.attemptedGuestInvites
                && exportResult.guestInvitesSucceeded == false
            if exportResult.guestInvitesSucceeded == true {
                AppNotificationCenter.shared.post(
                    kind: .success,
                    title: "Invites Sent",
                    message: "Guest invites were synced to connected calendars.",
                    autoDismissAfter: 3
                )
            } else if guestInviteSyncFailed {
                AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Invite Sync Failed",
                    message: "Could not send guest invites — check calendar connections and try again.",
                    autoDismissAfter: 5
                )
            }
        }
    }

    private func syncSuccessMessage(
        for title: String,
        exportResult: CalendarExportAfterWriteResult
    ) -> String {
        if exportResult.attemptedGuestInvites {
            return "Changes to \(title) saved, synced, and guest invites sent."
        }
        return "Changes to \(title) saved and synced."
    }

    private func syncFailureMessage(
        for title: String,
        exportResult: CalendarExportAfterWriteResult
    ) -> String {
        if exportResult.attemptedGuestInvites, exportResult.guestInvitesSucceeded == false {
            return "Changes to \(title) saved locally — guest invite sync failed. Tap Resend invites."
        }
        return "Changes to \(title) saved locally — calendar sync failed. Try Save & Sync again."
    }

    private func resolvedGoogleCalendarIDForExport() -> String? {
        if let selectedGoogleCalendarID,
           !selectedGoogleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedGoogleCalendarID
        }
        if calendarManager.googleStatus == .connected {
            return selectedOrPrimaryGoogleCalendar?.remoteID
        }
        return nil
    }

    private func buildWriteInput(
        title: String,
        start: Date,
        end: Date,
        notes: String?,
        location: String?
    ) -> CalendarEventWriteInput {
        CalendarEventWriteInput(
            title: title,
            startDate: start,
            endDate: end,
            allDay: allDay,
            semesterID: semester?.id,
            courseID: selectedCourseID,
            notes: notes,
            location: location,
            customColorHex: isColorOverridden ? customColor.hexRGBString() : nil,
            recurrenceRule: Self.recurrencePayloadString(from: recurrenceSettingsFromState),
            guestsJSON: encodedGuestsJSON()
        )
    }

    private func applySnapshotToStore(_ snapshot: Snapshot) {
        guard let eventToEdit else { return }

        let notes = snapshot.notes.isEmpty ? nil : snapshot.notes
        let location = snapshot.location.isEmpty ? nil : snapshot.location

        let course: PlannerCourse? = snapshot.courseID.flatMap { collegePersistence.fetchCourse(id: $0) }
        let settings = RecurrenceSettings(
            frequency: snapshot.recurrenceRule,
            interval: snapshot.recurrenceInterval,
            weekdays: Array(snapshot.recurrenceWeekdays).sorted(),
            endDate: snapshot.recurrenceHasEndDate ? snapshot.recurrenceEndDate : nil
        )

        collegePersistence.updateCalendarEvent(
            id: eventToEdit.id,
            title: snapshot.title.isEmpty ? eventToEdit.title : snapshot.title,
            startDate: snapshot.start,
            endDate: snapshot.end,
            allDay: snapshot.allDay,
            semester: semester,
            course: course,
            notes: notes,
            location: location,
            recurrenceRule: Self.recurrencePayloadString(from: settings)
        )

        applyColorOverride(eventID: eventToEdit.id, snapshot: snapshot)
    }

    func scheduleAutosaveIfEditing() {
        guard eventToEdit != nil else { return }
        if recurrenceRule == "weekly", recurrenceWeekdays.isEmpty {
            return
        }
        pendingAutosaveWorkItem?.cancel()
        let item = DispatchWorkItem { [snapshot = currentSnapshot] in
            guard let eventToEdit else { return }
            let trimmedTitle = snapshot.title
            let trimmedDescription = snapshot.notes
            let trimmedLocation = snapshot.location
            let notes = trimmedDescription.isEmpty ? nil : trimmedDescription
            let eventLocation = trimmedLocation.isEmpty ? nil : trimmedLocation
            let start: Date
            let end: Date
            if snapshot.allDay {
                let dayStart = Calendar.current.startOfDay(for: snapshot.start)
                start = dayStart
                end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            } else {
                start = snapshot.start
                let calendar = Calendar.current
                let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: start) ?? start
                end = max(snapshot.end, minimumEnd)
            }
            let input = buildWriteInput(
                title: trimmedTitle.isEmpty ? eventToEdit.title : trimmedTitle,
                start: start,
                end: end,
                notes: notes,
                location: eventLocation
            )
            Task { @MainActor in
                try? await CalendarEventWritePipeline.shared.update(
                    eventID: eventToEdit.id,
                    input: input,
                    options: CalendarEventWriteOptions(skipExport: true, skipReminders: true)
                )
                applyColorOverride(eventID: eventToEdit.id, snapshot: snapshot)
                persistTravelSettings(eventID: eventToEdit.id)
                persistReminderPayloadIfNeeded(for: eventToEdit)
                CalendarReminderScheduler.shared.reschedule(
                    eventID: eventToEdit.id,
                    title: input.title,
                    startDate: start,
                    leadMinutes: reminderScheduleMinutes
                )
            }
        }
        pendingAutosaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    var overlapPolicy: CalendarOverlapPolicy {
        CalendarOverlapPolicy.resolved(selection: overlapPolicyRaw)
    }

    var previewOverlappingEvents: [CalendarEvent] {
        let start: Date
        let end: Date
        if allDay {
            let dayStart = Calendar.current.startOfDay(for: startDateTime)
            start = dayStart
            end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } else {
            start = startDateTime
            end = normalizedEndDate()
        }
        guard end > start else { return [] }
        return checkForOverlappingEvents(
            start: start,
            end: end,
            excludingEventID: eventToEdit?.id
        )
    }

    private func checkForOverlappingEvents(start: Date, end: Date, excludingEventID: UUID? = nil) -> [CalendarEvent] {
        let repo = collegePersistence.calendarRepository
        guard let events = try? repo.fetchEventsOverlapping(start: start, end: end, limit: 50) else {
            return []
        }
        return events.filter { event in
            if event.id == excludingEventID { return false }
            if let semester, event.semester?.id != semester.id { return false }
            return true
        }
    }
    
    func save() {
        guard canSave else {
            AppNotificationCenter.shared.post(
                kind: .warning,
                title: "Missing Title",
                message: "Please enter an event title",
                autoDismissAfter: 3
            )
            return
        }
        
        // Validate end time is after start time
        let endTime = allDay ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: startDateTime)) ?? startDateTime : normalizedEndDate()
        let startTime = allDay ? Calendar.current.startOfDay(for: startDateTime) : startDateTime
        
        if endTime <= startTime {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Invalid Time",
                message: "End time must be after start time",
                autoDismissAfter: 4
            )
            return
        }
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let start: Date
        let end: Date
        if allDay {
            let dayStart = Calendar.current.startOfDay(for: startDateTime)
            start = dayStart
            end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        } else {
            start = startDateTime
            end = normalizedEndDate()
        }
        
        // Check for overlapping events
        let overlappingEvents = checkForOverlappingEvents(
            start: start,
            end: end,
            excludingEventID: eventToEdit?.id
        )
        
        if !overlappingEvents.isEmpty && overlapPolicy.blocksSave {
            let eventTitles = overlappingEvents.compactMap { $0.title }.prefix(3).joined(separator: ", ")
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Event Conflict",
                message: "Save blocked — overlaps with \(eventTitles)",
                autoDismissAfter: 5
            )
            return
        }
        
        if !overlappingEvents.isEmpty {
            let eventTitles = overlappingEvents.compactMap { $0.title }.prefix(3).joined(separator: ", ")
            let moreCount = overlappingEvents.count > 3 ? " and \(overlappingEvents.count - 3) more" : ""
            AppNotificationCenter.shared.post(
                kind: .warning,
                title: "Event Conflict",
                message: "\(trimmedTitle) overlaps with \(eventTitles)\(moreCount)",
                autoDismissAfter: 5
            )
        }
        
        // Check for events at the exact same time
        let sameTimeEvents = overlappingEvents.filter { event in
            event.startDate == start && event.endDate == end
        }
        
        if !sameTimeEvents.isEmpty && overlappingEvents.count > sameTimeEvents.count {
            // Only show if there are other overlapping events (not just same-time)
            let count = sameTimeEvents.count + 1 // +1 for the current event
            AppNotificationCenter.shared.post(
                kind: .info,
                title: "Multiple Events",
                message: "You have \(count) events at \(start.formatted(date: .omitted, time: .shortened))",
                autoDismissAfter: 4
            )
        }
        
        let notes = trimmedDescription.isEmpty ? nil : trimmedDescription
        let eventLocation = trimmedLocation.isEmpty ? nil : trimmedLocation
        let input = buildWriteInput(
            title: trimmedTitle,
            start: start,
            end: end,
            notes: notes,
            location: eventLocation
        )
        let options = writeOptionsForSave()

        Task { @MainActor in
            do {
                if let eventToEdit {
                    try await CalendarEventWritePipeline.shared.update(
                        eventID: eventToEdit.id,
                        input: input,
                        options: CalendarEventWriteOptions(
                            skipExport: true,
                            skipReminders: false,
                            reminderLeadMinutes: options.reminderLeadMinutes
                        )
                    )
                    persistTravelSettings(eventID: eventToEdit.id)
                    persistReminderPayloadIfNeeded(for: eventToEdit)
                    let exportResult = await CalendarSyncExportBridge.exportAfterWriteAndReport(
                        eventID: eventToEdit.id,
                        options: options
                    )
                    guestInviteSyncFailed = exportResult.attemptedGuestInvites
                        && exportResult.guestInvitesSucceeded == false
                    if exportResult.allSucceeded {
                        AppNotificationCenter.shared.post(
                            kind: .success,
                            title: "Event Updated",
                            message: syncSuccessMessage(for: trimmedTitle, exportResult: exportResult),
                            autoDismissAfter: 3
                        )
                    } else {
                        AppNotificationCenter.shared.post(
                            kind: .warning,
                            title: "Saved Locally",
                            message: syncFailureMessage(for: trimmedTitle, exportResult: exportResult),
                            autoDismissAfter: 5
                        )
                    }
                } else {
                    let createdID = try await CalendarEventWritePipeline.shared.create(
                        input: input,
                        options: CalendarEventWriteOptions(
                            skipExport: true,
                            skipReminders: false,
                            reminderLeadMinutes: options.reminderLeadMinutes
                        )
                    )
                    persistTravelSettings(eventID: createdID)
                    persistReminderPayloadIfNeeded(forID: createdID)
                    let exportResult = await CalendarSyncExportBridge.exportAfterWriteAndReport(
                        eventID: createdID,
                        options: options
                    )
                    guestInviteSyncFailed = exportResult.attemptedGuestInvites
                        && exportResult.guestInvitesSucceeded == false
                    if exportResult.allSucceeded {
                        AppNotificationCenter.shared.post(
                            kind: .success,
                            title: "Event Created",
                            message: syncSuccessMessage(for: trimmedTitle, exportResult: exportResult),
                            autoDismissAfter: 3
                        )
                    } else {
                        AppNotificationCenter.shared.post(
                            kind: .warning,
                            title: "Event Created",
                            message: syncFailureMessage(for: trimmedTitle, exportResult: exportResult),
                            autoDismissAfter: 5
                        )
                    }
                }
                isPresented = false
            } catch {
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Save Failed",
                    message: error.localizedDescription,
                    autoDismissAfter: 4
                )
            }
        }
    }

    private func persistReminderPayloadIfNeeded(forID id: UUID) {
        guard let event = try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: id) else { return }
        persistReminderPayloadIfNeeded(for: event)
    }

    private func persistTravelSettings(eventID: UUID) {
        let settings = TravelTimeSettings(
            enabled: travelTimeEnabled,
            transport: travelTransport,
            minutes: travelTimeMinutes,
            resolvedLocation: resolvedLocation
        )

        if settings.enabled || settings.minutes != nil || settings.resolvedLocation != nil {
            TravelTimeStore.saveOverride(settings, eventID: eventID)
        } else {
            TravelTimeStore.clearOverride(eventID: eventID)
        }
        TravelTimeStore.saveLastTransport(travelTransport)
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    do {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        defer { url.stopAccessingSecurityScopedResource() }

                        let document = try await collegePersistence.addVaultDocumentReturning(
                            fromSelectedURL: url,
                            category: .calendar,
                            source: "calendar"
                        )
                        if let eventToEdit {
                            try AppDataStore.shared.vaultRepository.linkVaultDocumentToCalendarEvent(
                                id: document.id,
                                eventID: eventToEdit.id
                            )
                            linkedAttachmentIDs.append(document.id)
                        }
                        recentFileImports.append(url)
                    } catch {
                        AppNotificationCenter.shared.post(
                            kind: .error,
                            title: "Import Failed",
                            message: error.localizedDescription,
                            autoDismissAfter: 4
                        )
                    }
                }
            }
        case .failure(let error):
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Import Failed",
                message: error.localizedDescription,
                autoDismissAfter: 4
            )
        }
    }

    // MARK: - Redesigned UI Implementation
    
    private var cardBackgroundColor: Color {
        DesignSystem.Colors.surface
    }

    var primaryTextColor: Color {
        DesignSystem.Colors.textMain
    }

    var secondaryTextColor: Color {
        DesignSystem.Colors.textLight
    }

    private var dividerColor: Color {
        Color(nsColor: .separatorColor).opacity(0.7)
    }

    private var chipBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    var fieldBackgroundColor: Color {
        DesignSystem.Colors.surface
    }

    var subtleStrokeColor: Color {
        Color(nsColor: .separatorColor)
    }

    private var selectedOrPrimaryGoogleCalendar: ConnectedCalendar? {
        let googleCalendars = calendarManager.connectedCalendars.filter { $0.source == "Google" }
        if let selectedGoogleCalendarID,
           let selected = googleCalendars.first(where: { $0.remoteID == selectedGoogleCalendarID }) {
            return selected
        }
        return googleCalendars.first
    }

    var associatedCalendarColor: Color {
        if let selectedGoogle = selectedOrPrimaryGoogleCalendar {
            return selectedGoogle.color
        }

        if let course = selectedCourse() {
            let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                return Self.stableColor(for: code)
            }
        }

        if let appCalendar = calendarManager.connectedCalendars.first(where: { $0.id == "Apple:Home" }) {
            return appCalendar.color
        }

        return DesignSystem.Colors.primary
    }

    var showsInternalHeaderPill: Bool {
        switch presentationStyle {
        case .fullScreenOverlay, .dynamicIsland:
            return true
        case .anchoredPanel, .bottomSheet, .inspectorSidebar:
            return false
        }
    }

    private var externalPrefill: ExternalPrefill {
        ExternalPrefill(title: initialTitle, start: initialStartDateTime, end: initialEndDateTime)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch presentationStyle {
        case .fullScreenOverlay:
            ZStack {
                Rectangle()
                    .fill(DesignSystem.Colors.bgMain.opacity(0.98))
                    .ignoresSafeArea()
                    .onTapGesture { requestDismissAnimated() }

                editorCard
                    .frame(maxWidth: 980)
            }
        case .anchoredPanel, .inspectorSidebar, .dynamicIsland, .bottomSheet:
            editorCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var body: some View {
        editorViewWithKeyboardHandlers
    }

    private var editorViewWithKeyboardHandlers: some View {
        editorViewWithStateObservers
            .onMoveCommand { handleLocationMoveCommand($0) }
            .onSubmit { handleLocationSubmitCommand() }
            .onExitCommand { handleLocationExitCommand() }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
    }

    private var editorViewWithStateObservers: some View {
        editorViewLifecycle
            .onChange(of: location) { _, newValue in handleLocationChanged(newValue) }
            .onChange(of: descriptionText) { _, _ in handleDescriptionChanged() }
            .onChange(of: externalPrefill) { _, _ in applyExternalPrefillIfNeeded() }
            .onChange(of: locationPermissionService.lastLocation) { _, newLocation in
                handleLocationPermissionLocationChanged(newLocation)
            }
            .onChange(of: selectedCourseID) { _, _ in handleSelectedCourseChanged() }
            .onChange(of: recurrenceRule) { _, _ in handleRecurrenceChanged() }
            .onChange(of: recurrenceInterval) { _, _ in handleRecurrenceChanged() }
            .onChange(of: recurrenceWeekdays) { _, _ in handleRecurrenceChanged() }
            .onChange(of: recurrenceHasEndDate) { _, _ in handleRecurrenceChanged() }
            .onChange(of: recurrenceEndDate) { _, _ in handleRecurrenceChanged() }
            .onChange(of: locationPermissionService.status) { _, _ in handleLocationPermissionStatusChanged() }
            .onChange(of: modalCoordinator.activeModal) { oldValue, newValue in
                handleModalCoordinatorChange(oldValue: oldValue, newValue: newValue)
            }
            .onDisappear {
                pendingLocationSuggestionWorkItem?.cancel()
            }
    }

    private var editorViewLifecycle: some View {
        rootContent
            .onAppear {
                applyExternalPrefillIfNeeded()
                applyInitialDisplayColorFromSourceIfNeeded()
                alertLeadMinutes = loadAlertLeadMinutesFromEvent()
                recomputeTravelEstimateIfPossible()
                locationSearchService.applyLocationBias(from: locationPermissionService.lastLocation)
                hydrateCalendarDestinationsIfNeeded()
                hydrateGuestsFromEventIfNeeded()
                hydrateLinkedAttachmentsIfNeeded()
                if isInspectorEmbedded {
                    showInspectorOnboardingTips = CalendarInspectorOnboarding.shouldShowTips
                }
                onLiveUpdate?(title, startDateTime, endDateTime, customColor)
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEditorSave)) { _ in
                save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEditorDismiss)) { _ in
                requestDismissAnimated()
            }
            .onReceive(collegePersistence.$vaultDidChangeToken) { _ in
                reloadLinkedAttachments()
            }
            .onChange(of: title) { _, newValue in
                eventToEdit?.title = newValue
                onLiveUpdate?(newValue, startDateTime, endDateTime, customColor)
                scheduleAutosaveIfEditing()
            }
            .onChange(of: startDateTime) { _, newValue in
                enforceDateRangeConsistency(changedByStart: true)
                eventToEdit?.startDate = newValue
                collegePersistence.saveCalendarChanges()
                collegePersistence.notifyCalendarDidChange()
                onLiveUpdate?(title, newValue, endDateTime, customColor)
                scheduleAutosaveIfEditing()
            }
            .onChange(of: endDateTime) { _, newValue in
                enforceDateRangeConsistency(changedByStart: false)
                eventToEdit?.endDate = newValue
                collegePersistence.saveCalendarChanges()
                collegePersistence.notifyCalendarDidChange()
                onLiveUpdate?(title, startDateTime, newValue, customColor)
                scheduleAutosaveIfEditing()
            }
            .onChange(of: allDay) { _, newValue in
                eventToEdit?.allDay = newValue
                guard newValue else {
                    hasAutoAdjustedEndTime = false
                    enforceDateRangeConsistency(changedByStart: true)
                    scheduleAutosaveIfEditing()
                    return
                }
                let dayStart = Calendar.current.startOfDay(for: startDateTime)
                startDateTime = dayStart
                endDateTime = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                hasAutoAdjustedEndTime = false
                scheduleAutosaveIfEditing()
            }
            .onChange(of: eventColorChoice) { _, _ in
                guard let eventToEdit else { return }
                applyCurrentColorOverride(eventID: eventToEdit.id)
                collegePersistence.notifyCalendarDidChange()
                scheduleAutosaveIfEditing()
            }
            .onChange(of: customColor) { _, _ in
                guard isColorOverridden, let eventToEdit else { return }
                applyCurrentColorOverride(eventID: eventToEdit.id)
                collegePersistence.notifyCalendarDidChange()
                scheduleAutosaveIfEditing()
            }
            .onChange(of: customColor) { _, newColor in
                onLiveUpdate?(title, startDateTime, endDateTime, newColor)
            }
    }

    private func handleLocationMoveCommand(_ direction: MoveCommandDirection) {
        guard case .some = focusedLocationInput else { return }
        if direction == .up {
            moveLocationSuggestionSelection(by: -1)
        } else if direction == .down {
            moveLocationSuggestionSelection(by: 1)
        }
    }

    private func handleLocationSubmitCommand() {
        guard case .some = focusedLocationInput else { return }
        applyHighlightedLocationSuggestionIfPossible()
    }

    private func handleLocationExitCommand() {
        guard case .some = focusedLocationInput else { return }
        locationSuggestions = []
    }

    private func handleSelectedCourseChanged() {
        if !isColorOverridden {
            setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: selectedCourse()))
        }
        scheduleAutosaveIfEditing()
    }

    private func handleLocationChanged(_ newValue: String) {
        eventToEdit?.location = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
        resolvedLocation = nil
        scheduleLocationSuggestionsRefresh()
        scheduleAutosaveIfEditing()
    }

    private func handleDescriptionChanged() {
        eventToEdit?.notes = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : descriptionText
        scheduleAutosaveIfEditing()
    }

    private func hydrateCalendarDestinationsIfNeeded() {
        if selectedGoogleCalendarID == nil {
            if let eventToEdit,
               let mapped = calendarManager.googleExportCalendarID(forLocalEventID: eventToEdit.id) {
                selectedGoogleCalendarID = mapped
            } else if calendarManager.googleStatus == .connected {
                selectedGoogleCalendarID = selectedOrPrimaryGoogleCalendar?.remoteID
            }
        }
        if selectedAppleCalendarID == nil, calendarManager.appleStatus == .connected {
            let appleCals = calendarManager.connectedCalendars.filter { $0.source == "Apple" }
            selectedAppleCalendarID = appleCals.first?.remoteID
        }
    }

    private func hydrateGuestsFromEventIfNeeded() {
        guard let eventToEdit, selectedGuests.isEmpty else { return }
        let records = CalendarEventGuestsCodec.decodeFlexible(eventToEdit.attendeesJSON)
        guard !records.isEmpty else { return }
        var responses: [String: String] = [:]
        selectedGuests = records.map { record in
            if let email = record.email?.lowercased(),
               let status = record.responseStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
               !status.isEmpty {
                responses[email] = status
            }
            let contact = CNMutableContact()
            contact.givenName = record.name
            if let email = record.email {
                contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
            }
            return contact
        }
        guestResponseByEmail = responses
    }

    private func hydrateLinkedAttachmentsIfNeeded() {
        guard linkedAttachmentIDs.isEmpty else { return }
        reloadLinkedAttachments()
    }

    private func reloadLinkedAttachments() {
        guard let eventToEdit else { return }
        if let docs = try? AppDataStore.shared.vaultRepository.fetchDocuments(
            linkedCalendarEventID: eventToEdit.id
        ) {
            linkedAttachmentIDs = docs.map(\.id)
        }
    }

    var linkedAttachmentDocuments: [VaultDocument] {
        guard let eventToEdit else { return [] }
        return (try? AppDataStore.shared.vaultRepository.fetchDocuments(
            linkedCalendarEventID: eventToEdit.id
        )) ?? []
    }

    func openLinkedAttachment(_ document: VaultDocument) {
        if let url = VaultDocumentAccess.urlForDocument(id: document.id, collegePersistence: collegePersistence) {
            NSWorkspace.shared.open(url)
            return
        }
        AppNotificationCenter.shared.post(
            kind: .warning,
            title: "Document Unavailable",
            message: "Could not access \(document.fileName).",
            autoDismissAfter: 3
        )
    }

    func unlinkLinkedAttachment(_ document: VaultDocument) {
        do {
            try AppDataStore.shared.vaultRepository.unlinkVaultDocumentFromCalendarEvent(id: document.id)
            linkedAttachmentIDs.removeAll { $0 == document.id }
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Attachment Unlinked",
                message: "Removed \(document.fileName) from this event.",
                autoDismissAfter: 2
            )
        } catch {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Unlink Failed",
                message: error.localizedDescription,
                autoDismissAfter: 4
            )
        }
    }

    private func handleLocationPermissionLocationChanged(_ newLocation: CLLocation?) {
        locationSearchService.applyLocationBias(from: newLocation)
        recomputeTravelEstimateIfPossible()
        scheduleLocationSuggestionsRefresh()
    }

    private func handleRecurrenceChanged() {
        recurrenceRule = Self.normalizedRecurrenceRule(recurrenceRule)
        recurrenceInterval = max(1, recurrenceInterval)
        if recurrenceRule == "none" {
            recurrenceInterval = 1
            recurrenceWeekdays = []
            recurrenceHasEndDate = false
        } else if recurrenceRule == "weekly", recurrenceWeekdays.isEmpty {
            let calendarWeekday = Calendar.current.component(.weekday, from: startDateTime)
            let weekday = ((calendarWeekday + 5) % 7) + 1
            recurrenceWeekdays = [weekday]
        } else if recurrenceRule != "weekly" {
            recurrenceWeekdays = []
        }
        scheduleAutosaveIfEditing()
    }

    private func handleLocationPermissionStatusChanged() {
        recomputeTravelEstimateIfPossible()
    }

    private func applyExternalPrefillIfNeeded() {
        guard eventToEdit == nil else { return }
        // Only update if the user hasn't changed anything yet.
        guard isEditorPristineForExternalPrefill else { return }

        let trimmedTitle = (initialTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            title = trimmedTitle
        }

        if let start = initialStartDateTime {
            startDateTime = start
            if let end = initialEndDateTime {
                endDateTime = end
            } else {
                endDateTime = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
            }
        } else if let end = initialEndDateTime {
            endDateTime = end
        }
    }

    private var isEditorPristineForExternalPrefill: Bool {
        let currentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentNotes = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentTitle == initialSnapshot.title
            && startDateTime == initialSnapshot.start
            && endDateTime == initialSnapshot.end
            && allDay == initialSnapshot.allDay
            && currentLocation == initialSnapshot.location
            && currentNotes == initialSnapshot.notes
            && selectedCourseID == initialSnapshot.courseID
            && recurrenceRule == initialSnapshot.recurrenceRule
            && recurrenceInterval == initialSnapshot.recurrenceInterval
            && recurrenceWeekdays == initialSnapshot.recurrenceWeekdays
            && recurrenceHasEndDate == initialSnapshot.recurrenceHasEndDate
            && recurrenceEndDate == initialSnapshot.recurrenceEndDate
    }

    private func applyInitialDisplayColorFromSourceIfNeeded() {
        guard let eventToEdit else { return }
        guard !isColorOverridden else { return }
        guard eventToEdit.course == nil else { return }
        guard let sourceColor = calendarManager.sourceCalendarColor(for: eventToEdit.calendarStoredSnapshot) else { return }

        setDisplayedColor(sourceColor)
    }

    private var editorCard: some View {
        ZStack(alignment: .trailing) {
            editorCardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    // Measure real content height via GeometryReader on the actual instance,
                    // eliminating the hidden duplicate-body layout pass.
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: AddCalendarItemOverlayPreferredHeightKey.self,
                                value: proxy.size.height
                            )
                    }
                )

            if isShowingLocationPicker {
                LocationPickerSheet(
                    onDismiss: {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            isShowingLocationPicker = false
                        }
                    },
                    searchService: locationSearchService,
                    onSelect: { resolved in
                        resolvedLocation = resolved
                        location = resolved.displayName
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            isShowingLocationPicker = false
                        }
                        recomputeTravelEstimateIfPossible()
                    }
                )
                .frame(width: 420)
                .transition(reduceMotion ? .identity : .move(edge: .trailing))
                .zIndex(2)
            }
        }
        .background(outerContainerBackground)
        .clipShape(.rect(cornerRadius: outerContainerCornerRadius))
        .shadow(
            color: outerContainerShadowColor,
            radius: outerContainerShadowRadius,
            x: 0,
            y: outerContainerShadowYOffset
        )
        .contentShape(Rectangle())
        .onTapGesture { }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { mainCardHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in mainCardHeight = newValue }
            }
        )
        .overlay(alignment: .top) {
            if activeBottomPanel != .none {
                Group {
                    if activeBottomPanel == .alerts {
                        CalendarAlertsPanel(
                            options: supportedAlertOffsets,
                            selectedOffsets: reminderScheduleMinutes,
                            onToggle: { toggleAlertOffset($0) },
                            onAddCustom: { addCustomAlertOffset($0) },
                            onClear: { alertLeadMinutes = [] },
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if activeBottomPanel == .recurrence {
                        CalendarRecurrencePanel(
                            frequency: $recurrenceRule,
                            interval: $recurrenceInterval,
                            weekdays: $recurrenceWeekdays,
                            hasEndDate: $recurrenceHasEndDate,
                            endDate: $recurrenceEndDate,
                            startDate: startDateTime,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            }
                        )
                    } else if activeBottomPanel == .course {
                        CalendarCoursePanel(
                            courses: allCourses,
                            selectedCourseID: selectedCourseID,
                            semesterName: semester?.name,
                            isFullscreen: usesCompactEditorLayout,
                            onSelectCourse: { id in
                                selectedCourseID = id
                                if !isColorOverridden {
                                    setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: selectedCourse()))
                                }
                            },
                            onCreateCourse: { code, name in
                                if let created = createCourseFromEditor(code: code, name: name) {
                                    selectedCourseID = created.id
                                    if !isColorOverridden {
                                        setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: created))
                                    }
                                }
                            },
                            onDeleteSelectedCourse: {
                                unlinkSelectedCourseFromEvent()
                            },
                            onOpenCourseBuilder: {
                                openCourseBuilderModal()
                            },
                            onBack: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            },
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            }
                        )
                        .frame(maxWidth: usesCompactEditorLayout ? 820 : nil)
                        .frame(maxHeight: usesCompactEditorLayout ? 560 : nil)
                    } else if activeBottomPanel == .notes {
                        CalendarNotesPanel(
                            text: $descriptionText,
                            onSave: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            }
                        )
                    } else if activeBottomPanel == .files {
                        CalendarFilesPanel(
                            linkedDocuments: linkedAttachmentDocuments,
                            recentImports: recentFileImports,
                            compactStyle: isInspectorEmbedded,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            },
                            onBrowse: { isShowingFileImporter = true },
                            onOpenDocument: openLinkedAttachment,
                            onUnlinkDocument: unlinkLinkedAttachment
                        )
                    }
                }
                .offset(y: usesCompactEditorLayout ? (activeBottomPanel == .course ? 0 : 12) : mainCardHeight + 16)
                .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var outerContainerBackground: Color {
        switch presentationStyle {
        case .dynamicIsland, .anchoredPanel, .inspectorSidebar:
            return .clear
        case .fullScreenOverlay, .bottomSheet:
            return cardBackgroundColor
        }
    }

    var outerContainerCornerRadius: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .anchoredPanel, .inspectorSidebar:
            return 0
        case .fullScreenOverlay:
            return 16
        case .bottomSheet:
            return 22
        }
    }

    private var outerContainerShadowColor: Color {
        switch presentationStyle {
        case .dynamicIsland, .anchoredPanel, .inspectorSidebar:
            return Color.clear
        case .fullScreenOverlay:
            return Color.black.opacity(0.4)
        case .bottomSheet:
            return Color.black.opacity(0.18)
        }
    }

    private var outerContainerShadowRadius: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .anchoredPanel, .inspectorSidebar:
            return 0
        case .fullScreenOverlay:
            return 24
        case .bottomSheet:
            return 22
        }
    }

    private var outerContainerShadowYOffset: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .anchoredPanel, .inspectorSidebar:
            return 0
        case .fullScreenOverlay:
            return 12
        case .bottomSheet:
            return 14
        }
    }

    private var editorCardContent: some View {
        Group {
            switch presentationStyle {
            case .bottomSheet:
                bottomSheetEditorContent
            case .fullScreenOverlay, .anchoredPanel, .inspectorSidebar, .dynamicIsland:
                scrollableEditorCardContent
            }
        }
    }




    var hexColorEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hex color")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundStyle(primaryTextColor)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: customHexInput))
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(subtleStrokeColor, lineWidth: 1))

                TextField("e.g. ff0000", text: $customHexInput)
                    .textFieldStyle(PlainTextFieldStyle()) 
                    .padding(DesignSystem.Spacing.xs)
                    .background(fieldBackgroundColor)
                    .clipShape(.rect(cornerRadius: 4))
                    .frame(width: 100)
                    .foregroundStyle(primaryTextColor)
                    .onChange(of: customHexInput) { _, newValue in
                        let normalized = AddCalendarItemOverlay.normalizedHex(newValue)
                        if normalized != newValue { 
                            customHexInput = normalized 
                            return 
                        }
                        guard AddCalendarItemOverlay.isValidHexRGB(normalized) else { return }
                        applySelectedColor(Color(hex: normalized), choice: .custom)
                    }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(width: 200)
    }


}
