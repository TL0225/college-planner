import Foundation
import SwiftUI
import Combine

/// Tracks app active/inactive lifecycle state and exposes a lightweight inactivity policy
/// (visual dim + periodic refresh throttling) for the main workspace window.
@MainActor
final class AppActivityCoordinator: ObservableObject {
    static let shared = AppActivityCoordinator()

    static let inactiveStateEnabledKey = "ui.inactiveStateEnabled"

    @Published private(set) var isAppActive: Bool = true
    @Published private(set) var isResourceThrottled: Bool = false
    @Published private(set) var shouldApplyInactiveDim: Bool = false

    private var resumeTask: Task<Void, Never>?
    private var transitionToken = UUID()

    private var inactiveStateEnabled: Bool {
        if let stored = UserDefaults.standard.object(forKey: Self.inactiveStateEnabledKey) as? Bool {
            return stored
        }
        return true
    }

    private init() {}

    func appDidResignActive() {
        setInactive(source: "appDelegate")
    }

    func appDidBecomeActive() {
        setActive(source: "appDelegate")
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            setActive(source: "scenePhase")
        case .inactive, .background:
            setInactive(source: "scenePhase")
        @unknown default:
            break
        }
    }

    func refreshPolicyFromSettings() {
        guard inactiveStateEnabled else {
            resumeTask?.cancel()
            isResourceThrottled = false
            shouldApplyInactiveDim = false
            return
        }

        if isAppActive {
            beginStaggeredResume()
        } else {
            isResourceThrottled = true
            shouldApplyInactiveDim = true
        }
    }

    private func setInactive(source: String) {
        resumeTask?.cancel()
        isAppActive = false

        guard inactiveStateEnabled else {
            isResourceThrottled = false
            shouldApplyInactiveDim = false
            DebugLogger.shared.lifecycle("AppActivity -> inactive (disabled, source=\(source))")
            return
        }

        isResourceThrottled = true
        shouldApplyInactiveDim = true
        DebugLogger.shared.lifecycle("AppActivity -> inactive (source=\(source))")
    }

    private func setActive(source: String) {
        isAppActive = true

        guard inactiveStateEnabled else {
            resumeTask?.cancel()
            isResourceThrottled = false
            shouldApplyInactiveDim = false
            DebugLogger.shared.lifecycle("AppActivity -> active (disabled, source=\(source))")
            return
        }

        shouldApplyInactiveDim = false
        beginStaggeredResume()
        DebugLogger.shared.lifecycle("AppActivity -> active (source=\(source))")
    }

    private func beginStaggeredResume() {
        resumeTask?.cancel()
        isResourceThrottled = true

        let token = UUID()
        transitionToken = token

        resumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self else { return }
            guard !Task.isCancelled, self.transitionToken == token, self.isAppActive else { return }
            self.isResourceThrottled = false
            DebugLogger.shared.lifecycle("AppActivity -> resume complete")
        }
    }
}
