// CalendarGhostEventOverlay.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarGhostEvent.
// Data: CollegePersistence / repositories when applicable.

import CollegeCalendar
import SwiftUI

/// Live ghost preview while drag-creating on the week/day grid.
struct CalendarGhostEvent: Equatable {
    var title: String
    var start: Date
    var end: Date
    var color: Color
    var location: String? = nil
}

struct CalendarGhostEventOverlay: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    let ghost: CalendarGhostEvent
    let hourHeight: CGFloat
    let calendar: Calendar
    @Binding var calendarEditorAnchor: CalendarEditorAnchor?
    var onAddPopoverDismiss: () -> Void

    private var collegePersistence: CollegePersistence { container.persistence }
        private var modalCoordinator: ModalCoordinator { container.modalCoordinator }
    private var blockHeight: CGFloat {
        max(24, CGFloat(ghost.end.timeIntervalSince(ghost.start) / 60) * (hourHeight / 60))
    }

    private var addPopoverBinding: Binding<CalendarEditorAnchor?> {
        Binding(
            get: {
                guard let anchor = calendarEditorAnchor,
                      case .add(_, _, let start, let end, _) = anchor.mode,
                      calendar.isDate(start, equalTo: ghost.start, toGranularity: .minute),
                      calendar.isDate(end, equalTo: ghost.end, toGranularity: .minute)
                else { return nil }
                return anchor
            },
            set: { newValue in
                calendarEditorAnchor = newValue
                if newValue == nil {
                    onAddPopoverDismiss()
                }
            }
        )
    }

    var body: some View {
        chipBody
            .frame(maxWidth: .infinity)
            .frame(height: blockHeight, alignment: .top)
            .offset(y: startOffset)
            .popover(item: addPopoverBinding, arrowEdge: .trailing) { anchor in
                CalendarEventEditorPopover(
                    anchor: anchor,
                    onDismiss: {
                        calendarEditorAnchor = nil
                        onAddPopoverDismiss()
                    },
                    onLiveUpdate: nil
                )
                .environment(modalCoordinator)
            }
    }

    private var chipBody: some View {
        CalendarTimedEventChipContent(
            title: ghost.title,
            start: ghost.start,
            end: ghost.end,
            location: ghost.location,
            accentColor: ghost.color,
            titleColor: ghost.color,
            secondaryColor: ghost.color.opacity(0.85),
            showsLocationLine: blockHeight >= 52
        )
        .background(ghost.color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(ghost.color.opacity(0.75))
        )
    }

    private var startOffset: CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: ghost.start)
        let totalMinutes = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return totalMinutes * (hourHeight / 60)
    }
}
