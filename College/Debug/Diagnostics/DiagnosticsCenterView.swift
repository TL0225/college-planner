// DiagnosticsCenterView.swift
// Feature: Debug
// Purpose: Unified Diagnostics Center host with a single navigation system and export.

import SwiftUI
import AppKit

enum DiagnosticsCenterTab: String, CaseIterable, Identifiable {
    case overview
    case health
    case crashes
    case performance
    case assistant
    case catalog
    case connectivity
    case system
    case logs
    #if DEBUG
    case developer
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .health: return "Health"
        case .crashes: return "Crashes"
        case .performance: return "Performance"
        case .assistant: return "Assistant"
        case .catalog: return "Catalog"
        case .connectivity: return "Connectivity"
        case .system: return "System Health"
        case .logs: return "Logs"
        #if DEBUG
        case .developer: return "Developer"
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "heart.text.square"
        case .health: return "checkmark.shield"
        case .crashes: return "exclamationmark.triangle"
        case .performance: return "gauge"
        case .assistant: return "brain"
        case .catalog: return "books.vertical"
        case .connectivity: return "network"
        case .system: return "cpu"
        case .logs: return "doc.text"
        #if DEBUG
        case .developer: return "hammer"
        #endif
        }
    }
}

struct DiagnosticsCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    @State private var selectedTab: DiagnosticsCenterTab = .overview
    @State private var healthReport: DiagnosticsHealthReport?
    @State private var memoryEstimates: [SubsystemMemoryEstimate] = []
    @State private var metricKitEvents: [DiagnosticsEventRecord] = []
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var performanceMonitor = PerformanceMonitor()
    @State private var runtimeDiagnostics = SettingsRuntimeDiagnosticsModel()
    @State private var isPerformanceSampling = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
        }
        .frame(minWidth: 740, idealWidth: 920, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refreshOverview() }
        .onChange(of: selectedTab) { _, tab in
            handleTabAppear(tab)
        }
        .onAppear {
            handleTabAppear(selectedTab)
        }
        .onDisappear {
            stopActiveSampling()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostics")
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                Text("Local, privacy-safe diagnostics you can review and export.")
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            Spacer()
            Menu {
                ForEach(DiagnosticsExportLevel.allCases) { level in
                    Button {
                        Task { await export(level: level) }
                    } label: {
                        Text(level.title)
                        Text(level.subtitle)
                    }
                }
            } label: {
                Label(isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.up")
            }
            .menuIndicator(.visible)
            .fixedSize()
            .disabled(isExporting)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(DesignSystem.Spacing.md)
    }

    // MARK: - Single navigation

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiagnosticsCenterTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .labelStyle(.titleAndIcon)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selectedTab == tab ? DesignSystem.Colors.primary.opacity(0.15) : Color.clear)
                            .foregroundStyle(selectedTab == tab ? DesignSystem.Colors.primary : DesignSystem.Colors.textMain)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .overview: overviewTab
        case .health: healthTab
        case .crashes: crashesTab
        case .performance: performanceTab
        case .assistant: assistantTab
        case .catalog: catalogTab
        case .connectivity: connectivityTab
        case .system: systemHealthTab
        case .logs: logsTab
        #if DEBUG
        case .developer: developerTab
        #endif
        }
    }

    // MARK: - Tabs

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let exportMessage {
                    Text(exportMessage)
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(DesignSystem.Colors.info)
                }
                if let healthReport {
                    healthCard(healthReport)
                }
                memoryBreakdownSection
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    private var healthTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let healthReport {
                    healthCard(healthReport)
                    ForEach(healthReport.checks) { check in
                        HStack {
                            Text(check.title)
                            Spacer()
                            Text(check.status.rawValue)
                                .foregroundStyle(check.status == .good ? DesignSystem.Colors.success : DesignSystem.Colors.warning)
                        }
                        Text(check.detail)
                            .font(DesignSystem.Fonts.caption1())
                            .foregroundStyle(DesignSystem.Colors.textLight)
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    private var crashesTab: some View {
        ScrollView {
            CrashReportsListView()
                .padding(DesignSystem.Spacing.lg)
        }
    }

    private var performanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isPerformanceSampling {
                    Text("CPU \(String(format: "%.1f", performanceMonitor.cpuPercent))% · Memory \(String(format: "%.1f", performanceMonitor.memoryMB)) MB")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                }
                memoryBreakdownSection
                if let latest = LaunchHistoryStore.latest() {
                    Text("Last launch — \(latest.launchDurationMs) ms · \(String(format: "%.1f", latest.footprintAtLaunchMB)) MB")
                        .font(DesignSystem.Fonts.caption1())
                }
                Text(AppleSiliconPlatform.report.deviceName)
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    private var assistantTab: some View {
        ScrollView {
            SettingsRuntimeDiagnosticsView(model: runtimeDiagnostics)
                .padding(DesignSystem.Spacing.lg)
        }
    }

    private var catalogTab: some View {
        ScrollView {
            CatalogDataDiagnosticsView(
                schoolID: CatalogDataDiagnosticsView.resolvedSchoolID(from: container.persistence)
            )
            .padding(DesignSystem.Spacing.lg)
        }
    }

    private var connectivityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                connectivityFileRow(title: "Google Calendar debug log", url: GoogleDebugLog.fileURL())
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    private var systemHealthTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Reported by macOS")
                if metricKitEvents.isEmpty {
                    Text("No system reports yet. macOS shares battery, thermal, CPU, and unresponsiveness reports here when they're available.")
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(metricKitEvents) { event in
                        systemEventRow(event)
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }

    private var logsTab: some View {
        AppLogsView(
            initialLevel: .warning,
            showTechnicalDetailsByDefault: false,
            showsTitleChrome: false
        )
    }

    #if DEBUG
    private var developerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("Enable console capture") { AppLogger.shared.redirectConsoleOutput() }
                Button("Reveal diagnostics folder") {
                    if let url = DiagnosticsArtifacts.diagnosticsDirectory() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Button("Reveal unlock debug log") { UnlockDebugLog.revealInFinder() }
                AppLogsView(showTechnicalDetailsByDefault: true, showsTitleChrome: false)
                    .frame(minHeight: 320)
            }
            .padding(DesignSystem.Spacing.lg)
        }
    }
    #endif

    // MARK: - Health card

    private func healthCard(_ report: DiagnosticsHealthReport) -> some View {
        let isGood = report.band == .good
        let accent: Color = report.band == .critical ? .red : (isGood ? .green : .orange)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isGood ? "All clear" : "Needs attention")
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                    Text(report.headline)
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
            }

            if !report.warnings.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(report.warnings.enumerated()), id: \.element.id) { index, warning in
                        if index > 0 { Divider().opacity(0.4) }
                        warningRow(warning, accent: accent)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("Last updated \(DiagnosticsPlainLanguage.smartTimestamp(report.generatedAt))")
                .font(DesignSystem.Fonts.caption2())
                .foregroundStyle(DesignSystem.Colors.textLight)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .leading) {
                accent.opacity(0.10)
                Rectangle().fill(accent).frame(width: 4)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func warningRow(_ warning: DiagnosticsHealthWarning, accent: Color) -> some View {
        Button {
            handleWarningAction(warning.action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: warningIcon(warning.action))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 16)
                Text(warning.message)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let label = warningActionLabel(warning.action) {
                    Text(label)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func warningIcon(_ action: DiagnosticsHealthAction) -> String {
        switch action {
        case .viewCrashes, .viewSessions: return "exclamationmark.triangle.fill"
        case .viewCatalog: return "books.vertical.fill"
        case .loadAssistantModel: return "brain"
        case .viewPerformance: return "memorychip"
        case .none: return "info.circle"
        }
    }

    private func warningActionLabel(_ action: DiagnosticsHealthAction) -> String? {
        switch action {
        case .viewCrashes: return "View crashes"
        case .viewSessions: return "View sessions"
        case .viewCatalog: return "Open catalog"
        case .loadAssistantModel: return "Open Assistant"
        case .viewPerformance: return "View memory"
        case .none: return nil
        }
    }

    private func handleWarningAction(_ action: DiagnosticsHealthAction) {
        switch action {
        case .viewCrashes, .viewSessions: selectedTab = .crashes
        case .viewCatalog: selectedTab = .catalog
        case .loadAssistantModel: selectedTab = .assistant
        case .viewPerformance: selectedTab = .performance
        case .none: break
        }
    }

    // MARK: - Memory breakdown

    private var memoryBreakdownSection: some View {
        let maxMB = max(memoryEstimates.map(\.estimatedMB).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Memory breakdown")
            VStack(spacing: 14) {
                ForEach(memoryEstimates) { item in
                    memoryRow(item, maxMB: maxMB)
                }
            }
        }
    }

    private func memoryRow(_ item: SubsystemMemoryEstimate, maxMB: Double) -> some View {
        let highlighted = item.badge != nil
        let barColor: Color = highlighted ? .orange : DesignSystem.Colors.primary
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                if let badge = item.badge {
                    Text(badge)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(String(format: "%.1f MB", item.estimatedMB))
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 6)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(item.estimatedMB > 0 ? 4 : 0, geo.size.width * CGFloat(item.estimatedMB / maxMB)), height: 6)
                }
            }
            .frame(height: 6)
            Text(item.detail)
                .font(DesignSystem.Fonts.caption2())
                .foregroundStyle(DesignSystem.Colors.textLight)
            if let note = item.note {
                Text(note)
                    .font(DesignSystem.Fonts.caption2())
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - System events

    private func systemEventRow(_ event: DiagnosticsEventRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(DiagnosticsPlainLanguage.severityLabel(event.severity))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(DiagnosticsPlainLanguage.severityColor(event.severity))
                Spacer()
                Text(DiagnosticsPlainLanguage.smartTimestamp(event.timestamp))
                    .font(DesignSystem.Fonts.caption2())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            Text(DiagnosticsPlainLanguage.summary(for: event))
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Shared components

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(DesignSystem.Colors.textLight)
    }

    private func connectivityFileRow(title: String, url: URL?) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                if let url {
                    Text(url.path)
                        .font(DesignSystem.Fonts.caption2().monospaced())
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            if let url, FileManager.default.fileExists(atPath: url.path) {
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Open") { NSWorkspace.shared.open(url) }
            } else {
                Text("Not available")
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        }
    }

    // MARK: - Actions

    private func refreshOverview() async {
        healthReport = await DiagnosticsHealthReportBuilder.generate()
        memoryEstimates = SubsystemMemoryEstimator.estimates()
    }

    private func handleTabAppear(_ tab: DiagnosticsCenterTab) {
        stopActiveSampling()
        switch tab {
        case .overview, .health:
            Task { await refreshOverview() }
        case .performance:
            isPerformanceSampling = true
            performanceMonitor.start()
        case .assistant:
            runtimeDiagnostics.startRefreshing(collegePersistence: container.persistence)
        case .system:
            Task {
                metricKitEvents = await DiagnosticsEventStore.shared.fetchRecent(
                    limit: 100,
                    subsystem: .metrickit
                )
            }
        default:
            break
        }
    }

    private func stopActiveSampling() {
        performanceMonitor.stop()
        isPerformanceSampling = false
        runtimeDiagnostics.stopRefreshing()
    }

    private func export(level: DiagnosticsExportLevel) async {
        isExporting = true
        defer { isExporting = false }
        do {
            if let result = try await DiagnosticsBundleExporter.export(level: level) {
                exportMessage = "Exported \(result.includedFiles) files to \(result.outputURL.lastPathComponent)."
                if let note = result.truncationNote { exportMessage? += " \(note)" }
            }
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}
