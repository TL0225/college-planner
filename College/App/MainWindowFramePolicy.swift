// MainWindowFramePolicy.swift
// Feature: App
// Purpose: Center the main window at launch without mutating borderless/titled chrome.

import AppKit
import SwiftUI

@MainActor
enum MainWindowFramePolicy {
    static let defaultMainSize = NSSize(width: 1100, height: 760)

    private static let splashWidthThreshold: CGFloat = 700
    private static let frameDefaultsKey = "NSWindow Frame \(AutosaveNames.mainWindow)"
    private static var hasCenteredMainShellThisLaunch = false

    /// Centers the launch splash card in the visible screen area.
    static func centerSplashWindowIfNeeded(_ window: NSWindow) {
        guard !UITestLaunchFlags.forcesMainUI else { return }
        let splashSize = NSSize(
            width: LaunchSplashWindowMetrics.windowSize.width,
            height: LaunchSplashWindowMetrics.windowSize.height
        )
        setCenteredFrame(on: window, size: splashSize)
    }

    /// After preload, expand to the default main-shell size and center unless the user has a saved position.
    static func adoptMainShellPlacementIfNeeded(_ window: NSWindow) {
        guard !UITestLaunchFlags.forcesMainUI else { return }
        guard window.styleMask.contains(.resizable), !window.isSheet else { return }

        let purgedStaleAutosave = purgeStaleSplashAutosaveIfNeeded()
        let shouldCenter = purgedStaleAutosave
            || isSplashSized(window.frame)
            || !hasValidAutosavedMainFrame()
            || isCornerClusteredFrame(window.frame, on: window.screen)
            || !hasCenteredMainShellThisLaunch

        if shouldCenter {
            setCenteredFrame(on: window, size: defaultMainSize)
            hasCenteredMainShellThisLaunch = true
        }

        enableMainWindowAutosave(on: window)
    }

    /// Assign autosave only after explicit placement so AppKit does not restore a stale corner frame first.
    static func enableMainWindowAutosave(on window: NSWindow) {
        guard window.frameAutosaveName != AutosaveNames.mainWindow else { return }
        window.setFrameAutosaveName(AutosaveNames.mainWindow)
    }

    private static func purgeStaleSplashAutosaveIfNeeded() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return false }
        guard let saved = autosavedFrame(from: raw) else { return false }
        if saved.width < splashWidthThreshold || isCornerClusteredSavedFrame(saved) {
            UserDefaults.standard.removeObject(forKey: frameDefaultsKey)
            return true
        }
        return false
    }

    private static func hasValidAutosavedMainFrame() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return false }
        guard let saved = autosavedFrame(from: raw) else { return false }
        return saved.width >= splashWidthThreshold && !isCornerClusteredSavedFrame(saved)
    }

    private static func autosavedFrame(from raw: String) -> NSRect? {
        let parts = raw.split(separator: " ")
        guard parts.count >= 4,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]) else { return nil }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func isSplashSized(_ frame: NSRect) -> Bool {
        frame.width < splashWidthThreshold
    }

    /// Detects frames hugging a screen corner — usually a bad restore from the old borderless splash path.
    private static func isCornerClusteredFrame(_ frame: NSRect, on screen: NSScreen?) -> Bool {
        let screenFrame = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        guard screenFrame.width > 0, screenFrame.height > 0 else { return false }
        let margin: CGFloat = 120
        let nearLeft = frame.minX - screenFrame.minX < margin
        let nearRight = screenFrame.maxX - frame.maxX < margin
        let nearBottom = frame.minY - screenFrame.minY < margin
        let nearTop = screenFrame.maxY - frame.maxY < margin
        return (nearLeft || nearRight) && (nearBottom || nearTop)
    }

    private static func isCornerClusteredSavedFrame(_ frame: NSRect) -> Bool {
        isCornerClusteredFrame(frame, on: NSScreen.main)
    }

    private static func setCenteredFrame(on window: NSWindow, size: NSSize) {
        guard let target = centeredFrame(for: size, on: window.screen) else { return }
        guard !framesApproximatelyEqual(window.frame, target) else { return }
        window.setFrame(target, display: true)
    }

    private static func centeredFrame(for size: NSSize, on screen: NSScreen?) -> NSRect? {
        let screenFrame = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        guard screenFrame.width > 0, screenFrame.height > 0 else { return nil }
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    private static func framesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.width - rhs.width) < 1
            && abs(lhs.height - rhs.height) < 1
            && abs(lhs.midX - rhs.midX) < 2
            && abs(lhs.midY - rhs.midY) < 2
    }
}

struct MainWindowSplashPlacementView: NSViewRepresentable {
    func makeNSView(context: Context) -> MainWindowSplashPlacementHostView {
        MainWindowSplashPlacementHostView()
    }

    func updateNSView(_ nsView: MainWindowSplashPlacementHostView, context: Context) {}
}

final class MainWindowSplashPlacementHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Run after AppKit/SwiftUI apply any restored frame autosave for this window.
        DispatchQueue.main.async {
            MainWindowFramePolicy.centerSplashWindowIfNeeded(window)
        }
    }
}
