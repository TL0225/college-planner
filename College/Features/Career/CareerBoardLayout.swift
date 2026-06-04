// CareerBoardLayout.swift
// Feature: Career
// Purpose: Career module — CareerBoardLayoutMenu.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI

enum CareerBoardLayout: String, CaseIterable, Identifiable, Sendable {
    case kanban
    case list

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kanban: return "Kanban Board"
        case .list: return "List"
        }
    }

    static let storageKey = "career.board.layout"
}

struct CareerBoardLayoutMenu: View {
    let layout: CareerBoardLayout
    let onSelect: (CareerBoardLayout) -> Void

    var body: some View {
        Menu {
            ForEach(CareerBoardLayout.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    if layout == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.3.group")
        }
        .help("Board layout")
        .accessibilityLabel("Board layout")
    }
}
