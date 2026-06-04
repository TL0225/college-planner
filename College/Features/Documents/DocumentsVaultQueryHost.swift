// DocumentsVaultQueryHost.swift
// Feature: Documents
// Purpose: Documents module — DocumentsVaultQueryHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import SwiftUI

/// Invalidates Documents UI when local store vault rows change (Phase 7f).
struct DocumentsVaultQueryHost: View {
    @Query(sort: \VaultDocument.addedAt, order: .reverse) private var vaultRows: [VaultDocument]
    @Binding var refreshToken: Int

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: vaultRows.count) { _, _ in
                refreshToken &+= 1
            }
            .onChange(of: vaultRows.map(\.id)) { _, _ in
                refreshToken &+= 1
            }
    }
}
