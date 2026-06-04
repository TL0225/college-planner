// CareerApplicationContextMenu.swift
// Feature: Career
// Purpose: Career module — CareerApplicationContextMenu.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct CareerApplicationContextMenu: ViewModifier {
    let persistence: CollegePersistence
    let application: JobApplication

    func body(content: Content) -> some View {
        content.contextMenu {
            ForEach(CareerApplicationStatus.allCases, id: \.self) { status in
                Button("Move to \(status.displayName)") {
                    persistence.moveCareerApplication(id: application.id, to: status)
                    CareerFollowUpScheduler.shared.reconcile(using: persistence)
                }
            }
            Divider()
            Button("Copy URL") {
                guard let url = application.postingURLString, !url.isEmpty else { return }
                copyToPasteboard(url)
            }
            Button(role: .destructive) {
                persistence.deleteCareerApplication(application)
                CareerFollowUpScheduler.shared.reconcile(using: persistence)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension View {
    func careerApplicationContextMenu(
        for application: JobApplication,
        persistence: CollegePersistence
    ) -> some View {
        modifier(CareerApplicationContextMenu(persistence: persistence, application: application))
    }
}
