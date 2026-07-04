// AssistantWebMemoryLibraryView.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantWebMemoryLibraryView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Browse and delete on-device web learnings used by the AI assistant.
struct AssistantWebMemoryLibraryView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [AssistantWebMemoryStore.EntryListItem] = []
    @State private var filterText: String = ""
    @State private var loadError: String?
    @State private var isLoading = true

    private var filteredEntries: [AssistantWebMemoryStore.EntryListItem] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.title.lowercased().contains(q)
                || $0.bodyPreview.lowercased().contains(q)
                || ($0.tags?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved web notes")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Text("These entries are stored only on this Mac and can appear in assistant context when relevant.")
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            TextField("Filter…", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Fonts.main(size: 13))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if let loadError {
                Text(loadError)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
                    .padding(.horizontal, 16)
            }

            List {
                ForEach(filteredEntries, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if row.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.info)
                            }
                            Text(row.title)
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textMain)
                            Spacer()
                            if !row.isIncludedInContext {
                                Text("Excluded")
                                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.warning)
                            }
                            Text(shortDate(row.createdAt))
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                        Text(row.bodyPreview)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .regular))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .lineLimit(4)
                        if let tags = row.tags, !tags.isEmpty {
                            Text("Tags: \(tags)")
                                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            Task { @MainActor in
                                await AssistantWebMemoryStore.shared.setEntryPinned(id: row.id, pinned: !row.isPinned)
                                await reload()
                            }
                        } label: {
                            Label(row.isPinned ? "Unpin" : "Pin", systemImage: row.isPinned ? "pin.slash" : "pin")
                        }
                        Button {
                            Task { @MainActor in
                                await AssistantWebMemoryStore.shared.setEntryIncludedInContext(id: row.id, included: !row.isIncludedInContext)
                                await reload()
                            }
                        } label: {
                            Label(
                                row.isIncludedInContext ? "Exclude from assistant context" : "Include in assistant context",
                                systemImage: row.isIncludedInContext ? "eye.slash" : "eye"
                            )
                        }
                        Button(role: .destructive) {
                            Task { @MainActor in await deleteEntry(row.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView().controlSize(.regular)
                } else if filteredEntries.isEmpty {
                    Text(entries.isEmpty ? "No saved notes yet." : "No matches.")
                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .task {
            await reload()
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    @MainActor
    private func reload() async {
        isLoading = true
        loadError = nil
        do {
            let rows = try await AssistantWebMemoryStore.shared.listRecentEntries(limit: 300)
            await MainActor.run {
                entries = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func deleteEntry(_ id: String) async {
        do {
            try await AssistantWebMemoryStore.shared.deleteEntry(id: id)
            await MainActor.run {
                entries.removeAll { $0.id == id }
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
            }
        }
    }
}
