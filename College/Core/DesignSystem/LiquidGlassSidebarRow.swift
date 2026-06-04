// LiquidGlassSidebarRow.swift
// Feature: Core
// Purpose: Core module — LiquidGlassSidebarRow.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Tahoe-style sidebar header row: squircle + headline, hover/selection glass materials.
struct LiquidGlassSidebarRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "building.columns.fill"
    var isSelected: Bool = false

    @State private var isHovered = false

    private let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    private let iconShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                iconShape
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .glassEffect(in: iconShape)
                    .overlay(
                        iconShape
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                Image(systemName: systemImage)
                    .font(DesignSystem.Fonts.main(size: 20))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground)
        .clipShape(rowShape)
        .contentShape(rowShape)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            rowShape
                .fill(Color.accentColor.opacity(0.12))
                .glassEffect(in: rowShape)
                .overlay(
                    rowShape
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        } else if isHovered {
            rowShape
                .fill(Color.primary.opacity(0.07))
        } else {
            Color.clear
        }
    }
}
