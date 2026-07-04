// CrashReportsListView.swift
// Feature: Debug
// Purpose: List crash reports with reveal/open/copy actions.

import SwiftUI
import AppKit

struct CrashReportsListView: View {
    @State private var records: [UnifiedCrashRecord] = []
    @State private var isLoading = false
    @State private var lastExitWasClean = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionBanner
            if isLoading {
                ProgressView()
            } else if records.isEmpty {
                Text("No crash reports yet.")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            } else {
                ForEach(records) { record in
                    crashCard(record)
                }
            }
        }
        .task { await refresh() }
        .onAppear { refreshSessionState() }
    }

    private var sessionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: lastExitWasClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(lastExitWasClean ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
            Text(lastExitWasClean
                 ? "Previous session ended normally."
                 : "Previous session may have ended unexpectedly.")
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func crashCard(_ record: UnifiedCrashRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DiagnosticsPlainLanguage.relativeTimestamp(record.timestamp))
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                Spacer()
                if record.hasMetricKitEnrichment {
                    Text("MetricKit")
                        .font(DesignSystem.Fonts.caption2())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.info.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(record.summary)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
            if let metric = record.metricKitSummary {
                Text(metric)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            HStack(spacing: 10) {
                if let url = record.localReportURL ?? record.signalReportURL {
                    actionButton("Reveal", systemImage: "folder") { CrashReportStore.revealInFinder(url) }
                    actionButton("Open", systemImage: "doc") { CrashReportStore.open(url) }
                    actionButton("Copy path", systemImage: "doc.on.doc") { CrashReportStore.copyPathToPasteboard(url) }
                }
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(DesignSystem.Fonts.caption1())
        }
        .buttonStyle(.borderless)
    }

    private func refresh() async {
        isLoading = true
        records = await UnifiedCrashRecordBuilder.allRecords()
        isLoading = false
    }

    private func refreshSessionState() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "College.session.lastExitWasClean") == nil {
            lastExitWasClean = true
        } else {
            lastExitWasClean = defaults.bool(forKey: "College.session.lastExitWasClean")
        }
    }
}
