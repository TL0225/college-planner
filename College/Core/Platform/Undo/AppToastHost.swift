// AppToastHost.swift
// Feature: Core
// Purpose: Core module — AppToast.
// Data: CollegePersistence / repositories when applicable.

import Observation
import SwiftUI

struct AppToast: Identifiable {
    let id = UUID()
    var title: String
    var message: String?
    var undoLabel: String?
    var onUndo: (() -> Void)?
}

/// Phase 6: queued toast banner with optional undo action.
@MainActor
@Observable
final class AppToastHost {
    static let shared = AppToastHost()

    private(set) var pendingToasts: [AppToast] = []

    private init() {}

    func show(_ toast: AppToast, autoDismissAfter seconds: TimeInterval = 5) {
        pendingToasts.append(toast)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            dismiss(id: toast.id)
        }
    }

    func dismiss(id: UUID) {
        pendingToasts.removeAll { $0.id == id }
    }
}

struct AppToastOverlay: View {
    @Bindable var host: AppToastHost

    var body: some View {
        VStack(spacing: 8) {
            ForEach(host.pendingToasts) { toast in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.title).font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                        if let message = toast.message {
                            Text(message).font(DesignSystem.Fonts.main(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let undo = toast.onUndo, let label = toast.undoLabel {
                        Button(label, action: undo)
                            .buttonStyle(.borderless)
                    }
                    Button {
                        host.dismiss(id: toast.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(!host.pendingToasts.isEmpty)
    }
}
