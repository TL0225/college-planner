import SwiftUI
import AppKit

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
        .task {
            await refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostics Logs")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("Recent app logs (including performance timings).")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }

            Spacer()

            Button("Reveal in Finder") {
                Task {
                    if let url = await AppLogger.shared.logsDirectoryURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .buttonStyle(.bordered)

            Button("Export…") {
                Task {
                    if let url = await AppLogger.shared.logFileURL() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            .buttonStyle(.bordered)
            .help("Reveals the current log file; you can share it from Finder.")

            Button(role: .destructive) {
                Task {
                    await AppLogger.shared.clearLogs()
                    await refresh()
                }
            } label: {
                Text("Clear")
            }
            .buttonStyle(.bordered)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .background(DesignSystem.Colors.surface)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            TextField("Search message…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 380)

            Picker("Category", selection: Binding(
                get: { selectedCategory },
                set: { selectedCategory = $0 }
            )) {
                Text("All").tag(AppLogger.Category?.none)
                ForEach(AppLogger.Category.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(Optional(c))
                }
            }
            .frame(width: 220)

            Picker("Level", selection: Binding(
                get: { selectedLevel },
                set: { selectedLevel = $0 }
            )) {
                Text("All").tag(AppLogger.Level?.none)
                Text("trace").tag(Optional(AppLogger.Level.trace))
                Text("info").tag(Optional(AppLogger.Level.info))
                Text("warning").tag(Optional(AppLogger.Level.warning))
                Text("error").tag(Optional(AppLogger.Level.error))
                Text("fault").tag(Optional(AppLogger.Level.fault))
            }
            .frame(width: 160)

            Spacer()

            Button {
                Task { await refresh() }
            } label: {
                if isLoading {
                    ProgressView().scaleEffect(0.85)
                } else {
                    Text("Refresh")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(DesignSystem.Colors.bgMain)
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
        .background(DesignSystem.Colors.bgMain)
    }

    private func refresh() async {
        isLoading = true
        let recent = await AppLogger.shared.readRecentEntries()
        // Show newest first
        entries = recent.reversed()
        isLoading = false
    }
}

private struct LogRow: View {
    let entry: AppLogger.Entry

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
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
        .cornerRadius(12)
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

