// AssistantWebSearchSettings.swift
// Feature: Assistant
// Purpose: UserDefaults keys and helpers for DeGoog web search + assistant web memory.

import Foundation

/// UserDefaults keys and helpers for built-in DeGoog search + assistant web memory.
enum AssistantWebSearchSettings {
    static let webSearchEnabledKey = "assistant.webSearch.enabled"
    /// Legacy key — migrated to ``customBaseURLKey`` on read when the new key is unset.
    static let legacySearxBaseURLKey = "assistant.searx.baseURL"
    static let customBaseURLKey = "assistant.webSearch.customBaseURL"
    static let extraFetchHostsKey = "assistant.web.extraFetchHosts"
    static let semanticMemoryEnabledKey = "assistant.webMemory.semanticEnabled"

    static var isWebSearchEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: webSearchEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: webSearchEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: webSearchEnabledKey) }
    }

    /// Optional advanced override. Empty means use the bundled local DeGoog sidecar.
    static var customBaseURL: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: customBaseURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !stored.isEmpty {
                return stored
            }
            let legacy = UserDefaults.standard.string(forKey: legacySearxBaseURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !legacy.isEmpty else { return "" }
            if legacy == "https://searx.be" {
                return ""
            }
            return legacy
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: customBaseURLKey)
            UserDefaults.standard.removeObject(forKey: legacySearxBaseURLKey)
        }
    }

    /// Comma-separated hostnames allowed for `fetchWebPageReadable` in addition to recent search result hosts.
    static var extraFetchHosts: [String] {
        get {
            let raw = UserDefaults.standard.string(forKey: extraFetchHostsKey) ?? ""
            return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        }
        set {
            UserDefaults.standard.set(newValue.joined(separator: ", "), forKey: extraFetchHostsKey)
        }
    }

    static var isSemanticMemoryEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: semanticMemoryEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: semanticMemoryEnabledKey) }
    }

    static func normalizedCustomBaseURL() -> URL? {
        let raw = customBaseURL
        guard !raw.isEmpty else { return nil }
        return normalizedBaseURL(raw)
    }

    /// Normalizes user input:
    /// - HTTPS for normal hosts
    /// - HTTP allowed only for localhost / loopback (127.0.0.1, ::1)
    /// - strip path/query/fragment and trim whitespace
    static func normalizedBaseURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed
        let lower = candidate.lowercased()
        if !lower.hasPrefix("https://") && !lower.hasPrefix("http://") {
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        let isLoopbackHost = host == "127.0.0.1" || host == "localhost" || host == "::1"
        if scheme == "http" {
            guard isLoopbackHost else { return nil }
        } else if scheme != "https" {
            return nil
        }

        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.path = ""
        c?.query = nil
        c?.fragment = nil
        return c?.url
    }

    // MARK: - Legacy migration

    @available(*, deprecated, renamed: "customBaseURLKey")
    static let searxBaseURLKey = legacySearxBaseURLKey

    @available(*, deprecated, renamed: "customBaseURL")
    static var searxBaseURL: String {
        get { customBaseURL }
        set { customBaseURL = newValue }
    }

    @available(*, deprecated, renamed: "normalizedBaseURL")
    static func normalizedSearxBaseURL(_ raw: String) -> URL? {
        normalizedBaseURL(raw)
    }
}
