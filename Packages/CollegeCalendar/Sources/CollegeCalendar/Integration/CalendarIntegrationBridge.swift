import Foundation

/// Weak bridge so write/sync paths can reach the integration manager without a global singleton.
@MainActor
public enum CalendarIntegrationBridge {
    public weak static var manager: CalendarIntegrationManager?

    /// Host wires registry-aware provider loop start after OAuth connect succeeds.
    public static var onProviderConnected: (() -> Void)?

    /// Host-owned BackgroundServiceScheduler polling for connected cloud providers.
    public static var startGoogleProviderPolling: (() -> Void)?
    public static var stopGoogleProviderPolling: (() -> Void)?
    public static var startOutlookProviderPolling: (() -> Void)?
    public static var stopOutlookProviderPolling: (() -> Void)?
    public static var startICloudProviderPolling: (() -> Void)?
    public static var stopICloudProviderPolling: (() -> Void)?
}
