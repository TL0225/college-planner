// WKWebViewProcessRecovery.swift
// Feature: Core/Platform
// Purpose: Reload WKWebView after WebKit content process termination.

import WebKit

enum WKWebViewProcessRecovery {
    @MainActor
    static func reloadIfMatching(_ webView: WKWebView, ownedBy owner: WKWebView?) {
        guard webView === owner else { return }
        webView.reload()
    }
}
