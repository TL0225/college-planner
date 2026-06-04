// ModelBootstrapService.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — ModelBootstrapService.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Handles automatic on-device LLM installation at app startup.
///
/// Called once from `CollegeApp` as a low-priority background task.
/// - If the model is already present on disk this returns immediately with no UI.
/// - If the model is missing it downloads from Hugging Face and reports progress
///   through `AppNotificationCenter` (macOS Notification Center banners).
/// - Model weights are not pre-warmed at launch; surfaces call ``LLMOnDemandPrewarm`` on open.
enum ModelBootstrapService {

    static func ensureModelReady() async {
        guard AppleSiliconPlatform.isSupported else { return }

        let spec = ModelSpec.jsonWorker

        if await ModelManager.shared.isModelInstalled(spec) {
            DebugLogger.shared.log(
                "ModelBootstrapService: \(spec.displayName) already installed — skipping download",
                category: .system,
                level: .info
            )
            return
        }

        DebugLogger.shared.log(
            "ModelBootstrapService: \(spec.displayName) not found — starting background download",
            category: .system,
            level: .info
        )

        let notifID = await MainActor.run {
            AppNotificationCenter.shared.post(
                kind: .progress,
                title: "Downloading AI Model",
                message: "Fetching \(spec.displayName). This runs once in the background.",
                isDismissible: false
            )
        }

        do {
            _ = try await ModelManager.shared.ensureModelInstalled(spec) { prog in
                let pct = Int((prog.fractionCompleted * 100).rounded())
                let detail: String
                if let completed = prog.completedBytes, let total = prog.totalBytes, total > 0 {
                    let completedMB = Double(completed) / 1_048_576
                    let totalMB = Double(total) / 1_048_576
                    detail = String(format: "%.0f / %.0f MB (%d%%)", completedMB, totalMB, pct)
                } else {
                    detail = "File \(prog.completedFiles)/\(prog.totalFiles) (\(pct)%)"
                }

                Task { @MainActor in
                    AppNotificationCenter.shared.update(
                        id: notifID,
                        message: detail,
                        progress: prog.fractionCompleted
                    )
                }
            }

            await MainActor.run {
                AppNotificationCenter.shared.complete(
                    id: notifID,
                    kind: .success,
                    title: "AI Model Ready",
                    message: "\(spec.displayName) downloaded and ready.",
                    autoDismissAfter: 5
                )
            }

            DebugLogger.shared.log(
                "ModelBootstrapService: \(spec.displayName) download complete",
                category: .system,
                level: .info
            )

        } catch {
            await MainActor.run {
                AppNotificationCenter.shared.complete(
                    id: notifID,
                    kind: .error,
                    title: "AI Model Download Failed",
                    message: error.localizedDescription,
                    autoDismissAfter: 10
                )
            }

            DebugLogger.shared.log(
                "ModelBootstrapService: download failed — \(error.localizedDescription)",
                category: .system,
                level: .error
            )
        }
    }
}
