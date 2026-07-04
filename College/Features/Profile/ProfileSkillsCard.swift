// ProfileSkillsCard.swift
// Feature: Profile
// Purpose: Skills section on the profile dashboard.

import SwiftUI

struct ProfileSkillsCard: View {
    @Bindable var profile: Profile
    @State private var newSkill: String = ""

    private var skills: [String] {
        profile.skillsList
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Skills", systemImage: "sparkles")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                Spacer()
            }

            if skills.isEmpty {
                Text("No skills added yet.")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            } else {
                ProfileSkillsFlowLayout(spacing: 8) {
                    ForEach(skills, id: \.self) { skill in
                        skillChip(skill)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add a skill", text: $newSkill)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSkill)
                Button("Add", action: addSkill)
                    .disabled(newSkill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .profileCardSurface(padding: 24)
    }

    @ViewBuilder
    private func skillChip(_ skill: String) -> some View {
        HStack(spacing: 6) {
            Text(skill)
                .font(.caption.weight(.medium))
            Button {
                removeSkill(skill)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private func addSkill() {
        let trimmed = newSkill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = skills
        guard !updated.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newSkill = ""
            return
        }
        updated.append(trimmed)
        profile.skillsList = updated
        newSkill = ""
    }

    private func removeSkill(_ skill: String) {
        profile.skillsList = skills.filter { $0.caseInsensitiveCompare(skill) != .orderedSame }
    }
}

private struct ProfileSkillsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
