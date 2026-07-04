// CalendarOverlaySupportViews.swift
// Feature: Calendar
// Purpose: Small AppKit bridge helpers used by calendar overlay sheets.

import AppKit
import Contacts
import ContactsUI
import SwiftUI

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

final class CalendarContactPickerDelegate: NSObject, CNContactPickerDelegate {
    private let onSelect: (CNContact) -> Void
    private let onClose: () -> Void

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
