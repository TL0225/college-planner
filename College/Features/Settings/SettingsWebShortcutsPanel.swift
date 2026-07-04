// SettingsWebShortcutsPanel.swift
// Feature: Settings
// Purpose: Settings module — SettingsWebShortcutsPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

/// Identifies the destination collection for a shortcut: either the top-level
/// ungrouped list or a specific named group.
enum WebShortcutGroupChoice: Hashable {
    case ungrouped
    case group(UUID)
}

/// Curated SF Symbols offered as a sidebar icon override for shortcuts that lack a usable favicon.
enum ShortcutIconCatalog {
    static let symbols: [String] = [
        "globe", "link", "book.closed", "graduationcap", "building.columns",
        "calendar", "envelope", "doc.text", "video", "play.rectangle",
        "music.note", "cart", "star", "bell", "folder",
        "tray.full", "newspaper", "chart.bar", "creditcard", "map",
    ]
}

struct SettingsWebShortcutsPanel: View {
    @State private var shortcuts: [WebShortcut] = WebShortcutStore.loadAll()
    @State private var groups: [WebShortcutGroup] = WebShortcutStore.loadGroups()
    @State private var draftTitle: String = ""
    @State private var draftURL: String = ""
    @State private var draftGroup: WebShortcutGroupChoice = .ungrouped
    @State private var draftGroupName: String = ""
    @State private var errorMessage: String?
    @State private var groupErrorMessage: String?

    private var isAtCapacity: Bool {
        switch draftGroup {
        case .ungrouped:
            return shortcuts.count >= WebShortcutStore.maxShortcuts
        case .group(let id):
            guard let group = groups.first(where: { $0.id == id }) else { return false }
            return group.shortcuts.count >= WebShortcutStore.maxShortcutsPerGroup
        }
    }

    private var groupChoices: [WebShortcutGroupChoice] {
        [.ungrouped] + groups.map { .group($0.id) }
    }

    private func label(for choice: WebShortcutGroupChoice) -> String {
        switch choice {
        case .ungrouped:
            return String(localized: "settings.shortcuts.no_group", defaultValue: "No group")
        case .group(let id):
            return groups.first(where: { $0.id == id })?.name
                ?? String(localized: "settings.shortcuts.group", defaultValue: "Group")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            newShortcutCard
            newGroupCard
            shortcutsCard
            ForEach(groups) { group in
                groupCard(for: group)
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .webShortcutsDidChange)) { _ in
            reload()
        }
    }

    // MARK: - New shortcut card

    private var newShortcutCard: some View {
        SettingsCard(
            title: String(localized: "settings.shortcuts.new", defaultValue: "New shortcut"),
            icon: "plus.circle.fill",
            iconColor: DesignSystem.Colors.success
        ) {
            STextFieldRow(
                label: String(localized: "settings.shortcuts.name", defaultValue: "Name"),
                placeholder: String(localized: "settings.shortcuts.name.placeholder", defaultValue: "e.g. YouTube"),
                text: $draftTitle
            )

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            STextFieldRow(
                label: String(localized: "settings.shortcuts.address", defaultValue: "Web address"),
                placeholder: "https://…",
                text: $draftURL
            )

            if !groups.isEmpty {
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SMenuRow(
                    label: String(localized: "settings.shortcuts.group_label", defaultValue: "Group"),
                    currentDisplay: label(for: draftGroup),
                    options: groupChoices,
                    optionLabel: { label(for: $0) },
                    onSelect: { draftGroup = $0 }
                )
            }

            if let errorMessage {
                SettingsStatusRow(
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: DesignSystem.Colors.error
                )
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: isAtCapacity
                    ? String(
                        format: String(localized: "settings.shortcuts.limit", defaultValue: "Limit of %d shortcuts reached"),
                        capacityLimit
                    )
                    : appearHelpText,
                actionLabel: String(localized: "settings.shortcuts.add", defaultValue: "Add"),
                isDisabled: isAtCapacity
            ) {
                addShortcut()
            }
        }
    }

    private var capacityLimit: Int {
        switch draftGroup {
        case .ungrouped: return WebShortcutStore.maxShortcuts
        case .group: return WebShortcutStore.maxShortcutsPerGroup
        }
    }

    private var appearHelpText: String {
        switch draftGroup {
        case .ungrouped:
            return String(localized: "settings.shortcuts.appear_help", defaultValue: "Appears in the sidebar under Shortcuts")
        case .group:
            return String(
                format: String(localized: "settings.shortcuts.appear_help_group", defaultValue: "Appears in the sidebar under “%@”"),
                label(for: draftGroup)
            )
        }
    }

    // MARK: - New group card

