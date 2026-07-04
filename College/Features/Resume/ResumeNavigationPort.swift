// ResumeNavigationPort.swift
// Feature: Resume
// Purpose: Open the Resume Builder window without editing shell files.

import SwiftUI

@MainActor
enum ResumeNavigationPort {
    static let builderWindowID = "resume-builder"

    static func openResumeBuilder(openWindow: OpenWindowAction) {
        openWindow(id: builderWindowID)
    }

    static func openResumeBuilder(openWindow: OpenWindowAction, documentID: UUID) {
        openWindow(id: builderWindowID, value: documentID)
    }
}
