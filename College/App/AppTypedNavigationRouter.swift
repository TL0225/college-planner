// AppTypedNavigationRouter.swift
// Feature: App
// Purpose: Typed navigation destinations replacing raw NotificationCenter payloads (Phase 6 / A11).

import Combine
import Foundation

enum AppNavigationAction: Equatable {
    case openPage(AppPage)
    case openDocuments(courseCode: String)
    case importCatalogBundle(URL)
}

enum AppTypedNavigationRouter {
    /// Merged publisher for ContentView — single subscription replaces per-notification handlers.
    static var publisher: AnyPublisher<Notification, Never> {
        Publishers.Merge3(
            NotificationCenter.default.publisher(for: .plannerOpenPage),
            NotificationCenter.default.publisher(for: .plannerOpenDocumentsForCourse),
            NotificationCenter.default.publisher(for: .plannerImportCatalogBundleFileURL)
        )
        .eraseToAnyPublisher()
    }

    static func action(from notification: Notification) -> AppNavigationAction? {
        switch notification.name {
        case .plannerOpenPage:
            guard let page = page(from: notification) else { return nil }
            return .openPage(page)
        case .plannerOpenDocumentsForCourse:
            let rawCode = (notification.userInfo?["courseCode"] as? String) ?? ""
            let normalized = rawCode
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !normalized.isEmpty else { return nil }
            return .openDocuments(courseCode: normalized)
        case .plannerImportCatalogBundleFileURL:
            guard let url = notification.userInfo?["url"] as? URL else { return nil }
            return .importCatalogBundle(url)
        default:
            return nil
        }
    }

    static func page(from notification: Notification) -> AppPage? {
        guard let raw = notification.userInfo?["pageRaw"] as? String else { return nil }
        return AppPage(rawValue: raw)
    }

    static func openPage(_ page: AppPage) {
        if page == .settings {
            MacPreferencesWindow.show()
            return
        }
        NotificationCenter.default.post(
            name: .plannerOpenPage,
            object: nil,
            userInfo: ["pageRaw": page.rawValue]
        )
    }

    static func openDocuments(forCourseCode code: String) {
        let normalized = code
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalized.isEmpty else { return }
        NotificationCenter.default.post(
            name: .plannerOpenDocumentsForCourse,
            object: nil,
            userInfo: ["courseCode": normalized]
        )
    }

    static func importCatalogBundle(at url: URL) {
        NotificationCenter.default.post(
            name: .plannerImportCatalogBundleFileURL,
            object: nil,
            userInfo: ["url": url]
        )
    }
}
