import SwiftUI
import CoreData
import MapKit
import AppKit
import Contacts
import ContactsUI
import UniformTypeIdentifiers

/// Full-screen modal used by the Calendar page to add a new event.
struct AddCalendarItemOverlay: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var locationPermissionService: LocationPermissionService
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @AppStorage("calDefaultReminderMinutes") private var defaultReminderMinutes: Int = 15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    enum PresentationStyle {
        case fullScreenOverlay
        case anchoredPanel
        case dynamicIsland
        case floatingCards
        case bottomSheet
    }

    @Binding var isPresented: Bool
    let semester: SemesterEntity?
    let initialTitle: String?
    let initialStartDateTime: Date?
    let initialEndDateTime: Date?
    let eventToEdit: CalendarEventEntity?
    let presentationStyle: PresentationStyle
    /// Called on every title/time/color change — drives the live ghost preview block.
    var onLiveUpdate: ((String, Date, Date, Color) -> Void)? = nil

    @State private var title: String = ""
    @State private var mainCardHeight: CGFloat = 0
    @State private var startDateTime: Date = Date()
    @State private var endDateTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var allDay: Bool = false

    @State private var location: String = ""
    @State private var descriptionText: String = ""
    @State private var isExpanded: Bool = true

    @State private var descriptionEditorMeasuredHeight: CGFloat = 18

    @State private var isShowingLocationPicker: Bool = false
    @StateObject private var locationSearchService = MapLocationSearchService()
    @State private var resolvedLocation: ResolvedLocation? = nil
    @State private var locationSuggestions: [ResolvedLocation] = []
    @State private var pendingLocationSuggestionWorkItem: DispatchWorkItem? = nil
    @State private var highlightedLocationSuggestionIndex: Int = 0

    @State private var travelTimeEnabled: Bool = false
    @State private var travelTransport: TravelTransport = TravelTimeStore.loadLastTransport()
    @State private var travelTimeMinutes: Int? = nil
    @State private var travelEstimateMinutes: Int? = nil
    @State private var isEstimatingTravel: Bool = false
    
    @State private var selectedGuests: [CNContact] = []
    @State private var contactPickerDelegate: Any? = nil // Holds strong reference to the delegate

    @State private var selectedCourseID: NSManagedObjectID? = nil
    @State private var selectedGoogleCalendarID: String? = nil

    private enum EventColorChoice: Equatable {
        case preset(Int)
        case custom
    }

    private static let presetEventColors: [Color] = [
        DesignSystem.Colors.primary,
        DesignSystem.Colors.success,
        DesignSystem.Colors.secondary,
        DesignSystem.Colors.warning,
        DesignSystem.Colors.error
    ]

    @State private var eventColorChoice: EventColorChoice = .preset(0)
    @State private var customColor: Color = DesignSystem.Colors.primary
    @State private var customHexInput: String = ""
    @State private var isShowingHexPopover: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isColorOverridden: Bool = false
    @State private var alertLeadMinutes: [Int] = [15]
    @State private var recurrenceRule: String = "none"
    @State private var recurrenceInterval: Int = 1
    @State private var recurrenceWeekdays: Set<Int> = []
    @State private var recurrenceHasEndDate: Bool = false
    @State private var recurrenceEndDate: Date = Date()
    @State private var hasAutoAdjustedEndTime: Bool = false

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

    private enum LocationInputFocus: Hashable {
        case bottomSheet
        case anchoredPanel
    }

    @FocusState private var focusedLocationInput: LocationInputFocus?

    private enum ActiveBottomPanel: Equatable {
        case none
        case alerts
        case recurrence
        case course
        case notes
        case files
    }
    
    @State private var activeBottomPanel: ActiveBottomPanel = .none
    @State private var recentFileImports: [URL] = [] // Track files for the current session UI
    
    private struct Snapshot: Equatable {
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        let location: String
        let notes: String
        let courseID: NSManagedObjectID?
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

    private static func defaultEventColor(for course: CourseEntity?) -> Color {
        guard let course else { return DesignSystem.Colors.primary }
        return stableColor(for: course.code ?? "")
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

    private func setDisplayedColor(_ color: Color, forceChoice: EventColorChoice? = nil) {
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

    private func applySelectedColor(_ color: Color, choice: EventColorChoice) {
        isColorOverridden = true
        setDisplayedColor(color, forceChoice: choice)
    }

    private var courses: [CourseEntity] { semester?.coursesArray ?? [] }

    private var allCourses: [CourseEntity] {
        let merged = coreDataManager.semesters
            .flatMap { $0.coursesArray }
            .reduce(into: [NSManagedObjectID: CourseEntity]()) { partialResult, course in
                partialResult[course.objectID] = course
            }
        return merged.values.sorted {
            let lhsCode = ($0.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsCode = ($1.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if lhsCode != rhsCode {
                return lhsCode.localizedCaseInsensitiveCompare(rhsCode) == .orderedAscending
            }
            let lhsName = ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsName = ($1.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    init(
        isPresented: Binding<Bool>,
        semester: SemesterEntity?,
        initialTitle: String? = nil,
        initialStartDateTime: Date? = nil,
        initialEndDateTime: Date? = nil,
        eventToEdit: CalendarEventEntity? = nil,
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
            let existingStart = eventToEdit.startDate ?? (initialStartDateTime ?? Date())
            let existingEnd = eventToEdit.endDate
                ?? (initialEndDateTime ?? (Calendar.current.date(byAdding: .hour, value: 1, to: existingStart) ?? existingStart))

            _title = State(initialValue: eventToEdit.title ?? "")
            _startDateTime = State(initialValue: existingStart)
            _endDateTime = State(initialValue: existingEnd)
            _allDay = State(initialValue: eventToEdit.allDay)
            _location = State(initialValue: eventToEdit.location ?? "")
            _descriptionText = State(initialValue: eventToEdit.notes ?? "")
            _selectedCourseID = State(initialValue: eventToEdit.course?.objectID)
            let recurrenceSettings = Self.recurrenceSettings(from: eventToEdit.value(forKey: "recurrenceRule") as? String)
            let existingRecurrence = recurrenceSettings.frequency
            _recurrenceRule = State(initialValue: existingRecurrence)
            _recurrenceInterval = State(initialValue: recurrenceSettings.interval)
            _recurrenceWeekdays = State(initialValue: Set(recurrenceSettings.weekdays))
            _recurrenceHasEndDate = State(initialValue: recurrenceSettings.endDate != nil)
            _recurrenceEndDate = State(initialValue: recurrenceSettings.endDate ?? existingEnd)

            let initialOverrideHex = (eventToEdit.id).flatMap { EventColorOverrides.color(for: $0)?.hexRGBString() }
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
                title: (eventToEdit.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                start: existingStart,
                end: existingEnd,
                allDay: eventToEdit.allDay,
                location: (eventToEdit.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                notes: (eventToEdit.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                courseID: eventToEdit.course?.objectID,
                colorHex: initialOverrideHex,
                recurrenceRule: existingRecurrence,
                recurrenceInterval: recurrenceSettings.interval,
                recurrenceWeekdays: Set(recurrenceSettings.weekdays),
                recurrenceHasEndDate: recurrenceSettings.endDate != nil,
                recurrenceEndDate: recurrenceSettings.endDate ?? existingEnd
            )

            let storedTravel = (eventToEdit.id).flatMap { TravelTimeStore.loadOverride(eventID: $0) }
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

    private var travelTimeMinuteOptions: [Int] {
        [5, 10, 15, 20, 30, 45, 60, 90, 120]
    }

    private func roundedToNearestFive(_ minutes: Int) -> Int {
        max(0, Int((Double(minutes) / 5.0).rounded() * 5.0))
    }

    private func distanceText(for option: ResolvedLocation) -> String? {
        guard let origin = locationPermissionService.lastLocation else { return nil }
        let meters = CLLocation(latitude: option.latitude, longitude: option.longitude).distance(from: origin)
        guard meters.isFinite else { return nil }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    private func applyLocationSuggestion(_ option: ResolvedLocation) {
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

    private static let recurrenceOptions: [String] = ["none", "daily", "weekly", "monthly", "yearly"]

    private static func normalizedRecurrenceRule(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if recurrenceOptions.contains(value) {
            return value
        }
        return "none"
    }

    private static func recurrenceSettings(from raw: String?) -> RecurrenceSettings {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }

        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RecurrenceSettings.self, from: data) {
            let frequency = normalizedRecurrenceRule(decoded.frequency)
            let interval = max(1, decoded.interval)
            let weekdays = Array(Set(decoded.weekdays.filter { (1...7).contains($0) })).sorted()
            let endDate = decoded.endDate
            if frequency == "none" {
                return .none
            }
            return RecurrenceSettings(frequency: frequency, interval: interval, weekdays: weekdays, endDate: endDate)
        }

        let legacy = normalizedRecurrenceRule(raw)
        if legacy == "none" { return .none }
        return RecurrenceSettings(frequency: legacy, interval: 1, weekdays: [], endDate: nil)
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

    private var recurrenceSummaryLabel: String {
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

    private func recurrenceLabel(for rule: String) -> String {
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

    private func setRecurrenceRule(_ value: String) {
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

    private func openCourseSearchOrBuilder() {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeBottomPanel = .course
        }
    }

    private func courseDisplayLabel(_ course: CourseEntity?) -> String {
        guard let course else { return "No course" }
        let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty && !name.isEmpty { return "\(code) - \(name)" }
        if !code.isEmpty { return code }
        if !name.isEmpty { return name }
        return "Course"
    }

    private func openCourseBuilderModal() {
        shouldReturnToCoursePanelAfterCatalog = true
        let targetSemester: SemesterEntity?
        if let semester {
            targetSemester = semester
        } else {
            if let existing = coreDataManager.semesters.first {
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
                let created = coreDataManager.findOrCreateSemester(season: season, year: year)
                coreDataManager.saveCalendarChanges()
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
        modalCoordinator.activeModal = .addCatalogCourse(semesterObjectID: targetSemester.objectID)
    }

    private func handleModalCoordinatorChange(oldValue: ModalCoordinator.ActiveModal?, newValue: ModalCoordinator.ActiveModal?) {
        if shouldReturnToCoursePanelAfterCatalog, oldValue != nil, newValue == nil {
            shouldReturnToCoursePanelAfterCatalog = false
            withAnimation(.easeInOut(duration: 0.2)) {
                activeBottomPanel = .course
            }
        }
    }

    private var selectedCourseSummaryLabel: String {
        guard let course = selectedCourse() else { return "No course" }
        let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty { return code }
        let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Course" : name
    }

    private func recomputeTravelEstimateIfPossible() {
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

    private func selectedCourse() -> CourseEntity? {
        guard let id = selectedCourseID else { return nil }
        return (try? coreDataManager.viewContext.existingObject(with: id)) as? CourseEntity
    }

    private func createCourseFromEditor(code: String, name: String) -> CourseEntity? {
        guard let semester else { return nil }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty || !trimmedName.isEmpty else { return nil }

        let normalizedCode = trimmedCode.isEmpty ? "NEW100" : trimmedCode.uppercased()
        let normalizedName = trimmedName.isEmpty ? normalizedCode : trimmedName
        return coreDataManager.addCourse(
            to: semester,
            code: normalizedCode,
            name: normalizedName,
            credits: 3,
            status: "Planned",
            gradingType: "Letter Grade",
            professor: nil
        )
    }

    private func removeSelectedCourseFromPlanner() {
        guard let course = selectedCourse() else { return }
        selectedCourseID = nil
        coreDataManager.deleteCourse(course)
        if !isColorOverridden {
            setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: nil))
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedEndDate() -> Date {
        let calendar = Calendar.current
        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
        return max(endDateTime, minimumEnd)
    }

    private var supportedAlertOffsets: [Int] {
        [0, 5, 10, 15, 30, 60, 120, 1440]
    }

    private func normalizeAlertLeadMinutes(_ raw: [Int]) -> [Int] {
        Array(Set(raw.filter { $0 >= 0 })).sorted()
    }

    private func loadAlertLeadMinutesFromEvent() -> [Int] {
        guard let raw = eventToEdit?.value(forKey: "remindersJSON") as? String,
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

    private func toggleAlertOffset(_ minutes: Int) {
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

    private var reminderScheduleMinutes: [Int] {
        let normalized = normalizeAlertLeadMinutes(alertLeadMinutes)
        return normalized.isEmpty ? [] : normalized
    }

    private func reminderSummaryText(_ values: [Int]? = nil) -> String {
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

    private func persistReminderPayloadIfNeeded(for event: CalendarEventEntity) {
        let payload = reminderScheduleMinutes
        if payload.isEmpty {
            event.setValue(nil, forKey: "remindersJSON")
            return
        }
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        event.setValue(json, forKey: "remindersJSON")
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

    private func requestDismissAnimated() {
        if reduceMotion {
            requestDismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            requestDismiss()
        }
    }

    private func deleteEventNow() {
        guard let eventToEdit else { return }
        pendingAutosaveWorkItem?.cancel()

        let eventTitle = eventToEdit.title ?? "Event"

        if let localID = eventToEdit.id {
            Task { @MainActor in
                calendarManager.deleteEventFromGoogle(localEventID: localID)
            }
            Task { @MainActor in
                calendarManager.deleteEventFromAppleCalendar(localEventID: localID)
            }
        }

        if let id = eventToEdit.id {
            EventColorOverrides.clearColor(for: id)
            TravelTimeStore.clearOverride(eventID: id)
        }

        coreDataManager.deleteCalendarEvent(objectID: eventToEdit.objectID)
        
        AppNotificationCenter.shared.post(
            kind: .info,
            title: "Event Deleted",
            message: "\(eventTitle) removed from calendar",
            autoDismissAfter: 3
        )
        
        isPresented = false
    }

    private func applyColorOverride(eventID: UUID?, snapshot: Snapshot) {
        guard let eventID else { return }
        if let hex = snapshot.colorHex {
            EventColorOverrides.setColor(Color(hex: hex), for: eventID)
        } else {
            EventColorOverrides.clearColor(for: eventID)
        }
    }

    private func applyCurrentColorOverride(eventID: UUID?) {
        guard let eventID else { return }
        if isColorOverridden, let hex = customColor.hexRGBString() {
            EventColorOverrides.setColor(Color(hex: hex), for: eventID)
        } else {
            EventColorOverrides.clearColor(for: eventID)
        }
    }

    private func applySnapshotToStore(_ snapshot: Snapshot) {
        guard let eventToEdit else { return }

        let notes = snapshot.notes.isEmpty ? nil : snapshot.notes
        let location = snapshot.location.isEmpty ? nil : snapshot.location

        let course: CourseEntity? = {
            guard let courseID = snapshot.courseID else { return nil }
            return (try? coreDataManager.viewContext.existingObject(with: courseID)) as? CourseEntity
        }()

        coreDataManager.updateCalendarEvent(
            objectID: eventToEdit.objectID,
            title: snapshot.title.isEmpty ? (eventToEdit.title ?? "Event") : snapshot.title,
            startDate: snapshot.start,
            endDate: snapshot.end,
            allDay: snapshot.allDay,
            semester: semester,
            course: course,
            notes: notes,
            location: location
        )

        let settings = RecurrenceSettings(
            frequency: snapshot.recurrenceRule,
            interval: snapshot.recurrenceInterval,
            weekdays: Array(snapshot.recurrenceWeekdays).sorted(),
            endDate: snapshot.recurrenceHasEndDate ? snapshot.recurrenceEndDate : nil
        )
        eventToEdit.setValue(Self.recurrencePayloadString(from: settings), forKey: "recurrenceRule")
        coreDataManager.saveCalendarChanges()

        applyColorOverride(eventID: eventToEdit.id, snapshot: snapshot)
    }

    private func scheduleAutosaveIfEditing() {
        guard eventToEdit != nil else { return }
        pendingAutosaveWorkItem?.cancel()
        let item = DispatchWorkItem { [snapshot = currentSnapshot] in
            guard let eventToEdit else { return }
            let trimmedTitle = snapshot.title
            let trimmedDescription = snapshot.notes
            let trimmedLocation = snapshot.location
            let notes = trimmedDescription.isEmpty ? nil : trimmedDescription
            let eventLocation = trimmedLocation.isEmpty ? nil : trimmedLocation
            let course = selectedCourse()
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
            coreDataManager.updateCalendarEvent(
                objectID: eventToEdit.objectID,
                title: trimmedTitle.isEmpty ? (eventToEdit.title ?? "Event") : trimmedTitle,
                startDate: start,
                endDate: end,
                allDay: snapshot.allDay,
                semester: semester,
                course: course,
                notes: notes,
                location: eventLocation
            )
            let settings = RecurrenceSettings(
                frequency: snapshot.recurrenceRule,
                interval: snapshot.recurrenceInterval,
                weekdays: Array(snapshot.recurrenceWeekdays).sorted(),
                endDate: snapshot.recurrenceHasEndDate ? snapshot.recurrenceEndDate : nil
            )
            eventToEdit.setValue(Self.recurrencePayloadString(from: settings), forKey: "recurrenceRule")
            coreDataManager.saveCalendarChanges()
            applyColorOverride(eventID: eventToEdit.id, snapshot: snapshot)
        }
        pendingAutosaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func checkForOverlappingEvents(start: Date, end: Date, excludingEventID: UUID? = nil) -> [CalendarEventEntity] {
        let context = coreDataManager.viewContext
        let request = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
        
        // Find events that overlap with the given time range
        // Two events overlap if: start1 < end2 AND end1 > start2
        let predicate = NSPredicate(format: "startDate < %@ AND endDate > %@", end as NSDate, start as NSDate)
        
        if let excludingID = excludingEventID {
            let excludePredicate = NSPredicate(format: "id != %@", excludingID as CVarArg)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludePredicate])
        } else {
            request.predicate = predicate
        }
        
        // Filter by same semester if applicable
        if let semester = semester {
            let semesterPredicate = NSPredicate(format: "semester == %@", semester)
            if let existingPredicate = request.predicate {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [existingPredicate, semesterPredicate])
            } else {
                request.predicate = semesterPredicate
            }
        }
        
        do {
            return try context.fetch(request)
        } catch {
            return []
        }
    }
    
    private func save() {
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
        let course = selectedCourse()
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
            guard let eventStart = event.startDate, let eventEnd = event.endDate else { return false }
            return eventStart == start && eventEnd == end
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
        if let eventToEdit {
            eventToEdit.setValue(Self.recurrencePayloadString(from: recurrenceSettingsFromState), forKey: "recurrenceRule")
            coreDataManager.updateCalendarEvent(
                objectID: eventToEdit.objectID,
                title: trimmedTitle,
                startDate: start,
                endDate: end,
                allDay: allDay,
                semester: semester,
                course: course,
                notes: notes,
                location: eventLocation
            )
            persistReminderPayloadIfNeeded(for: eventToEdit)
            coreDataManager.saveCalendarChanges()
            applyColorOverride(eventID: eventToEdit.id, snapshot: currentSnapshot)

            if let eventID = eventToEdit.id {
                persistTravelSettings(eventID: eventID)
            }
            // Sync to Google only when the user explicitly selected a Google calendar.
            if let selectedGoogleCalendarID,
               !selectedGoogleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { @MainActor in
                    calendarManager.exportEventToGoogle(eventToEdit, targetCalendarID: selectedGoogleCalendarID)
                }
            }
            // Sync to Apple Calendar
            Task { @MainActor in
                calendarManager.exportEventToAppleCalendar(eventToEdit)
            }
            // Reschedule OS reminder
            if let eventID = eventToEdit.id {
                CalendarReminderScheduler.shared.reschedule(
                    eventID: eventID,
                    title: trimmedTitle,
                    startDate: start,
                    leadMinutes: reminderScheduleMinutes
                )
            }
            
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Event Updated",
                message: "Changes to \(trimmedTitle) saved",
                autoDismissAfter: 3
            )
        } else {
            let created = coreDataManager.addCalendarEvent(
                title: trimmedTitle,
                startDate: start,
                endDate: end,
                allDay: allDay,
                semester: semester,
                course: course,
                notes: notes,
                location: eventLocation
            )
            created.setValue(Self.recurrencePayloadString(from: recurrenceSettingsFromState), forKey: "recurrenceRule")
            persistReminderPayloadIfNeeded(for: created)
            coreDataManager.saveCalendarChanges()
            applyColorOverride(eventID: created.id, snapshot: currentSnapshot)

            if let eventID = created.id {
                persistTravelSettings(eventID: eventID)
            }
            // Sync to Google only when the user explicitly selected a Google calendar.
            if let selectedGoogleCalendarID,
               !selectedGoogleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { @MainActor in
                    calendarManager.exportEventToGoogle(created, targetCalendarID: selectedGoogleCalendarID)
                }
            }
            // Sync to Apple Calendar
            Task { @MainActor in
                calendarManager.exportEventToAppleCalendar(created)
            }
            // Schedule OS reminder
            if let eventID = created.id {
                CalendarReminderScheduler.shared.schedule(
                    eventID: eventID,
                    title: trimmedTitle,
                    startDate: start,
                    leadMinutes: reminderScheduleMinutes
                )
            }
            
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Event Created",
                message: "\(trimmedTitle) added to calendar",
                autoDismissAfter: 3
            )
        }
        isPresented = false
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

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    do {
                        guard url.startAccessingSecurityScopedResource() else { continue }
                        defer { url.stopAccessingSecurityScopedResource() }

                        try await coreDataManager.addVaultDocument(
                            fromSelectedURL: url,
                            category: .calendar,
                            source: "calendar"
                        )
                        recentFileImports.append(url)
                    } catch {
                        print("Failed to import file: \(error)")
                    }
                }
            }
        case .failure(let error):
            print("File import failed: \(error)")
        }
    }

    // MARK: - Redesigned UI Implementation
    
    private var cardBackgroundColor: Color {
        DesignSystem.Colors.surface
    }

    private var primaryTextColor: Color {
        DesignSystem.Colors.textMain
    }

    private var secondaryTextColor: Color {
        DesignSystem.Colors.textLight
    }

    private var dividerColor: Color {
        Color(nsColor: .separatorColor).opacity(0.7)
    }

    private var chipBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var fieldBackgroundColor: Color {
        DesignSystem.Colors.surface
    }

    private var subtleStrokeColor: Color {
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

    private var associatedCalendarColor: Color {
        if let selectedGoogle = selectedOrPrimaryGoogleCalendar {
            return selectedGoogle.color
        }

        if let course = selectedCourse(),
           let code = course.code?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            return Self.stableColor(for: code)
        }

        if let appCalendar = calendarManager.connectedCalendars.first(where: { $0.id == "Apple:Home" }) {
            return appCalendar.color
        }

        return DesignSystem.Colors.primary
    }

    private var showsInternalHeaderPill: Bool {
        switch presentationStyle {
        case .fullScreenOverlay, .dynamicIsland:
            return true
        case .anchoredPanel, .floatingCards, .bottomSheet:
            return false
        }
    }

    private var externalPrefill: ExternalPrefill {
        ExternalPrefill(title: initialTitle, start: initialStartDateTime, end: initialEndDateTime)
    }

    private var rootContent: AnyView {
        switch presentationStyle {
        case .fullScreenOverlay:
            return AnyView(
                ZStack {
                    Rectangle()
                        .fill(DesignSystem.Colors.bgMain.opacity(0.98))
                        .ignoresSafeArea()
                        .onTapGesture { requestDismissAnimated() }

                    editorCard
                        .frame(maxWidth: 980)
                }
            )
        case .anchoredPanel, .dynamicIsland, .floatingCards, .bottomSheet:
            return AnyView(editorCard)
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
                // Fire initial live update so the ghost block reflects the initial state.
                onLiveUpdate?(title, startDateTime, endDateTime, customColor)
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEditorSave)) { _ in
                save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEditorDismiss)) { _ in
                requestDismissAnimated()
            }
            .onChange(of: title) { _, newValue in
                eventToEdit?.title = newValue
                onLiveUpdate?(newValue, startDateTime, endDateTime, customColor)
                scheduleAutosaveIfEditing()
            }
            .onChange(of: startDateTime) { _, newValue in
                enforceDateRangeConsistency(changedByStart: true)
                // Immediately reflect time changes on the event block (no autosave delay).
                eventToEdit?.startDate = newValue
                coreDataManager.notifyCalendarDidChange()
                onLiveUpdate?(title, newValue, endDateTime, customColor)
                scheduleAutosaveIfEditing()
            }
            .onChange(of: endDateTime) { _, newValue in
                enforceDateRangeConsistency(changedByStart: false)
                eventToEdit?.endDate = newValue
                coreDataManager.notifyCalendarDidChange()
                onLiveUpdate?(title, startDateTime, newValue, customColor)
                scheduleAutosaveIfEditing()
            }
            .onChange(of: allDay) { _, newValue in
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
                coreDataManager.notifyCalendarDidChange()
                scheduleAutosaveIfEditing()
            }
            .onChange(of: customColor) { _, _ in
                guard isColorOverridden, let eventToEdit else { return }
                applyCurrentColorOverride(eventID: eventToEdit.id)
                coreDataManager.notifyCalendarDidChange()
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
        scheduleLocationSuggestionsRefresh()
        scheduleAutosaveIfEditing()
    }

    private func handleDescriptionChanged() {
        scheduleAutosaveIfEditing()
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
        guard let sourceColor = calendarManager.sourceCalendarColor(for: eventToEdit) else { return }

        setDisplayedColor(sourceColor)
    }

    private var editorCard: some View {
        ZStack(alignment: .trailing) {
            editorCardContent
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
        .cornerRadius(outerContainerCornerRadius)
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
                            isFullscreen: presentationStyle == .anchoredPanel,
                            onSelectCourse: { id in
                                selectedCourseID = id
                                if !isColorOverridden {
                                    setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: selectedCourse()))
                                }
                            },
                            onCreateCourse: { code, name in
                                if let created = createCourseFromEditor(code: code, name: name) {
                                    selectedCourseID = created.objectID
                                    if !isColorOverridden {
                                        setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: created))
                                    }
                                }
                            },
                            onDeleteSelectedCourse: {
                                removeSelectedCourseFromPlanner()
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
                        .frame(maxWidth: presentationStyle == .anchoredPanel ? 820 : nil)
                        .frame(maxHeight: presentationStyle == .anchoredPanel ? 560 : nil)
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
                            files: recentFileImports,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    activeBottomPanel = .none
                                }
                            },
                            onBrowse: { isShowingFileImporter = true }
                        )
                    }
                }
                .offset(y: presentationStyle == .anchoredPanel ? (activeBottomPanel == .course ? 0 : 12) : mainCardHeight + 16)
                .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var outerContainerBackground: Color {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return .clear
        case .fullScreenOverlay, .bottomSheet:
            return cardBackgroundColor
        }
    }

    private var outerContainerCornerRadius: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return 0
        case .fullScreenOverlay:
            return 16
        case .bottomSheet:
            return 22
        }
    }

    private var outerContainerShadowColor: Color {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return Color.clear
        case .fullScreenOverlay:
            return Color.black.opacity(0.4)
        case .bottomSheet:
            return Color.black.opacity(0.18)
        }
    }

    private var outerContainerShadowRadius: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return 0
        case .fullScreenOverlay:
            return 24
        case .bottomSheet:
            return 22
        }
    }

    private var outerContainerShadowYOffset: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
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
            case .floatingCards:
                verticalFloatingCardsContent
            case .bottomSheet:
                bottomSheetEditorContent
            case .fullScreenOverlay, .anchoredPanel, .dynamicIsland:
                scrollableEditorCardContent
            }
        }
    }

    private var bottomSheetEditorContent: some View {
        VStack(spacing: 0) {
            bottomSheetHeader
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Group {
                if isExpanded {
                    ViewThatFits(in: .vertical) {
                        bottomSheetExpandedContent

                        ScrollView {
                            bottomSheetExpandedContent
                        }
                    }
                } else {
                    bottomSheetMainFields
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().overlay(Color(hex: "f1f5f9"))

            bottomSheetFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: outerContainerCornerRadius, style: .continuous)
                .stroke(Color(hex: "f1f5f9"), lineWidth: 1)
        )
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: isExpanded)
    }

    private var bottomSheetExpandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            bottomSheetMainFields
            bottomSheetMoreOptionsExpanded
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomSheetMainFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            bottomSheetTitleField
            bottomSheetCourseAndLocationRow
            bottomSheetDateAndTimeRow
            if !calendarManager.connectedCalendars.filter({ $0.source == "Google" }).isEmpty {
                bottomSheetCalendarPicker
            }
            bottomSheetMoreOptionsToggle
        }
    }

    private var bottomSheetCalendarPicker: some View {
        let googleCals = calendarManager.connectedCalendars.filter { $0.source == "Google" }
        let selectedName = googleCals.first { $0.remoteID == selectedGoogleCalendarID }?.name
            ?? googleCals.first?.name
            ?? "Google Calendar"
        return VStack(alignment: .leading, spacing: 6) {
            Text("SAVE TO")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))
            Menu {
                ForEach(googleCals, id: \.id) { cal in
                    Button {
                        selectedGoogleCalendarID = cal.remoteID
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(cal.color)
                                .font(.system(size: 10))
                            Text(cal.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                    Text(selectedName)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private var bottomSheetMoreOptionsToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Text("More Options")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var bottomSheetMoreOptionsExpanded: some View {
        VStack(alignment: .leading, spacing: 14) {
            bottomSheetNotesSection

            HStack(alignment: .top, spacing: 14) {
                bottomSheetColorTagSection
                bottomSheetAlertsSection
            }

            bottomSheetAttachmentsSection
        }
        .padding(.top, 6)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
    }

    private var bottomSheetNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

            ZStack(alignment: .topLeading) {
                TextEditor(text: $descriptionText)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .frame(minHeight: 86)

                if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add detailed notes about the event...")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(subtleStrokeColor.opacity(0.55), lineWidth: 1)
            )
        }
    }

    private var bottomSheetColorTagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COLOR TAG")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

            HStack(spacing: 10) {
                ForEach(Array(AddCalendarItemOverlay.presetEventColors.enumerated()), id: \.offset) { index, color in
                    Button {
                        applySelectedColor(color, choice: .preset(index))
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle().stroke(
                                    DesignSystem.Colors.textMain.opacity(isColorSelection(index: index) ? 0.25 : 0.0),
                                    lineWidth: 3
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isColorSelection(index: Int) -> Bool {
        if case .preset(let selectedIndex) = eventColorChoice {
            return selectedIndex == index
        }
        return false
    }

    private var bottomSheetAlertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALERTS")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

            Menu {
                Button("None") { alertLeadMinutes = [] }
                Divider()
                ForEach(supportedAlertOffsets, id: \.self) { minutes in
                    Button {
                        toggleAlertOffset(minutes)
                    } label: {
                        if reminderScheduleMinutes.contains(minutes) {
                            Label(reminderSummaryText([minutes]), systemImage: "checkmark")
                        } else {
                            Text(reminderSummaryText([minutes]))
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    Text(reminderSummaryText())
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain.opacity(0.85))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(subtleStrokeColor.opacity(0.55), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomSheetAttachmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ATTACHMENTS")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

            Button {
                isShowingFileImporter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    Text("Click to upload")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain.opacity(0.85))

                    Text("or drag and drop")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            subtleStrokeColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var bottomSheetHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(eventToEdit == nil ? "New Event" : "Edit Event")
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Spacer(minLength: 0)

            Button {
                requestDismissAnimated()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var bottomSheetTitleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EVENT TITLE")
                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

            TextField("", text: $title, prompt: Text("e.g., Midterm Exam").foregroundColor(DesignSystem.Colors.textLight.opacity(0.75)))
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                )
        }
    }

    private var bottomSheetCourseAndLocationRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("COURSE")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

                bottomSheetCourseMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("LOCATION")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

                bottomSheetLocationField
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bottomSheetCourseMenu: some View {
        let selected = selectedCourse()
        let labelText: String = {
            guard let selected else { return "No course" }
            let code = (selected.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { return code }
            let name = (selected.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Course" : name
        }()

        return Menu {
            Button("No course") {
                selectedCourseID = nil
            }

            Button("Search or add course…") {
                openCourseSearchOrBuilder()
            }

            if !allCourses.isEmpty {
                Divider()
                ForEach(allCourses, id: \.objectID) { course in
                    Button {
                        selectedCourseID = course.objectID
                        if !isColorOverridden {
                            setDisplayedColor(AddCalendarItemOverlay.defaultEventColor(for: course))
                        }
                    } label: {
                        let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !code.isEmpty && !name.isEmpty {
                            Text("\(code) — \(name)")
                        } else if !code.isEmpty {
                            Text(code)
                        } else if !name.isEmpty {
                            Text(name)
                        } else {
                            Text("Course")
                        }
                    }
                }
            } else {
                Divider()
                Button("No courses available") { }
                    .disabled(true)
            }
        } label: {
            HStack(spacing: 8) {
                Text(labelText)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var bottomSheetLocationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.9))

                TextField("", text: $location, prompt: Text("Add location").foregroundColor(DesignSystem.Colors.textLight.opacity(0.75)))
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .focused($focusedLocationInput, equals: .bottomSheet)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                    )
            )

            if !locationSuggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(locationSuggestions.prefix(5).enumerated()), id: \.element.id) { index, option in
                            Button {
                                highlightedLocationSuggestionIndex = index
                                applyLocationSuggestion(option)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "mappin.circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.displayName)
                                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                            .foregroundColor(DesignSystem.Colors.textMain)
                                            .lineLimit(1)
                                        if !option.subtitle.isEmpty {
                                            Text(option.subtitle)
                                                .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                                .foregroundColor(DesignSystem.Colors.textLight)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 6)
                                    if let distanceLabel = distanceText(for: option) {
                                        Text(distanceLabel)
                                            .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(index == highlightedLocationSuggestionIndex ? Color.black.opacity(0.06) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var bottomSheetDateAndTimeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DATE")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

                bottomSheetDateField
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("TIME")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.8))

                HStack(spacing: 10) {
                    bottomSheetTimeField(selection: $startDateTime, showsDurationFrom: nil) { newStart in
                        let calendar = Calendar.current
                        startDateTime = newStart
                        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                        if endDateTime < minimumEnd {
                            endDateTime = minimumEnd
                        }
                    }

                    bottomSheetTimeField(selection: $endDateTime, showsDurationFrom: startDateTime) { newEnd in
                        let calendar = Calendar.current
                        var adjusted = newEnd
                        if adjusted <= startDateTime {
                            adjusted = calendar.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
                        }
                        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                        if adjusted < minimumEnd {
                            adjusted = minimumEnd
                        }
                        endDateTime = adjusted
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(allDay ? 0.92 : 1)
    }

    private var bottomSheetDateField: some View {
        let dateBinding = Binding<Date>(
            get: { Calendar.current.startOfDay(for: startDateTime) },
            set: { newDay in
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: startDateTime)
                let minute = calendar.component(.minute, from: startDateTime)
                let duration = max(15 * 60, endDateTime.timeIntervalSince(startDateTime))
                let newStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
                startDateTime = newStart
                endDateTime = newStart.addingTimeInterval(duration)
            }
        )

        return HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.9))

            DatePicker("", selection: dateBinding, displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.field)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        )
    }

    private func bottomSheetTimeField(
        selection: Binding<Date>,
        showsDurationFrom: Date?,
        onSelect: @escaping (Date) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TimeMenuField(
                selection: selection,
                isDisabled: allDay,
                fontSize: 13,
                textColor: DesignSystem.Colors.textMain,
                showsDurationFrom: showsDurationFrom,
                onSelect: onSelect
            )

            Spacer(minLength: 0)

            Image(systemName: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        )
    }

    private var bottomSheetAllDayRow: some View {
        HStack(spacing: 10) {
            Text("All day")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Spacer(minLength: 0)

            Toggle("", isOn: $allDay)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.success))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "f8fafc"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        )
    }

    private var bottomSheetFooter: some View {
        HStack(spacing: 12) {
            Button {
                requestDismissAnimated()
            } label: {
                Text("Cancel")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(eventToEdit == nil ? "Create Event" : "Save")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)
        }
    }

    // MARK: - Google Calendar-style editor (floatingCards presentation)

    private var verticalFloatingCardsContent: some View {
        VStack(spacing: 0) {
            gcTitleBar
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    gcDateTimeSection
                    gcInsetDivider
                    gcLocationSection
                    gcInsetDivider
                    gcGuestsSection
                    gcInsetDivider
                    gcCalendarSection
                    gcInsetDivider
                    gcColorSection
                    gcInsetDivider
                    gcNotesSection
                    gcInsetDivider
                    gcReminderSection
                }
                .padding(.vertical, 4)
            }
            // fixedSize makes the ScrollView use its content's natural height
            // instead of greedily expanding to fill whatever the parent offers.
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            gcFooter
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 30, x: 0, y: 10)
        // Do NOT use .frame(maxHeight: .infinity) — that creates a circular
        // dependency where the content fills the panel height, the GeometryReader
        // reports that height back, and the panel never shrinks to fit content.
        // Natural sizing lets the GR measure intrinsic content height correctly.
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // Title bar: close button + large title field + optional delete
    private var gcTitleBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { requestDismissAnimated() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
                if eventToEdit != nil {
                    Button { deleteEventNow() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                    .help("Delete event")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            TextField(
                "Add title",
                text: $title,
                prompt: Text("Add title").foregroundColor(Color.secondary.opacity(0.55))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // Shared icon-row layout used by all sections
    private func gcRow<Content: View>(
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // Divider inset to align with text content column
    private var gcInsetDivider: some View {
        Divider().padding(.leading, 52)
    }

    // ── Date & Time ──────────────────────────────────────────────────────────
    private var gcDateTimeSection: some View {
        gcRow(icon: "clock", iconColor: Color(hex: "1a73e8")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(startDateTime.formatted(
                    .dateTime.weekday(.wide).month(.wide).day().year()
                ))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

                if !allDay {
                    HStack(spacing: 6) {
                        TimeMenuField(
                            selection: $startDateTime,
                            isDisabled: false,
                            fontSize: 13,
                            textColor: DesignSystem.Colors.primary,
                            showsDurationFrom: nil,
                            onSelect: { newStart in
                                startDateTime = newStart
                                let minEnd = Calendar.current.date(byAdding: .minute, value: 15, to: newStart) ?? newStart
                                if endDateTime < minEnd { endDateTime = minEnd }
                            }
                        )
                        Text("–")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TimeMenuField(
                            selection: $endDateTime,
                            isDisabled: false,
                            fontSize: 13,
                            textColor: DesignSystem.Colors.primary,
                            showsDurationFrom: startDateTime,
                            onSelect: { newEnd in
                                var adj = newEnd
                                if adj <= startDateTime {
                                    adj = Calendar.current.date(byAdding: .day, value: 1, to: adj) ?? adj
                                }
                                let minEnd = Calendar.current.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                                if adj < minEnd { adj = minEnd }
                                endDateTime = adj
                            }
                        )
                    }
                }

                Toggle(isOn: $allDay) {
                    Text("All day")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
            }
        }
    }

    // ── Location ─────────────────────────────────────────────────────────────
    private var gcLocationSection: some View {
        Button {
            isShowingLocationPicker = true
            locationSearchService.query = ""
            locationSearchService.applyLocationBias(from: locationPermissionService.lastLocation)
        } label: {
            gcRow(icon: "mappin", iconColor: Color(hex: "ea4335")) {
                let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(loc.isEmpty ? "Add location" : loc)
                    .font(.system(size: 13))
                    .foregroundColor(loc.isEmpty ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }

    // ── Guests ───────────────────────────────────────────────────────────────
    private var gcGuestsSection: some View {
        gcRow(icon: "person", iconColor: Color(hex: "5f6368")) {
            if selectedGuests.isEmpty {
                Button { showContactPicker() } label: {
                    Text("Add guests")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedGuests, id: \.identifier) { guest in
                        HStack(spacing: 10) {
                            if let data = guest.thumbnailImageData, let img = NSImage(data: data) {
                                Image(nsImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 28, height: 28).clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable().frame(width: 28, height: 28)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CNContactFormatter.string(from: guest, style: .fullName) ?? "")
                                    .font(.system(size: 13)).foregroundColor(.primary)
                                if let email = guest.emailAddresses.first?.value as String? {
                                    Text(email).font(.system(size: 11))
                                        .foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button { removeGuest(guest) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { showContactPicker() } label: {
                        Label("Add more guests", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Calendar picker ───────────────────────────────────────────────────────
    private var gcCalendarSection: some View {
        gcRow(icon: "calendar", iconColor: Color(hex: "1a73e8")) {
            let googleCals = calendarManager.connectedCalendars.filter { $0.source == "Google" }
            let selectedName = googleCals.first { $0.remoteID == selectedGoogleCalendarID }?.name
                ?? googleCals.first?.name
                ?? "Calendar"
            if googleCals.isEmpty {
                Text("Calendar")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            } else {
                Menu {
                    ForEach(googleCals, id: \.id) { cal in
                        Button { selectedGoogleCalendarID = cal.remoteID } label: {
                            Label(cal.name, systemImage: "circle.fill")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedName).font(.system(size: 13)).foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    // current event display color (always tracks customColor)
    private var currentDisplayColor: Color { customColor }

    // ── Color ────────────────────────────────────────────────────────────────
    private var gcColorSection: some View {
        gcRow(icon: "circle.fill", iconColor: currentDisplayColor) {
            HStack(spacing: 12) {
                ForEach(Array(AddCalendarItemOverlay.presetEventColors.enumerated()), id: \.offset) { idx, col in
                    Button { applySelectedColor(col, choice: .preset(idx)) } label: {
                        ZStack {
                            Circle().fill(col).frame(width: 20, height: 20)
                            if eventColorChoice == .preset(idx) {
                                Circle().stroke(col, lineWidth: 2).frame(width: 25, height: 25)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // ── Notes / Description ───────────────────────────────────────────────────
    private var gcNotesSection: some View {
        gcRow(icon: "text.alignleft", iconColor: Color(hex: "5f6368")) {
            ZStack(alignment: .topLeading) {
                if descriptionText.isEmpty {
                    Text("Add description")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                }
                TextEditor(text: $descriptionText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 54, maxHeight: 110)
            }
        }
    }

    // ── Reminder ─────────────────────────────────────────────────────────────
    private var gcReminderSection: some View {
        gcRow(icon: "bell", iconColor: Color(hex: "5f6368")) {
            Menu {
                Button("None") { alertLeadMinutes = [] }
                Divider()
                ForEach(supportedAlertOffsets, id: \.self) { mins in
                    Button {
                        toggleAlertOffset(mins)
                    } label: {
                        if reminderScheduleMinutes.contains(mins) {
                            Label(reminderSummaryText([mins]), systemImage: "checkmark")
                        } else {
                            Text(reminderSummaryText([mins]))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(reminderSummaryText())
                        .font(.system(size: 13)).foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Button {
                openCourseSearchOrBuilder()
            } label: {
                Label("Search or add course", systemImage: "magnifyingglass")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    private var gcFooter: some View {
        HStack(spacing: 8) {
            if eventToEdit != nil {
                Button { deleteEventNow() } label: {
                    Label("Delete", systemImage: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { requestDismissAnimated() } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Button(action: save) {
                Text(eventToEdit == nil ? "Save" : "Save")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(DesignSystem.Colors.primary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var scrollableEditorCardContent: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 920
            let detailsRowHeight = max(280, proxy.size.height * 0.46)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    topHeaderPill

                    if isWide {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 14) {
                                macTimeCard
                                macLocationCard
                                macDescriptionCard
                                    .frame(height: detailsRowHeight, alignment: .top)
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 14) {
                                macCourseCard
                                macExtrasCard
                                macEventDetailsCard
                                    .frame(height: detailsRowHeight, alignment: .top)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 14) {
                            macTimeCard
                            macLocationCard
                            macCourseCard
                            macExtrasCard
                            macDescriptionCard
                            macEventDetailsCard
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 980, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var compactFloatingCardsContent: some View {
        let spacing: CGFloat = 10
        let rightColumnWidth: CGFloat = 260

        return ViewThatFits(in: .horizontal) {
            VStack(spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        timeCard
                        locationTravelCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: spacing) {
                        guestsCard
                        toolsCard
                    }
                    .frame(width: rightColumnWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.clear)

            VStack(spacing: spacing) {
                timeCard
                locationTravelCard
                guestsCard
                toolsCard
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.clear)
        }
    }

    private var topHeaderPill: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                if eventToEdit != nil {
                    deleteEventNow()
                } else {
                    requestDismissAnimated()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(fieldBackgroundColor))
            }
            .buttonStyle(.plain)
            .help(eventToEdit == nil ? "Dismiss" : "Delete Event")
            .accessibilityLabel(eventToEdit == nil ? "Dismiss" : "Delete Event")

            Spacer(minLength: 2)

            VStack(alignment: .center, spacing: 2) {
                TextField("Event Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 20, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 220)

                Text(headerSubtitle)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(associatedCalendarColor))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)
            .help(eventToEdit == nil ? "Create Event" : "Save Event")
            .accessibilityLabel(eventToEdit == nil ? "Create Event" : "Save Event")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DesignSystem.Colors.glassCardBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
    }

        private var headerSubtitle: String {
                startDateTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }

            private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.glassCardBase, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
                )
            }

            private var macTimeCard: some View {
                groupedCard {
                    HStack {
                        Label("Time", systemImage: "clock")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: 10)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeBottomPanel = .recurrence
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(secondaryTextColor)
                                Text(recurrenceSummaryLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(secondaryTextColor)
                            }
                        }
                        .buttonStyle(.plain)

                        Toggle("All day", isOn: $allDay)
                            .toggleStyle(.switch)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Start")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .frame(width: 34, alignment: .leading)

                            DatePicker(
                                "",
                                selection: Binding<Date>(
                                    get: { Calendar.current.startOfDay(for: startDateTime) },
                                    set: { newDay in
                                        let calendar = Calendar.current
                                        let hour = calendar.component(.hour, from: startDateTime)
                                        let minute = calendar.component(.minute, from: startDateTime)
                                        let newStart = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
                                        startDateTime = newStart
                                    }
                                ),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.field)
                            .labelsHidden()

                            if !allDay {
                                TimeMenuField(
                                    selection: $startDateTime,
                                    isDisabled: false,
                                    fontSize: 13,
                                    textColor: DesignSystem.Colors.textMain,
                                    showsDurationFrom: nil,
                                    onSelect: { startDateTime = $0 }
                                )
                            }
                        }

                        HStack(spacing: 8) {
                            Text("End")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .frame(width: 34, alignment: .leading)

                            DatePicker(
                                "",
                                selection: Binding<Date>(
                                    get: { Calendar.current.startOfDay(for: endDateTime) },
                                    set: { newDay in
                                        let calendar = Calendar.current
                                        let hour = calendar.component(.hour, from: endDateTime)
                                        let minute = calendar.component(.minute, from: endDateTime)
                                        let newEnd = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: newDay) ?? newDay
                                        endDateTime = newEnd
                                    }
                                ),
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.field)
                            .labelsHidden()

                            if !allDay {
                                TimeMenuField(
                                    selection: $endDateTime,
                                    isDisabled: false,
                                    fontSize: 13,
                                    textColor: DesignSystem.Colors.textMain,
                                    showsDurationFrom: startDateTime,
                                    onSelect: { endDateTime = $0 }
                                )
                            }
                        }
                    }

                    if hasAutoAdjustedEndTime && !allDay {
                        Text("End time was adjusted to stay after start time.")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            private var macLocationCard: some View {
                groupedCard {
                    Label("Location", systemImage: "mappin.and.ellipse")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    HStack(spacing: 10) {
                        TextField("Add location", text: $location)
                            .textFieldStyle(.plain)
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .focused($focusedLocationInput, equals: .anchoredPanel)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        fieldBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                    )

                    if !locationSuggestions.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(locationSuggestions.prefix(5).enumerated()), id: \.element.id) { index, option in
                                    Button {
                                        highlightedLocationSuggestionIndex = index
                                        applyLocationSuggestion(option)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "mappin.circle")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(option.displayName)
                                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                    .foregroundColor(DesignSystem.Colors.textMain)
                                                    .lineLimit(1)
                                                if !option.subtitle.isEmpty {
                                                    Text(option.subtitle)
                                                        .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                                                        .foregroundColor(DesignSystem.Colors.textLight)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer(minLength: 6)
                                            if let distanceLabel = distanceText(for: option) {
                                                Text(distanceLabel)
                                                    .font(DesignSystem.Fonts.main(size: 10, weight: .medium))
                                                    .foregroundColor(DesignSystem.Colors.textLight)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(index == highlightedLocationSuggestionIndex ? Color.black.opacity(0.06) : .clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(fieldBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            private var macCourseCard: some View {
                groupedCard {
                    Label("Course / Category", systemImage: "book.closed")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    Menu {
                        Button("No course") {
                            selectedCourseID = nil
                        }

                        if !allCourses.isEmpty {
                            Divider()
                            ForEach(allCourses, id: \.objectID) { course in
                                Button {
                                    selectedCourseID = course.objectID
                                } label: {
                                    Text(courseDisplayLabel(course))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Label("Assign to Course", systemImage: "graduationcap")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            Spacer(minLength: 0)
                            Text(selectedCourseSummaryLabel)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundStyle(primaryTextColor)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(secondaryTextColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            fieldBackgroundColor,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    Button {
                        openCourseSearchOrBuilder()
                    } label: {
                        Label("Search or add course", systemImage: "magnifyingglass")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    .buttonStyle(.plain)

                    if allCourses.isEmpty {
                        Text("No courses found yet. Add a course to unlock assignment.")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            private var macExtrasCard: some View {
                groupedCard {
                    HStack(spacing: 0) {
                        macExtraButton(title: "Alerts", systemImage: "bell", tint: .secondary) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeBottomPanel = .alerts
                            }
                        }
                        macExtraButton(title: "Color", systemImage: "paintpalette", tint: .orange) {
                            isShowingHexPopover = true
                        }
                        macExtraButton(title: "Notes", systemImage: "doc.text", tint: .green) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeBottomPanel = .notes
                            }
                        }
                    }
                    .background(fieldBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Divider()

                    HStack(spacing: 10) {
                        Label(reminderSummaryText(), systemImage: "bell")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Label(selectedCourseSummaryLabel, systemImage: "graduationcap")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(associatedCalendarColor.opacity(0.9))
                            .lineLimit(1)
                        Label(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No notes" : "Notes added", systemImage: "doc.text")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: 0)
                    }
                }
                .popover(isPresented: $isShowingHexPopover) {
                    hexColorEditor
                }
            }

            private var macDescriptionCard: some View {
                groupedCard {
                    Label("Description", systemImage: "text.alignleft")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $descriptionText)
                            .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(minHeight: 230)

                        if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Add context, agenda, links, or prep notes for this event...")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                                .foregroundStyle(secondaryTextColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(
                        fieldBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                    )

                    HStack(spacing: 10) {
                        Label(eventDurationSummaryLabel, systemImage: "clock")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Label(descriptionWordCountLabel, systemImage: "text.word.spacing")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: 0)
                    }
                }
            }

            private var macEventDetailsCard: some View {
                let googleCals = calendarManager.connectedCalendars.filter { $0.source == "Google" }
                let selectedGoogleName = googleCals.first { $0.remoteID == selectedGoogleCalendarID }?.name
                    ?? googleCals.first?.name
                    ?? "Planner Calendar"
                let guestCountLabel = selectedGuests.isEmpty ? "No guests" : "\(selectedGuests.count) guest\(selectedGuests.count == 1 ? "" : "s")"
                let filesCountLabel = recentFileImports.isEmpty ? "No attachments" : "\(recentFileImports.count) attachment\(recentFileImports.count == 1 ? "" : "s")"

                return groupedCard {
                    Label("Event Details", systemImage: "slider.horizontal.3")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(associatedCalendarColor)
                            Text("Calendar")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                            Spacer(minLength: 0)
                            if googleCals.isEmpty {
                                Button {
                                    AppNotificationCenter.shared.post(
                                        kind: .info,
                                        title: "Calendar Selection",
                                        message: "Connect a Google calendar in Settings to choose a destination.",
                                        autoDismissAfter: 3
                                    )
                                } label: {
                                    Text(selectedGoogleName)
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                        .foregroundStyle(associatedCalendarColor)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Menu {
                                    ForEach(googleCals, id: \.id) { cal in
                                        Button {
                                            selectedGoogleCalendarID = cal.remoteID
                                        } label: {
                                            Text(cal.name)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedGoogleName)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                            .foregroundStyle(associatedCalendarColor)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(secondaryTextColor)
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "bell")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                            Text("Alerts")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeBottomPanel = .alerts
                                }
                            } label: {
                                Text(reminderSummaryText())
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                            Text("Travel")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                            Spacer(minLength: 0)
                            Button {
                                travelTimeEnabled.toggle()
                                if travelTimeEnabled {
                                    recomputeTravelEstimateIfPossible()
                                } else {
                                    travelEstimateMinutes = nil
                                }
                            } label: {
                                Text(travelSummaryLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                            Text("Guests")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                            Spacer(minLength: 0)
                            Button {
                                showContactPicker(anchorWindowPoint: NSApp.currentEvent?.locationInWindow)
                            } label: {
                                Text(guestCountLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)

                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                            Text("Attachments")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                            Spacer(minLength: 0)
                            Button {
                                isShowingFileImporter = true
                            } label: {
                                Text(filesCountLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                    }
                    .background(
                        fieldBackgroundColor,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(subtleStrokeColor.opacity(0.25), lineWidth: 1)
                    )
                }
            }

            private var travelSummaryLabel: String {
                guard travelTimeEnabled else { return "Off" }
                guard let estimate = travelEstimateMinutes else { return "Estimating..." }
                if estimate < 60 {
                    return "\(estimate)m"
                }
                let hours = estimate / 60
                let minutes = estimate % 60
                if minutes == 0 {
                    return "\(hours)h"
                }
                return "\(hours)h \(minutes)m"
            }

            private var eventDurationSummaryLabel: String {
                let minutes = max(0, Int(endDateTime.timeIntervalSince(startDateTime) / 60))
                if allDay { return "All day" }
                if minutes < 60 { return "\(minutes)m duration" }
                let hours = minutes / 60
                let remaining = minutes % 60
                if remaining == 0 { return "\(hours)h duration" }
                return "\(hours)h \(remaining)m duration"
            }

            private var descriptionWordCountLabel: String {
                let words = descriptionText
                    .split { $0.isWhitespace || $0.isNewline }
                    .count
                return words == 1 ? "1 word" : "\(words) words"
            }

            private func macExtraButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
                Button(action: action) {
                    VStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(title)
                            .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

        private var cardPadding: CGFloat {
            switch presentationStyle {
            case .floatingCards:
                return 12
            case .fullScreenOverlay, .anchoredPanel, .dynamicIsland, .bottomSheet:
                return 18
            }
        }

        private var cardCornerRadius: CGFloat {
            switch presentationStyle {
            case .floatingCards:
                return 18
            case .fullScreenOverlay, .anchoredPanel, .dynamicIsland, .bottomSheet:
                return 24
            }
        }

        private func softCard<Content: View>(
            padding: CGFloat = 18,
            cornerRadius: CGFloat = 24,
            @ViewBuilder content: () -> Content
        ) -> some View {
            content()
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.thinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
                )
        }

        private var timeCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                let timeFontSize: CGFloat = (presentationStyle == .floatingCards) ? 18 : 20

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "clock")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .frame(width: 28)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 12) {
                        if !showsInternalHeaderPill {
                            TextField(
                                "Event Name",
                                text: $title,
                                prompt: Text("Event").foregroundColor(DesignSystem.Colors.textLight)
                            )
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .textFieldStyle(.plain)

                            DashedDivider()
                        }

                        HStack(alignment: .center, spacing: 10) {
                            HStack(spacing: 8) {
                                if allDay {
                                    HStack(spacing: 8) {
                                        Image(systemName: "sun.max")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("All day")
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.04))
                                            .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                                    )
                                } else {
                                    TimeMenuField(
                                        selection: $startDateTime,
                                        isDisabled: false,
                                        fontSize: timeFontSize,
                                        textColor: DesignSystem.Colors.textMain,
                                        showsDurationFrom: nil,
                                        onSelect: { newStart in
                                            let calendar = Calendar.current
                                            startDateTime = newStart

                                            let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                                            if endDateTime < minimumEnd {
                                                endDateTime = minimumEnd
                                            }
                                        }
                                    )
                                    Text("→")
                                        .font(DesignSystem.Fonts.main(size: 16, weight: .regular))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                    TimeMenuField(
                                        selection: $endDateTime,
                                        isDisabled: false,
                                        fontSize: timeFontSize,
                                        textColor: DesignSystem.Colors.textMain,
                                        showsDurationFrom: startDateTime,
                                        onSelect: { newEndSameDay in
                                            let calendar = Calendar.current
                                            var adjustedEnd = newEndSameDay
                                            if adjustedEnd <= startDateTime {
                                                adjustedEnd = calendar.date(byAdding: .day, value: 1, to: adjustedEnd) ?? adjustedEnd
                                            }
                                            let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
                                            if adjustedEnd < minimumEnd {
                                                adjustedEnd = minimumEnd
                                            }
                                            endDateTime = adjustedEnd
                                        }
                                    )
                                }
                            }

                            Spacer(minLength: 0)

                            HStack(spacing: 10) {
                                Text("All day")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                Toggle("", isOn: $allDay)
                                    .labelsHidden()
                                    .accessibilityLabel("All day event")
                                    .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.success))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.04))
                                    .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                            )
                        }

                        if presentationStyle != .floatingCards {
                            Text(startDateTime.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)

                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Menu {
                                    ForEach(Self.recurrenceOptions, id: \.self) { option in
                                        Button {
                                            setRecurrenceRule(option)
                                        } label: {
                                            if recurrenceRule == option {
                                                Label(recurrenceLabel(for: option), systemImage: "checkmark")
                                            } else {
                                                Text(recurrenceLabel(for: option))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(recurrenceSummaryLabel)
                                            .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                            }
                        }
                    }
                }
            }
        }

        private var locationTravelCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                let locationFontSize: CGFloat = (presentationStyle == .floatingCards) ? 16 : 18

                VStack(spacing: 16) {
                    Button {
                        isShowingLocationPicker = true
                        locationSearchService.query = ""
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.orange)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("LOCATION")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Text(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add location" : location)
                                    .font(DesignSystem.Fonts.main(size: locationFontSize, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .opacity(0.75)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    DashedDivider()

                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "car")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.blue)
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("TRAVEL TIME")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Spacer(minLength: 0)

                                Menu {
                                    Button("Off") {
                                        travelTimeEnabled = false
                                        travelTimeMinutes = nil
                                        travelEstimateMinutes = nil
                                    }

                                    if let estimate = travelEstimateMinutes {
                                        Divider()
                                        Button("Suggested: \(estimate) min") {
                                            travelTimeEnabled = true
                                            travelTimeMinutes = roundedToNearestFive(estimate)
                                            locationPermissionService.requestWhenInUseAuthorizationIfNeeded()
                                            locationPermissionService.requestOneShotLocation()
                                            recomputeTravelEstimateIfPossible()
                                        }
                                    }

                                    Divider()
                                    ForEach(travelTimeMinuteOptions, id: \.self) { minutes in
                                        Button("\(minutes) min") {
                                            travelTimeEnabled = true
                                            travelTimeMinutes = minutes
                                            locationPermissionService.requestWhenInUseAuthorizationIfNeeded()
                                            locationPermissionService.requestOneShotLocation()
                                            recomputeTravelEstimateIfPossible()
                                        }
                                    }
                                } label: {
                                    Text(travelTimeEnabled ? ((travelTimeMinutes != nil) ? "\(travelTimeMinutes!) min" : "On") : "Off")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.black.opacity(0.06))
                                        )
                                }
                                .menuStyle(.borderlessButton)
                            }

                            HStack(spacing: 8) {
                                Text("Starting from")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textMain)

                                HStack(spacing: 6) {
                                    Image(systemName: "location.north.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Current Location")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                }
                                .foregroundColor(DesignSystem.Colors.primary)
                            }

                            Text(travelArrivalLine)
                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }

        private struct DashedDivider: View {
            var body: some View {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 1)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundColor(Color.clear)
                    )
            }
        }

        private var travelArrivalLine: String {
            guard travelTimeEnabled else {
                return "Travel time is off."
            }
            guard resolvedLocation != nil else {
                return "Add a location to estimate travel time."
            }
            guard locationPermissionService.status == .authorized else {
                return "Enable Location Services to estimate travel time."
            }
            if isEstimatingTravel {
                return "Estimating travel time…"
            }
            if let estimate = travelEstimateMinutes {
                let arrival = Date().addingTimeInterval(Double(estimate) * 60)
                return "Est. arrival at \(arrival.formatted(date: .omitted, time: .shortened)) if you leave now."
            }
            return "Travel time unavailable."
        }

        private func showContactPicker(anchorWindowPoint: NSPoint? = nil) {
            let picker = CNContactPicker()
            let delegate = CalendarContactPickerDelegate(
                onSelect: { contact in
                    if !self.selectedGuests.contains(where: { $0.identifier == contact.identifier }) {
                        self.selectedGuests.append(contact)
                    }
                },
                onClose: {
                    self.contactPickerDelegate = nil
                }
            )
            self.contactPickerDelegate = delegate
            picker.delegate = delegate
            
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                let windowPoint = anchorWindowPoint ?? NSApp.currentEvent?.locationInWindow ?? window.mouseLocationOutsideOfEventStream
                let localPoint = contentView.convert(windowPoint, from: nil)
                let anchorRect = NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1)
                picker.showRelative(to: anchorRect, of: contentView, preferredEdge: .maxX)
            }
        }

        private func removeGuest(_ contact: CNContact) {
            selectedGuests.removeAll(where: { $0.identifier == contact.identifier })
        }

        private var guestsCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                let placeholderVerticalPadding: CGFloat = (presentationStyle == .floatingCards) ? 24 : 34

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("GUESTS")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Spacer(minLength: 0)
                        Button {
                            showContactPicker()
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(DesignSystem.Colors.primary.opacity(0.10)))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if selectedGuests.isEmpty {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color.black.opacity(0.04))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "person.2")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                )
                            Text("Add guests")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Text("Invite via email")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, placeholderVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                                .foregroundColor(Color.black.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showContactPicker()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(selectedGuests.enumerated()), id: \.element.identifier) { index, guest in
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        if let imageData = guest.thumbnailImageData, let nsImage = NSImage(data: imageData) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 32, height: 32)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .frame(width: 32, height: 32)
                                                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.5))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(CNContactFormatter.string(from: guest, style: .fullName) ?? "Unknown")
                                                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                                .foregroundColor(DesignSystem.Colors.textMain)
                                            
                                            if let email = guest.emailAddresses.first?.value as String? {
                                                Text(email)
                                                    .font(DesignSystem.Fonts.main(size: 11, weight: .regular))
                                                    .foregroundColor(DesignSystem.Colors.textLight)
                                                    .lineLimit(1)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            removeGuest(guest)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(DesignSystem.Colors.textLight)
                                                .frame(width: 24, height: 24)
                                                .background(Circle().fill(Color.black.opacity(0.05)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 8)
                                    
                                    if index < selectedGuests.count - 1 {
                                        DashedDivider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        private var toolsCard: some View {
            softCard(padding: cardPadding, cornerRadius: cardCornerRadius) {
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        toolButton(title: "Alerts", systemImage: "bell", tint: DesignSystem.Colors.textLight) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeBottomPanel = .alerts
                            }
                        }
                        toolButton(title: "Color", systemImage: "paintpalette", tint: .orange) {
                            isShowingHexPopover = true
                        }
                        toolButton(title: "Notes", systemImage: "doc.text", tint: .green) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeBottomPanel = .notes
                            }
                        }
                        toolButton(title: "Files", systemImage: "paperclip", tint: .blue) {
                            isShowingFileImporter = true
                        }
                    }

                    if presentationStyle == .floatingCards {
                        DashedDivider()

                        HStack(spacing: 10) {
                            Button {
                                requestDismissAnimated()
                            } label: {
                                Text("Cancel")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.05))
                                            .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: save) {
                                Text(eventToEdit == nil ? "Create" : "Save")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(
                                        Capsule()
                                            .fill(DesignSystem.Colors.primary)
                                            .shadow(color: DesignSystem.Colors.primary.opacity(0.18), radius: 10, x: 0, y: 6)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!canSave)
                            .opacity(canSave ? 1 : 0.6)
                        }
                    }
                }
            }
            .popover(isPresented: $isShowingHexPopover) {
                hexColorEditor
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }

        private func toolButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                let iconSize: CGFloat = (presentationStyle == .floatingCards) ? 16 : 18
                let labelSize: CGFloat = (presentationStyle == .floatingCards) ? 9 : 10

                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(tint)
                    Text(title.uppercased())
                        .font(DesignSystem.Fonts.main(size: labelSize, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }



    private var hexColorEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hex color")
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(primaryTextColor)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: customHexInput))
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(subtleStrokeColor, lineWidth: 1))

                TextField("e.g. ff0000", text: $customHexInput)
                    .textFieldStyle(PlainTextFieldStyle()) 
                    .padding(4)
                    .background(fieldBackgroundColor)
                    .cornerRadius(4)
                    .frame(width: 100)
                    .foregroundColor(primaryTextColor)
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
        .padding(10)
        .frame(width: 200)
    }

    private struct FormattedDateField: View {
        @Binding var selection: Date
        let fontSize: CGFloat
        let textColor: Color

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "dd MMM yyyy"
            f.locale = .autoupdatingCurrent
            f.timeZone = .autoupdatingCurrent
            return f
        }()
        
        private var formattedDate: String {
            Self.formatter.string(from: selection)
        }
        
        var body: some View {
            Text(formattedDate)
                .font(.system(size: fontSize))
                .foregroundColor(textColor)
                .animation(.easeInOut(duration: 0.18), value: selection)
        }
    }

    private struct MDYDateFields: View {
        @Binding var selection: Date
        let fontSize: CGFloat
        let textColor: Color

        @State private var monthText: String = ""
        @State private var dayText: String = ""
        @State private var yearText: String = ""
        @State private var isEditingAnyField: Bool = false

        var body: some View {
            HStack(spacing: 6) {
                numberField("MM", text: $monthText, maxDigits: 2)
                Text("/")
                    .font(DesignSystem.Fonts.main(size: fontSize, weight: .bold))
                    .foregroundColor(textColor.opacity(0.5))
                numberField("DD", text: $dayText, maxDigits: 2)
                Text("/")
                    .font(DesignSystem.Fonts.main(size: fontSize, weight: .bold))
                    .foregroundColor(textColor.opacity(0.5))
                numberField("YYYY", text: $yearText, maxDigits: 4, width: 56)
            }
            .onAppear { syncFromSelection() }
            .onChange(of: selection) { _, _ in
                if !isEditingAnyField {
                    syncFromSelection()
                }
            }
            .onChange(of: monthText) { _, _ in applyIfPossible() }
            .onChange(of: dayText) { _, _ in applyIfPossible() }
            .onChange(of: yearText) { _, _ in applyIfPossible() }
        }

        private func numberField(_ placeholder: String, text: Binding<String>, maxDigits: Int, width: CGFloat = 34) -> some View {
            TextField(
                placeholder,
                text: Binding(
                    get: { text.wrappedValue },
                    set: { newValue in
                        let digitsOnly = newValue.filter { $0.isNumber }
                        text.wrappedValue = String(digitsOnly.prefix(maxDigits))
                    }
                ),
                onEditingChanged: { editing in
                    isEditingAnyField = editing
                    if !editing {
                        applyIfPossible(force: true)
                    }
                }
            )
            .textFieldStyle(PlainTextFieldStyle())
            .font(DesignSystem.Fonts.main(size: fontSize, weight: .bold))
            .foregroundColor(textColor)
            .frame(width: width)
            .multilineTextAlignment(.center)
        }

        private func syncFromSelection() {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: selection)
            monthText = String(format: "%02d", comps.month ?? 1)
            dayText = String(format: "%02d", comps.day ?? 1)
            yearText = String(comps.year ?? cal.component(.year, from: Date()))
        }

        private func applyIfPossible(force: Bool = false) {
            guard let mRaw = Int(monthText), let dRaw = Int(dayText), let yRaw = Int(yearText) else { return }
            if !force && yearText.count < 2 { return }
            let cal = Calendar.current
            let year = (yearText.count <= 2) ? (2000 + yRaw) : yRaw
            let month = max(1, min(12, mRaw))
            let time = cal.dateComponents([.hour, .minute, .second], from: selection)
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.hour = time.hour
            comps.minute = time.minute
            comps.second = time.second
            let day = max(1, dRaw)
            comps.day = day
            var built: Date? = cal.date(from: comps)
            if built == nil {
                var adjustedDay = day
                while adjustedDay > 28 && built == nil {
                    adjustedDay -= 1
                    comps.day = adjustedDay
                    built = cal.date(from: comps)
                }
            }
            if let updated = built, updated != selection {
                selection = updated
            }
        }
    }

    private struct TimeMenuField: View {
        @Binding var selection: Date
        let isDisabled: Bool
        let fontSize: CGFloat
        let textColor: Color
        let showsDurationFrom: Date?
        let onSelect: (Date) -> Void

        private var displayText: String {
            selection.formatted(date: .omitted, time: .shortened)
        }

        var body: some View {
            Menu {
                ForEach(TimeMenuField.timeOptions15Minutes, id: \.self) { option in
                    Button {
                        let calendar = Calendar.current
                        let updated = calendar.date(bySettingHour: option.hour ?? 0, minute: option.minute ?? 0, second: 0, of: selection) ?? selection
                        onSelect(updated)
                    } label: {
                        if let base = showsDurationFrom {
                            let label = TimeMenuField.menuLabel(for: option, selectionDate: selection, durationBase: base)
                            Text(label)
                        } else {
                            let label = TimeMenuField.menuLabel(for: option, selectionDate: selection)
                            Text(label)
                        }
                    }
                }
            } label: {
                Text(displayText)
                    .font(DesignSystem.Fonts.main(size: fontSize, weight: .regular))
                    .foregroundColor(textColor)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
        }

        private static let timeOptions15Minutes: [DateComponents] = {
            var out: [DateComponents] = []
            out.reserveCapacity(96)
            for hour in 0..<24 {
                for minute in stride(from: 0, to: 60, by: 15) {
                    var comps = DateComponents()
                    comps.hour = hour
                    comps.minute = minute
                    out.append(comps)
                }
            }
            return out
        }()

        private static func menuLabel(for option: DateComponents, selectionDate: Date, durationBase: Date? = nil) -> String {
            let calendar = Calendar.current
            let candidate = calendar.date(bySettingHour: option.hour ?? 0, minute: option.minute ?? 0, second: 0, of: selectionDate) ?? selectionDate
            let timeText = candidate.formatted(date: .omitted, time: .shortened)

            guard let durationBase else {
                return timeText
            }

            // If candidate is not after base, interpret it as next day for duration display.
            var effectiveCandidate = candidate
            if effectiveCandidate <= durationBase {
                effectiveCandidate = calendar.date(byAdding: .day, value: 1, to: effectiveCandidate) ?? effectiveCandidate
            }

            let seconds = max(0, effectiveCandidate.timeIntervalSince(durationBase))
            let durationText = formatDuration(seconds)
            return "\(timeText) (\(durationText))"
        }

        private static func formatDuration(_ seconds: TimeInterval) -> String {
            let totalMinutes = max(0, Int(seconds.rounded() / 60))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            }
            return String(format: "%d:%02dh", hours, minutes)
        }
    }

    // MARK: - Bottom Panels

    private struct CalendarRecurrencePanel: View {
        @Binding var frequency: String
        @Binding var interval: Int
        @Binding var weekdays: Set<Int>
        @Binding var hasEndDate: Bool
        @Binding var endDate: Date
        let startDate: Date
        let onClose: () -> Void

        private let frequencyOptions: [(String, String)] = [
            ("none", "Does not repeat"),
            ("daily", "Daily"),
            ("weekly", "Weekly"),
            ("monthly", "Monthly"),
            ("yearly", "Yearly")
        ]

        private let weekdaySymbols: [(Int, String)] = [
            (1, "Mon"),
            (2, "Tue"),
            (3, "Wed"),
            (4, "Thu"),
            (5, "Fri"),
            (6, "Sat"),
            (7, "Sun")
        ]

        private var frequencyLabel: String {
            frequencyOptions.first(where: { $0.0 == frequency })?.1 ?? "Does not repeat"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Repeat")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Frequency")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Spacer(minLength: 0)
                        Menu {
                            ForEach(frequencyOptions, id: \.0) { option in
                                Button {
                                    frequency = option.0
                                    interval = max(1, interval)
                                    if frequency != "weekly" {
                                        weekdays = []
                                    }
                                    if frequency == "none" {
                                        hasEndDate = false
                                    }
                                } label: {
                                    if frequency == option.0 {
                                        Label(option.1, systemImage: "checkmark")
                                    } else {
                                        Text(option.1)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(frequencyLabel)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }

                    if frequency != "none" {
                        HStack(spacing: 8) {
                            Text("Every")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            Stepper(value: $interval, in: 1...30) {
                                Text("\(interval)")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                            }
                            .labelsHidden()
                            Text(frequency == "daily" ? "day(s)" : frequency == "weekly" ? "week(s)" : frequency == "monthly" ? "month(s)" : "year(s)")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            Spacer(minLength: 0)
                        }

                        if frequency == "weekly" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Repeat on")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)

                                HStack(spacing: 6) {
                                    ForEach(weekdaySymbols, id: \.0) { weekday in
                                        let selected = weekdays.contains(weekday.0)
                                        Button {
                                            if selected {
                                                weekdays.remove(weekday.0)
                                            } else {
                                                weekdays.insert(weekday.0)
                                            }
                                        } label: {
                                            Text(weekday.1)
                                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                .foregroundColor(selected ? .white : DesignSystem.Colors.textMain)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule()
                                                        .fill(selected ? DesignSystem.Colors.primary : Color.black.opacity(0.06))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Toggle("Ends", isOn: $hasEndDate)
                                .toggleStyle(.switch)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                            Spacer(minLength: 0)
                        }

                        if hasEndDate {
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: [.date])
                                .labelsHidden()
                                .datePickerStyle(.field)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                        )
                )

                HStack {
                    Button("Clear") {
                        frequency = "none"
                        interval = 1
                        weekdays = []
                        hasEndDate = false
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                    Spacer(minLength: 0)

                    Button("Done") { onClose() }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    private struct CalendarCoursePanel: View {
        let courses: [CourseEntity]
        let selectedCourseID: NSManagedObjectID?
        let semesterName: String?
        let isFullscreen: Bool
        let onSelectCourse: (NSManagedObjectID?) -> Void
        let onCreateCourse: (String, String) -> Void
        let onDeleteSelectedCourse: () -> Void
        let onOpenCourseBuilder: () -> Void
        let onBack: () -> Void
        let onClose: () -> Void

        @State private var searchText: String = ""
        @State private var newCourseCode: String = ""
        @State private var newCourseName: String = ""
        @State private var showDeleteConfirmation: Bool = false
        @State private var showAllCourses: Bool = false

        private var filteredCourses: [CourseEntity] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return courses }
            return courses.filter { course in
                let code = (course.code ?? "").localizedLowercase
                let name = (course.name ?? "").localizedLowercase
                let q = query.localizedLowercase
                return code.contains(q) || name.contains(q)
            }
        }

        private func label(for course: CourseEntity) -> String {
            let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty && !name.isEmpty { return "\(code) - \(name)" }
            if !code.isEmpty { return code }
            if !name.isEmpty { return name }
            return "Course"
        }

        private var canCreateCourse: Bool {
            !newCourseCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !newCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private var shouldCollapseCourses: Bool {
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private var visibleCourses: [CourseEntity] {
            guard shouldCollapseCourses, !showAllCourses else { return filteredCourses }
            return Array(filteredCourses.prefix(4))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if isFullscreen {
                        Button(action: onBack) {
                            Label("Back", systemImage: "chevron.left")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Course Assignment")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                TextField("Search courses", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(spacing: 0) {
                            Button {
                                onSelectCourse(nil)
                            } label: {
                                HStack {
                                    Image(systemName: selectedCourseID == nil ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedCourseID == nil ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                                    Text("No course")
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)

                            Divider()

                            if filteredCourses.isEmpty {
                                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No courses available" : "No matching courses")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(visibleCourses, id: \.objectID) { course in
                                    Button {
                                        onSelectCourse(course.objectID)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: selectedCourseID == course.objectID ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedCourseID == course.objectID ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                                            Text(label(for: course))
                                                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                                .foregroundColor(DesignSystem.Colors.textMain)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)

                                    if course.objectID != visibleCourses.last?.objectID {
                                        Divider()
                                    }
                                }

                                if shouldCollapseCourses && filteredCourses.count > 4 {
                                    Divider()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showAllCourses.toggle()
                                        }
                                    } label: {
                                        HStack {
                                            Text(showAllCourses ? "Show fewer courses" : "Show all courses (\(filteredCourses.count))")
                                                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                                .foregroundColor(DesignSystem.Colors.primary)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                                )
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create New Course")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)

                            Button {
                                onOpenCourseBuilder()
                            } label: {
                                Label("Open Full Course Roster", systemImage: "square.and.pencil")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.primary)

                            TextField("Course code (e.g. CSE 191)", text: $newCourseCode)
                                .textFieldStyle(.roundedBorder)

                            TextField("Course name", text: $newCourseName)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Text(semesterName.map { "Will add to \($0)" } ?? "Select a semester first to add courses")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Spacer(minLength: 0)
                                Button("Add") {
                                    onCreateCourse(newCourseCode, newCourseName)
                                    newCourseCode = ""
                                    newCourseName = ""
                                }
                                .buttonStyle(.plain)
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                                .disabled(!canCreateCourse || semesterName == nil)
                            }
                        }

                        if selectedCourseID != nil {
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete selected course from planner", systemImage: "trash")
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .confirmationDialog(
                                "Delete selected course?",
                                isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Delete Course", role: .destructive) {
                                    onDeleteSelectedCourse()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("This removes the course from the planner.")
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: isFullscreen ? nil : 340)
            .frame(maxWidth: isFullscreen ? .infinity : nil, alignment: .leading)
            .frame(maxHeight: isFullscreen ? .infinity : nil, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    private struct CalendarAlertsPanel: View {
        let options: [Int]
        let selectedOffsets: [Int]
        let onToggle: (Int) -> Void
        let onAddCustom: (Int) -> Void
        let onClear: () -> Void
        let onClose: () -> Void

        @State private var customMinutesText: String = ""

        private var allOffsets: [Int] {
            Array(Set(options + selectedOffsets)).sorted()
        }

        private func label(for minutes: Int) -> String {
            if minutes == 0 { return "At time of event" }
            if minutes < 60 { return "\(minutes) mins before" }
            if minutes == 60 { return "1 hour before" }
            if minutes == 1440 { return "1 day before" }
            return "\(minutes / 60) hours before"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Alerts")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    ForEach(allOffsets, id: \.self) { minutes in
                        Button {
                            onToggle(minutes)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedOffsets.contains(minutes) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedOffsets.contains(minutes) ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                                Text(label(for: minutes))
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if minutes != allOffsets.last {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                        )
                )

                HStack(spacing: 8) {
                    TextField(
                        "Custom minutes",
                        text: Binding(
                            get: { customMinutesText },
                            set: { customMinutesText = String($0.filter(\.isNumber).prefix(4)) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        guard let minutes = Int(customMinutesText) else { return }
                        onAddCustom(minutes)
                        customMinutesText = ""
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .disabled(Int(customMinutesText) == nil)
                }

                HStack {
                    Button("Clear") { onClear() }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    Spacer(minLength: 0)
                    Button("Done") { onClose() }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(14)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
        }
    }

    private struct CalendarNotesPanel: View {
        @Binding var text: String
        let onSave: () -> Void
        @State private var measuredHeight: CGFloat = 100

        var body: some View {
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "bold").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "italic").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "list.bullet").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "list.number").font(.system(size: 14, weight: .semibold))
                        Divider().frame(height: 16)
                        Image(systemName: "link").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(DesignSystem.Colors.textMain.opacity(0.6))

                    Spacer()

                    Text("DRAFT")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.04))
                        .cornerRadius(4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.thinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor).opacity(0.6)), alignment: .bottom)

                // Editor
                ScrollView {
                    AutoGrowingTextEditor(
                        text: $text,
                        measuredHeight: $measuredHeight,
                        font: NSFont.systemFont(ofSize: 15, weight: .regular),
                        textColor: NSColor.labelColor.withAlphaComponent(0.85),
                        placeholder: "Start typing your event notes here..."
                    )
                    .padding(20)
                    .frame(minHeight: 200)
                }

                // Footer
                VStack {
                   Button(action: onSave) {
                        HStack(spacing: 8) {
                            Image(systemName: "floppy.disk.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("Save Notes")
                                .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(DesignSystem.Colors.primary)
                                .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text("LAST SAVED: JUST NOW")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight.opacity(0.6))
                        .padding(.top, 12)
                }
                .padding(24)
                .background(
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor).opacity(0), Color(nsColor: .windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .background(.thinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 30, x: 0, y: -5)
            .frame(height: 500)
        }
    }

    private struct CalendarFilesPanel: View {
        let files: [URL]
        let onClose: () -> Void
        let onBrowse: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("ATTACHMENTS")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain.opacity(0.7))
                        .tracking(1)

                    Spacer()

                    Text("\(files.count) FILES")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DesignSystem.Colors.primary.opacity(0.12))
                        .cornerRadius(12)
                }
                .padding(24)

                ScrollView {
                    VStack(spacing: 16) {
                        // Drop Zone
                        Button(action: onBrowse) {
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(DesignSystem.Colors.primary.opacity(0.08))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "cloud.upload.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(DesignSystem.Colors.primary)
                                    )
                                
                                VStack(spacing: 4) {
                                    Text("Drop files here")
                                        .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    Text("or click to browse")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .regular))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.2))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // File List
                        ForEach(files, id: \.self) { url in
                            HStack(spacing: 16) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(fileIconColor(for: url).opacity(0.12))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Image(systemName: fileIcon(for: url))
                                            .font(.system(size: 20))
                                            .foregroundColor(fileIconColor(for: url))
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    Text(formattedSize(for: url))
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }
                                
                                Spacer()
                            }
                            .padding(16)
                            .background(.ultraThinMaterial)
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(.thinMaterial)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: -4)
            .frame(height: 550)
        }
        
        private func fileIcon(for url: URL) -> String {
            if url.pathExtension.lowercased() == "pdf" { return "doc.text.fill" }
            if ["jpg", "png", "jpeg"].contains(url.pathExtension.lowercased()) { return "photo.fill" }
            return "doc.fill"
        }
        
        private func fileIconColor(for url: URL) -> Color {
            if url.pathExtension.lowercased() == "pdf" { return .red }
            if ["jpg", "png", "jpeg"].contains(url.pathExtension.lowercased()) { return .blue }
            return .gray
        }
        
        private func formattedSize(for url: URL) -> String {
            guard let resources = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resources.fileSize else { return "Unknown" }
            return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        }
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

private class CalendarContactPickerDelegate: NSObject, CNContactPickerDelegate {
    private let onSelect: (CNContact) -> Void
    private let onClose: () -> Void

    init(onSelect: @escaping (CNContact) -> Void, onClose: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose
    }

    func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
        onSelect(contact)
        picker.close()
    }

    func contactPickerDidClose(_ picker: CNContactPicker) {
        onClose()
    }
}
