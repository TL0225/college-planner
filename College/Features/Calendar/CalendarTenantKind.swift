// CalendarTenantKind.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarTenantKind.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI

/// Multi-tenant lane classification for calendar chip geometry and aggregation.
enum CalendarTenantKind: String, CaseIterable, Sendable {
    case personal
    case work
    case school

    static let cornerRadiusOverridesKey = "calendar.tenant.cornerRadiusOverrides"

    var defaultCornerRadius: CGFloat {
        switch self {
        case .personal: return 10
        case .work: return 6
        case .school: return 8
        }
    }

    func resolvedCornerRadius(cellRadius: CGFloat) -> CGFloat {
        let stored = UserDefaults.standard.dictionary(forKey: Self.cornerRadiusOverridesKey) as? [String: Double]
        let base = stored?[rawValue].map { CGFloat($0) } ?? defaultCornerRadius
        switch self {
        case .work:
            return max(4, min(base, cellRadius - 4))
        case .school, .personal:
            return min(max(4, base), max(4, cellRadius - 4))
        }
    }

    static func resolve(for event: CalendarEvent) -> CalendarTenantKind {
        if event.course != nil { return .school }
        let source = (event.providerSource ?? "").lowercased()
        if source.contains("outlook") || source.contains("google") { return .work }
        return .personal
    }
}
