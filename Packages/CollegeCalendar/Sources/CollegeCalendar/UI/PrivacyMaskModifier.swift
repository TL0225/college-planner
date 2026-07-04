// PrivacyMaskModifier.swift
// Feature: Calendar
// Purpose: Calendar module — PrivacyMirrorEnabledKey.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

private struct PrivacyMirrorEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var privacyMirrorEnabled: Bool {
        get { self[PrivacyMirrorEnabledKey.self] }
        set { self[PrivacyMirrorEnabledKey.self] = newValue }
    }
}

/// Masks confidential calendar content when Privacy Mirror is enabled.
struct PrivacyMaskModifier: ViewModifier {
    @Environment(\.privacyMirrorEnabled) private var mirrorEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isConfidential: Bool
    let displayTitle: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if mirrorEnabled, isConfidential {
            content
                .blur(radius: reduceTransparency ? 0 : 6)
                .overlay {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                    }
                }
                .overlay {
                    Text("Busy")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Busy")
                .accessibilityRemoveTraits(.isStaticText)
        } else {
            content
        }
    }
}

extension View {
    func privacyMasked(isConfidential: Bool, displayTitle: String) -> some View {
        modifier(PrivacyMaskModifier(isConfidential: isConfidential, displayTitle: displayTitle))
    }
}
