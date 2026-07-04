// CareerApplyCoordinator.swift
// Feature: Career / Apply
// Purpose: WKWebView owner for apply sessions (modeled on LMSWebCoordinator).

import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class CareerApplyCoordinator: NSObject, ObservableObject {
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var verificationReport: CareerApplyVerificationReport = .empty
    @Published var manualOnlyBanner: String?
    @Published var bridgeReady = false
    @Published var pageLoaded = false
    @Published var offerSavePassword: WebPortalCredentialOffer?

    private var webView: WKWebView?
    private var session: CareerApplySession
    private let adapter: any CareerApplyPlatformAdapter
    private var pingTask: Task<Void, Never>?

    init(session: CareerApplySession) {
        self.session = session
        self.adapter = CareerApplyAdapterRegistry.adapter(for: session.platform)
        super.init()
    }

    var view: WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let controller = WKUserContentController()
        adapter.userScripts().forEach { controller.addUserScript($0) }
        controller.add(CareerApplyScriptMessageHandler(coordinator: self), name: "careerApply")
        config.userContentController = controller
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        webView = wv
        scheduleBridgePing()
        return wv
    }

    func loadApplyURL() {
        pageLoaded = false
        bridgeReady = false
        let url = session.postingURL
        if url.isFileURL {
            if let html = try? String(contentsOf: url, encoding: .utf8) {
                view.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            } else {
                view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        } else {
            view.load(URLRequest(url: url))
        }
    }

    func runAutofill() {
        guard var payload = session.payload else { return }
        payload = CareerATSFieldNormalizer.normalizePayload(payload)
        session.payload = payload
        CareerApplySessionStore.shared.update(session)

        let tier = CareerApplyTierRegistry.tier(for: session.platform)
        guard let payloadData = try? JSONEncoder().encode(payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }
        let escaped = payloadJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script: String
        if tier.allowsAutofillWrites {
            let fn = platformAutofillFunction(for: session.platform)
            script = "(\(fn))('\(escaped)');"
        } else {
            script = "window.collegeCareerApply && window.collegeCareerApply.inventory();"
        }
        view.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.manualOnlyBanner = error.localizedDescription
                self.session.status = .manualOnly
                return
            }
            self.attachResumeIfNeeded(from: payload)
        }
    }

    private func attachResumeIfNeeded(from payload: CareerApplicationAutofillPayload) {
        guard let fileURL = payload.documents.resumeFileURL,
              let data = try? Data(contentsOf: fileURL)
        else { return }
        let base64 = data.base64EncodedString()
        let escapedName = payload.documents.resumeFileName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let fn = platformAttachResumeFunction(for: session.platform)
        let script = "(\(fn))('\(escapedName)', '\(base64)', 'application/pdf');"
        view.evaluateJavaScript(script, completionHandler: nil)
    }

    private func platformAttachResumeFunction(for platform: JobBoardPlatform) -> String {
        switch platform {
        case .greenhouse: return "window.collegeCareerApplyGreenhouse.attachResume"
        case .lever: return "window.collegeCareerApplyLever.attachResume"
        case .workday: return "window.collegeCareerApplyWorkday.attachResume"
        case .icims: return "window.collegeCareerApplyICIMS.attachResume"
        default: return "window.collegeCareerApply.attachResume"
        }
    }

    func tearDown() {
        pingTask?.cancel()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "careerApply")
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
    }

    func presentFindNavigator() {
        NSApp.sendAction(Selector(("find:")), to: nil, from: nil)
    }

    func find(_ text: String, forward: Bool) {
        guard let webView else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        webView.find(trimmed, configuration: config) { _ in }
    }

    fileprivate func handleMessage(_ body: Any) {
        guard let dict = body as? [String: Any] else { return }
        if dict["type"] as? String == "bridgePing" {
            bridgeReady = true
            return
        }
        if dict["type"] as? String == "loginFormDetected" {
            Task { @MainActor in
                await injectSavedCredentialsIfAvailable()
            }
            return
        }
        if dict["type"] as? String == "loginCredentials" {
            guard
                let username = dict["username"] as? String,
                let host = dict["host"] as? String,
                !username.isEmpty
            else { return }
            let saveEnabled = UserDefaults.standard.object(forKey: LMSStorageKeys.savePassword) as? Bool ?? true
            guard saveEnabled else { return }
            offerSavePassword = WebPortalCredentialOffer(username: username, host: host)
            return
        }
        if let report = adapter.handleMessage(dict, session: &session) {
            verificationReport = report
            CareerApplySessionStore.shared.update(session)
        }
    }

    func dismissSavePasswordOffer() {
        offerSavePassword = nil
    }

    func replaceSession(_ updated: CareerApplySession) {
        session = updated
    }

    private func injectSavedCredentialsIfAvailable() async {
        guard let host = view.url?.host else { return }
        WebPortalKeychainService.shared.migrateFromLMSIfNeeded(host: host)
        guard let creds = WebPortalKeychainService.shared.load(host: host) else { return }
        let js = Self.javascriptFillCredentials(username: creds.username, password: creds.password)
        _ = try? await view.evaluateJavaScript(js)
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
            fillAndDispatch(userInput, \(quotedJSString(username)));
            fillAndDispatch(pwInput, \(quotedJSString(password)));
        })();
        """
    }

    private static func quotedJSString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }

    private func scheduleBridgePing() {
        pingTask?.cancel()
        pingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CareerApplyFillStabilizer.bridgePingTimeoutSeconds * 1_000_000_000))
            if !bridgeReady {
                manualOnlyBanner = "This employer site blocks in-app autofill — use manual fill."
                session.status = .manualOnly
                CareerApplySessionStore.shared.update(session)
            }
        }
    }

    private func platformAutofillFunction(for platform: JobBoardPlatform) -> String {
        switch platform {
        case .greenhouse: return "window.collegeCareerApplyGreenhouse && window.collegeCareerApplyGreenhouse.autofill"
        case .lever: return "window.collegeCareerApplyLever && window.collegeCareerApplyLever.autofill"
        case .workday: return "window.collegeCareerApplyWorkday && window.collegeCareerApplyWorkday.autofill"
        case .icims: return "window.collegeCareerApplyICIMS && window.collegeCareerApplyICIMS.autofill"
        default: return "window.collegeCareerApply && window.collegeCareerApply.inventory"
        }
    }
}

extension CareerApplyCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        currentURL = webView.url
        pageLoaded = true
        Task { @MainActor in
            await injectSavedCredentialsIfAvailable()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        pageLoaded = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        pageLoaded = true
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            WKWebViewProcessRecovery.reloadIfMatching(webView, ownedBy: self?.webView)
        }
    }
}

extension CareerApplyCoordinator: WKUIDelegate {
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

private final class CareerApplyScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var coordinator: CareerApplyCoordinator?

    init(coordinator: CareerApplyCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            coordinator?.handleMessage(message.body)
        }
    }
}

struct WebPortalCredentialOffer: Equatable {
    var username: String
    var host: String
}
