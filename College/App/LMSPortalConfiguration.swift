import Foundation

/// Supported learning platforms for the in-app portal tab (single active provider + per-provider URLs).
enum LMSProvider: String, CaseIterable, Identifiable, Hashable {
    case brightspace = "Brightspace"
    case canvas = "Canvas"
    case moodle = "Moodle"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .brightspace: return "safari.fill"
        case .canvas: return "rectangle.split.3x3.fill"
        case .moodle: return "graduationcap.fill"
        }
    }

    var defaultPortalURL: URL {
        switch self {
        case .brightspace:
            return URL(string: "https://ublearns.buffalo.edu") ?? URL(fileURLWithPath: "/")
        case .canvas:
            return URL(string: "https://canvas.buffalo.edu") ?? URL(fileURLWithPath: "/")
        case .moodle:
            return URL(string: "https://ublearn.buffalo.edu") ?? URL(fileURLWithPath: "/")
        }
    }

    var defaultPortalURLString: String {
        defaultPortalURL.absoluteString
    }

    fileprivate var portalURLStorageKey: String {
        "lms.portalURL.\(rawValue)"
    }
}

enum LMSPortalConfiguration {
    static let activeProviderKey = "lms.activeProvider"

    private static let legacyBrightspacePortalKey = "brightspace.portalURL"

    static func resolvedActiveProvider() -> LMSProvider {
        let raw = UserDefaults.standard.string(forKey: activeProviderKey) ?? LMSProvider.brightspace.rawValue
        return LMSProvider(rawValue: raw) ?? .brightspace
    }

    /// Sidebar / dock label for the unified LMS page.
    static var sidebarDisplayTitle: String {
        resolvedActiveProvider().rawValue
    }

    static func resolvedPortalURL() -> URL {
        let provider = resolvedActiveProvider()

        if provider == .brightspace {
            let legacy = UserDefaults.standard.string(forKey: legacyBrightspacePortalKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacy.isEmpty, let url = URL(string: legacy) { return url }
        }

        let stored = UserDefaults.standard.string(forKey: provider.portalURLStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty, let url = URL(string: stored) { return url }

        return provider.defaultPortalURL
    }

    static func setActiveProvider(_ provider: LMSProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: activeProviderKey)
    }

    static func setPortalURLString(_ raw: String?, for provider: LMSProvider) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = provider.portalURLStorageKey
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }

        if provider == .brightspace {
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: legacyBrightspacePortalKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: legacyBrightspacePortalKey)
            }
        }
    }

    static func portalURLString(for provider: LMSProvider) -> String {
        if provider == .brightspace {
            let legacy = UserDefaults.standard.string(forKey: legacyBrightspacePortalKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacy.isEmpty { return legacy }
        }
        return UserDefaults.standard.string(forKey: provider.portalURLStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