    private var newGroupCard: some View {
        SettingsCard(
            title: String(localized: "settings.shortcuts.new_group", defaultValue: "New group"),
            icon: "folder.fill.badge.plus",
            iconColor: DesignSystem.Colors.primary
        ) {
            STextFieldRow(
                label: String(localized: "settings.shortcuts.group_name", defaultValue: "Group name"),
                placeholder: String(localized: "settings.shortcuts.group_name.placeholder", defaultValue: "e.g. Research"),
                text: $draftGroupName
            )

            if let groupErrorMessage {
                SettingsStatusRow(
                    message: groupErrorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: DesignSystem.Colors.error
                )
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: groups.count >= WebShortcutStore.maxGroups
                    ? String(
                        format: String(localized: "settings.shortcuts.group_limit", defaultValue: "Limit of %d groups reached"),
                        WebShortcutStore.maxGroups
                    )
                    : String(localized: "settings.shortcuts.group_help", defaultValue: "Organize related shortcuts under one name"),
                actionLabel: String(localized: "settings.shortcuts.create", defaultValue: "Create"),
                isDisabled: groups.count >= WebShortcutStore.maxGroups
            ) {
                createGroup()
            }
        }
    }

    // MARK: - Ungrouped shortcuts card

    private var shortcutsCard: some View {
        SettingsCard(
            title: String(localized: "settings.shortcuts.your_shortcuts", defaultValue: "Your shortcuts"),
            icon: "link.circle.fill",
            iconColor: DesignSystem.Colors.primary
        ) {
            if shortcuts.isEmpty {
                SettingsInfoRow(text: String(localized: "settings.shortcuts.empty", defaultValue: "No shortcuts yet."))
            } else {
                ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    if index > 0 {
                        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                    }
                    WebShortcutRow(
                        shortcut: shortcut,
                        index: index,
                        count: shortcuts.count,
                        currentChoice: .ungrouped,
                        groupChoices: groupChoices,
                        groupLabel: { label(for: $0) },
                        onMoveUp: { move(in: .ungrouped, from: index, to: index - 1) },
                        onMoveDown: { move(in: .ungrouped, from: index, to: index + 1) },
                        onOpen: { open(shortcut) },
                        onRemove: { remove(id: shortcut.id) },
                        onSave: { title, url, choice, icon in
                            save(id: shortcut.id, title: title, url: url, target: choice, iconSystemName: icon)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Group card

    private func groupCard(for group: WebShortcutGroup) -> some View {
        SettingsCard(
            title: group.name,
            icon: "folder.fill",
            iconColor: DesignSystem.Colors.info
        ) {
            if group.shortcuts.isEmpty {
                SettingsInfoRow(text: String(localized: "settings.shortcuts.group_empty", defaultValue: "No shortcuts in this group yet."))
            } else {
                ForEach(Array(group.shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                    WebShortcutRow(
                        shortcut: shortcut,
                        index: index,
                        count: group.shortcuts.count,
                        currentChoice: .group(group.id),
                        groupChoices: groupChoices,
                        groupLabel: { label(for: $0) },
                        onMoveUp: { move(in: .group(group.id), from: index, to: index - 1) },
                        onMoveDown: { move(in: .group(group.id), from: index, to: index + 1) },
                        onOpen: { open(shortcut) },
                        onRemove: { remove(id: shortcut.id) },
                        onSave: { title, url, choice, icon in
                            save(id: shortcut.id, title: title, url: url, target: choice, iconSystemName: icon)
                        }
                    )
                    Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                }
            }

            WebShortcutGroupManageRow(
                group: group,
                onRename: { newName in renameGroup(id: group.id, name: newName) },
                onDelete: { deleteGroup(id: group.id) }
            )
        }
    }

    // MARK: - Actions

    private func reload() {
        shortcuts = WebShortcutStore.loadAll()
        groups = WebShortcutStore.loadGroups()
        if case .group(let id) = draftGroup, !groups.contains(where: { $0.id == id }) {
            draftGroup = .ungrouped
        }
    }

    private func addShortcut() {
        errorMessage = nil
        if let err = WebShortcutStore.validate(title: draftTitle, urlString: draftURL) {
            errorMessage = err
            return
        }
        guard !isAtCapacity else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let newShortcut = WebShortcut(title: title, urlString: url)

        switch draftGroup {
        case .ungrouped:
            var next = shortcuts
            next.append(newShortcut)
            WebShortcutStore.saveAll(next)
        case .group(let id):
            var next = groups
            guard let idx = next.firstIndex(where: { $0.id == id }) else { return }
            next[idx].shortcuts.append(newShortcut)
            WebShortcutStore.saveGroups(next)
        }

        reload()
        draftTitle = ""
        draftURL = ""
    }

    private func createGroup() {
        groupErrorMessage = nil
        if let err = WebShortcutStore.validateGroupName(draftGroupName) {
            groupErrorMessage = err
            return
        }
        guard groups.count < WebShortcutStore.maxGroups else { return }
        var next = groups
        next.append(WebShortcutGroup(name: draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines)))
        WebShortcutStore.saveGroups(next)
        reload()
        draftGroupName = ""
    }

    private func renameGroup(id: UUID, name: String) -> String? {
        if let err = WebShortcutStore.validateGroupName(name) { return err }
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return nil }
        var next = groups
        next[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        WebShortcutStore.saveGroups(next)
        reload()
        return nil
    }

    private func deleteGroup(id: UUID) {
        var next = groups
        next.removeAll { $0.id == id }
        WebShortcutStore.saveGroups(next)
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        reload()
    }

    private func remove(id: UUID) {
        WebShortcutStore.removeShortcutEverywhere(id: id)
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        reload()
    }

    private func move(in collection: WebShortcutGroupChoice, from: Int, to: Int) {
        switch collection {
        case .ungrouped:
            guard shortcuts.indices.contains(from), shortcuts.indices.contains(to) else { return }
            var next = shortcuts
            let item = next.remove(at: from)
            next.insert(item, at: to)
            WebShortcutStore.saveAll(next)
        case .group(let id):
            guard let gIdx = groups.firstIndex(where: { $0.id == id }) else { return }
            guard groups[gIdx].shortcuts.indices.contains(from),
                  groups[gIdx].shortcuts.indices.contains(to) else { return }
            var next = groups
            let item = next[gIdx].shortcuts.remove(at: from)
            next[gIdx].shortcuts.insert(item, at: to)
            WebShortcutStore.saveGroups(next)
        }
        reload()
    }

    /// Saves an edited shortcut, moving it between collections when the chosen group changed.
    /// Returns a validation error message, or nil on success.
    private func save(
        id: UUID,
        title: String,
        url: String,
        target: WebShortcutGroupChoice,
        iconSystemName: String?
    ) -> String? {
        if let err = WebShortcutStore.validate(title: title, urlString: url) {
            return err
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = WebShortcut(id: id, title: trimmedTitle, urlString: trimmedURL, iconSystemName: iconSystemName)

        var nextUngrouped = shortcuts
        var nextGroups = groups

        // Update in place if the shortcut stays in its current collection; otherwise relocate.
        let currentlyInUngrouped = nextUngrouped.contains { $0.id == id }
        let currentGroupIndex = nextGroups.firstIndex { $0.shortcuts.contains { $0.id == id } }

        switch target {
        case .ungrouped where currentlyInUngrouped:
            if let i = nextUngrouped.firstIndex(where: { $0.id == id }) { nextUngrouped[i] = updated }
        case .group(let gid) where currentGroupIndex.map({ nextGroups[$0].id == gid }) == true:
            if let gi = currentGroupIndex,
               let i = nextGroups[gi].shortcuts.firstIndex(where: { $0.id == id }) {
                nextGroups[gi].shortcuts[i] = updated
            }
        default:
            // Relocating: capacity check on the destination first.
            switch target {
            case .ungrouped:
                if nextUngrouped.count >= WebShortcutStore.maxShortcuts {
                    return String(
                        format: String(localized: "settings.shortcuts.limit", defaultValue: "Limit of %d shortcuts reached"),
                        WebShortcutStore.maxShortcuts
                    )
                }
            case .group(let gid):
                if let gi = nextGroups.firstIndex(where: { $0.id == gid }),
                   nextGroups[gi].shortcuts.count >= WebShortcutStore.maxShortcutsPerGroup {
                    return String(
                        format: String(localized: "settings.shortcuts.limit", defaultValue: "Limit of %d shortcuts reached"),
                        WebShortcutStore.maxShortcutsPerGroup
                    )
                }
            }
            nextUngrouped.removeAll { $0.id == id }
            for gi in nextGroups.indices { nextGroups[gi].shortcuts.removeAll { $0.id == id } }
            switch target {
            case .ungrouped:
                nextUngrouped.append(updated)
            case .group(let gid):
                if let gi = nextGroups.firstIndex(where: { $0.id == gid }) {
                    nextGroups[gi].shortcuts.append(updated)
                }
            }
        }

        WebShortcutStore.saveAll(nextUngrouped)
        WebShortcutStore.saveGroups(nextGroups)
        reload()
        return nil
    }

    private func open(_ shortcut: WebShortcut) {
        guard let url = shortcut.resolvedURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Web shortcut row

private struct WebShortcutRow: View {
    let shortcut: WebShortcut
    let index: Int
    let count: Int
    let currentChoice: WebShortcutGroupChoice
    let groupChoices: [WebShortcutGroupChoice]
    let groupLabel: (WebShortcutGroupChoice) -> String
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onSave: (_ title: String, _ url: String, _ choice: WebShortcutGroupChoice, _ icon: String?) -> String?

    @State private var editTitle: String = ""
    @State private var editURL: String = ""
    @State private var editChoice: WebShortcutGroupChoice = .ungrouped
    @State private var editIcon: String?
    @State private var editError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "link")
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .font(DesignSystem.Fonts.main(size: 14))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.title)
                        .font(DesignSystem.Fonts.body(weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .help(shortcut.title)
                    Text(shortcut.normalizedURLString)
                        .font(DesignSystem.Fonts.caption2())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(shortcut.normalizedURLString)
                }

                Spacer()

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.primary)
                .help(String(localized: "settings.shortcuts.open", defaultValue: "Open"))

                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(index == 0)
                .help(String(localized: "settings.shortcuts.move_up", defaultValue: "Move up"))

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(index >= count - 1)
                .help(String(localized: "settings.shortcuts.move_down", defaultValue: "Move down"))

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Colors.error)
                .help(String(localized: "common.remove", defaultValue: "Remove"))
            }
            .font(DesignSystem.Fonts.main(size: 14))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            SAdvancedDisclosure(title: String(localized: "settings.shortcuts.edit", defaultValue: "Edit")) {
                STextFieldRow(
                    label: String(localized: "settings.shortcuts.name", defaultValue: "Name"),
                    text: $editTitle
                )
                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                STextFieldRow(
                    label: String(localized: "settings.shortcuts.address", defaultValue: "Web address"),
                    text: $editURL
                )

                if groupChoices.count > 1 {
                    Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
                    SMenuRow(
                        label: String(localized: "settings.shortcuts.group_label", defaultValue: "Group"),
                        currentDisplay: groupLabel(editChoice),
                        options: groupChoices,
                        optionLabel: groupLabel,
                        onSelect: { editChoice = $0 }
                    )
                }

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SCustomRow(
                    label: String(localized: "settings.shortcuts.icon", defaultValue: "Icon"),
                    subtitle: String(localized: "settings.shortcuts.icon_help", defaultValue: "Overrides the site favicon in the sidebar")
                ) {
                    Menu {
                        Button {
                            editIcon = nil
                        } label: {
                            Label(
                                String(localized: "settings.shortcuts.icon_default", defaultValue: "Default (favicon)"),
                                systemImage: "globe"
                            )
                        }
                        Divider()
                        ForEach(ShortcutIconCatalog.symbols, id: \.self) { symbol in
                            Button {
                                editIcon = symbol
                            } label: {
                                Label(symbol, systemImage: symbol)
                            }
                        }
                    } label: {
                        Image(systemName: editIcon ?? "globe")
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if let editError {
                    SettingsStatusRow(
                        message: editError,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: DesignSystem.Colors.error
                    )
                }

                Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

                SActionRow(
                    label: String(localized: "settings.shortcuts.save_changes", defaultValue: "Save changes"),
                    actionLabel: String(localized: "common.save", defaultValue: "Save")
                ) {
                    editError = onSave(editTitle, editURL, editChoice, editIcon)
                }
            }
        }
        .onAppear(perform: syncDraft)
        .onChange(of: shortcut) { _, _ in syncDraft() }
        .onChange(of: currentChoice) { _, _ in syncDraft() }
    }

    private func syncDraft() {
        editTitle = shortcut.title
        editURL = shortcut.urlString
        editChoice = currentChoice
        editIcon = shortcut.iconSystemName
        editError = nil
    }
}

// MARK: - Group management row

private struct WebShortcutGroupManageRow: View {
    let group: WebShortcutGroup
    let onRename: (_ name: String) -> String?
    let onDelete: () -> Void

    @State private var editName: String = ""
    @State private var renameError: String?

    var body: some View {
        SAdvancedDisclosure(title: String(localized: "settings.shortcuts.manage_group", defaultValue: "Manage group")) {
            STextFieldRow(
                label: String(localized: "settings.shortcuts.group_name", defaultValue: "Group name"),
                text: $editName
            )

            if let renameError {
                SettingsStatusRow(
                    message: renameError,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: DesignSystem.Colors.error
                )
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: String(localized: "settings.shortcuts.rename_group", defaultValue: "Rename group"),
                actionLabel: String(localized: "common.save", defaultValue: "Save")
            ) {
                renameError = onRename(editName)
            }

            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SActionRow(
                label: String(localized: "settings.shortcuts.delete_group_help", defaultValue: "Deletes the group and its shortcuts"),
                actionLabel: String(localized: "settings.shortcuts.delete_group", defaultValue: "Delete group"),
                actionColor: DesignSystem.Colors.error,
                role: .destructive
            ) {
                onDelete()
            }
        }
        .onAppear { editName = group.name }
        .onChange(of: group) { _, _ in
            editName = group.name
            renameError = nil
        }
    }
}
