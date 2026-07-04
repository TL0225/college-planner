// ShellToolbarSearchModifier.swift
// Feature: App
// Purpose: Scoped `.searchable` for main-window detail pages.

import CollegeCalendar
import SwiftUI

struct ShellToolbarSearchModifier: ViewModifier {
    let activePage: AppPage
    @Binding var searchText: String
    var isSearchFocused: FocusState<Bool>.Binding
    var calendarScene: CalendarSceneState?

    func body(content: Content) -> some View {
        switch activePage {
        case .documents:
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: String(localized: "documents.search.prompt", defaultValue: "Search Documents")
                )
                .searchFocused(isSearchFocused)
        case .calendar:
            content
                .searchable(
                    text: calendarSearchBinding,
                    placement: .toolbar,
                    prompt: String(localized: "calendar.search.prompt", defaultValue: "Search events")
                )
                .searchFocused(isSearchFocused)
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .primaryAction)
                        .sharedBackgroundVisibility(.hidden)
                }
        case .academics:
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: String(localized: "academics.search.prompt", defaultValue: "Search courses")
                )
                .searchFocused(isSearchFocused)
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .primaryAction)
                        .sharedBackgroundVisibility(.hidden)
                }
        case .career:
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: String(localized: "career.search.prompt", defaultValue: "Search applications")
                )
                .searchFocused(isSearchFocused)
        case .transferDatabase:
            content
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: String(localized: "transfer.search.prompt", defaultValue: "Search transfer courses")
                )
                .searchFocused(isSearchFocused)
        default:
            content
        }
    }

    private var calendarSearchBinding: Binding<String> {
        Binding(
            get: { calendarScene?.toolbarSearchText ?? "" },
            set: { calendarScene?.toolbarSearchText = $0 }
        )
    }

}
