// AssistantUndoSupport.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantUndoSupport.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

@MainActor
enum AssistantUndoSupport {
    static func performUndoable(in manager: CollegePersistence, _ work: () -> Void) {
        _ = manager
        work()
        manager.save()
    }

    static func confirmDestructive(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if let delete = alert.buttons.first {
            delete.hasDestructiveAction = true
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
