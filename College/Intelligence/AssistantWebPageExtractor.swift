import Foundation
import WebKit

enum AssistantWebPageExtractorError: LocalizedError {
    case notAllowed
    case navigationFailed
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            return "That URL is not allowed for fetching. Run a web search first or add the host under allowed fetch hosts in Settings."
        case .navigationFailed:
            return "The page could not be loaded."
        case .emptyContent:
            return "No readable text could be extracted from the page."
        }
    }
}

/// Loads a page in an off-screen `WKWebView` and returns `document.body.innerText` (capped).
@MainActor
final class AssistantWebPageExtractor: NSObject {

    static let shared = AssistantWebPageExtractor()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func fetchReadableText(from url: URL, maxCharacters: Int = 12_000) async throws -> String {
        guard AssistantWebFetchPolicy.isURLAllowedForFetch(url) else {
            throw AssistantWebPageExtractorError.notAllowed
        }

        if webView == nil {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 400), configuration: config)
            wv.navigationDelegate = self
            wv.isInspectable = false
            self.webView = wv
        }
        guard let wv = webView else {
            throw AssistantWebPageExtractorError.navigationFailed
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            if self.continuation != nil {
                cont.resume(throwing: AssistantWebPageExtractorError.navigationFailed)
                return
            }
            self.continuation = cont
            self.timeoutTask?.cancel()
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 28_000_000_000)
                guard let self else { return }
                await MainActor.run {
                    if let c = self.continuation {
                        self.continuation = nil
                        c.resume(throwing: AssistantWebPageExtractorError.navigationFailed)
                    }
                }
            }
            let req = URLRequest(url: url, timeoutInterval: 25)
            wv.load(req)
        }
    }

    private func finishSuccess(_ text: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: text)
        continuation = nil
    }

    private func finishFailure(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func extractInnerText(webView: WKWebView, maxCharacters: Int) {
        let js = """
        (function(){
          try {
            var t = document.body ? document.body.innerText : '';
            return t || '';
          } catch(e) { return ''; }
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                let raw = (result as? String) ?? ""
                let trimmed = self.sanitizeUntrustedPageText(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.finishFailure(AssistantWebPageExtractorError.emptyContent)
                } else {
                    self.finishSuccess(String(trimmed.prefix(maxCharacters)))
                }
            }
        }
    }

    /// Basic prompt-injection containment for untrusted web text.
    /// The prompt also isolates fetched text in explicit untrusted-content tags.
    private func sanitizeUntrustedPageText(_ raw: String) -> String {
        let blockedPhrases = [
            "ignore previous instructions",
            "disregard previous instructions",
            "you are chatgpt",
            "system prompt",
            "developer message",
            "tool call",
            "execute this instruction",
            "jailbreak"
        ]
        let lines = raw.components(separatedBy: .newlines).filter { line in
            let lower = line.lowercased()
            return !blockedPhrases.contains(where: { lower.contains($0) })
        }
        return lines.joined(separator: "\n")
    }
}

extension AssistantWebPageExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extractInnerText(webView: webView, maxCharacters: 12_000)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishFailure(error)
    }
}
