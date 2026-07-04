// ResumeBuilderChecklistFooter.swift
// Feature: Resume
// Purpose: Wizard checklist footer showing section completion progress.

import SwiftUI

struct ResumeBuilderChecklistFooter: View {
    @Bindable var viewModel: ResumeBuilderViewModel

    var body: some View {
        HStack(spacing: 16) {
            Label {
                Text("\(viewModel.completedChecklistCount) of \(viewModel.totalChecklistCount) sections complete")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: progressIcon)
                    .foregroundStyle(progressColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ResumeSectionKind.checklistCases) { kind in
                        Button {
                            viewModel.selectCategory(kind)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.isSectionComplete(kind) ? "checkmark.circle.fill" : "circle")
                                    .font(.caption2)
                                Text(kind.title)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        viewModel.selectedCategory == kind
                                            ? DesignSystem.Colors.primary.opacity(0.14)
                                            : Color.secondary.opacity(0.08)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(kind.title), \(viewModel.isSectionComplete(kind) ? "complete" : "incomplete")")
                    }
                }
            }

            Spacer(minLength: 0)

            if viewModel.completedChecklistCount >= 3 {
                Text("Ready to export")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignSystem.Colors.bgMain)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Resume completion checklist")
    }

    private var progressIcon: String {
        if viewModel.completedChecklistCount == viewModel.totalChecklistCount {
            return "checkmark.seal.fill"
        }
        return "list.bullet.clipboard"
    }

    private var progressColor: Color {
        if viewModel.completedChecklistCount == viewModel.totalChecklistCount {
            return .green
        }
        return DesignSystem.Colors.primary
    }
}
