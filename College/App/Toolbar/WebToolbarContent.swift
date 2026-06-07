// WebToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct WebToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(id: "portal.home", placement: .navigation) {
            PortalHomeToolbarButton()
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .primaryAction) {
            WebNavigationToolbar()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

struct WebNavigationToolbar: View {
    @Environment(AppContainer.self) private var appContainer

    private var webPortalScene: WebPortalSceneState { appContainer.webPortalScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    private var projection: WebPortalSceneState.ToolbarProjection {
        webPortalScene.toolbarProjection
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                toolbarDispatcher.dispatch(.web(.back))
            } label: {
                ToolbarMetrics.glassIconLabel(systemName: "chevron.left")
            }
            .toolbarIconButtonStyle()
            .help("Back")
            .accessibilityLabel("Back")
            .accessibilityIdentifier("toolbar.web.back")
            .disabled(!projection.canGoBack)

            Button {
                toolbarDispatcher.dispatch(.web(.forward))
            } label: {
                ToolbarMetrics.glassIconLabel(systemName: "chevron.right")
            }
            .toolbarIconButtonStyle()
            .help("Forward")
            .accessibilityLabel("Forward")
            .accessibilityIdentifier("toolbar.web.forward")
            .disabled(!projection.canGoForward)

            Button {
                toolbarDispatcher.dispatch(.web(.reload))
            } label: {
                ToolbarMetrics.glassIconLabel(systemName: "arrow.clockwise")
            }
            .toolbarIconButtonStyle()
            .help("Reload")
            .accessibilityLabel("Reload")
            .accessibilityIdentifier("toolbar.web.reload")
        }
    }
}

struct PortalHomeToolbarButton: View {
    @Environment(AppContainer.self) private var appContainer

    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    var body: some View {
        Button {
            toolbarDispatcher.dispatch(.web(.portalHome))
        } label: {
            ToolbarMetrics.glassIconLabel(systemName: "house")
        }
        .toolbarIconButtonStyle()
        .help(String(localized: "brightspace.toolbar.portal_home_help"))
        .accessibilityLabel(String(localized: "brightspace.toolbar.portal_home_a11y"))
        .accessibilityIdentifier("toolbar.web.portalHome")
    }
}
