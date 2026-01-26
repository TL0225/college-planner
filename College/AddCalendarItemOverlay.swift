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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    enum PresentationStyle {
        case fullScreenOverlay
        case anchoredPanel
        case dynamicIsland
        case floatingCards
    }

    @Binding var isPresented: Bool
    let semester: SemesterEntity?
    let initialTitle: String?
    let initialStartDateTime: Date?
    let initialEndDateTime: Date?
    let eventToEdit: CalendarEventEntity?
    let presentationStyle: PresentationStyle

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

    @State private var travelTimeEnabled: Bool = false
    @State private var travelTransport: TravelTransport = TravelTimeStore.loadLastTransport()
    @State private var travelTimeMinutes: Int? = nil
    @State private var travelEstimateMinutes: Int? = nil
    @State private var isEstimatingTravel: Bool = false
    
    @State private var selectedGuests: [CNContact] = []
    @State private var contactPickerDelegate: Any? = nil // Holds strong reference to the delegate

    @State private var selectedCourseID: NSManagedObjectID? = nil

    private enum EventColorChoice: Equatable {
        case preset(Int)
        case custom
    }

    private static let presetEventColors: [Color] = [
        DesignSystem.Colors.primary,
        DesignSystem.Colors.success,
        DesignSystem.Colors.warning,
        DesignSystem.Colors.error
    ]

    @State private var eventColorChoice: EventColorChoice = .preset(0)
    @State private var customColor: Color = DesignSystem.Colors.primary
    @State private var customHexInput: String = ""
    @State private var isShowingHexPopover: Bool = false
    @State private var isShowingFileImporter: Bool = false
    @State private var isColorOverridden: Bool = false

    private var isEditingEvent: Bool {
        eventToEdit != nil
    }
    
    // Legacy font properties
    private var sectionTitleFontSize: CGFloat { isEditingEvent ? 12 : 13 }
    private var titleFieldFontSize: CGFloat { isEditingEvent ? 15 : 18 }
    private var standardFieldFontSize: CGFloat { isEditingEvent ? 13 : 14 }

    @State private var pendingAutosaveWorkItem: DispatchWorkItem? = nil
    @State private var showAdvancedDynamicIslandFields: Bool = false
    // @State private var isNotesPresented: Bool = false - Replaced by activeBottomPanel

    private enum ActiveBottomPanel: Equatable {
        case none
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
    }

    private struct ExternalPrefill: Equatable {
        let title: String?
        let start: Date?
        let end: Date?
    }

    private let initialSnapshot: Snapshot
    private let initialTravelSettings: TravelTimeSettings
    private enum CourseColorOverrides {
        private static let keyPrefix = "College.CourseColorOverride."

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

    init(
        isPresented: Binding<Bool>,
        semester: SemesterEntity?,
        initialTitle: String? = nil,
        initialStartDateTime: Date? = nil,
        initialEndDateTime: Date? = nil,
        eventToEdit: CalendarEventEntity? = nil,
        presentationStyle: PresentationStyle = .fullScreenOverlay
    ) {
        _isPresented = isPresented
        self.semester = semester
        self.initialTitle = initialTitle
        self.initialStartDateTime = initialStartDateTime
        self.initialEndDateTime = initialEndDateTime
        self.eventToEdit = eventToEdit
        self.presentationStyle = presentationStyle

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
                colorHex: initialOverrideHex
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

            initialSnapshot = Snapshot(
                title: trimmedTitle,
                start: start,
                end: end,
                allDay: false,
                location: "",
                notes: "",
                courseID: nil,
                colorHex: initialHex
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
            let etaSeconds = await calculateETASeconds(
                origin: originCoordinate,
                destination: destinationCoordinate,
                transport: transportType
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

    private func calculateETASeconds(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType
    ) async -> TimeInterval? {
        await withCheckedContinuation { continuation in
            let request = MKDirections.Request()
            let originPlacemark = MKPlacemark(coordinate: origin)
            let destinationPlacemark = MKPlacemark(coordinate: destination)
            request.source = MKMapItem(placemark: originPlacemark)
            request.destination = MKMapItem(placemark: destinationPlacemark)
            request.transportType = transport

            let directions = MKDirections(request: request)
            directions.calculateETA { response, error in
                if let seconds = response?.expectedTravelTime {
                    continuation.resume(returning: seconds)
                } else {
                    _ = error
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func selectedCourse() -> CourseEntity? {
        guard let id = selectedCourseID else { return nil }
        return (try? coreDataManager.viewContext.existingObject(with: id)) as? CourseEntity
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func normalizedEndDate() -> Date {
        let calendar = Calendar.current
        let minimumEnd = calendar.date(byAdding: .minute, value: 15, to: startDateTime) ?? startDateTime
        return max(endDateTime, minimumEnd)
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
            colorHex: hex
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
            Task.detached(priority: .utility) { [calendarManager] in
                calendarManager.deleteEventFromGoogle(localEventID: localID)
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
            applyColorOverride(eventID: eventToEdit.id, snapshot: currentSnapshot)

            if let eventID = eventToEdit.id {
                persistTravelSettings(eventID: eventID)
            }
            // Sync to Google
            Task.detached(priority: .utility) { [calendarManager] in
                calendarManager.exportEventToGoogle(eventToEdit)
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
            applyColorOverride(eventID: created.id, snapshot: currentSnapshot)

            if let eventID = created.id {
                persistTravelSettings(eventID: eventID)
            }
            // Sync to Google
            Task.detached(priority: .utility) { [calendarManager] in
                calendarManager.exportEventToGoogle(created)
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
            for url in urls {
                do {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    try coreDataManager.addVaultDocument(
                        fromSelectedURL: url,
                        category: .calendar,
                        source: "calendar"
                    )
                    recentFileImports.append(url)
                } catch {
                    print("Failed to import file: \(error)")
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

    private var showsInternalHeaderPill: Bool {
        switch presentationStyle {
        case .fullScreenOverlay, .dynamicIsland:
            return true
        case .anchoredPanel, .floatingCards:
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
        case .anchoredPanel, .dynamicIsland, .floatingCards:
            return AnyView(editorCard)
        }
    }

    var body: some View {
        rootContent
            .onAppear {
                applyExternalPrefillIfNeeded()
                applyInitialDisplayColorFromSourceIfNeeded()
                recomputeTravelEstimateIfPossible()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEditorSave)) { _ in
                save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEditorDismiss)) { _ in
                requestDismissAnimated()
            }
            .onChange(of: currentSnapshot) { _, _ in scheduleAutosaveIfEditing() }
            .onChange(of: externalPrefill) { _, _ in applyExternalPrefillIfNeeded() }
            .onChange(of: locationPermissionService.lastLocation) { _, _ in recomputeTravelEstimateIfPossible() }
            .onChange(of: locationPermissionService.status) { _, _ in recomputeTravelEstimateIfPossible() }
    }

    private func applyExternalPrefillIfNeeded() {
        guard eventToEdit == nil else { return }
        // Only update if the user hasn't changed anything yet.
        guard currentSnapshot == initialSnapshot else { return }

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
                .background(preferredHeightSizingProbe)

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
                    if activeBottomPanel == .notes {
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
                .offset(y: mainCardHeight + 16)
                .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var outerContainerBackground: Color {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return .clear
        case .fullScreenOverlay:
            return cardBackgroundColor
        }
    }

    private var outerContainerCornerRadius: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return 0
        case .fullScreenOverlay:
            return 16
        }
    }

    private var outerContainerShadowColor: Color {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return Color.clear
        case .fullScreenOverlay:
            return Color.black.opacity(0.4)
        }
    }

    private var outerContainerShadowRadius: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return 0
        case .fullScreenOverlay:
            return 24
        }
    }

    private var outerContainerShadowYOffset: CGFloat {
        switch presentationStyle {
        case .dynamicIsland, .floatingCards, .anchoredPanel:
            return 0
        case .fullScreenOverlay:
            return 12
        }
    }

    private var editorCardContent: some View {
        Group {
            switch presentationStyle {
            case .floatingCards:
                verticalFloatingCardsContent
            case .fullScreenOverlay, .anchoredPanel, .dynamicIsland:
                scrollableEditorCardContent
            }
        }
    }

    private var verticalFloatingCardsContent: some View {
        VStack(spacing: 10) {
            timeCard
            locationTravelCard
            guestsCard
            toolsCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    private var scrollableEditorCardContent: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let isWide = availableWidth >= 920

            VStack(spacing: 18) {
                if showsInternalHeaderPill {
                    topHeaderPill
                }

                if isWide {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 18) {
                            timeCard
                            locationTravelCard
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 18) {
                            guestsCard
                            toolsCard
                        }
                        .frame(maxWidth: 320)
                    }
                } else {
                    VStack(spacing: 18) {
                        timeCard
                        locationTravelCard
                        guestsCard
                        toolsCard
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            HStack(spacing: 14) {
                Button {
                    requestDismissAnimated()
                } label: {
                    Image(systemName: "xmark")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Close")

                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "Event Name",
                        text: $title,
                        prompt: Text("Event").foregroundColor(DesignSystem.Colors.textLight)
                    )
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .textFieldStyle(.plain)

                    Text(headerSubtitle)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    // Future: date picker for start/end date.
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .semibold))
                        Text(startDateTime.formatted(.dateTime.month(.abbreviated).day()))
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    }
                    .foregroundColor(DesignSystem.Colors.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Capsule().fill(DesignSystem.Colors.primary.opacity(0.12)))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Date")

                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 1, height: 26)

                if eventToEdit != nil {
                    Button {
                        // Already in edit mode.
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.04)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Edit")

                    Button(role: .destructive) {
                        deleteEventNow()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.04)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Delete")
                }

                Button(action: save) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(DesignSystem.Colors.primary))
                        .shadow(color: DesignSystem.Colors.primary.opacity(0.18), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.6)
                .help(eventToEdit == nil ? "Create Event" : "Save Changes")
                .accessibilityLabel(eventToEdit == nil ? "Create event" : "Save changes")
                .accessibilityHint("Saves this event")
            }
            .padding(10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
            )
        }

        private var headerSubtitle: String {
            var text = "\(startDateTime.formatted(date: .omitted, time: .shortened)) – \(endDateTime.formatted(date: .omitted, time: .shortened))"
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedLocation.isEmpty {
                text += " • \(trimmedLocation)"
            }
            return text
        }

        private var cardPadding: CGFloat {
            switch presentationStyle {
            case .floatingCards:
                return 12
            case .fullScreenOverlay, .anchoredPanel, .dynamicIsland:
                return 18
            }
        }

        private var cardCornerRadius: CGFloat {
            switch presentationStyle {
            case .floatingCards:
                return 18
            case .fullScreenOverlay, .anchoredPanel, .dynamicIsland:
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
                                Text("Does not repeat")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                Button("Change") {
                                    // Future: repeat rules.
                                }
                                .buttonStyle(PlainButtonStyle())
                                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
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

        private func showContactPicker() {
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
                picker.showRelative(to: contentView.bounds, of: contentView, preferredEdge: .maxY)
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
                            // Future.
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
                            withAnimation(.easeInOut(duration: 0.25)) {
                                activeBottomPanel = .files
                            }
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
        
        private var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMM yyyy"
            return formatter.string(from: selection)
        }
        
        var body: some View {
            Text(formattedDate)
                .font(.system(size: fontSize))
                .foregroundColor(textColor)
                .animation(.easeInOut(duration: 0.18), value: selection)
        }
    }

    private var preferredHeightSizingProbe: some View {
        editorCardContent
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: AddCalendarItemOverlayPreferredHeightKey.self, value: proxy.size.height)
                }
            )
            .hidden()
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
