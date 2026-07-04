// WidgetRegistry.swift
// Feature: Overview
// Purpose: Overview module — WidgetRegistry.
// Data: CollegePersistence / repositories when applicable.

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
import Observation

@Observable
@MainActor
final class WidgetRegistry {

    static let shared = WidgetRegistry()

    private(set) var allDescriptors: [WidgetDescriptor] = []

    func register(_ descriptor: WidgetDescriptor) {
        guard !allDescriptors.contains(where: { $0.id == descriptor.id }) else { return }
        allDescriptors.append(descriptor)
    }

    func descriptor(for id: String) -> WidgetDescriptor? {
        allDescriptors.first(where: { $0.id == id })
    }

    /// Registers all built-in widgets in their default display order.
    /// Called from `CollegeApp.init()` and idempotently from `OverviewView.onAppear`.
    func bootstrapBuiltIns() {
        register(AcademicsWidget.descriptor)
        register(AcademicCalendarWidget.descriptor)
        register(DeadlinesWidget.descriptor)
        register(ScheduleWidget.descriptor)
        register(DocumentsWidget.descriptor)
        register(EventsWidget.descriptor)
        register(TasksWidget.descriptor)
        register(CareerPipelineWidget.descriptor)
        register(CareerFollowUpsWidget.descriptor)
        register(CareerSummaryWidget.descriptor)
    }
}
