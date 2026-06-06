// WebToolbarContent.swift
// Feature: App / Toolbar

import SwiftUI

struct WebToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(id: "portal.home", placement: .navigation) {
            PortalHomeToolbarButton()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            WebNavigationToolbar()
        }
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
            StaticToolbarGlassButton(
                symbol: "chevron.left",
                tip: "Back",
                accessibilityIdentifier: "toolbar.web.back",
                action: { toolbarDispatcher.dispatch(.web(.back)) },
                isEnabled: projection.canGoBack
            )
            StaticToolbarGlassButton(
                symbol: "chevron.right",
                tip: "Forward",
                accessibilityIdentifier: "toolbar.web.forward",
                action: { toolbarDispatcher.dispatch(.web(.forward)) },
                isEnabled: projection.canGoForward
            )
            StaticToolbarGlassButton(
                symbol: "arrow.clockwise",
                tip: "Reload",
                accessibilityIdentifier: "toolbar.web.reload"
            ) {
                toolbarDispatcher.dispatch(.web(.reload))
            }
        }
    }
}

struct PortalHomeToolbarButton: View {
    @Environment(AppContainer.self) private var appContainer

    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    var body: some View {
        StaticToolbarGlassButton(
            symbol: "house",
            tip: String(localized: "brightspace.toolbar.portal_home_help"),
            accessibilityIdentifier: "toolbar.web.portalHome"
        ) {
            toolbarDispatcher.dispatch(.web(.portalHome))
        }
        .accessibilityLabel(String(localized: "brightspace.toolbar.portal_home_a11y"))
    }
}
