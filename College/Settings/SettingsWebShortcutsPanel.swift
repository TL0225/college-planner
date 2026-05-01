import SwiftUI

#if os(macOS)
struct SettingsWebShortcutsPanel: View {
    @State private var shortcuts: [WebShortcut] = WebShortcutStore.loadAll()
    @State private var draftTitle: String = ""
    @State private var draftURL: String = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Name (e.g. YouTube)", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("https://...", text: $draftURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Add Shortcut") {
                    addShortcut()
                }
                .disabled(shortcuts.count >= WebShortcutStore.maxShortcuts)
            } header: {
                Label("New shortcut", systemImage: "plus.circle.fill")
            } footer: {
                Text("Shortcuts appear in the main sidebar under SHORTCUTS, below your LMS portal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if shortcuts.isEmpty {
                    Text("No shortcuts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shortcuts) { sc in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sc.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2)
                                    .help(sc.title)
                                Text(sc.normalizedURLString)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .help(sc.normalizedURLString)
                            }
                            Spacer(minLength: 8)
                            Button(role: .destructive) {
                                remove(id: sc.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Label("Your shortcuts", systemImage: "link.circle.fill")
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcuts = WebShortcutStore.loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .webShortcutsDidChange)) { _ in
            shortcuts = WebShortcutStore.loadAll()
        }
    }

    private func addShortcut() {
        errorMessage = nil
        if let err = WebShortcutStore.validate(title: draftTitle, urlString: draftURL) {
            errorMessage = err
            return
        }
        guard shortcuts.count < WebShortcutStore.maxShortcuts else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = shortcuts
        next.append(WebShortcut(title: title, urlString: url))
        WebShortcutStore.saveAll(next)
        shortcuts = WebShortcutStore.loadAll()
        draftTitle = ""
        draftURL = ""
    }

    private func remove(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        WebShortcutStore.saveAll(shortcuts)
    }
}
#endif
