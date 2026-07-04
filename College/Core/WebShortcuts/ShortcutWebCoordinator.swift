// ShortcutWebCoordinator.swift
// Feature: Core
// Purpose: Core module — ShortcutWebCoordinator.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import WebKit
import Combine
import AppKit

@MainActor
enum WebShortcutCoordinatorPool {
    private static var coordinators: [UUID: ShortcutWebCoordinator] = [:]
    /// The shortcut whose page is currently on screen. Its web view is kept awake;
    /// every other coordinator is put to sleep to reclaim page memory.
    private(set) static var activeId: UUID?

    static var activeCoordinatorCount: Int { coordinators.count }

    static func coordinator(for shortcutId: UUID) -> ShortcutWebCoordinator {
        if let existing = coordinators[shortcutId] {
            return existing
        }
        let created = ShortcutWebCoordinator()
        coordinators[shortcutId] = created
        return created
    }

    /// Marks one shortcut as active: wakes its web view and sleeps every other one.
    static func activate(_ shortcutId: UUID) {
        activeId = shortcutId
        for (id, coordinator) in coordinators {
            if id == shortcutId {
                coordinator.wake()
            } else {
                coordinator.sleep()
            }
        }
    }

    /// Sleeps every coordinator. Used when navigating away from shortcuts entirely (e.g. to
    /// Calendar) so no shortcut page stays resident while it is off screen.
    static func deactivate() {
        activeId = nil
        for (_, coordinator) in coordinators {
            coordinator.sleep()
        }
    }

    /// Sleeps every coordinator except the active one. Used on memory pressure so a
    /// background of vetted LMS pages does not keep multiple full DOM/JS heaps resident.
    static func sleepInactiveForMemoryPressure() {
        for (id, coordinator) in coordinators where id != activeId {
            coordinator.sleep()
        }
    }

    /// Drops the shared HTTP/disk/memory caches without touching cookies, local storage, or
    /// IndexedDB — so login sessions for LMS portals survive while reclaimable cache is freed.
    static func purgeTransientWebCaches() {
        let cacheTypes: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeFetchCache,
        ]
        WKWebsiteDataStore.default().removeData(
            ofTypes: cacheTypes,
            modifiedSince: .distantPast
        ) {}
    }

    static func prune(keepingIds: Set<UUID>) {
        coordinators = coordinators.filter { keepingIds.contains($0.key) }
        if let activeId, !keepingIds.contains(activeId) {
            self.activeId = nil
        }
    }

    /// Drops WKWebView coordinators for shortcuts that no longer exist (Phase 2 P1).
    static func pruneToRegisteredShortcuts() {
        prune(keepingIds: WebShortcutStore.allShortcutIDsSync())
    }
}

@MainActor
final class ShortcutWebCoordinator: NSObject, ObservableObject {
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var estimatedProgress: Double = 0
    @Published private(set) var pageTitle: String = ""
    /// `true` while this coordinator's page has been unloaded to `about:blank` to free memory.
    @Published private(set) var isAsleep: Bool = false
    /// A user-facing message when the page fails to load (offline, DNS, server error).
    @Published private(set) var loadError: String?
    /// Last successful render, shown while the page reloads on wake so it doesn't flash blank.
    @Published private(set) var pageSnapshot: NSImage?
    /// `true` from the moment a slept page is woken until its reload finishes.
    @Published private(set) var isWaking: Bool = false

    let webView: WKWebView

    // Note: an explicit shared WKProcessPool is intentionally not used. Since macOS 12 it is
    // a no-op — WebKit already shares Web Content processes across web views that use the same
    // WKWebsiteDataStore, which all shortcut coordinators do (the default store below).
    private static let blankURL = URL(string: "about:blank")!

    private var homeURL: URL?
    private var boundShortcutId: UUID?
    /// The last real (non-blank) URL the user was on, restored when the page wakes.
    private var wakeURL: URL?
    /// Whether a real page is currently loaded (vs. never loaded / unloaded to blank).
    private var hasLivePage: Bool = false

    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // LMS portals embed lecture/video players; require an explicit tap before they
        // start so idle pages don't keep decoders and buffers resident.
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.allowsAirPlayForMediaPlayback = false

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

    /// Binds the coordinator to a shortcut and updates its home URL. Actual loading is
    /// driven by ``wake()`` so the active/inactive (awake/asleep) policy stays in one place.
    func configure(shortcut: WebShortcut) {
        let id = shortcut.id
        let resolved = shortcut.resolvedURL

        if boundShortcutId != id {
            // New shortcut bound to this (reused) coordinator: start fresh.
            boundShortcutId = id
            homeURL = resolved
            wakeURL = nil
            hasLivePage = false
        } else if let resolved, homeURL?.absoluteString != resolved.absoluteString {
            // User edited the address of the same shortcut: navigate to the new home.
            homeURL = resolved
            wakeURL = nil
            hasLivePage = false
        } else if homeURL == nil {
            homeURL = resolved
        }
    }

    /// Restores the page (active tab). Loads the last visited URL, or home on first use.
    func wake() {
        isAsleep = false
        guard !hasLivePage else { return }
        guard let target = wakeURL ?? homeURL else { return }
        hasLivePage = true
        isWaking = true
        webView.load(URLRequest(url: target))
    }

    /// Unloads the page to `about:blank` to release its DOM/JS heap while keeping the
    /// coordinator and login session (cookies live in the shared data store) intact.
    func sleep() {
        guard !isAsleep else { return }
        if let current = webView.url, current != Self.blankURL {
            wakeURL = current
        }
        isAsleep = true
        hasLivePage = false
        webView.stopLoading()
        webView.load(URLRequest(url: Self.blankURL))
    }

    func loadHome() {
        guard let homeURL else { return }
        isAsleep = false
        hasLivePage = true
        wakeURL = homeURL
        webView.load(URLRequest(url: homeURL))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() {
        loadError = nil
        if isAsleep || !hasLivePage {
            wake()
        } else {
            webView.reload()
        }
    }

    /// Reloads from the home URL after an error.
    func retry() {
        loadError = nil
        hasLivePage = false
        wake()
    }

    /// Searches the current page, scrolling to and highlighting the next/previous match.
    func find(_ text: String, forward: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        webView.find(trimmed, configuration: config) { _ in }
    }

    private func registrableDomain(_ host: String) -> String {
        let parts = host.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return host.lowercased() }
        return parts.suffix(2).joined(separator: ".")
    }
}

extension ShortcutWebCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url != Self.blankURL else { return }
        // Track the live URL so a later sleep/wake cycle restores the user's location.
        wakeURL = url
        loadError = nil
        isWaking = false
        // Capture a fresh snapshot while the page is on screen for instant-looking wakes.
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            if let image { self?.pageSnapshot = image }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        recordFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        recordFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            WKWebViewProcessRecovery.reloadIfMatching(webView, ownedBy: self?.webView)
        }
    }

    private func recordFailure(_ error: Error) {
        isWaking = false
        let nsError = error as NSError
        // Ignore user/programmatic cancellations (e.g. sleep's stopLoading, rapid taps).
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if webView.url == Self.blankURL { return }
        loadError = nsError.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // Route user-clicked links to other sites out to the system browser so heavy
        // third-party pages don't load inside (and stay in) the embedded view. Server-side
        // redirects and SSO (not .linkActivated) stay in-app so logins keep working.
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let targetHost = url.host, let homeHost = homeURL?.host,
           registrableDomain(targetHost) != registrableDomain(homeHost) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

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
