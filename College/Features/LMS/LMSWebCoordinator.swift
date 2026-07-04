// LMSWebCoordinator.swift
// Feature: LMS
// Purpose: LMS module — LMSImportItem.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import WebKit
import SwiftUI
import Combine
import AppKit

// MARK: - Supporting Types

enum LMSPageType: String {
    case login, courseHome, assignment, grades, announcement, dashboard, content, other
}

struct LMSImportItem: Identifiable {
    let id: String
    var title: String
    var dueDate: Date?
    var courseCode: String?
    var points: String?
    var description: String?
    var lmsItemId: String
    var pageType: LMSPageType
    var isSelected: Bool = true
}

struct LMSDownload: Identifiable {
    let id: UUID
    var filename: String
    var progress: Double
    enum State { case downloading, importingToVault, done, failed }
    var state: State
}

struct LMSCredentialOffer: Equatable {
    var username: String
    var host: String
}

// MARK: - LMSWebCoordinator

@MainActor
final class LMSWebCoordinator: NSObject, ObservableObject {

    // MARK: Published state
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var currentURL: URL?
    @Published var pageTitle: String = LMSPortalConfiguration.lmsDisplayName
    @Published var pageType: LMSPageType = .other
    @Published var pendingImportItems: [LMSImportItem] = []
    @Published var activeDownloads: [LMSDownload] = []
    @Published var offerSavePassword: LMSCredentialOffer? = nil
    /// Bounded visible text from the page when the user opts in (on-device features / future AI).
    @Published var lastPageContextSnippet: String?

    /// UserDefaults key for last successfully loaded LMS URL (Phase A session restore).
    static let lastVisitedURLStorageKey = LMSStorageKeys.lastVisitedURL
    /// When true, next LMS tab appearance loads the portal and clears the resume bookmark (intents / menu).
    static let pendingLoadPortalKey = LMSStorageKeys.pendingLoadPortalOnNextAppear
    private static let pageContextExtractionKey = LMSStorageKeys.allowPageContextExtraction
    private static let pageContextDebounceNanos: UInt64 = 1_200_000_000

    // MARK: Owned WebView (lazy — avoids WKWebView process spin-up during app init)
    private var _webView: WKWebView?
    var webView: WKWebView {
        ensureWebViewCreated()
        return _webView!
    }
    private var pageContextExtractionTask: Task<Void, Never>?

    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    /// SSO / `window.open` flows need a real auxiliary `WKWebView`; loading popups into the main view breaks IdP handshakes.
    private var authPopupHost: LMSAuthPopupHost?

    override init() {
        super.init()
    }

