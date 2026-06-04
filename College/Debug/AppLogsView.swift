// AppLogsView.swift
// Feature: Debug
// Purpose: Debug module — AppLogsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import Combine

struct AppLogsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [AppLogger.Entry] = []
    @State private var isLoading: Bool = false
    @State private var query: String = ""
    @State private var selectedCategory: AppLogger.Category? = nil
    @State private var selectedLevel: AppLogger.Level? = nil

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            filters

            Divider()

            content
        }
        .frame(minWidth: 840, minHeight: 620)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostics Logs")
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("Recent app logs (including performance timings).")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
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

            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.75))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 6)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var filters: some View {
        HStack(spacing: 14) {
            searchField
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Text("CATEGORY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)

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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)

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

            Button {
                Task { await refresh() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("Refresh")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color(hex: "2563eb"))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
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
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .padding(16)
                }
                ForEach(filtered) { entry in
                    LogRow(entry: entry)
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
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .padding(.leading, 10)

            TextField("Search message…", text: $query)
                .textFieldStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)

            Menu {
                Button("Clear search") { query = "" }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
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
                .foregroundColor(DesignSystem.Colors.textMain)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
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
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(entry.timestampISO8601)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .lineLimit(1)

                Text(entry.level.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(levelColor(entry.level))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelColor(entry.level).opacity(0.10))
                    .cornerRadius(6)

                Text(entry.category.rawValue)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(6)

                Spacer()

                Text(entry.thread)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }

            Text(entry.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .fixedSize(horizontal: false, vertical: true)

            if let md = entry.metadata, !md.isEmpty {
                Text(md.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • "))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let file = entry.file, let line = entry.line {
                Text("\(file):\(line) \(entry.function ?? "")")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
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
        .cornerRadius(12)
        .shadow(color: isHovering ? Color.accentColor.opacity(0.08) : .clear, radius: 8, x: 0, y: 2)
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

    private func levelColor(_ level: AppLogger.Level) -> Color {
        switch level {
        case .trace: return DesignSystem.Colors.textLight
        case .info: return DesignSystem.Colors.info
        case .warning: return DesignSystem.Colors.warning
        case .error: return DesignSystem.Colors.error
        case .fault: return DesignSystem.Colors.error
        }
    }
}

