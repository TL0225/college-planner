// SheetDismissOnOutsideClick.swift
// Feature: Core
// Purpose: Core module — SheetWindowReader.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

import AppKit

private struct SheetWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

private struct DismissOnOutsideClickSheetModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    @State private var sheetWindow: NSWindow?
    @State private var mouseMonitor: Any?
    @State private var keyMonitor: Any?

    func body(content: Content) -> some View {
        content
            .shellDynamicTypeReadable()
            .background(
                SheetWindowReader(window: $sheetWindow)
                    .frame(width: 0, height: 0)
            )
            .onAppear {
                installLocalMonitorsIfNeeded()
            }
            .onDisappear {
                removeMonitors()
            }
    }

    private func installLocalMonitorsIfNeeded() {
        installMouseMonitorIfNeeded()
        installEscapeMonitorIfNeeded()
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            guard let sheetWindow else { return event }

            // Dismiss only when the click lands outside the visible sheet frame.
            if isEventOutsideSheetFrame(event, sheetWindow: sheetWindow) {
                dismiss()
            }
            return event
        }
    }

    private func installEscapeMonitorIfNeeded() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // Escape
            dismiss()
            return nil
        }
    }

    private func isEventOutsideSheetFrame(_ event: NSEvent, sheetWindow: NSWindow) -> Bool {
        guard let eventWindow = event.window else { return false }

        if isWindowInSheetHierarchy(eventWindow, sheetWindow: sheetWindow) {
            return false
        }

        let clickPointInScreen = eventWindow.convertPoint(toScreen: event.locationInWindow)

        // Keep the sheet open when the click lands inside the sheet frame even if AppKit
        // routed the event through a sibling window (e.g. toolbar `.searchable` fields).
        if sheetWindow.frame.contains(clickPointInScreen) {
            return false
        }

        // Parent presenter click: dismiss for dimmed content hits only, not titlebar/toolbar chrome.
        if let parent = sheetWindow.parent, eventWindow === parent {
            return isClickOnPresenterDimmedContent(
                event,
                parentWindow: parent,
                sheetWindow: sheetWindow,
                clickPointInScreen: clickPointInScreen
            )
        }

        return true
    }

    private func isWindowInSheetHierarchy(_ window: NSWindow, sheetWindow: NSWindow) -> Bool {
        if window === sheetWindow { return true }
        if window.parent === sheetWindow { return true }

        var current: NSWindow? = window
        while let candidate = current {
            if candidate === sheetWindow { return true }
            current = candidate.parent
        }
        return false
    }

    private func isClickOnPresenterDimmedContent(
        _ event: NSEvent,
        parentWindow: NSWindow,
        sheetWindow: NSWindow,
        clickPointInScreen: NSPoint
    ) -> Bool {
        guard let contentView = parentWindow.contentView else { return false }

        let pointInContent = contentView.convert(event.locationInWindow, from: nil)
        if !contentView.bounds.contains(pointInContent) {
            // Title bar / unified toolbar — not an outside dismiss.
            return false
        }

        return !sheetWindow.frame.contains(clickPointInScreen)
    }

    private func removeMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

extension View {
    func dismissOnOutsideClickForSheet() -> some View {
        modifier(DismissOnOutsideClickSheetModifier())
    }
}

