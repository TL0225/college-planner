// AppLogsView.swift
// Feature: Debug
// Purpose: Debug module — AppLogsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import Combine

struct AppLogsView: View {
    @Environment(\.dismiss) private var dismiss

    private let initialCategory: AppLogger.Category?
    private let showTechnicalDetailsByDefault: Bool
    /// When false, the large title block and panel close button are hidden so the
    /// view can be embedded inside a host (e.g. the Diagnostics Center) without
    /// duplicating the title and close affordance.
    private let showsTitleChrome: Bool

    @State private var entries: [AppLogger.Entry] = []
    @State private var isLoading: Bool = false
    @State private var query: String = ""
    @State private var selectedCategory: AppLogger.Category?
    @State private var selectedLevel: AppLogger.Level?
    @State private var lastRefreshed: Date = Date()

    init(
        initialCategory: AppLogger.Category? = nil,
        initialLevel: AppLogger.Level? = nil,
        showTechnicalDetailsByDefault: Bool = false,
        showsTitleChrome: Bool = true
    ) {
        self.initialCategory = initialCategory
        self.showTechnicalDetailsByDefault = showTechnicalDetailsByDefault
        self.showsTitleChrome = showsTitleChrome
        _selectedCategory = State(initialValue: initialCategory)
        _selectedLevel = State(initialValue: initialLevel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            filters

            Divider()

            content
        }
        .frame(minWidth: 720, idealWidth: 840, minHeight: 540, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .appLoggerDidAppendEntry)
                .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        ) { _ in
            Task { await refreshIfIdle() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if showsTitleChrome {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics Logs")
                        .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                    Text("Recent app logs (including performance timings).")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
            }

            Spacer()

            toolbarButton("Reveal in Finder", systemImage: "folder") {
                Task {
                    if let url = await AppLogger.shared.logsDirectoryURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }

            toolbarButton("Export…", systemImage: "square.and.arrow.down") {
                Task {
                    if let url = await AppLogger.shared.logFileURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .help("Reveals the current log file; you can share it from Finder.")

            toolbarButton("Clear", systemImage: "trash") {
                Task {
                    await AppLogger.shared.clearLogs()
                    await refresh()
                }
            }

            if showsTitleChrome {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.75))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 6)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, showsTitleChrome ? DesignSystem.Spacing.md : 8)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var filters: some View {
        HStack(spacing: 14) {
            searchField
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Text("CATEGORY")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)

                Menu {
                    Button("All") { selectedCategory = nil }
                    Divider()
                    ForEach(AppLogger.Category.allCases, id: \.self) { c in
                        Button(c.rawValue) { selectedCategory = c }
                    }
                } label: {
                    dropdownLabel(selectedCategory?.rawValue ?? "All")
                }
            }

            HStack(spacing: 10) {
                Text("LEVEL")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)

                Menu {
                    Button("All") { selectedLevel = nil }
                    Divider()
                    Button("trace") { selectedLevel = .trace }
                    Button("info") { selectedLevel = .info }
                    Button("warning") { selectedLevel = .warning }
                    Button("error") { selectedLevel = .error }
                    Button("fault") { selectedLevel = .fault }
                } label: {
                    dropdownLabel(selectedLevel?.rawValue ?? "All")
                }
            }

            Spacer()

            Text("Updated \(DiagnosticsPlainLanguage.smartTimestamp(lastRefreshed))")
                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)

            Button {
                Task { await refresh() }
            } label: {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    }
                    Text("Refresh")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                }
            }
            .controlSize(.small)
            .disabled(isLoading)
            .help("Logs refresh automatically; use this to refresh now.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var content: some View {
        let filtered = entries.filter { entry in
            if let selectedCategory, entry.category != selectedCategory { return false }
            if let selectedLevel, entry.level != selectedLevel { return false }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let q = query.lowercased()
                if !entry.message.lowercased().contains(q),
                   !(entry.metadata?.description.lowercased().contains(q) ?? false) {
                    return false
                }
            }
            return true
        }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if filtered.isEmpty {
                    Text("No logs.")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .padding(DesignSystem.Spacing.lg)
                }
                ForEach(filtered) { entry in
                    LogRow(entry: entry, showTechnicalDetailsByDefault: showTechnicalDetailsByDefault)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func refresh() async {
        isLoading = true
        let recent = await AppLogger.shared.readRecentEntries()
        // Show newest first
        entries = recent.reversed()
        lastRefreshed = Date()
        isLoading = false
    }

    private func refreshIfIdle() async {
        guard !isLoading else { return }
        await refresh()
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .padding(.leading, 10)

            TextField("Search message…", text: $query)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)

            Menu {
                Button("Clear search") { query = "" }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.trailing, 4)
        }
        .frame(height: 34)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func dropdownLabel(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textLight)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LogRow: View {
    let entry: AppLogger.Entry
    let showTechnicalDetailsByDefault: Bool
    @State private var isHovering: Bool = false
    @State private var showTechnicalDetails: Bool

    init(entry: AppLogger.Entry, showTechnicalDetailsByDefault: Bool) {
        self.entry = entry
        self.showTechnicalDetailsByDefault = showTechnicalDetailsByDefault
        _showTechnicalDetails = State(initialValue: showTechnicalDetailsByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(DiagnosticsPlainLanguage.smartTimestamp(isoDate(entry.timestampISO8601)))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .lineLimit(1)

                Text(DiagnosticsPlainLanguage.levelLabel(entry.level))
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(DiagnosticsPlainLanguage.levelColor(entry.level))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DiagnosticsPlainLanguage.levelColor(entry.level).opacity(0.10))
                    .clipShape(.rect(cornerRadius: 6))

                Text(entry.category.rawValue)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.04))
                    .clipShape(.rect(cornerRadius: 6))

                Spacer()

                // Expansion affordance: a chevron that rotates when open and stays
                // dimmed until the row is hovered, so it doesn't form a noisy column.
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                    .rotationEffect(.degrees(showTechnicalDetails ? 90 : 0))
                    .opacity(showTechnicalDetails || isHovering ? 1 : 0)
                    .accessibilityLabel(showTechnicalDetails ? "Hide technical details" : "Show technical details")
            }

            Text(DiagnosticsPlainLanguage.summary(for: entry))
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)

            if showTechnicalDetails {
                Text(entry.message)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                if let md = entry.metadata, !md.isEmpty {
                    Text(md.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • "))
                        .font(DesignSystem.Fonts.main(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let file = entry.file, let line = entry.line {
                    Text("\(file):\(line) \(entry.function ?? "")")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.85))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DesignSystem.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovering
                        ? Color.accentColor.opacity(0.28)
                        : Color(nsColor: .separatorColor).opacity(0.55),
                    lineWidth: isHovering ? 1.5 : 1
                )
        )
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: isHovering ? Color.accentColor.opacity(0.08) : .clear, radius: 8, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.14)) {
                showTechnicalDetails.toggle()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }
        }
    }

    private func isoDate(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date()
    }
}

