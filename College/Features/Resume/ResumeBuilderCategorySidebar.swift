// ResumeBuilderCategorySidebar.swift
// Feature: Resume
// Purpose: Guided builder category list with completion checkmarks and section reorder.

import SwiftUI

struct ResumeBuilderCategorySidebar: View {
    @Bindable var viewModel: ResumeBuilderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CATEGORIES")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 6) {
                    categoryRow(.personal, isLocked: true)

                    ForEach(orderedSidebarKinds) { kind in
                        categoryRow(kind, isLocked: false)
                            .dropDestination(for: ResumeSectionKind.self) { items, _ in
                                guard let incoming = items.first else { return false }
                                viewModel.placeSection(incoming, before: kind)
                                return true
                            }
                    }

                    ghostDropSlot
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.bgMain)
    }

    private var orderedSidebarKinds: [ResumeSectionKind] {
        let ordered = viewModel.document.sectionOrder
        let remaining = ResumeSectionKind.orderableCases.filter { !ordered.contains($0) }
        return ordered + remaining
    }

    @ViewBuilder
    private func categoryRow(_ kind: ResumeSectionKind, isLocked: Bool) -> some View {
        let isSelected = viewModel.selectedCategory == kind
        let isComplete = viewModel.isSectionComplete(kind)

        Button {
            viewModel.selectCategory(kind)
        } label: {
            HStack(spacing: 10) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }

                Image(systemName: kind.systemImage)
                    .font(.body)
                    .foregroundStyle(DesignSystem.Colors.primary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.subheadline.weight(isSelected ? .bold : .semibold))
                        .foregroundStyle(.primary)
                    Text(viewModel.sectionSubtitle(for: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isComplete ? .green : .secondary.opacity(0.55))
                    .accessibilityLabel(isComplete ? "\(kind.title) complete" : "\(kind.title) incomplete")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.12) : DesignSystem.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? DesignSystem.Colors.primary.opacity(0.35) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .modifier(SectionDragModifier(kind: kind, isEnabled: !isLocked))
        .accessibilityIdentifier("resume.builder.category.\(kind.rawValue)")
        .accessibilityHint("Select to edit \(kind.title)")
    }

    private var ghostDropSlot: some View {
        HStack {
            Image(systemName: "arrow.down.to.line")
                .foregroundStyle(.secondary)
            Text("Drop to reorder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.secondary.opacity(0.3))
        )
        .dropDestination(for: ResumeSectionKind.self) { items, _ in
            guard let incoming = items.first, incoming != .personal else { return false }
            viewModel.placeSection(incoming, before: nil)
            return true
        }
    }
}

private struct SectionDragModifier: ViewModifier {
    let kind: ResumeSectionKind
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(kind) {
                Text(kind.title)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        } else {
            content
        }
    }
}
