// AssistantInferenceSessionFactory.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantInferenceSessionFactory.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
enum AssistantInferenceSessionFactory {
    /// When set, ``makeSession`` ignores availability and uses this backend (tests / UI automation).
    static var forcedBackend: AssistantInferenceBackend? {
        if let forcedRaw = UITestLaunchFlags.assistantInferenceBackendOverride {
            let normalized: String = {
                switch forcedRaw.lowercased() {
                case "fm", "foundationmodels": return "foundationModels"
                case "gemma": return "jsonWorker"
                default: return forcedRaw
                }
            }()
            if let backend = AssistantInferenceBackend(rawValue: normalized) {
                return backend
            }
        }
        if let env = ProcessInfo.processInfo.environment["COLLEGE_ASSISTANT_INFERENCE_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !env.isEmpty {
            let normalized = env == "fm" || env == "foundationmodels" ? "foundationModels" : (env == "gemma" ? "jsonWorker" : env)
            return AssistantInferenceBackend(rawValue: normalized)
        }
        if UITestLaunchFlags.assistantInferenceStubEnabled {
            return .stub
        }
        return nil
    }

    static func makeSession(
        availability: AssistantInferenceAvailability,
        executor: AIAssistantToolExecutor?
    ) -> any AssistantInferenceSession {
        if let forced = forcedBackend {
            return session(for: forced, executor: executor)
        }

        switch availability {
        case .foundationModels:
            if AssistantInferenceSettings.preferFoundationModels {
                return foundationModelsSession(executor: executor)
            }
            return JsonWorkerAssistantSession()
        case .jsonWorkerFallback, .unavailable:
            return JsonWorkerAssistantSession()
        }
    }

    private static func session(
        for backend: AssistantInferenceBackend,
        executor: AIAssistantToolExecutor?
    ) -> any AssistantInferenceSession {
        switch backend {
        case .foundationModels:
            return foundationModelsSession(executor: executor)
        case .jsonWorker:
            return JsonWorkerAssistantSession()
        case .stub:
            return StubAssistantInferenceSession()
        }
    }

    private static func foundationModelsSession(executor: AIAssistantToolExecutor?) -> any AssistantInferenceSession {
        let provider: @MainActor @Sendable () -> AIAssistantToolExecutor = {
            if let executor {
                return executor
            }
            return AIAssistantToolExecutor(
                context: AssistantToolExecutionContext(
                    collegePersistence: CollegePersistence.shared,
                    activePage: .assistant,
                    selectedPersona: .academicAdvisor,
                    snapshot: AssistantPlannerSnapshot(
                        events: [],
                        tasks: [],
                        majors: [],
                        minors: [],
                        programs: []
                    ),
                    currentDate: Date()
                )
            )
        }
        return FoundationModelsAssistantSession(makeExecutor: provider)
    }
}
