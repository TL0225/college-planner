import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct ShortcutWebHostView: View {
    let shortcut: WebShortcut
    @ObservedObject var coordinator: ShortcutWebCoordinator
    @Binding var activePage: AppPage
    var isTabVisible: Bool = true

    @EnvironmentObject private var toolbarCoordinator: AppToolbarCoordinator

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
        .onChange(of: shortcut.urlString) { _, _ in
            coordinator.sync(shortcut: shortcut)
        }
        .onChange(of: shortcut.title) { _, _ in
            toolbarCoordinator.bsTitle = shortcut.title
        }
        .onChange(of: isTabVisible) { _, visible in
            if visible { wireToolbarIfVisible() }
        }
        .onChange(of: coordinator.canGoBack) { _, val in
            guard isTabVisible else { return }
            toolbarCoordinator.bsCanGoBack = val
        }
        .onChange(of: coordinator.canGoForward) { _, val in
            guard isTabVisible else { return }
            toolbarCoordinator.bsCanGoForward = val
        }
        .onChange(of: coordinator.isLoading) { _, val in
            guard isTabVisible else { return }
            toolbarCoordinator.bsIsLoading = val
        }
        .onChange(of: coordinator.pageTitle) { _, val in
            guard isTabVisible else { return }
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                toolbarCoordinator.bsTitle = trimmed
            } else {
                toolbarCoordinator.bsTitle = shortcut.title
            }
        }
    }

    private func wireToolbarIfVisible() {
        guard isTabVisible else { return }
        toolbarCoordinator.onBsBack = { coordinator.goBack() }
        toolbarCoordinator.onBsForward = { coordinator.goForward() }
        toolbarCoordinator.onBsReload = { coordinator.reload() }
        toolbarCoordinator.onBsPortalHome = { coordinator.loadHome() }
        toolbarCoordinator.onBsFind = {}
        toolbarCoordinator.bsTitle = shortcut.title
        syncToolbarChrome()
    }

    private func syncToolbarChrome() {
        toolbarCoordinator.bsCanGoBack = coordinator.canGoBack
        toolbarCoordinator.bsCanGoForward = coordinator.canGoForward
        toolbarCoordinator.bsIsLoading = coordinator.isLoading
    }
}

struct ShortcutWebViewRepresentable: NSViewRepresentable {
    let coordinator: ShortcutWebCoordinator

    func makeNSView(context: Context) -> WKWebView {
        coordinator.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