    private func ensureWebViewCreated() {
        guard _webView == nil else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        _webView = webView

        if let jsURL = Bundle.main.url(forResource: "LMSJSBridge", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            userContentController.addUserScript(script)
        }

        userContentController.add(WeakScriptMessageHandler(target: self), name: "pageContext")
        userContentController.add(WeakScriptMessageHandler(target: self), name: "loginCredentials")

        webView.navigationDelegate = self
        webView.uiDelegate = self

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.estimatedProgress = wv.estimatedProgress }
        }
        loadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.isLoading = wv.isLoading }
        }
        backObservation = webView.observe(\.canGoBack, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.canGoBack = wv.canGoBack }
        }
        forwardObservation = webView.observe(\.canGoForward, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.canGoForward = wv.canGoForward }
        }
        titleObservation = webView.observe(\.title, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.pageTitle = Self.sanitizedDocumentTitle(wv.title)
            }
        }
        urlObservation = webView.observe(\.url, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.currentURL = wv.url }
        }
    }

    deinit {
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
        backObservation?.invalidate()
        forwardObservation?.invalidate()
        titleObservation?.invalidate()
        urlObservation?.invalidate()
    }

    // MARK: - Navigation

    func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Loads the portal URL from Settings when configured; does not clear the last-visited bookmark.
    func loadPortalHome() {
        guard let url = resolvePortalURL() else { return }
        load(url: url)
    }

    /// D2L often sets `document.title` to "Loading..." during SPA transitions; avoid showing that in chrome / Handoff.
    static func sanitizedDocumentTitle(_ raw: String?) -> String {
        let fallback = String(localized: "app.page.lms")
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return fallback }
        let lower = trimmed.lowercased()
        if lower == "loading" || lower.hasPrefix("loading") { return fallback }
        return trimmed
    }

    /// Restores the last session URL when the web view has no document; otherwise no-op.
    func restoreIfNeeded() {
        if webView.url != nil { return }
        if webView.canGoBack { return }
        let portalHost = resolvePortalURL()?.host
        if let raw = UserDefaults.standard.string(forKey: Self.lastVisitedURLStorageKey),
           !raw.isEmpty,
           let url = URL(string: raw),
           Self.shouldPersistLastVisitedURL(url, portalHost: portalHost) {
            load(url: url)
            return
        }
        if UserDefaults.standard.string(forKey: Self.lastVisitedURLStorageKey) != nil {
            Self.clearPersistedLastVisitedURL()
        }
        if let url = resolvePortalURL() {
            load(url: url)
        }
    }

    /// Loads the configured portal and clears the persisted last-visited URL (menu / intent “sign in”).
    func loadPortalAndClearResumeBookmark() {
        Self.clearPersistedLastVisitedURL()
        guard let url = resolvePortalURL() else { return }
        load(url: url)
    }

    /// Launch preload hook: proactively boots the web session so LMS tab entry is warm.
    func preloadPortalForLaunch(
        timeout: TimeInterval = 20,
        progress: ((Double) -> Void)? = nil,
        detail: ((String) -> Void)? = nil
    ) async throws {
        detail?("Initializing LMS web session")
        if webView.url == nil {
            detail?("Loading LMS portal")
            loadPortalHome()
            progress?(0.12)
        } else {
            detail?("Using existing LMS session")
            progress?(0.22)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let hasURL = currentURL != nil
            let hasMeaningfulProgress = estimatedProgress >= 0.65

            if hasURL {
                detail?("Loading portal content")
            } else {
                detail?("Waiting for portal response")
            }

            let synthesizedProgress: Double = {
                if hasURL {
                    return min(0.95, max(0.35, estimatedProgress * 0.9))
                }
                return min(0.3, max(0.1, estimatedProgress * 0.6))
            }()
            progress?(synthesizedProgress)

            if hasURL && (hasMeaningfulProgress || !isLoading) {
                detail?("LMS preload complete")
                progress?(1)
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        throw NSError(
            domain: "College.LMSPreload",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out preloading the learning management system."]
        )
    }

    static func clearPersistedLastVisitedURL() {
        UserDefaults.standard.removeObject(forKey: lastVisitedURLStorageKey)
    }

    private static func shouldPersistLastVisitedURL(_ url: URL, portalHost: String?) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        guard let portalHost = portalHost?.lowercased(), !portalHost.isEmpty else { return false }
        let isPortalHost = host == portalHost || host.hasSuffix(".\(portalHost)")
        guard isPortalHost else { return false }

        let path = url.path.lowercased()
        let query = (url.query ?? "").lowercased()
        let blockedPathFragments = [
            "/d2l/login",
            "/d2l/auth",
            "/logout",
            "/signout",
            "/callback",
            "/oauth",
            "/saml",
            "/wsfed",
            "/error",
            "/forbidden",
        ]
        if blockedPathFragments.contains(where: { path.contains($0) }) {
            return false
        }
        let blockedQueryFragments = [
            "ticket=",
            "samlrequest",
            "samlresponse",
            "code=",
            "wa=",
            "wresult=",
            "forbidden",
            "error=",
        ]
        if blockedQueryFragments.contains(where: { query.contains($0) }) {
            return false
        }
        return true
    }

    @MainActor
    func presentFindNavigator() {
        _ = webView.window?.makeFirstResponder(webView)
        NSApp.sendAction(Selector(("find:")), to: nil, from: nil)
    }

    @MainActor
    func printCurrentPage() {
        let op = webView.printOperation(with: .shared)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let window = webView.window {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    /// One-shot visible text for on-device analysis (opt-in via Settings). Does not log content.
    func extractVisibleTextPreview(maxCharacters: Int = 8000) async -> String? {
        let js = """
        (function() {
          try {
            var t = document.body ? document.body.innerText : '';
            return typeof t === 'string' ? t : '';
          } catch (e) { return ''; }
        })();
        """
        let any = try? await webView.evaluateJavaScript(js)
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxCharacters { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        return String(trimmed[..<end])
    }

    func goBack()    { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload()    { webView.reload() }

    func resolvePortalURL() -> URL? {
        LMSPortalConfiguration.resolvedPortalURL()
    }

    /// Returns a JS string literal (double-quoted, with internal quotes and backslashes escaped).
    private static func quotedJSString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    // MARK: - Import helpers

    func clearPendingItems() {
        pendingImportItems = []
    }

    func dismissSavePasswordOffer() {
        offerSavePassword = nil
    }

    #if DEBUG
    @MainActor
    func debugLogLMSFocusSnapshot() {
        let wvURL = webView.url?.absoluteString ?? "(nil)"
        let back = webView.canGoBack
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let n = cookies.count
            Task { @MainActor in
                print("[LMS DEBUG] webView.url=\(wvURL) canGoBack=\(back) cookieCount=\(n)")
            }
        }
    }
    #endif

    @MainActor
    private func schedulePageContextExtractionIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.pageContextExtractionKey) else {
            lastPageContextSnippet = nil
            return
        }
        pageContextExtractionTask?.cancel()
        pageContextExtractionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.pageContextDebounceNanos)
            guard !Task.isCancelled, let self else { return }
            let text = await self.extractVisibleTextPreview(maxCharacters: 12_000)
            self.lastPageContextSnippet = text
        }
    }

    @MainActor
    private func injectSavedCredentialsForLoginPage(webView: WKWebView) async {
        guard let host = webView.url?.host else { return }
        let path = webView.url?.path.lowercased() ?? ""
        let hostLower = host.lowercased()
        let looksLogin = pageType == .login
            || path.contains("/d2l/login")
            || path.contains("/d2l/auth")
            || hostLower.contains("microsoftonline.com")
            || hostLower.contains("okta.com")
            || hostLower.contains("shibboleth")
        guard looksLogin else { return }
        guard let creds = LMSKeychainService.shared.load(host: host) else { return }
        let js = Self.javascriptFillCredentials(username: creds.username, password: creds.password)
        _ = try? await webView.evaluateJavaScript(js)
    }

    private static func javascriptFillCredentials(username: String, password: String) -> String {
        """
        (function() {
            var pwInput = document.querySelector('input[type="password"]');
            var userInput = document.querySelector(
                'input[autocomplete="username"], input[name="userName"], input[name="username"], input[id="userName"], input[id="username"], input[type="email"], input[type="text"][name*="user"], input[type="text"][id*="user"], input[type="text"][name*="login"], input[type="text"][id*="login"]'
            );
            function fillAndDispatch(el, value) {
                if (!el) return;
                var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
                nativeSetter.call(el, value);
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
            }
            fillAndDispatch(userInput, \(Self.quotedJSString(username)));
            fillAndDispatch(pwInput, \(Self.quotedJSString(password)));
        })();
        """
    }
}

