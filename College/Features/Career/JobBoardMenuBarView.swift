// JobBoardMenuBarView.swift
// Feature: Career
// Purpose: Career module — JobBoardMenuBarView.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import SwiftUI

struct JobBoardMenuBarView: View {
    @Environment(AppContainer.self) private var container
    private var brightspaceCoordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var coordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @ObservedObject private var coordinator = WorkdayJobBoardSyncCoordinator.shared

    var body: some View {
        menuContent
            .onAppear { refreshRecentPostings() }
            .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in refreshRecentPostings() }
    }

    @ViewBuilder
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New openings")
                .font(.headline)
            if recentPostings.isEmpty {
                Text("No new jobs right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentPostings, id: \.id) { posting in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(posting.title ?? "Untitled")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(posting.companyDisplayName ?? posting.companySlug)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Button("View all openings") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .jobBoardOpenOpenings, object: nil)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .frame(width: 280)
    }

    @State private var recentPostings: [WorkdayJobPosting] = []

    private func refreshRecentPostings() {
        recentPostings = WorkdayReadBridge.recentActivePostings(limit: 5)
    }
}

extension Notification.Name {
    static let jobBoardOpenOpenings = Notification.Name("jobBoard.openOpenings")
}
