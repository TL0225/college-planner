// AdvisorMeetingPrepView.swift
// Feature: Profile
// Purpose: Profile module — AdvisorMeetingPrepView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

/// Generates an advisor meeting prep document showing degree audit, GPA, and course plan.
struct AdvisorMeetingPrepView: View {
    @Environment(AppContainer.self) private var container
    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) var dismiss
    @State private var htmlContent: String = ""
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advisor Meeting Prep")
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold, design: .serif))
                    Text("Share this summary with your academic advisor")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Export PDF") { exportPDF() }
                    .buttonStyle(.borderedProminent)
                    .disabled(htmlContent.isEmpty)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isGenerating {
                ProgressView("Generating report…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if htmlContent.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HTMLWebView(html: htmlContent)
            }
        }
        .frame(width: 780, height: 900)
        .task(id: collegePersistence.profileRevision) {
            await generateHTML()
        }
    }

    @MainActor
    private func generateHTML() async {
        isGenerating = true
        defer { isGenerating = false }

        let report = AdvisorMeetingPrepReport.build(
            collegePersistence: collegePersistence,
            metricsStore: container.academicMetricsStore
        )
        htmlContent = AdvisorMeetingPrepHTMLRenderer.render(report)
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "AcademicSummary.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 780, height: 1100))
        webView.loadHTMLString(htmlContent, baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 595, height: 842)
            webView.createPDF(configuration: config) { result in
                if case .success(let data) = result {
                    try? data.write(to: url)
                }
            }
        }
    }
}

/// A simple NSViewRepresentable wrapping WKWebView for HTML preview.
struct HTMLWebView: NSViewRepresentable {
    let html: String
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