// MARK: - WKNavigationDelegate

extension LMSWebCoordinator: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, webView === self.webView else { return }
            // Pre-classify page type from URL so autofill injection in didFinish can check it
            if let path = webView.url?.path {
                let detectedType: LMSPageType
                if path.contains("/d2l/login") || path.contains("/d2l/auth") {
                    detectedType = .login
                } else {
                    detectedType = .other
                }
                self.pageType = detectedType
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if webView === self.webView {
                self.currentURL = webView.url
                let portalHost = self.resolvePortalURL()?.host
                if let u = webView.url, Self.shouldPersistLastVisitedURL(u, portalHost: portalHost) {
                    UserDefaults.standard.set(u.absoluteString, forKey: Self.lastVisitedURLStorageKey)
                }
                self.schedulePageContextExtractionIfEnabled()
            }
            // Login: fill from Keychain immediately and once more after DOM settles (D2L / SSO / IdP popups).
            await self.injectSavedCredentialsForLoginPage(webView: webView)
            try? await Task.sleep(nanoseconds: 450_000_000)
            await self.injectSavedCredentialsForLoginPage(webView: webView)
        }
    }

    func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction) async
    -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload {
            return .download
        }
        return .allow
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            WKWebViewProcessRecovery.reloadIfMatching(webView, ownedBy: self?.webView)
        }
    }

    func webView(_ webView: WKWebView,
                             decidePolicyFor navigationResponse: WKNavigationResponse) async
    -> WKNavigationResponsePolicy {
        if Self.responseSuggestsFileDownload(navigationResponse.response) {
            return .download
        }
        return .allow
    }

    /// MIME + HTTP `Content-Disposition` heuristics for LMS file endpoints.
    private static func responseSuggestsFileDownload(_ response: URLResponse) -> Bool {
        if let http = response as? HTTPURLResponse {
            let cd = (http.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
            if cd.contains("attachment") { return true }
        }
        guard let mimeType = response.mimeType?.lowercased() else { return false }
        let downloadPrefixes = [
            "application/pdf",
            "application/zip",
            "application/x-zip-compressed",
            "application/octet-stream",
            "binary/octet-stream",
            "application/vnd.ms-excel",
            "application/vnd.ms-powerpoint",
            "application/msword",
            "application/vnd.openxmlformats-officedocument",
            "application/vnd.apple.pages",
            "application/vnd.apple.numbers",
            "application/vnd.apple.keynote",
            "text/csv",
            "text/plain",
            "text/tab-separated-values",
            "application/rtf",
            "text/rtf",
        ]
        return downloadPrefixes.contains { mimeType.hasPrefix($0) }
    }

    nonisolated func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                             didBecome download: WKDownload) {
        Task { @MainActor [weak self] in
            self?.assignDownloadDelegate(download)
        }
    }

    nonisolated func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                             didBecome download: WKDownload) {
        Task { @MainActor [weak self] in
            self?.assignDownloadDelegate(download)
        }
    }

    @MainActor
    private func assignDownloadDelegate(_ download: WKDownload) {
        if objc_getAssociatedObject(download, &Self.dlManagerKey) != nil {
            return
        }
        let dlManager = LMSDownloadManager()
        dlManager.onDownloadAdded = { [weak self] dl in
            self?.activeDownloads.append(dl)
        }
        dlManager.onDownloadProgress = { [weak self] id, progress in
            if let idx = self?.activeDownloads.firstIndex(where: { $0.id == id }) {
                self?.activeDownloads[idx].progress = progress
            }
        }
        dlManager.onVaultImportStarted = { [weak self] id in
            guard let idx = self?.activeDownloads.firstIndex(where: { $0.id == id }) else { return }
            self?.activeDownloads[idx].state = .importingToVault
            self?.activeDownloads[idx].progress = 1
        }
        dlManager.onDownloadRowDismiss = { [weak self] id in
            self?.activeDownloads.removeAll { $0.id == id }
        }
        download.delegate = dlManager
        // Hold a reference by tagging the download object via objc association
        objc_setAssociatedObject(download, &LMSWebCoordinator.dlManagerKey, dlManager, .OBJC_ASSOCIATION_RETAIN)
    }

    private static var dlManagerKey = 0
}

