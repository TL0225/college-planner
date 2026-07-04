// AssistantStudentGuidePanel.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantStudentGuidePanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct AssistantStudentGuidePanel: View {
    let selectedRole: AssistantAgentRole
    let localModelInstalled: Bool
    let webSearchEnabled: Bool

    private var examples: [String] {
        switch selectedRole {
        case .academicAdvisor:
            return [
                "What career paths fit my major and coursework?",
                "Can you create a semester-by-semester breakdown of my major?",
                "What's the residency requirement for my degree?",
                "What's due this week?"
            ]
        case .financialAid:
            return [
                "Am I full-time for financial aid?",
                "Explain FAFSA verification.",
                "Do I look at risk for SAP?",
                "What should I check on this award letter?"
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedRole.symbol)
                    .font(DesignSystem.Fonts.main(size: 20, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Ask your \(selectedRole.rawValue.lowercased())")
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                    Text(selectedRole == .academicAdvisor
                         ? "I can help explain requirements, sequence courses, draft schedules, and prepare planner changes for review."
                         : "I can explain FAFSA, state aid, SAP, enrollment intensity, deadlines, and aid documents without asking for sensitive IDs.")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Text(example)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                AssistantStatusPill(
                    label: localModelInstalled ? "On-device JSON model ready" : "Local model not installed",
                    systemImage: localModelInstalled ? "checkmark.seal" : "arrow.down.circle"
                )
                AssistantStatusPill(
                    label: webSearchEnabled ? "Web search can leave device" : "Web search off",
                    systemImage: webSearchEnabled ? "network" : "lock"
                )
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.chromeStroke, lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant.studentGuidePanel")
    }
}

private struct AssistantStatusPill: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.textLight)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DesignSystem.Colors.surface.opacity(0.7), in: Capsule())
    }
}
