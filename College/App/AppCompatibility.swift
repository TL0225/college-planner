// AppCompatibility.swift
// Feature: App
// Purpose: App module — PlannerMenuCommands.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import CollegeCalendar
import CollegeCareer
#if canImport(AppKit)
import AppKit
#endif

extension AppPage {
    /// Window/menu proxy title when `navigationTitle` is empty (e.g. Settings).
    var windowChromeTitle: String {
        switch self {
        case .documents:
            return String(localized: "documents.screen.title")
        case .assistant:
            return "AI Assistant"
        default:
            return displayTitle
        }
    }

    static func webShortcutPage(id: UUID) -> AppPage { .webShortcut(id: id) }
}

extension Notification.Name {
    static let plannerOpenPage = Notification.Name("plannerOpenPage")
    static let collegeOpenResumeBuilder = Notification.Name("collegeOpenResumeBuilder")
    static let collegeImportSharedResume = Notification.Name("collegeImportSharedResume")
}

enum CollegeInboundURLDispatcher {
    /// Routes `college://` deep links to the appropriate `AppPage` and state change.
    ///
    /// Supported routes:
    /// - `college://tab/<name>` — switch to a top-level page (academics, calendar, career, …)
    /// - `college://event/<uuid>` — open Calendar and focus the given event
    /// - `college://job/<uuid>` — open Career and focus the given board job
    ///
    /// Any non-`college` scheme (e.g. Spotify auth callbacks) is forwarded to `spotifyHandler`.
    @discardableResult
    static func handle(
        _ url: URL,
        spotifyHandler: (URL) -> Void,
        careerJobHandler: ((UUID) -> Void)? = nil
    ) -> Bool {
        guard url.scheme?.lowercased() == "college" else {
            spotifyHandler(url)
            return true
        }

        // For custom schemes, `host` carries the route kind and the first path
        // component carries the identifier (e.g. college://event/<uuid>).
        let kind = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let identifier = pathComponents.first

        switch kind {
        case "tab":
            guard let identifier else { return false }
            if identifier.lowercased() == "settings" {
                MacPreferencesWindow.show()
                return true
            }
            guard let page = page(forTabName: identifier) else { return false }
            postOpenPage(page)
            return true

        case "event":
            guard let identifier, let eventID = UUID(uuidString: identifier) else { return false }
            postOpenPage(.calendar)
            NotificationCenter.default.post(name: .calendarFocusEvent, object: eventID)
            return true

        case "job":
            guard let identifier, let jobID = UUID(uuidString: identifier) else { return false }
            postOpenPage(.career)
            careerJobHandler?(jobID)
            return true

        case "ingest":
            postOpenPage(.career)
            Task { @MainActor in
                await CareerIngestCoordinator.shared.processPendingIngestIfNeeded()
                await CareerIngestCoordinator.shared.processPendingSaveRequests()
            }
            return true

        case "resume":
            postOpenPage(.career)
            if identifier?.lowercased() == "new" || identifier == nil {
                NotificationCenter.default.post(name: .collegeOpenResumeBuilder, object: nil)
                return true
            }
            if identifier?.lowercased() == "import" {
                let requestID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "requestId" })?
                    .value
                NotificationCenter.default.post(
                    name: .collegeImportSharedResume,
                    object: requestID
                )
                return true
            }
            guard let identifier, let documentID = UUID(uuidString: identifier) else { return false }
            NotificationCenter.default.post(name: .collegeOpenResumeBuilder, object: documentID)
            return true

        default:
            return false
        }
    }

    private static func postOpenPage(_ page: AppPage) {
        AppTypedNavigationRouter.openPage(page)
    }

    private static func page(forTabName name: String) -> AppPage? {
        switch name.lowercased() {
        case "degree": return .degree
        case "academics", "courses": return .academics
        case "transfer", "transfer-database": return .transferDatabase
        case "calendar": return .calendar
        case "career", "jobs": return .career
        case "assistant", "ai": return .assistant
        case "profile": return .profile
        case "settings": return .settings
        case "brightspace", "lms": return .lms
        case "documents", "vault": return .documents
        default: return nil
        }
    }
}

