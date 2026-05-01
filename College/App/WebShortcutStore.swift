import Foundation

struct WebShortcut: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String

    init(id: UUID = UUID(), title: String, urlString: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
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

enum WebShortcutStore {
    private static let defaultsKey = "sidebar.web.shortcuts"
    static let maxShortcuts = 12

    static func loadAllSync() -> [WebShortcut] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([WebShortcut].self, from: data)) ?? []
    }

    static func shortcutSync(id: UUID) -> WebShortcut? {
        loadAllSync().first { $0.id == id }
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
}

extension Notification.Name {
    static let webShortcutsDidChange = Notification.Name("webShortcutsDidChange")
}
