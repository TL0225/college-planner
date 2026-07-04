// CatalogRenderedHTMLFetcher.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogRenderedHTMLFetcher.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import WebKit

/// Headless ``WKWebView`` fetch that returns **serialized HTML** for SwiftSoup (unlike ``AssistantWebPageExtractor``, which returns inner text for RAG).
///
/// Used only as a narrow fallback when ``ModernCampusEngine`` detects WAF / client-side challenge pages from ``URLSession``.
/// All loads run on the main actor; ``ModernCampusEngine`` caps concurrent fallbacks with a dedicated semaphore.
@MainActor
final class CatalogRenderedHTMLFetcher: NSObject, WKNavigationDelegate {
    static let shared = CatalogRenderedHTMLFetcher()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var pendingFetches: [(url: URL, continuation: CheckedContinuation<String, Error>)] = []
    private var timeoutTask: Task<Void, Never>?
    private var maxBytes: Int = 2_500_000
    private var settleDelayNanoseconds: UInt64 = 0
    private var minimumMatchingAnchors: Int = 0
    private var anchorSelector: String = "a[href*='programs']"
    private var postLoadHashRoute: String?
    private var postLoadJavaScript: String?
    private var anchorPollTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    enum FetchError: LocalizedError {
        case notAllowed
        case navigationFailed
        case emptyHTML

        var errorDescription: String? {
            switch self {
            case .notAllowed:
                return "Catalog host is not registered for rendered HTML fallback."
            case .navigationFailed:
                return "Rendered catalog page could not be loaded."
            case .emptyHTML:
                return "Rendered catalog page produced no HTML."
            }
        }
    }

    /// Loads `url` and returns `document.documentElement.outerHTML` (byte-capped).
    func fetchRenderedHTML(
        from url: URL,
        settleDelayNanoseconds: UInt64 = 0,
        minimumMatchingAnchors: Int = 0,
        anchorSelector: String = "a[href*='programs']",
        postLoadHashRoute: String? = nil,
        postLoadJavaScript: String? = nil
    ) async throws -> String {
        try AssistantWebFetchPolicy.ensureCatalogRenderedFetchAllowed(for: url)

        if webView == nil {
            installWebView()
        }
        guard let wv = webView else {
            throw FetchError.navigationFailed
        }

        maxBytes = 2_500_000
        self.settleDelayNanoseconds = settleDelayNanoseconds
        self.minimumMatchingAnchors = minimumMatchingAnchors
        self.anchorSelector = anchorSelector
        self.postLoadHashRoute = postLoadHashRoute
        self.postLoadJavaScript = postLoadJavaScript
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            if self.continuation != nil {
                self.pendingFetches.append((url, cont))
                return
            }
            self.beginFetch(url: url, webView: wv, continuation: cont)
        }
    }

    /// Drops the headless web view and cancels in-flight fetches (Phase 5 P0 — memory pressure).
    func releaseWebViewForMemoryPressure() {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: FetchError.navigationFailed)
        continuation = nil
        let queued = pendingFetches
        pendingFetches.removeAll()
        for pending in queued {
            pending.continuation.resume(throwing: FetchError.navigationFailed)
        }
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
    }

    private func installWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), configuration: config)
        wv.navigationDelegate = self
        wv.isInspectable = false
        wv.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView = wv
    }

    private func beginFetch(
        url: URL,
        webView: WKWebView,
        continuation: CheckedContinuation<String, Error>
    ) {
        self.continuation = continuation
        self.timeoutTask?.cancel()
        self.timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard let self else { return }
            self.failNavigation()
        }
        var req = URLRequest(url: url, timeoutInterval: 40)
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        webView.load(req)
    }

    private func drainPendingFetchQueue() {
        guard continuation == nil, !pendingFetches.isEmpty else { return }
        guard let wv = webView else { return }
        let next = pendingFetches.removeFirst()
        beginFetch(url: next.url, webView: wv, continuation: next.continuation)
    }

    private func failNavigation() {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: FetchError.navigationFailed)
        continuation = nil
        drainPendingFetchQueue()
    }

    private func finishSuccess(_ html: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: html)
        continuation = nil
        drainPendingFetchQueue()
    }

    private func finishFailure(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
        drainPendingFetchQueue()
    }

    private func extractHTML(webView: WKWebView) {
        let limit = maxBytes
        let js = """
        (function(){
          try {
            var root = document.documentElement;
            if (!root) return '';
            var s = root.outerHTML || '';
            return s;
          } catch(e) { return ''; }
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let raw = (result as? String) ?? ""
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.finishFailure(FetchError.emptyHTML)
                } else {
                    self.finishSuccess(String(trimmed.prefix(limit)))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        anchorPollTask?.cancel()
        let delay = settleDelayNanoseconds
        let minAnchors = minimumMatchingAnchors
        let selector = anchorSelector
        let hashRoute = postLoadHashRoute
        let preloadScript = postLoadJavaScript
        postLoadHashRoute = nil
        postLoadJavaScript = nil
        anchorPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let hashRoute, !hashRoute.isEmpty {
                let escaped = hashRoute.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                await self.evaluateJavaScript(
                    webView: webView,
                    script: "window.location.hash='\(escaped)'; true;"
                )
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
            if let preloadScript, !preloadScript.isEmpty {
                await self.evaluateAsyncJavaScript(webView: webView, script: preloadScript)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            await self.waitForAnchorsOrSettle(
                webView: webView,
                minimumMatchingAnchors: minAnchors,
                anchorSelector: selector,
                settleDelayNanoseconds: delay
            )
        }
    }

    private func waitForAnchorsOrSettle(
        webView: WKWebView,
        minimumMatchingAnchors: Int,
        anchorSelector: String,
        settleDelayNanoseconds: UInt64
    ) async {
        if minimumMatchingAnchors > 0 {
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if Task.isCancelled { return }
                let count = await matchingAnchorCount(webView: webView, selector: anchorSelector)
                if count >= minimumMatchingAnchors {
                    extractHTML(webView: webView)
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        if settleDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: settleDelayNanoseconds)
        }
        extractHTML(webView: webView)
    }

    private func evaluateAsyncJavaScript(webView: WKWebView, script: String) async {
        if #available(macOS 11.0, *) {
            _ = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
            return
        }
        await evaluateJavaScript(webView: webView, script: script)
    }

    private func evaluateJavaScript(webView: WKWebView, script: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(script) { _, _ in
                continuation.resume()
            }
        }
    }

    private func matchingAnchorCount(webView: WKWebView, selector: String) async -> Int {
        let escaped = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = "document.querySelectorAll('\(escaped)').length"
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                continuation.resume(returning: (result as? Int) ?? (result as? Double).map { Int($0) } ?? 0)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isBenignNavigationCancellation(error) { return }
        finishFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if isBenignNavigationCancellation(error) { return }
        finishFailure(error)
    }

    private func isBenignNavigationCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
