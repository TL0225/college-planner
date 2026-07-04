// AppCommandPalette.swift
import CollegeCalendar
// Feature: Core
// Purpose: Quick Actions palette (⌘K) — navigation, file actions, and calendar NL create.

import SwiftUI

private enum CommandPaletteEntry: Identifiable, Hashable {
    case navigate(AppPage)
    case openWebShortcut(WebShortcut)
    case exportBackup
    case importBackup
    case importCatalog
    case openSettings
    case createCalendarEvent(String)

    var id: String {
        switch self {
        case .navigate(let page): return "nav-\(page.rawValue)"
        case .openWebShortcut(let shortcut): return "web-\(shortcut.id.uuidString)"
        case .exportBackup: return "export-backup"
        case .importBackup: return "import-backup"
        case .importCatalog: return "import-catalog"
        case .openSettings: return "open-settings"
        case .createCalendarEvent(let text): return "event-\(text)"
        }
    }

    var title: String {
        switch self {
        case .navigate(let page): return "Go to \(page.displayTitle)"
        case .openWebShortcut(let shortcut): return "Open \(shortcut.title)"
        case .exportBackup: return "Export Backup…"
        case .importBackup: return "Import Backup…"
        case .importCatalog: return "Import Catalog Bundle…"
        case .openSettings: return "Open Settings"
        case .createCalendarEvent(let text): return "Create Event: \(text)"
        }
    }

    var subtitle: String? {
        switch self {
        case .navigate(let page): return page.higDomainLabel
        case .openWebShortcut: return "Web Shortcut"
        case .exportBackup, .importBackup: return "File"
        case .importCatalog: return "Catalog"
        case .openSettings: return "Preferences"
        case .createCalendarEvent: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .navigate(let page): return page.icon
        case .openWebShortcut: return "link.circle.fill"
        case .exportBackup: return "square.and.arrow.up"
        case .importBackup: return "square.and.arrow.down"
        case .importCatalog: return "books.vertical"
        case .openSettings: return "gearshape"
        case .createCalendarEvent: return "calendar.badge.plus"
        }
    }
}

/// Global Quick Actions palette (⌘K) — supplementary to menus; routes navigation and common actions.
struct AppCommandPalette: View {
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedEntryID: CommandPaletteEntry.ID?
    @State private var isParsing = false
    @State private var errorMessage: String?
    @FocusState private var isQueryFocused: Bool

    private var allEntries: [CommandPaletteEntry] {
        var entries: [CommandPaletteEntry] = AppPage.shellSectionShortcuts.map { .navigate($0.page) }
        entries.append(contentsOf: WebShortcutStore.allShortcutsSync().map { .openWebShortcut($0) })
        entries.append(contentsOf: [
            .exportBackup,
            .importBackup,
            .importCatalog,
            .openSettings
        ])
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            entries.append(.createCalendarEvent(trimmed))
        }
        return entries
    }

    private var filteredEntries: [CommandPaletteEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allEntries }
        let needle = trimmed.lowercased()
        return allEntries.filter { entry in
            entry.title.lowercased().contains(needle)
                || (entry.subtitle?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search actions or type an event…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isQueryFocused)
                .onSubmit { Task { await activateSelection() } }
                .accessibilityLabel("Quick Actions search")

            if isParsing {
                ProgressView("Creating event…")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            List(filteredEntries, selection: $selectedEntryID) { entry in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                        if let subtitle = entry.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: entry.systemImage)
                }
                .tag(entry.id)
                .accessibilityLabel(entry.title)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .listStyle(.inset)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(primaryActionTitle) { Task { await activateSelection() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(filteredEntries.isEmpty || isParsing)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 460)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onAppear {
            selectedEntryID = filteredEntries.first?.id
            isQueryFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedEntryID = filteredEntries.first?.id
        }
        .onExitCommand { dismiss() }
    }

    private var primaryActionTitle: String {
        guard let selectedEntryID,
              let entry = filteredEntries.first(where: { $0.id == selectedEntryID }) else {
            return "Run"
        }
        switch entry {
        case .createCalendarEvent: return "Create Event"
        default: return "Go"
        }
    }

    @MainActor
    private func activateSelection() async {
        let entry: CommandPaletteEntry?
        if let selectedEntryID,
           let match = filteredEntries.first(where: { $0.id == selectedEntryID }) {
            entry = match
        } else {
            entry = filteredEntries.first
        }
        guard let entry else { return }
        await run(entry)
    }

    @MainActor
    private func run(_ entry: CommandPaletteEntry) async {
        errorMessage = nil
        switch entry {
        case .navigate(let page):
            AppTypedNavigationRouter.openPage(page)
            dismiss()
        case .openWebShortcut(let shortcut):
            AppTypedNavigationRouter.openPage(.webShortcut(id: shortcut.id))
            dismiss()
        case .exportBackup:
            dismiss()
            AppFileMenuActions.exportBackup()
        case .importBackup:
            dismiss()
            AppFileMenuActions.importBackup()
        case .importCatalog:
            dismiss()
            AppFileMenuActions.importCatalogBundle()
        case .openSettings:
            dismiss()
            MacPreferencesWindow.show()
        case .createCalendarEvent(let text):
            await createEvent(from: text)
        }
    }

    @MainActor
    private func createEvent(from text: String) async {
        isParsing = true
        defer { isParsing = false }
        do {
            let intent = try await NaturalLanguageEventParser.parse(text)
            let start = intent.start ?? Date()
            let end = intent.end ?? start.addingTimeInterval(3600)
            let input = CalendarEventWriteInput(
                title: intent.title,
                startDate: start,
                endDate: end,
                allDay: intent.allDay
            )
            _ = try await CalendarEventWritePipeline.shared.create(input: input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismiss() {
        isPresented = false
        query = ""
        errorMessage = nil
    }
}
