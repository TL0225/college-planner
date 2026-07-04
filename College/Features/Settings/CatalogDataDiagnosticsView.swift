// CatalogDataDiagnosticsView.swift
// Feature: Settings
// Purpose: Reusable catalog ingest / integrity diagnostics panel.

import SwiftUI

struct CatalogDataDiagnosticsView: View {
    @Environment(AppContainer.self) private var container
    private var appNotifications: AppNotificationCenter { container.appNotifications }

    let schoolID: String
    let isAnySyncRunning: Bool

    init(schoolID: String, isAnySyncRunning: Bool = false) {
        self.schoolID = schoolID
        self.isAnySyncRunning = isAnySyncRunning
    }

    var body: some View {
        let pdfReport = schoolID.isEmpty ? nil : PDFScrapeReport.load(schoolID: schoolID)
        let integrity = schoolID.isEmpty ? nil : CatalogIntegrityReport.load(schoolID: schoolID)
        let archiveIndex = schoolID.isEmpty ? nil : CatalogArchiveStore.loadIndex(schoolID: schoolID)
        let storeDiagnostics = schoolID.isEmpty ? nil : CatalogStoreCoordinator.shared.diagnostics(for: schoolID)
        let ingestObs = CatalogIngestObservability.summarizeRecent()
        let reviewItems = CatalogReviewQueue.load()
        let layoutFingerprint = schoolID.isEmpty ? nil : CatalogLayoutFingerprintStore.latest(forSchoolID: schoolID)
        let platformVerification = schoolID.isEmpty ? nil : CatalogPlatformProbe.verificationRecord(schoolID: schoolID)

        if pdfReport != nil || integrity != nil || archiveIndex != nil || !schoolID.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let pdfReport {
                    Text("PDF scrape — \(pdfReport.schoolName)")
                        .font(.caption.weight(.semibold))
                    Text("Pages \(pdfReport.pageCount) · Programs \(pdfReport.programsExtracted) · Courses \(pdfReport.coursesExtracted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let integrity {
                    Text("Integrity — academic \(integrity.academicReady ? "ready" : "partial") · archive \(integrity.archiveReady ? "ready" : "pending") · search \(integrity.vectorsReady ? "ready" : "indexing")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let archiveIndex {
                    Text("Archive index — \(archiveIndex.archivedPages)/\(archiveIndex.totalPages) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let storeDiagnostics {
                    Text("Per-school sqlite — \(storeDiagnostics.exists ? "present" : "missing") · \(ByteCountFormatter.string(fromByteCount: storeDiagnostics.sizeBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Ingest observability — failures \(Int((ingestObs.failureRate * 100).rounded()))% · avg duration \(Int(ingestObs.avgDurationMs.rounded()))ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !ingestObs.discoveryTelemetryCounts.isEmpty {
                    let telemetryPreview = ingestObs.discoveryTelemetryCounts
                        .sorted { lhs, rhs in
                            if lhs.value != rhs.value { return lhs.value > rhs.value }
                            return lhs.key < rhs.key
                        }
                        .prefix(3)
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: ", ")
                    Text("Discovery telemetry — \(telemetryPreview)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Review queue — \(reviewItems.count) item(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let layoutFingerprint {
                    Text("Layout fingerprint — profile \(layoutFingerprint.layoutProfileID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let platformVerification {
                    let mismatchLabel = platformVerification.mismatch ? "mismatch" : "aligned"
                    let evidencePreview = platformVerification.evidence.prefix(2).joined(separator: ", ")
                    Text(
                        "Platform probe — declared \(platformVerification.declaredFormat) · detected \(platformVerification.detectedFormat) (\(mismatchLabel), confidence \(String(format: "%.1f", platformVerification.confidence)))"
                    )
                    .font(.caption2)
                    .foregroundStyle(platformVerification.mismatch ? .orange : .secondary)
                    if !evidencePreview.isEmpty {
                        Text("Probe evidence — \(evidencePreview)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !schoolID.isEmpty {
                    SettingsCatalogReviewDiagnosticsView(schoolID: schoolID)
                }
                if !schoolID.isEmpty {
                    Button("Request catalog import cancel") {
                        CatalogIngestCheckpoint.requestCancel(schoolID: schoolID)
                        appNotifications.post(
                            kind: AppNotificationCenter.AppNotification.Kind.info,
                            title: "Cancel requested",
                            message: "The current catalog import will stop at the next checkpoint.",
                            isDismissible: true,
                            autoDismissAfter: 5
                        )
                    }
                    .disabled(!isAnySyncRunning)
                }
            }
        } else {
            Text("No catalog diagnostics are available for your profile school yet.")
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
        }
    }
}

extension CatalogDataDiagnosticsView {
    @MainActor
    static func resolvedSchoolID(from persistence: CollegePersistence) -> String {
        let profileSchool = persistence.profile?.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return persistence.catalogManifestSchoolID(forUniversityName: profileSchool) ?? ""
    }
}
