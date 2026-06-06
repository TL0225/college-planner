import Foundation

/// Weak bridge so write/sync paths can reach the integration manager without a global singleton.
@MainActor
public enum CalendarIntegrationBridge {
    public weak static var manager: CalendarIntegrationManager?
}
