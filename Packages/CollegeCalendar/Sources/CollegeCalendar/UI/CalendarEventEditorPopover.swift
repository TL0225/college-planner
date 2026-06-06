// CalendarEventEditorPopover.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventEditorPopover.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Grid-attached editor hosted in `popover(item:)` on `CalendarViewContent`.
struct CalendarEventEditorPopover: View {
    let anchor: CalendarEditorAnchor
    var onDismiss: () -> Void
    var onLiveUpdate: (() -> Void)?

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @StateObject private var editorSession = CalendarEditorSession()
    @State private var isPresented = true

    private var dismissBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { presented in
                if !presented {
                    editorSession.discardDraft(collegePersistence: collegePersistence)
                    onDismiss()
                }
            }
        )
    }

    var body: some View {
        Group {
            switch anchor.mode {
            case .add(let semesterID, let title, let start, let end, _):
                AddCalendarItemOverlay(
                    isPresented: dismissBinding,
                    semester: semesterID.flatMap { collegePersistence.semester(with: $0) },
                    initialTitle: title,
                    initialStartDateTime: start,
                    initialEndDateTime: end,
                    eventToEdit: nil,
                    presentationStyle: .floatingCards,
                    onLiveUpdate: liveUpdateHandler
                )
            case .edit(let eventID):
                let event = collegePersistence.calendarEventEntity(id: eventID)
                AddCalendarItemOverlay(
                    isPresented: dismissBinding,
                    semester: event?.semester,
                    initialTitle: nil,
                    initialStartDateTime: event?.startDate,
                    initialEndDateTime: event?.endDate,
                    eventToEdit: event,
                    presentationStyle: .floatingCards,
                    onLiveUpdate: liveUpdateHandler
                )
            case .monthAllDayChoice(let date):
                MonthAllDayChoicePopover(
                    date: date,
                    onTimed: {
                        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                        let durationMinutes = UserDefaults.standard.integer(forKey: "calendar.defaultEventDurationMinutes")
                        let minutes = (durationMinutes > 0) ? durationMinutes : 60
                        let end = Calendar.current.date(byAdding: .minute, value: minutes, to: start)
                            ?? start.addingTimeInterval(TimeInterval(minutes * 60))
                        onDismiss()
                        // Caller re-opens with timed anchor via notification
                        NotificationCenter.default.post(
                            name: .calendarOpenGridEditor,
                            object: nil,
                            userInfo: [
                                "start": start,
                                "end": end,
                                "allDay": false,
                            ]
                        )
                    },
                    onAllDay: {
                        let cal = Calendar.current
                        let start = cal.startOfDay(for: date)
                        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
                        onDismiss()
                        NotificationCenter.default.post(
                            name: .calendarOpenGridEditor,
                            object: nil,
                            userInfo: [
                                "start": start,
                                "end": end,
                                "allDay": true,
                            ]
                        )
                    },
                    onCancel: onDismiss
                )
            }
        }
        .calendarEditorPresentation(.gridPopover)
        .frame(
            width: CalendarGridPopoverMetrics.width,
            alignment: .top
        )
        .frame(
            minHeight: CalendarGridPopoverMetrics.minHeight,
            maxHeight: CalendarGridPopoverMetrics.maxHeight,
            alignment: .top
        )
    }

    private var liveUpdateHandler: ((String, Date, Date, Color) -> Void)? {
        { _, _, _, _ in onLiveUpdate?() }
    }
}

extension Notification.Name {
    static let calendarOpenGridEditor = Notification.Name("calendarOpenGridEditor")
}

/// Phase 5: month empty-cell all-day vs timed chooser.
private struct MonthAllDayChoicePopover: View {
    let date: Date
    var onTimed: () -> Void
    var onAllDay: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New event")
                .font(.headline)
            Text(date, style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Timed event", action: onTimed)
                    .keyboardShortcut(.defaultAction)
                Button("All-day", action: onAllDay)
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .padding(16)
    }
}