// MARK: - WKUIDelegate

extension LMSWebCoordinator: WKUIDelegate {
    @MainActor
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let fromMain = webView === self.webView
        let fromOurPopup = authPopupHost?.popupWebView === webView
        guard fromMain || fromOurPopup else { return nil }

        prepareConfigurationForAuthAuxiliaryWebView(configuration)

        authPopupHost?.dismiss()
        let host = LMSAuthPopupHost(coordinator: self)
        authPopupHost = host
        return host.present(
            configuration: configuration,
            windowFeatures: windowFeatures,
            navigationDelegate: self,
            uiDelegate: self
        )
    }

    @MainActor
    func webViewDidClose(_ webView: WKWebView) {
        guard authPopupHost?.popupWebView === webView else { return }
        authPopupHost?.dismiss()
    }

    /// Shares cookies / process pool with the main LMS web view and wires the same JS bridge handlers.
    @MainActor
    private func prepareConfigurationForAuthAuxiliaryWebView(_ configuration: WKWebViewConfiguration) {
        let main = webView
        configuration.websiteDataStore = main.configuration.websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if let jsURL = Bundle.main.url(forResource: "LMSJSBridge", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL, encoding: .utf8) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
        }
        configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: "pageContext")
        configuration.userContentController.add(WeakScriptMessageHandler(target: self), name: "loginCredentials")
    }

    fileprivate func clearAuthPopupHost(_ host: LMSAuthPopupHost) {
        if authPopupHost === host {
            authPopupHost = nil
        }
    }
}

// MARK: - WKScriptMessageHandler

