import CollegeCalendar
import SwiftUI

@MainActor
final class CalendarOverlayBuilder: CalendarOverlayBuilding {
    static let shared = CalendarOverlayBuilder()

    func addCalendarItemOverlay(
        isPresented: Binding<Bool>,
        semesterID: UUID?,
        initialTitle: String?,
        initialStart: Date?,
        initialEnd: Date?,
        eventID: UUID?,
        style: CalendarOverlayPresentationStyle
    ) -> AnyView {
        let presentation: AddCalendarItemOverlay.PresentationStyle = switch style {
        case .anchoredPanel: .anchoredPanel
        case .fullScreenOverlay: .fullScreenOverlay
        }
        return AnyView(
            AddCalendarItemOverlay(
                isPresented: isPresented,
                semester: semesterID.flatMap { CollegePersistence.shared.semester(with: $0) },
                initialTitle: initialTitle,
                initialStartDateTime: initialStart,
                initialEndDateTime: initialEnd,
                eventToEdit: eventID.flatMap { CollegePersistence.shared.calendarEventEntity(id: $0) },
                presentationStyle: presentation
            )
        )
    }
}

extension CalendarPersistencePortBootstrap {
    @MainActor
    static func wireOverlays() {
        CalendarOverlayAccess.builder = CalendarOverlayBuilder.shared
    }
}
