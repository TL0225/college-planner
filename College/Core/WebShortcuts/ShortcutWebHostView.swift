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
    @State private var showFindBar = false
    @State private var findText = ""

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

            ZStack(alignment: .top) {
                ShortcutWebViewRepresentable(coordinator: coordinator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if coordinator.isWaking, let snapshot = coordinator.pageSnapshot {
                    Image(nsImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .allowsHitTesting(false)
                }

                if let error = coordinator.loadError {
                    ShortcutWebErrorView(message: error) { coordinator.retry() }
                }

                if showFindBar {
                    findBar
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.windowBackground)
        .onAppear {
            coordinator.configure(shortcut: shortcut)
            WebShortcutCoordinatorPool.activate(shortcut.id)
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
            coordinator.configure(shortcut: shortcut)
            WebShortcutCoordinatorPool.activate(shortcut.id)
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
                showFindBar.toggle()
            }
        }
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "shortcuts.find.placeholder", defaultValue: "Find on page"),
                text: $findText
            )
            .textFieldStyle(.plain)
            .frame(width: 180)
            .onSubmit { coordinator.find(findText, forward: true) }

            Button {
                coordinator.find(findText, forward: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(findText.isEmpty)
            .help(String(localized: "shortcuts.find.previous", defaultValue: "Previous match"))

            Button {
                coordinator.find(findText, forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(findText.isEmpty)
            .help(String(localized: "shortcuts.find.next", defaultValue: "Next match"))

            Button {
                showFindBar = false
                findText = ""
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(String(localized: "common.close", defaultValue: "Close"))
        }
        .font(DesignSystem.Fonts.main(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
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

private struct ShortcutWebErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(DesignSystem.Fonts.main(size: 42))
                .foregroundStyle(.secondary)
            Text(String(localized: "shortcuts.error.title", defaultValue: "This page didn’t load"))
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button(String(localized: "shortcuts.error.retry", defaultValue: "Try Again")) {
                onRetry()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}
