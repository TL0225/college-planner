// CatalogBundleTrustStore.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBundleTrustStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

@MainActor
@Observable
final class CatalogBundleTrustStore {
    static let shared = CatalogBundleTrustStore()

    private static let storageKey = "catalog.trusted.sources.v1"

    private(set) var trustedSources: [TrustedCatalogSource] = []

    private init() {
        load()
    }

    var myFingerprint: String {
        CatalogSigningKeyManager.shared.fingerprint
    }

    func isTrusted(fingerprint: String) -> Bool {
        let normalized = normalizeFingerprint(fingerprint)
        return trustedSources.contains { normalizeFingerprint($0.fingerprint) == normalized }
    }

    func add(
        publicKeyBase64: String,
        fingerprint: String,
        label: String?,
        trustAlways: Bool
    ) {
        guard trustAlways else { return }
        let normalized = normalizeFingerprint(fingerprint)
        trustedSources.removeAll { normalizeFingerprint($0.fingerprint) == normalized }
        trustedSources.append(
            TrustedCatalogSource(
                publicKeyBase64: publicKeyBase64,
                fingerprint: fingerprint,
                label: label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                trustedAt: Date()
            )
        )
        save()
    }

    func revoke(fingerprint: String) {
        let normalized = normalizeFingerprint(fingerprint)
        trustedSources.removeAll { normalizeFingerprint($0.fingerprint) == normalized }
        save()
    }

    private func normalizeFingerprint(_ value: String) -> String {
        value.uppercased().replacingOccurrences(of: " ", with: "")
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            trustedSources = []
            return
        }
        trustedSources = (try? JSONDecoder().decode([TrustedCatalogSource].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(trustedSources) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
