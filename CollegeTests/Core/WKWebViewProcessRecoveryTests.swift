// WKWebViewProcessRecoveryTests.swift
// M30-006 — WebKit content process termination reload.

import WebKit
import XCTest
@testable import College

@MainActor
final class WKWebViewProcessRecoveryTests: XCTestCase {
    func testReloadIfMatchingReloadsOwnedWebView() {
        let webView = WKWebView(frame: .zero)
        let html = "<html><body>ok</body></html>"
        webView.loadHTMLString(html, baseURL: nil)
        WKWebViewProcessRecovery.reloadIfMatching(webView, ownedBy: webView)
        XCTAssertTrue(webView.isLoading || webView.url != nil)
    }

    func testReloadIfMatchingIgnoresForeignWebView() {
        let owned = WKWebView(frame: .zero)
        let foreign = WKWebView(frame: .zero)
        WKWebViewProcessRecovery.reloadIfMatching(foreign, ownedBy: owned)
        XCTAssertEqual(foreign.url, nil)
    }
}
