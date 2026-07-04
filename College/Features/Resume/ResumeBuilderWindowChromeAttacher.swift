// ResumeBuilderWindowChromeAttacher.swift
// Feature: Resume
// Purpose: Disable window background drag while builder section DnD is active.

import AppKit
import SwiftUI

struct ResumeBuilderWindowChromeAttacher: NSViewRepresentable {
    var presentation: ResumeBuilderPresentation

    func makeCoordinator() -> Coordinator {
        Coordinator(presentation: presentation)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.applyChrome(on: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.presentation = presentation
        DispatchQueue.main.async {
            context.coordinator.applyChrome(on: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.restoreChrome(on: nsView.window)
        }
    }

    @MainActor
    final class Coordinator {
        var presentation: ResumeBuilderPresentation

        init(presentation: ResumeBuilderPresentation) {
            self.presentation = presentation
        }

        func applyChrome(on window: NSWindow?) {
            guard let window else { return }
            window.isMovableByWindowBackground = false
        }

        func restoreChrome(on window: NSWindow?) {
            guard presentation == .inline else { return }
            window?.isMovableByWindowBackground = true
        }
    }
}
