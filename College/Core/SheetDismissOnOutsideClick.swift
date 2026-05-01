import SwiftUI

#if os(macOS)
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
    @State private var localMonitor: Any?

    func body(content: Content) -> some View {
        content
            .background(
                SheetWindowReader(window: $sheetWindow)
                    .frame(width: 0, height: 0)
            )
            .onAppear {
                installLocalMonitorIfNeeded()
            }
            .onDisappear {
                removeMonitors()
            }
    }

    private func installLocalMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            guard let sheetWindow else { return event }

            // Dismiss only when the click lands outside the visible sheet frame.
            if isEventOutsideSheetFrame(event, sheetWindow: sheetWindow) {
                dismiss()
            }
            return event
        }
    }

    private func isEventOutsideSheetFrame(_ event: NSEvent, sheetWindow: NSWindow) -> Bool {
        guard let eventWindow = event.window else { return false }

        // If the event originated from the sheet window or one of its child windows,
        // treat it as inside interaction and keep the sheet open.
        if eventWindow === sheetWindow || eventWindow.parent === sheetWindow {
            return false
        }

        let clickPointInScreen = eventWindow.convertPoint(toScreen: event.locationInWindow)
        return !sheetWindow.frame.contains(clickPointInScreen)
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}

extension View {
    func dismissOnOutsideClickForSheet() -> some View {
        modifier(DismissOnOutsideClickSheetModifier())
    }
}

#else

extension View {
    func dismissOnOutsideClickForSheet() -> some View {
        self
    }
}

#endif
