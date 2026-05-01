//
//  WidgetRegistry.swift
//  College
//
//  Central registry of all available widgets.
//
//  ╔══════════════════════════════════════════════════════════════════╗
//  ║  DEVELOPER GUIDE — Registering a Custom Widget                  ║
//  ╠══════════════════════════════════════════════════════════════════╣
//  ║  1. Create MyWidget.swift in College/Overview/Widgets/.         ║
//  ║  2. Add `static var descriptor: WidgetDescriptor` that fills    ║
//  ║     in makePreview.                                             ║
//  ║  3. Call WidgetRegistry.shared.register(MyWidget.descriptor)   ║
//  ║     from bootstrapBuiltIns() below — or from any module that   ║
//  ║     loads before OverviewView appears.                          ║
//  ╚══════════════════════════════════════════════════════════════════╝
//

import SwiftUI
import Combine

final class WidgetRegistry: ObservableObject {

    // Shared singleton — also injectable as @EnvironmentObject.
    nonisolated(unsafe) static let shared = WidgetRegistry()

    @Published private(set) var allDescriptors: [WidgetDescriptor] = []

    // MARK: Public API

    /// Add a widget definition to the registry.
    /// Silently ignores duplicate IDs so it is safe to call multiple times.
    func register(_ descriptor: WidgetDescriptor) {
        guard !allDescriptors.contains(where: { $0.id == descriptor.id }) else { return }
        allDescriptors.append(descriptor)
    }

    /// Look up a descriptor by its stable string ID.
    func descriptor(for id: String) -> WidgetDescriptor? {
        allDescriptors.first(where: { $0.id == id })
    }

    // MARK: Built-in Bootstrap

    /// Registers all built-in widgets in their default display order.
    /// Called once from `CollegeApp.init()`.
    func bootstrapBuiltIns() {
        register(WeatherWidget.descriptor)
        register(AcademicsWidget.descriptor)
        register(DeadlinesWidget.descriptor)
        register(ScheduleWidget.descriptor)
        register(DocumentsWidget.descriptor)
        register(EventsWidget.descriptor)
        register(TasksWidget.descriptor)
    }
}
