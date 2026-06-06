import CollegeCalendar
import Foundation

enum CalendarFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "calendar-toolbar",
                title: "Calendar toolbar",
                criticality: .bestEffort,
                timeoutSeconds: 0.5,
                retryLimit: 0,
                run: { _, onProgress, _ in
                    onProgress(1)
                }
            )
        )
    }
}
