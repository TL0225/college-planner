// WebShortcutStore.swift
// Feature: App
// Purpose: App module — WebShortcut.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct WebShortcut: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String
    /// Optional SF Symbol name that overrides the site favicon in the sidebar.
    var iconSystemName: String?

    init(id: UUID = UUID(), title: String, urlString: String, iconSystemName: String? = nil) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.iconSystemName = iconSystemName
    }

    var normalizedURLString: String {
        let t = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return t }
        return "https://\(t)"
    }

    var resolvedURL: URL? {
        let n = normalizedURLString
        guard !n.isEmpty else { return nil }
        return URL(string: n)
    }
}

/// A named collection of related shortcuts. Renders as a collapsible folder in the sidebar.
struct WebShortcutGroup: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var shortcuts: [WebShortcut]

    init(id: UUID = UUID(), name: String, shortcuts: [WebShortcut] = []) {
        self.id = id
        self.name = name
        self.shortcuts = shortcuts
    }
}

enum WebShortcutStore {
    private static let defaultsKey = "sidebar.web.shortcuts"
    private static let groupsDefaultsKey = "sidebar.web.shortcut.groups"
    static let maxShortcuts = 12
    static let maxGroups = 8
    static let maxShortcutsPerGroup = 12

    // MARK: - Ungrouped shortcuts

    static func loadAllSync() -> [WebShortcut] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([WebShortcut].self, from: data)) ?? []
    }

    static func loadAll() -> [WebShortcut] {
        loadAllSync()
    }

    static func saveAllSync(_ shortcuts: [WebShortcut]) {
        let trimmed = Array(shortcuts.prefix(maxShortcuts))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        NotificationCenter.default.post(name: .webShortcutsDidChange, object: nil)
    }

    static func saveAll(_ shortcuts: [WebShortcut]) {
        saveAllSync(shortcuts)
    }

    // MARK: - Groups

    static func loadGroupsSync() -> [WebShortcutGroup] {
        guard let data = UserDefaults.standard.data(forKey: groupsDefaultsKey) else { return [] }
        return (try? JSONDecoder().decode([WebShortcutGroup].self, from: data)) ?? []
    }

    static func loadGroups() -> [WebShortcutGroup] {
        loadGroupsSync()
    }

    static func saveGroupsSync(_ groups: [WebShortcutGroup]) {
        let trimmed = groups.prefix(maxGroups).map { group -> WebShortcutGroup in
            var copy = group
            copy.shortcuts = Array(group.shortcuts.prefix(maxShortcutsPerGroup))
            return copy
        }
        guard let data = try? JSONEncoder().encode(Array(trimmed)) else { return }
        UserDefaults.standard.set(data, forKey: groupsDefaultsKey)
        NotificationCenter.default.post(name: .webShortcutsDidChange, object: nil)
    }

    static func saveGroups(_ groups: [WebShortcutGroup]) {
        saveGroupsSync(groups)
    }

    // MARK: - Sidebar group expansion state

    private static let expandedGroupsKey = "sidebar.web.shortcut.expandedGroups"

    static func loadExpandedGroupIDsSync() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: expandedGroupsKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func saveExpandedGroupIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: expandedGroupsKey)
    }

    // MARK: - Reordering / moving (drag & drop)

    /// Moves a shortcut to a destination group (or the ungrouped list when `groupID` is nil),
    /// inserting at `index` (appended when nil). No-op if the destination is at capacity.
    @discardableResult
    static func moveShortcut(id: UUID, toGroup groupID: UUID?, atIndex index: Int?) -> Bool {
        var ungrouped = loadAllSync()
        var groups = loadGroupsSync()

        // Find and detach the shortcut from its current location.
        var moved: WebShortcut?
        if let i = ungrouped.firstIndex(where: { $0.id == id }) {
            moved = ungrouped.remove(at: i)
        } else {
            for gi in groups.indices {
                if let i = groups[gi].shortcuts.firstIndex(where: { $0.id == id }) {
                    moved = groups[gi].shortcuts.remove(at: i)
                    break
                }
            }
        }
        guard let shortcut = moved else { return false }

        if let groupID {
            guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return false }
            guard groups[gi].shortcuts.count < maxShortcutsPerGroup else { return false }
            let clamped = clampIndex(index, count: groups[gi].shortcuts.count)
            groups[gi].shortcuts.insert(shortcut, at: clamped)
        } else {
            guard ungrouped.count < maxShortcuts else { return false }
            let clamped = clampIndex(index, count: ungrouped.count)
            ungrouped.insert(shortcut, at: clamped)
        }

        saveAllSync(ungrouped)
        saveGroupsSync(groups)
        return true
    }

    /// Reorders a group to `index` within the group list.
    static func moveGroup(id: UUID, toIndex index: Int) {
        var groups = loadGroupsSync()
        guard let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups.remove(at: from)
        let clamped = clampIndex(index, count: groups.count)
        groups.insert(group, at: clamped)
        saveGroupsSync(groups)
    }

    private static func clampIndex(_ index: Int?, count: Int) -> Int {
        guard let index else { return count }
        return max(0, min(index, count))
    }

    // MARK: - Cross-collection lookups

    /// Every shortcut the app knows about, ungrouped first then grouped, used for routing
    /// resolution, dock menus, and web-coordinator pruning.
    static func allShortcutsSync() -> [WebShortcut] {
        loadAllSync() + loadGroupsSync().flatMap { $0.shortcuts }
    }

    static func allShortcutIDsSync() -> Set<UUID> {
        Set(allShortcutsSync().map(\.id))
    }

    static func shortcutSync(id: UUID) -> WebShortcut? {
        allShortcutsSync().first { $0.id == id }
    }

    /// Removes a shortcut by id from the ungrouped list and from every group.
    static func removeShortcutEverywhere(id: UUID) {
        let ungrouped = loadAllSync()
        if ungrouped.contains(where: { $0.id == id }) {
            saveAllSync(ungrouped.filter { $0.id != id })
        }
        var groups = loadGroupsSync()
        var didChangeGroups = false
        for index in groups.indices where groups[index].shortcuts.contains(where: { $0.id == id }) {
            groups[index].shortcuts.removeAll { $0.id == id }
            didChangeGroups = true
        }
        if didChangeGroups {
            saveGroupsSync(groups)
        }
    }

    // MARK: - Validation

    static func validate(title: String, urlString: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Enter a name for this shortcut." }
        if u.isEmpty { return "Enter a web address (URL)." }
        guard WebShortcut(title: t, urlString: u).resolvedURL != nil else {
            return "That does not look like a valid URL."
        }
        return nil
    }

    static func validateGroupName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a name for this group." }
        return nil
    }
}

extension Notification.Name {
    static let webShortcutsDidChange = Notification.Name("webShortcutsDidChange")
}
