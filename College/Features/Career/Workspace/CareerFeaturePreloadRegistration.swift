import CollegeCareer
import Foundation

enum CareerFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "career",
                title: "Career data",
                criticality: .bestEffort,
                timeoutSeconds: 0.5,
                retryLimit: 0,
                run: { context, onProgress, onDetail in
                    let count = await context.collegePersistence.prefetchCareerApplicationsForLaunch()
                    onDetail("Loaded \(count) applications")
                    onProgress(1)
                }
            )
        )
    }
}
