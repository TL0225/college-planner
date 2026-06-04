// AssistantWebSearchSettings.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantWebSearchSettings.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// UserDefaults keys and helpers for SearXNG + assistant web memory.
enum AssistantWebSearchSettings {
    static let searxBaseURLKey = "assistant.searx.baseURL"
    static let extraFetchHostsKey = "assistant.web.extraFetchHosts"
    static let semanticMemoryEnabledKey = "assistant.webMemory.semanticEnabled"
    static let defaultSearxBaseURL = "https://searx.be"

    static var searxBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: searxBaseURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? defaultSearxBaseURL : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: searxBaseURLKey) }
    }

    /// Comma-separated hostnames allowed for `fetchWebPageReadable` in addition to recent SearXNG result hosts.
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

    /// Normalizes user input:
    /// - HTTPS for normal hosts
    /// - HTTP allowed only for localhost / loopback (127.0.0.1, ::1)
    /// - strip path/query/fragment and trim whitespace
    static func normalizedSearxBaseURL(_ raw: String) -> URL? {
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
}