struct PlannerMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Quick Actions…") {
                NotificationCenter.default.post(name: .collegeShowCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
        }

        CommandGroup(after: .importExport) {
            Button("Export Backup…") {
                AppFileMenuActions.exportBackup()
            }
            Button("Import Backup…") {
                AppFileMenuActions.importBackup()
            }
            Divider()
            Button("Import Catalog Bundle…") {
                AppFileMenuActions.importCatalogBundle()
            }
            Button("Import Transfer Community Data…") {
                AppFileMenuActions.importTransferCommunityJSON()
            }
        }

        CommandMenu("View") {
            Button("Find…") {
                NotificationCenter.default.post(name: .collegeFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Divider()

            ForEach(AppPage.shellSectionShortcuts, id: \.page) { shortcut in
                Button("Go to \(shortcut.page.displayTitle)") {
                    AppTypedNavigationRouter.openPage(shortcut.page)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(shortcut.keyEquivalent)),
                    modifiers: .command
                )
                .disabled(shortcut.page == .lms && !LMSPortalConfiguration.isLMSTabEnabled())
            }

            Divider()

            Menu("Career") {
                Button("Add Application…") {
                    AppTypedNavigationRouter.openPage(.career)
                    NotificationCenter.default.post(name: .collegeCareerAddApplication, object: nil)
                }
                Divider()
                ForEach(CareerSubView.allCases) { view in
                    Button(view.rawValue) {
                        AppTypedNavigationRouter.openPage(.career)
                        NotificationCenter.default.post(
                            name: .careerSelectSubview,
                            object: nil,
                            userInfo: ["rawValue": view.rawValue]
                        )
                    }
                }
            }

            Menu("Calendar Inspector") {
                Button("Event List") {
                    AppTypedNavigationRouter.openPage(.calendar)
                    NotificationCenter.default.post(
                        name: .collegeCalendarSelectSidebarPanel,
                        object: nil,
                        userInfo: ["panel": CalendarSidebarPanel.eventList.rawValue]
                    )
                }
                Button("Tasks & Deadlines") {
                    AppTypedNavigationRouter.openPage(.calendar)
                    NotificationCenter.default.post(
                        name: .collegeCalendarSelectSidebarPanel,
                        object: nil,
                        userInfo: ["panel": CalendarSidebarPanel.tasks.rawValue]
                    )
                }
                Button("Study / Focus") {
                    AppTypedNavigationRouter.openPage(.calendar)
                    NotificationCenter.default.post(
                        name: .collegeCalendarSelectSidebarPanel,
                        object: nil,
                        userInfo: ["panel": CalendarSidebarPanel.studyFocus.rawValue]
                    )
                }
            }

            Button("Add Course…") {
                AppTypedNavigationRouter.openPage(.academics)
                NotificationCenter.default.post(name: .collegeAcademicsAddCourse, object: nil)
            }

            Button("Advisor Meeting Prep…") {
                AppTypedNavigationRouter.openPage(.profile)
                NotificationCenter.default.post(name: .profileOpenAdvisorPrep, object: nil)
            }

            Button("Edit Profile…") {
                AppTypedNavigationRouter.openPage(.profile)
                NotificationCenter.default.post(name: .collegeProfileEditProfile, object: nil)
            }
        }

        CommandMenu("Assistant") {
            Button("Open AI Assistant") {
                AppTypedNavigationRouter.openPage(.assistant)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help("⌘⇧A here; ⌘6 via View → Go to Assistant")

            Divider()

            Button("Open Web Memory Library…") {
                AppTypedNavigationRouter.openPage(.assistant)
                NotificationCenter.default.post(name: .collegeAssistantOpenWebMemory, object: nil)
            }
            Button("Export Transcript…") {
                AppTypedNavigationRouter.openPage(.assistant)
                NotificationCenter.default.post(name: .collegeAssistantExportTranscript, object: nil)
            }
            Button("Clear Assistant Thread…") {
                AppTypedNavigationRouter.openPage(.assistant)
                NotificationCenter.default.post(name: .collegeAssistantClearThread, object: nil)
            }
        }

        CommandGroup(replacing: .help) {
            Button("College Help") {
                if let url = URL(string: "https://github.com/timothyleung/College#readme") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Privacy Overview…") {
                NotificationCenter.default.post(name: .collegeShowPrivacyOverview, object: nil)
            }
            Button("Diagnostics…") {
                NotificationCenter.default.post(name: .collegeShowDiagnostics, object: nil)
            }
        }

        CommandGroup(after: .windowArrangement) {
            Button("New Documents Window") {
                NotificationCenter.default.post(name: .collegeOpenDocumentsWindow, object: nil)
            }
        }
    }
}
