// AssistantTestFixtures.swift
// Shared snapshots and harness helpers for Swift Testing Assistant suites.

import Foundation
@testable import College

enum AssistantTestFixtures {

    static let emptySnapshot = AssistantPlannerSnapshot(
        events: [],
        tasks: [],
        majors: [],
        minors: [],
        programs: []
    )

    static let csSnapshot = AssistantPlannerSnapshot(
        events: [],
        tasks: [],
        majors: ["Computer Science"],
        minors: [],
        programs: []
    )

    static let seededSnapshot: AssistantPlannerSnapshot = {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return AssistantPlannerSnapshot(
            events: [
                .init(title: "UITest Study Group", startDate: tomorrow, allDay: false)
            ],
            tasks: [
                .init(title: "UITest Assignment", dueDate: tomorrow, isCompleted: false)
            ],
            majors: ["UITest Computer Science"],
            minors: [],
            programs: [
                .init(
                    name: "UITest Computer Science",
                    kind: .major,
                    completedCredits: 45,
                    requiredCredits: 120,
                    pendingCourses: [
                        .init(code: "CSE 331", title: "Computer Security", credits: 3)
                    ]
                )
            ]
        )
    }()

    @MainActor
    static func toolContext(
        persistence: CollegePersistence = .shared,
        snapshot: AssistantPlannerSnapshot = emptySnapshot,
        persona: AssistantPersona = .academicAdvisor,
        page: AppPage = .assistant
    ) -> AssistantToolExecutionContext {
        AssistantToolExecutionContext(
            collegePersistence: persistence,
            activePage: page,
            selectedPersona: persona,
            snapshot: snapshot,
            currentDate: Date(),
            programIdentity: AssistantProgramIdentityBuilder.build(persistence: persistence)
        )
    }

    /// Resets NL / embedding toggles after a test.
    static func resetIntentClassifierDefaults() {
        UserDefaults.standard.removeObject(forKey: AssistantIntentNLModelSettings.enabledKey)
        UserDefaults.standard.removeObject(forKey: AssistantIntentNLModelSettings.probabilityThresholdKey)
        UserDefaults.standard.removeObject(forKey: AssistantIntentEmbeddingSettings.enabledKey)
        ProductionIntentClassifier.resetForTesting()
    }

#if DEBUG
    @MainActor
    static func resetTelemetryAndSession() {
        AssistantTurnTelemetry.resetForTesting()
        AssistantSessionContinuity.resetForTesting()
    }
#endif
}
