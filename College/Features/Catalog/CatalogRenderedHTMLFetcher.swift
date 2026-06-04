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
    func fetchRenderedHTML(from url: URL) async throws -> String {
        try AssistantWebFetchPolicy.ensureCatalogRenderedFetchAllowed(for: url)

        if webView == nil {
            installWebView()
        }
        guard let wv = webView else {
            throw FetchError.navigationFailed
        }

        maxBytes = 2_500_000
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
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self else { return }
            self.failNavigation()
        }
        var req = URLRequest(url: url, timeoutInterval: 40)
        req.setValue("CollegeApp/1.0 (macOS; catalog-sync)", forHTTPHeaderField: "User-Agent")
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
        extractHTML(webView: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishFailure(error)
    }
}