extension LMSWebCoordinator: WKScriptMessageHandler {

    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in
            self?.handleScriptMessage(name: message.name, body: message.body)
        }
    }

    @MainActor
    private func handleScriptMessage(name: String, body: Any) {
        switch name {
        case "pageContext":
            guard let dict = body as? [String: Any] else { return }
            handlePageContext(dict)
        case "loginCredentials":
            guard let dict = body as? [String: Any],
                  let username = dict["username"] as? String,
                  let host = dict["host"] as? String,
                  !username.isEmpty else { return }
            // Respect the "Offer to Save Password" toggle in Settings
            let saveEnabled = UserDefaults.standard.object(forKey: LMSStorageKeys.savePassword) as? Bool ?? true
            guard saveEnabled else { return }
            offerSavePassword = LMSCredentialOffer(username: username, host: host)
        default:
            break
        }
    }

    @MainActor
    private func handlePageContext(_ dict: [String: Any]) {
        let typeStr = dict["pageType"] as? String ?? "other"
        let newType = LMSPageType(rawValue: typeStr) ?? .other
        pageType = newType

        guard let rawItems = dict["items"] as? [[String: Any]], !rawItems.isEmpty else { return }

        var importItems: [LMSImportItem] = []
        let df = ISO8601DateFormatter()

        for raw in rawItems {
            guard let title = raw["title"] as? String, !title.isEmpty else { continue }
            let id = raw["id"] as? String ?? UUID().uuidString
            let lmsItemId = raw["lmsItemId"] as? String
                ?? raw["brightspaceItemId"] as? String
                ?? (currentURL?.absoluteString ?? "")
            var dueDate: Date?
            if let dueDateStr = raw["dueDate"] as? String {
                dueDate = df.date(from: dueDateStr)
            }
            // For grade items, store letterGrade in `description` and percentage in `points`
            // so they survive the trip to LMSImportSheet without adding new fields.
            let resolvedPoints: String?
            let resolvedDescription: String?
            if newType == .grades {
                resolvedPoints = raw["percentage"] as? String
                resolvedDescription = raw["letterGrade"] as? String
            } else {
                resolvedPoints = raw["points"] as? String
                resolvedDescription = raw["description"] as? String
            }
            let item = LMSImportItem(
                id: id,
                title: title,
                dueDate: dueDate,
                courseCode: raw["courseCode"] as? String,
                points: resolvedPoints,
                description: resolvedDescription,
                lmsItemId: lmsItemId,
                pageType: newType
            )
            importItems.append(item)
        }

        if !importItems.isEmpty {
            pendingImportItems = importItems
        }
    }
}

// MARK: - SSO / auth auxiliary window (macOS)

/// Hosts a separate `WKWebView` in an `NSWindow` so IdP `window.open` flows keep opener semantics and shared cookies.
@MainActor
fileprivate final class LMSAuthPopupHost: NSObject, NSWindowDelegate {
    private weak var coordinator: LMSWebCoordinator?
    private var window: NSWindow?
    private(set) weak var popupWebView: WKWebView?

    init(coordinator: LMSWebCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func present(
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        navigationDelegate: WKNavigationDelegate,
        uiDelegate: WKUIDelegate
    ) -> WKWebView {
        let w = max(400, (windowFeatures.width?.doubleValue).map { CGFloat($0) } ?? 920)
        let h = max(380, (windowFeatures.height?.doubleValue).map { CGFloat($0) } ?? 700)
        let initialSize = NSSize(width: w, height: h)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate

        let container = NSView(frame: NSRect(origin: .zero, size: initialSize))
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.contentView = container
        win.setContentSize(initialSize)
        win.title = String(localized: "lms.auth_popup_title")
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        window = win
        popupWebView = webView
        win.makeKeyAndOrderFront(nil)
        return webView
    }

    func dismiss() {
        let win = window
        win?.delegate = nil
        window = nil
        popupWebView = nil
        coordinator?.clearAuthPopupHost(self)
        win?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === window else { return }
        window?.delegate = nil
        window = nil
        popupWebView = nil
        coordinator?.clearAuthPopupHost(self)
    }
}

// MARK: - WeakScriptMessageHandler (avoids retain cycle)

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (NSObject & WKScriptMessageHandler)?
    init(target: NSObject & WKScriptMessageHandler) { self.target = target }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}
