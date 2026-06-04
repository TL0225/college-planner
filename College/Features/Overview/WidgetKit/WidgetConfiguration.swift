// WidgetConfiguration.swift
// Feature: Overview
// Purpose: Overview module — WidgetConfiguration.
// Data: CollegePersistence / repositories when applicable.

//
//  WidgetConfiguration.swift
//  College
//
//  Persists each user's enabled-widget list and custom widget heights to
//  UserDefaults so the Overview layout survives app restarts.
//

import SwiftUI
import Combine

// MARK: - Default order

private let defaultWidgetIDs: [String] = [
    "weather", "academics", "deadlines", "schedule",
    "documents", "events", "tasks"
]

// MARK: - Codable model

private struct WidgetConfiguration: Codable {
    var enabledIDs: [String]
    var heights:    [String: CGFloat]
}

// MARK: - Store

/// Observable store that reads/writes the user's widget layout to UserDefaults.
/// Inject as `@StateObject` in `CollegeApp` and pass down as `.environmentObject`.
final class WidgetConfigurationStore: ObservableObject {

    @Published var enabledIDs: [String]
    @Published var heights:    [String: CGFloat]

    private let storageKey = "overview.widgetConfiguration"

    // MARK: Init

    init() {
        if let data   = UserDefaults.standard.data(forKey: "overview.widgetConfiguration"),
           let config = try? JSONDecoder().decode(WidgetConfiguration.self, from: data) {
            self.enabledIDs = config.enabledIDs
            self.heights    = config.heights
        } else {
            // First launch — show all built-in widgets in default order.
            self.enabledIDs = defaultWidgetIDs
            self.heights    = [:]
        }
    }

    // MARK: Mutations

    func addWidget(id: String) {
        guard !enabledIDs.contains(id) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            enabledIDs.append(id)
        }
        save()
    }

    func removeWidget(id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            enabledIDs.removeAll { $0 == id }
        }
        save()
    }

    func swapWidgets(idA: String, idB: String) {
        guard let i = enabledIDs.firstIndex(of: idA),
              let j = enabledIDs.firstIndex(of: idB) else { return }
        enabledIDs.swapAt(i, j)
        save()
    }

    func setHeight(id: String, height: CGFloat) {
        heights[id] = height
        save()
    }

    func resetToDefaults() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            enabledIDs = defaultWidgetIDs
            heights    = [:]
        }
        save()
    }

    // MARK: Private

    private func save() {
        let config = WidgetConfiguration(enabledIDs: enabledIDs, heights: heights)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
