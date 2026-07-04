// CareerApplyWebHostView.swift
// Feature: Career / Apply
// Purpose: SwiftUI wrapper for apply WKWebView.

import SwiftUI
import WebKit

struct CareerApplyWebHostView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
