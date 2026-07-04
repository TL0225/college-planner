// DocumentsWindowRoot.swift
// Feature: Documents
// Purpose: Tear-off Documents window for side-by-side file workflows.

import SwiftUI

struct DocumentsWindowRoot: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var searchText = ""
    @State private var isInspectorPresented = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        DocumentsView(
            searchText: $searchText,
            isInspectorPresented: $isInspectorPresented
        )
        .navigationTitle(String(localized: "documents.screen.title"))
        .toolbarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: String(localized: "documents.search.prompt", defaultValue: "Search Documents")
        )
        .searchFocused($isSearchFocused)
        .onReceive(NotificationCenter.default.publisher(for: .collegeFocusSearch)) { _ in
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeToggleInspector)) { _ in
            isInspectorPresented.toggle()
        }
    }
}
