// ShortcutWebCoordinator.swift
// Feature: Core
// Purpose: Core module — ShortcutWebCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import WebKit
import Combine

@MainActor
enum WebShortcutCoordinatorPool {
    private static var coordinators: [UUID: ShortcutWebCoordinator] = [:]

    static func coordinator(for shortcutId: UUID) -> ShortcutWebCoordinator {
        if let existing = coordinators[shortcutId] {
            return existing
        }
        let created = ShortcutWebCoordinator()
        coordinators[shortcutId] = created
        return created
    }

    static func prune(keepingIds: Set<UUID>) {
        coordinators = coordinators.filter { keepingIds.contains($0.key) }
    }

    /// Drops WKWebView coordinators for shortcuts that no longer exist (Phase 2 P1).
    static func pruneToRegisteredShortcuts() {
        prune(keepingIds: Set(WebShortcutStore.loadAllSync().map(\.id)))
    }
}

@MainActor
final class ShortcutWebCoordinator: NSObject, ObservableObject {
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var estimatedProgress: Double = 0
    @Published private(set) var pageTitle: String = ""

    let webView: WKWebView

    private var homeURL: URL?
    private var boundShortcutId: UUID?
    private var lastLoadedURLString: String?

    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsMagnification = true
        self.webView = wv

        super.init()

        wv.navigationDelegate = self
        wv.uiDelegate = self

        progressObservation = wv.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.estimatedProgress = wv.estimatedProgress }
        }
        loadingObservation = wv.observe(\.isLoading, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.isLoading = wv.isLoading }
        }
        backObservation = wv.observe(\.canGoBack, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.canGoBack = wv.canGoBack }
        }
        forwardObservation = wv.observe(\.canGoForward, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.canGoForward = wv.canGoForward }
        }
        titleObservation = wv.observe(\.title, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.pageTitle = wv.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }
    }

    deinit {
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
        backObservation?.invalidate()
        forwardObservation?.invalidate()
        titleObservation?.invalidate()
    }

    func sync(shortcut: WebShortcut) {
        let id = shortcut.id
        if boundShortcutId != id {
            boundShortcutId = id
            lastLoadedURLString = nil
        }

        guard let url = shortcut.resolvedURL else { return }
        homeURL = url

        let target = url.absoluteString
        if lastLoadedURLString == target { return }

        lastLoadedURLString = target
        webView.load(URLRequest(url: url))
    }

    func loadHome() {
        guard let homeURL else { return }
        webView.load(URLRequest(url: homeURL))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
}

extension ShortcutWebCoordinator: WKNavigationDelegate {}

extension ShortcutWebCoordinator: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
