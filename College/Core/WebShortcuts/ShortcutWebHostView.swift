// ShortcutWebHostView.swift
// Feature: Core
// Purpose: Core module — ShortcutWebHostView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import WebKit
import AppKit

struct ShortcutWebHostView: View {
    let shortcut: WebShortcut
    @ObservedObject var coordinator: ShortcutWebCoordinator
    @Binding var activePage: AppPage
    var isTabVisible: Bool = true

    @Environment(AppContainer.self) private var appContainer

    private var webPortalScene: WebPortalSceneState { appContainer.webPortalScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }
    @State private var toolbarHandlerToken: ToolbarHandlerToken?

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * coordinator.estimatedProgress, height: 2)
                        .animation(.easeInOut(duration: 0.1), value: coordinator.estimatedProgress)
                }
                .frame(height: 2)
            }

            ShortcutWebViewRepresentable(coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.windowBackground)
        .onAppear {
            coordinator.sync(shortcut: shortcut)
            wireToolbarIfVisible()
            syncToolbarChrome()
        }
        .onDisappear {
            if isTabVisible {
                toolbarHandlerToken?.invalidate()
                toolbarHandlerToken = nil
            }
        }
        .onChange(of: shortcut.urlString) { _, _ in
            coordinator.sync(shortcut: shortcut)
        }
        .onChange(of: shortcut.title) { _, title in
            webPortalScene.title = title
        }
        .onChange(of: isTabVisible) { _, visible in
            if visible {
                wireToolbarIfVisible()
            } else {
                toolbarHandlerToken?.invalidate()
                toolbarHandlerToken = nil
            }
        }
        .onChange(of: coordinator.canGoBack) { _, val in
            guard isTabVisible else { return }
            webPortalScene.canGoBack = val
        }
        .onChange(of: coordinator.canGoForward) { _, val in
            guard isTabVisible else { return }
            webPortalScene.canGoForward = val
        }
        .onChange(of: coordinator.isLoading) { _, val in
            guard isTabVisible else { return }
            webPortalScene.isLoading = val
        }
        .onChange(of: coordinator.pageTitle) { _, val in
            guard isTabVisible else { return }
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            webPortalScene.title = trimmed.isEmpty ? shortcut.title : trimmed
        }
    }

    private func wireToolbarIfVisible() {
        guard isTabVisible else { return }
        webPortalScene.title = shortcut.title
        syncToolbarChrome()

        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = toolbarDispatcher.register(owner: .webPortal(nil)) { action in
            guard case .web(let webAction) = action else { return }
            switch webAction {
            case .back:
                coordinator.goBack()
            case .forward:
                coordinator.goForward()
            case .reload:
                coordinator.reload()
            case .portalHome:
                coordinator.loadHome()
            case .findInPage:
                break
            }
        }
    }

    private func syncToolbarChrome() {
        webPortalScene.canGoBack = coordinator.canGoBack
        webPortalScene.canGoForward = coordinator.canGoForward
        webPortalScene.isLoading = coordinator.isLoading
    }
}

struct ShortcutWebViewRepresentable: NSViewRepresentable {
    let coordinator: ShortcutWebCoordinator

    func makeNSView(context: Context) -> WKWebView {
        coordinator.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
