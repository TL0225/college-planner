// CareerKPIStatCard.swift
// Feature: Career
// Purpose: Career module — CareerKPIStatCard.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CareerKPIStatCard: View {
    let title: String
    let valueText: String
    let valueColor: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

