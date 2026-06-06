import CoreGraphics
import Foundation

/// Multi-tenant lane classification for calendar chip geometry and aggregation.
public enum CalendarTenantKind: String, CaseIterable, Sendable {
    case personal
    case work
    case school

    public static let cornerRadiusOverridesKey = "calendar.tenant.cornerRadiusOverrides"

    public var defaultCornerRadius: CGFloat {
        switch self {
        case .personal: return 10
        case .work: return 6
        case .school: return 8
        }
    }

    public func resolvedCornerRadius(cellRadius: CGFloat) -> CGFloat {
        let stored = UserDefaults.standard.dictionary(forKey: Self.cornerRadiusOverridesKey) as? [String: Double]
        let base = stored?[rawValue].map { CGFloat($0) } ?? defaultCornerRadius
        switch self {
        case .work:
            return max(4, min(base, cellRadius - 4))
        case .school, .personal:
            return min(max(4, base), max(4, cellRadius - 4))
        }
    }

    public static func resolve(courseCode: String?, providerSource: String?, hasCourse: Bool) -> CalendarTenantKind {
        if hasCourse { return .school }
        let trimmedCode = courseCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCode.isEmpty { return .school }
        let source = (providerSource ?? "").lowercased()
        if source.contains("outlook") || source.contains("google") { return .work }
        return .personal
    }

    public static func resolve(for event: CalendarStoredEvent) -> CalendarTenantKind {
        resolve(
            courseCode: event.courseCode,
            providerSource: event.providerSource,
            hasCourse: event.courseID != nil
        )
    }
}
