import CollegePlatform
import Foundation

/// Phase 2 extraction boundary for the Calendar feature (ADR 004).
///
/// Intended dependency edges:
///   - CollegeCalendar → CollegePlatform (shared messaging, integration health)
///   - CollegeCalendar ↛ other feature modules (Academics, Career, Catalog, …)
///
/// Migration source: `College/Features/Calendar/` (63 Swift files).
/// First movers into this target: pure cache/sync types with no SwiftUI.
public enum CollegeCalendarBoundary {
    public static let moduleName = "CollegeCalendar"
    public static let sourceRoot = "College/Features/Calendar"
    public static let migrationOrderRank = 1

    /// Re-exports the shared change channel Calendar already uses via CollegePlatform.
    public static let changeNotification: Notification.Name = .calendarDidChange
}
