// CatalogTrustedSourcesView.swift
// Feature: Settings
// Purpose: Settings module — CatalogTrustedSourcesView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct CatalogTrustedSourcesView: View {
    @State private var trustStore = CatalogBundleTrustStore.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This device")
                            .font(.headline)
                        Text(trustStore.myFingerprint)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(trustStore.myFingerprint, forType: .string)
                    }
                }
            } header: {
                Text("My fingerprint")
            } footer: {
                Text("Share this fingerprint with others so they can recognize bundles you export.")
            }

            Section("Trusted sources") {
                if trustStore.trustedSources.isEmpty {
                    Text("No trusted sources yet. You will be prompted when importing a catalog from a new device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trustStore.trustedSources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            if let label = source.label, !label.isEmpty {
                                Text(label).font(.headline)
                            }
                            Text(source.fingerprint)
                                .font(.system(.caption, design: .monospaced))
                            Text("Trusted \(source.trustedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteSources)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Trusted Catalog Sources")
        .frame(minWidth: 480, minHeight: 320)
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let source = trustStore.trustedSources[index]
            trustStore.revoke(fingerprint: source.fingerprint)
        }
    }
}
