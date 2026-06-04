// AppleSiliconRequiredView.swift
// Feature: App
// Purpose: App module — AppleSiliconRequiredView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Shown when the app is opened on hardware College does not support.
struct AppleSiliconRequiredView: View {
    let report: AppleSiliconPlatform.Report

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("Apple Silicon Required")
                .font(DesignSystem.Fonts.title1())

            Text(report.requirementMessage ?? AppleSiliconPlatform.requirementMessage)
                .font(DesignSystem.Fonts.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if !report.deviceName.isEmpty, report.deviceName != "unsupported-architecture" {
                Text("Detected GPU: \(report.deviceName)")
                    .font(DesignSystem.Fonts.caption1())
                    .foregroundStyle(.tertiary)
                if let maxThreads = report.maxThreadsPerThreadgroup {
                    Text("Metal threadgroup limit: \(maxThreads) (need \(AppleSiliconPlatform.mlxRequiredThreadsPerThreadgroup))")
                        .font(DesignSystem.Fonts.caption1())
                        .foregroundStyle(.tertiary)
                }
            }

            Text("College uses on-device MLX models and Metal features that are only available on M-series Macs.")
                .font(DesignSystem.Fonts.caption1())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
    }
}
