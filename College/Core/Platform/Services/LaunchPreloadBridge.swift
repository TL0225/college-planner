// LaunchPreloadBridge.swift
// Feature: Core/Platform
// Purpose: Tier 3 launch preload — shares executor and lane budget with background services.

import CollegeCalendar
import Foundation

@MainActor
enum LaunchPreloadBridge {
    static func runPipelineIfNeeded(
        coordinator: LaunchPreloadCoordinator,
        collegePersistence: CollegePersistence,
        calendarManager: CalendarIntegrationManager,
        lmsCoordinator: LMSWebCoordinator,
        cloudIntegration: CloudIntegrationService
    ) {
        Task {
            await BackgroundServiceOnDemand.run(id: "launch_preload_pipeline") {
                coordinator.startIfNeeded(
                    collegePersistence: collegePersistence,
                    calendarManager: calendarManager,
                    lmsCoordinator: lmsCoordinator,
                    cloudIntegration: cloudIntegration
                )
            }
        }
    }
}
