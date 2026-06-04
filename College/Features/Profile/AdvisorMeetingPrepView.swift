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
    @EnvironmentObject var collegePersistence: CollegePersistence
    @Environment(\.dismiss) var dismiss
    @State private var htmlContent: String = ""
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advisor Meeting Prep")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                    Text("Share this summary with your academic advisor")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Export PDF") { exportPDF() }
                    .buttonStyle(.borderedProminent)
                    .disabled(htmlContent.isEmpty)
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if isGenerating {
                ProgressView("Generating report…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if htmlContent.isEmpty {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HTMLWebView(html: htmlContent)
            }
        }
        .frame(width: 780, height: 900)
        .task { await generateHTML() }
    }

    @MainActor
    private func generateHTML() async {
        isGenerating = true
        defer { isGenerating = false }

        let profile = collegePersistence.profile
        let name = profile?.name ?? "Student"
        let major = collegePersistence.resolvedMajorNames().first ?? "Undeclared"
        let gpa = collegePersistence.primaryGPA()
        let creditsEarned = collegePersistence.primaryCreditsEarned()
        let storedRequired = collegePersistence.primaryCreditsRequired()
        let creditsRequired = storedRequired > 0 ? storedRequired : 120
        let graduation = collegePersistence.primaryExpectedGraduation() ?? "—"
        let sap = collegePersistence.sapStats()

        // Build semester rows HTML
        var semesterHTML = ""
        let sortedSemesters = collegePersistence.semesters.sorted { a, b in
            if a.year != b.year { return a.year < b.year }
            return a.seasonOrder < b.seasonOrder
        }
        for sem in sortedSemesters {
            let semName = sem.name.isEmpty ? "Semester" : sem.name
            semesterHTML += "<tr><td colspan='4' style='background:#f3f4f6;font-weight:600;padding:8px 12px;font-size:13px'>\(semName)</td></tr>"
            for c in sem.coursesArray {
                let statusColor = c.isCompleted ? "#16a34a" : "#6b7280"
                let gradeText = c.grade ?? "—"
                let gradeSuffix = gradeText != "—" ? " · \(gradeText)" : ""
                semesterHTML += "<tr><td style='padding:6px 12px'>\(c.code)</td><td style='padding:6px 12px'>\(c.name)</td><td style='padding:6px 12px;text-align:center'>\(c.credits)</td><td style='padding:6px 12px;color:\(statusColor);font-weight:500'>\(c.status)\(gradeSuffix)</td></tr>"
            }
        }

        let sapClass = sap.rate < 0.67 ? "warn" : ""
        let sapBadge = sap.rate < 0.67 ? " ⚠️" : ""
        let gpaDisplay = gpa > 0 ? String(format: "%.2f", gpa) : "—"
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)

        let html = """
        <!DOCTYPE html><html><head><meta charset='UTF-8'>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111;margin:0;padding:32px;background:#fff}
        h1{font-size:24px;font-weight:700;margin:0 0 4px}
        .subtitle{color:#6b7280;font-size:14px;margin:0 0 24px}
        .stats{display:flex;gap:16px;margin-bottom:24px}
        .stat{background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;padding:16px 20px;flex:1}
        .stat-label{font-size:11px;color:#9ca3af;text-transform:uppercase;letter-spacing:.5px}
        .stat-value{font-size:24px;font-weight:700;color:#111;margin-top:4px}
        h2{font-size:16px;font-weight:600;margin:24px 0 12px;color:#374151}
        table{width:100%;border-collapse:collapse;font-size:13px}
        th{background:#f3f4f6;padding:8px 12px;text-align:left;font-weight:600;color:#374151;font-size:12px}
        tr:nth-child(even) td{background:#fafafa}
        .warn{color:#d97706;font-size:11px}
        </style></head><body>
        <h1>\(name)</h1>
        <p class='subtitle'>Academic Summary · Generated \(dateStr)</p>
        <div class='stats'>
          <div class='stat'><div class='stat-label'>GPA</div><div class='stat-value'>\(gpaDisplay)</div></div>
          <div class='stat'><div class='stat-label'>Credits</div><div class='stat-value'>\(creditsEarned)/\(creditsRequired)</div></div>
          <div class='stat'><div class='stat-label'>Major</div><div class='stat-value' style='font-size:14px'>\(major)</div></div>
          <div class='stat'><div class='stat-label'>Grad Target</div><div class='stat-value' style='font-size:16px'>\(graduation)</div></div>
          <div class='stat'><div class='stat-label'>SAP Rate</div><div class='stat-value \(sapClass)'>\(String(format: "%.0f%%", sap.rate * 100))\(sapBadge)</div></div>
        </div>
        <h2>Course Plan</h2>
        <table><thead><tr><th>Code</th><th>Course</th><th>Cr</th><th>Status</th></tr></thead><tbody>
        \(semesterHTML)
        </tbody></table>
        </body></html>
        """
        htmlContent = html
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
            config.rect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
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
