// CalendarIntegrationBridge.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarIntegrationBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Weak bridge so `CalendarEventWritePipeline` can export without a global `CalendarIntegrationManager` singleton.
@MainActor
enum CalendarIntegrationBridge {
    weak static var manager: CalendarIntegrationManager?
}
