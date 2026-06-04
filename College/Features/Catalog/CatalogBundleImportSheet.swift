// CatalogBundleImportSheet.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBundleImportPreview.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CatalogBundleImportPreview: Sendable {
    let bundle: CatalogBundle
    let envelope: CatalogBundleEnvelope
    let fingerprint: String
    let signatureValid: Bool
    let existingCourseCount: Int
}

@MainActor
@Observable
final class CatalogImportCoordinator {
    var pendingURL: URL?
    var preview: CatalogBundleImportPreview?
    var loadError: String?
    var isTrustSheetPresented = false
    var isConfirmSheetPresented = false
    var isErrorAlertPresented = false
    var trustLabel = ""
    var trustOnceAccepted = false
    var isImporting = false
    var importError: String?
    var importSuccessMessage: String?

    private let persistence: CollegePersistence

    init(persistence: CollegePersistence = .shared) {
        self.persistence = persistence
    }

    func handleIncomingFile(url: URL) {
        if url.lastPathComponent.lowercased().hasSuffix(".collegecatalog.sqlite") {
            Task { @MainActor in
                do {
                    try CatalogStorePortableBridge.importSignedCatalogStore(from: url)
                    importSuccessMessage = "Imported signed catalog store."
                } catch {
                    loadError = error.localizedDescription
                    isErrorAlertPresented = true
                }
            }
            return
        }

        pendingURL = url
        loadError = nil
        preview = nil
        trustOnceAccepted = false
        trustLabel = ""

        do {
            let (bundle, envelope, fingerprint) = try CatalogBundleSecurity.verifyFile(at: url)
            switch CatalogBundleValidator.validate(bundle) {
            case .valid:
                break
            case .invalid(let reason):
                loadError = reason
                isErrorAlertPresented = true
                return
            }
            let existing = persistence.existingCatalogCourseCount(for: bundle.schoolName)
            preview = CatalogBundleImportPreview(
                bundle: bundle,
                envelope: envelope,
                fingerprint: fingerprint,
                signatureValid: true,
                existingCourseCount: existing
            )
            if CatalogBundleTrustStore.shared.isTrusted(fingerprint: fingerprint) || trustOnceAccepted {
                isConfirmSheetPresented = true
            } else {
                isTrustSheetPresented = true
            }
        } catch {
            loadError = error.localizedDescription
            isErrorAlertPresented = true
        }
    }

    func acceptTrustOnce() {
        trustOnceAccepted = true
        isTrustSheetPresented = false
        isConfirmSheetPresented = true
    }

    func acceptTrustAlways() {
        guard let preview else { return }
        CatalogBundleTrustStore.shared.add(
            publicKeyBase64: preview.envelope.signerPublicKey,
            fingerprint: preview.fingerprint,
            label: trustLabel.nilIfEmpty,
            trustAlways: true
        )
        trustOnceAccepted = true
        isTrustSheetPresented = false
        isConfirmSheetPresented = true
    }

    func cancelImport() {
        reset()
    }

    func performImport() async {
        guard let url = pendingURL, preview != nil else { return }
        isImporting = true
        importError = nil
        defer { isImporting = false }
        do {
            let summary = try await persistence.importCatalogBundle(from: url)
            importSuccessMessage = "Imported \(summary.courseCount) courses for \(summary.schoolName)."
            reset()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func reset() {
        pendingURL = nil
        preview = nil
        isTrustSheetPresented = false
        isConfirmSheetPresented = false
        trustLabel = ""
        trustOnceAccepted = false
    }
}

// MARK: - Modifier

struct CatalogBundleImportSheetsModifier: ViewModifier {
    @Bindable var coordinator: CatalogImportCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.isTrustSheetPresented) {
                CatalogBundleTrustSheet(coordinator: coordinator)
            }
            .sheet(isPresented: $coordinator.isConfirmSheetPresented) {
                CatalogBundleConfirmImportSheet(coordinator: coordinator)
            }
            .alert("Catalog Import Failed", isPresented: $coordinator.isErrorAlertPresented) {
                Button("OK", role: .cancel) { coordinator.cancelImport() }
            } message: {
                Text(coordinator.loadError ?? "Unknown error")
            }
            .alert("Import Error", isPresented: Binding(
                get: { coordinator.importError != nil },
                set: { if !$0 { coordinator.importError = nil } }
            )) {
                Button("OK", role: .cancel) { coordinator.importError = nil }
            } message: {
                Text(coordinator.importError ?? "")
            }
            .alert("Import Complete", isPresented: Binding(
                get: { coordinator.importSuccessMessage != nil },
                set: { if !$0 { coordinator.importSuccessMessage = nil } }
            )) {
                Button("OK", role: .cancel) { coordinator.importSuccessMessage = nil }
            } message: {
                Text(coordinator.importSuccessMessage ?? "")
            }
    }
}

extension View {
    func catalogBundleImportSheets(coordinator: CatalogImportCoordinator) -> some View {
        modifier(CatalogBundleImportSheetsModifier(coordinator: coordinator))
    }
}

// MARK: - Trust sheet

private struct CatalogBundleTrustSheet: View {
    @Bindable var coordinator: CatalogImportCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unrecognized Catalog Source")
                .font(.title2.bold())
            Text("This catalog bundle was signed by a device that is not in your trusted list.")
                .foregroundStyle(.secondary)
            if let preview = coordinator.preview {
                Label(preview.bundle.schoolName, systemImage: "building.columns")
                    .font(.headline)
                HStack {
                    Text("Device fingerprint")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(preview.fingerprint)
                        .font(.system(.body, design: .monospaced))
                }
            }
            TextField("Name this source (optional)", text: $coordinator.trustLabel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") {
                    coordinator.cancelImport()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Trust Once") {
                    coordinator.acceptTrustOnce()
                    dismiss()
                }
                Button("Trust Always") {
                    coordinator.acceptTrustAlways()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

// MARK: - Confirmation sheet

private struct CatalogBundleConfirmImportSheet: View {
    @Bindable var coordinator: CatalogImportCoordinator
    @Environment(\.dismiss) private var dismiss

    private var isTrusted: Bool {
        guard let preview = coordinator.preview else { return false }
        return CatalogBundleTrustStore.shared.isTrusted(fingerprint: preview.fingerprint) || coordinator.trustOnceAccepted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Catalog Bundle")
                .font(.title2.bold())

            if let preview = coordinator.preview {
                if preview.signatureValid {
                    Label(isTrusted ? "Trusted source" : "Trusted for this import", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Invalid signature — import blocked", systemImage: "xmark.seal.fill")
                        .foregroundStyle(.red)
                }

                Group {
                    row("School", preview.bundle.schoolName)
                    row("Exported", preview.bundle.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    row("Courses", "\(preview.bundle.courses.count)")
                    row("Programs", "\(preview.bundle.programs.count)")
                    row("Requirement sections", "\(preview.bundle.requirementSections.count)")
                    row("Signer", preview.fingerprint)
                }

                if preview.existingCourseCount > 0 {
                    Label(
                        "Will update existing catalog data (\(preview.existingCourseCount) courses already on file).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            }

            HStack {
                Button("Cancel") {
                    coordinator.cancelImport()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") {
                    Task {
                        await coordinator.performImport()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.preview?.signatureValid != true || coordinator.isImporting)
            }
        }
        .padding(24)
        .frame(minWidth: 440)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
            Spacer(minLength: 0)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
