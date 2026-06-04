// CalendarGuestContactPickerHost.swift
// Feature: Calendar
// Purpose: Calendar module — Delegate.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Contacts
import ContactsUI
import SwiftUI

/// Presents `CNContactPicker` anchored at the current click (works inside nested SwiftUI popovers).
@MainActor
enum CalendarGuestContactPickerPresenter {
    private static var activeDelegate: Delegate?

    static func present(
        onSelect: @escaping (CNContact) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        activeDelegate?.picker?.close()
        activeDelegate = nil

        let delegate = Delegate(
            onSelect: { contact in
                onSelect(contact)
                activeDelegate = nil
                onClose()
            },
            onClose: {
                activeDelegate = nil
                onClose()
            }
        )
        activeDelegate = delegate

        let picker = CNContactPicker()
        picker.delegate = delegate
        delegate.picker = picker

        guard let window = NSApp.keyWindow,
              let contentView = window.contentView
        else { return }

        let windowPoint: NSPoint = {
            if let event = NSApp.currentEvent {
                return event.locationInWindow
            }
            return NSPoint(x: window.frame.width * 0.5, y: window.frame.height * 0.5)
        }()

        let anchorRect = NSRect(x: windowPoint.x, y: windowPoint.y, width: 1, height: 1)
        picker.showRelative(to: anchorRect, of: contentView, preferredEdge: .maxY)
    }

    private final class Delegate: NSObject, CNContactPickerDelegate {
        var onSelect: (CNContact) -> Void
        var onClose: () -> Void
        weak var picker: CNContactPicker?

        init(onSelect: @escaping (CNContact) -> Void, onClose: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onClose = onClose
        }

        func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
            onSelect(contact)
            picker.close()
        }

        func contactPickerDidClose(_ picker: CNContactPicker) {
            onClose()
        }
    }
}
