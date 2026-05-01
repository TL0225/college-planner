import Foundation
#if os(macOS)
import AppKit
#endif

/// Shared detection for UI-test bootstrap (must match `CollegeApp.forceUITestMainUI`).
enum UITestLaunchFlags {
    static var forcesMainUI: Bool {
        let p = ProcessInfo.processInfo
        if p.environment["COLLEGE_UI_TEST_BOOT_MAIN"] == "1" { return true }
        return p.arguments.contains("--ui-test-boot-main")
    }

    /// Pretend Gemma is installed so Assistant chat is reachable without MLX weights (only with `forcesMainUI`).
    static var fakeAssistantModelForUITest: Bool {
        guard forcesMainUI else { return false }
        if ProcessInfo.processInfo.environment["COLLEGE_UITEST_FAKE_ASSISTANT_MODEL"] == "1" { return true }
        return ProcessInfo.processInfo.arguments.contains("--uitest-fake-assistant-model")
    }

    /// Return scripted JSON from `LocalLLMRunner` instead of loading MLX (only with `forcesMainUI`).
    static var localLLMStubEnabled: Bool {
        guard forcesMainUI else { return false }
        if ProcessInfo.processInfo.environment["COLLEGE_UITEST_LOCAL_LLM_STUB"] == "1" { return true }
        return ProcessInfo.processInfo.arguments.contains("--uitest-local-llm-stub")
    }

    /// Insert minimal planner rows (profile, task, event) for tool/snapshot tests.
    static var seedMinimalPlannerData: Bool {
        guard forcesMainUI else { return false }
        if ProcessInfo.processInfo.environment["COLLEGE_UITEST_SEED_PLANNER"] == "1" { return true }
        return ProcessInfo.processInfo.arguments.contains("--uitest-seed-minimal-planner")
    }

    /// Apply `UserDefaults` consumed by `@AppStorage` before SwiftUI reads them (call from `CollegeApp.init`).
    static func applyInjectedUserDefaultsIfNeeded() {
        guard forcesMainUI else { return }
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment

        if args.contains("--uitest-assistant-diagnostics=1")
            || env["COLLEGE_UITEST_ASSISTANT_DIAGNOSTICS"] == "1" {
            UserDefaults.standard.set(true, forKey: "assistant.runtime.showDiagnostics")
        }

        if let raw = env["COLLEGE_UITEST_ASSISTANT_LENGTH_PRESET"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           ["short", "balanced", "detailed"].contains(raw) {
            UserDefaults.standard.set(raw, forKey: "assistant.response.lengthPreset")
        }
        for arg in args where arg.hasPrefix("--uitest-assistant-length-preset=") {
            let raw = String(arg.dropFirst("--uitest-assistant-length-preset=".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ["short", "balanced", "detailed"].contains(raw) {
                UserDefaults.standard.set(raw, forKey: "assistant.response.lengthPreset")
            }
        }

        if env["COLLEGE_UITEST_ASSISTANT_STREAMING"] == "0" {
            UserDefaults.standard.set(false, forKey: "assistant.streaming.enabled")
        } else if env["COLLEGE_UITEST_ASSISTANT_STREAMING"] == "1" {
            UserDefaults.standard.set(true, forKey: "assistant.streaming.enabled")
        }
        for arg in args where arg.hasPrefix("--uitest-assistant-streaming=") {
            let raw = String(arg.dropFirst("--uitest-assistant-streaming=".count))
            if raw == "0" {
                UserDefaults.standard.set(false, forKey: "assistant.streaming.enabled")
            } else if raw == "1" {
                UserDefaults.standard.set(true, forKey: "assistant.streaming.enabled")
            }
        }
    }

    #if os(macOS)
    /// `xcodebuild`/XCTest often launches the app without foreground activation; mirror a dock click
    /// so the main window becomes key before AX queries run.
    static func activateMainWindowIfUITestBoot() {
        guard forcesMainUI else { return }
        let app = NSApplication.shared
        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
        }
        app.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: .activateAllWindows)
        DispatchQueue.main.async {
            app.unhide(nil)
            for window in app.windows where window.isVisible && !window.isSheet {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            if app.keyWindow == nil {
                let main = app.windows.first(where: { $0.isVisible && !$0.isSheet && $0.styleMask.contains(.resizable) })
                    ?? app.windows.first(where: { $0.isVisible && !$0.isSheet })
                main?.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Re-attempt activation while SwiftUI creates the first window (AX can lag behind `launch()`).
    static func scheduleUITestActivationRetriesIfNeeded() {
        guard forcesMainUI else { return }
        activateMainWindowIfUITestBoot()
        let delays: [TimeInterval] = [0.05, 0.15, 0.35, 0.75, 1.5, 3.0, 5.0, 8.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                activateMainWindowIfUITestBoot()
            }
        }
    }
    #endif
}
