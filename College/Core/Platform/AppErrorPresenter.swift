// AppErrorPresenter.swift
// Feature: Core/Platform
// Purpose: User-visible errors for extension handoffs and host surfaces.

import AppKit

enum AppErrorPresenter {
    @MainActor
    static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
