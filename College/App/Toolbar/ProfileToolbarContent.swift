// ProfileToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct ProfileToolbarContent: ToolbarContent {
    let dispatcher: ToolbarDispatcher

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                dispatcher.dispatch(.profile(.advisorPrep))
            } label: {
                Label("Advisor Meeting Prep", systemImage: "person.2.wave.2")
            }
            .collegeInteractiveSurface(.toolbar)
            .help("Open advisor meeting prep")
            .accessibilityIdentifier("toolbar.profile.advisorPrep")

            Button {
                dispatcher.dispatch(.profile(.editProfile))
            } label: {
                Label("Edit Profile", systemImage: "pencil")
            }
            .collegeInteractiveSurface(.toolbar)
            .help("Edit profile details")
            .accessibilityIdentifier("toolbar.profile.edit")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

enum ProfileToolbarProvider: ToolbarProviding {
    @ToolbarContentBuilder
    static func toolbarContent(context: ToolbarProviderContext) -> some ToolbarContent {
        ProfileToolbarContent(dispatcher: context.dispatcher)
    }
}
