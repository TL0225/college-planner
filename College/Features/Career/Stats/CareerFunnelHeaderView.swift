// CareerFunnelHeaderView.swift
// Feature: Career
// Purpose: Career module — CareerFunnelHeaderView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CareerFunnelHeaderView: View {
    let appliedCount: Int
    let interviewCount: Int
    let offerCount: Int

    private var interviewRate: Double {
        guard appliedCount > 0 else { return 0 }
        return (Double(interviewCount) / Double(appliedCount)) * 100
    }

    private var offerRate: Double {
        guard interviewCount > 0 else { return 0 }
        return (Double(offerCount) / Double(interviewCount)) * 100
    }

    var body: some View {
        HStack(spacing: 16) {
            FunnelStatCard(
                title: "Applied",
                subtitle: "In pipeline",
                valueText: "\(appliedCount)",
                valueColor: .blue
            )

            FunnelStatCard(
                title: "Interview",
                subtitle: "\(interviewCount) roles",
                valueText: String(format: "%.0f%%", interviewRate),
                valueColor: .orange
            )

            FunnelStatCard(
                title: "Offer",
                subtitle: "\(offerCount) offers",
                valueText: String(format: "%.0f%%", offerRate),
                valueColor: .green
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

struct FunnelStatCard: View {
    let title: String
    let subtitle: String
    let valueText: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text(valueText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(valueColor)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CareerKanbanTheme.cardBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
