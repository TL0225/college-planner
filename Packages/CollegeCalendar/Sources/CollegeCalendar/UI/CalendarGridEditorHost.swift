// CalendarGridEditorHost.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarGridEditorHostModifier.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

private struct CalendarGridEditorHostModifier: ViewModifier {
    @Binding var anchor: CalendarEditorAnchor?
    var addAnchorGhost: CalendarGhostEvent?
    var onLiveUpdate: () -> Void

    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @Environment(ModalCoordinator.self) private var modalCoordinator

    private var addOnlyAnchor: Binding<CalendarEditorAnchor?> {
        Binding(
            get: {
                guard addAnchorGhost == nil else { return nil }
                guard let current = anchor else { return nil }
                if case .edit = current.mode { return nil }
                return current
            },
            set: { anchor = $0 }
        )
    }

    func body(content: Content) -> some View {
        content
            .popover(item: addOnlyAnchor, arrowEdge: addOnlyAnchor.wrappedValue?.arrowEdge ?? .leading) { item in
                CalendarEventEditorPopover(
                    anchor: item,
                    onDismiss: { anchor = nil },
                    onLiveUpdate: onLiveUpdate
                )
                .environmentObject(collegePersistence)
                .environmentObject(calendarManager)
                .environment(modalCoordinator)
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarOpenGridEditor)) { note in
                guard let start = note.userInfo?["start"] as? Date,
                      let end = note.userInfo?["end"] as? Date else { return }
                let allDay = (note.userInfo?["allDay"] as? Bool) ?? false
                anchor = .addFromGrid(start: start, end: end, allDay: allDay)
            }
    }
}

extension View {
    func calendarGridEditorHost(
        anchor: Binding<CalendarEditorAnchor?>,
        addAnchorGhost: CalendarGhostEvent?,
        onLiveUpdate: @escaping () -> Void
    ) -> some View {
        modifier(
            CalendarGridEditorHostModifier(
                anchor: anchor,
                addAnchorGhost: addAnchorGhost,
                onLiveUpdate: onLiveUpdate
            )
        )
    }
}
