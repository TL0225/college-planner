// JobInspectorSidebar.swift
// Feature: Career
// Purpose: Career module — JobInspectorFlowLayout.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - Company initials

extension String {
    /// Two-letter initials from a company name (first word prefix-2, or first letters of first two words).
    func careerCompanyInitials() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let tokens = trimmed.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if tokens.isEmpty { return "?" }
        if tokens.count == 1 {
            return String(tokens[0].prefix(2)).uppercased()
        }
        let first = tokens[0].prefix(1)
        let second = tokens[1].prefix(1)
        return "\(first)\(second)".uppercased()
    }
}

// MARK: - Keyword parsing (aligned with Kanban card)

private enum JobInspectorKeywordParser {
    static func keywords(from json: String?) -> [String] {
        let raw = (json ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return normalize(decoded)
        }
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return normalize(decoded.split(separator: ",").map(String.init))
        }
        return normalize(raw.split(separator: ",").map(String.init))
    }

    private static func normalize(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for token in raw {
            let trimmed = token
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }
}

// MARK: - Wrapping flow (skills row)

private struct JobInspectorFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (i, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[i].minX, y: bounds.minY + result.frames[i].minY), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let maxW = proposal.replacingUnspecifiedDimensions().width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var frames: [CGRect] = []

        for sub in subviews {
            let sz = sub.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0.5 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            rowH = max(rowH, sz.height)
            x += sz.width + spacing
        }
        return (frames, CGSize(width: maxW, height: y + rowH))
    }
}

// MARK: - Stat card (CareerKPIStatCard chrome)

private struct JobInspectorInfoCard: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = .primary
    var titleColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Sidebar

struct JobInspectorSidebar: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Bindable var job: JobApplication
    @Binding var selectedJobID: UUID?
    private var collegePersistence: CollegePersistence { container.persistence }
    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private let grid2 = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let stageGrid = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var status: CareerApplicationStatus {
        CareerApplicationStatus(rawValue: job.statusRaw) ?? .interested
    }

    private var laneAccent: Color {
        CareerKanbanTheme.laneAccent(for: status)
    }

    private var priority: CareerKanbanTheme.Priority {
        collegePersistence.careerPriority(for: job)
    }

    private var priorityStyle: CareerKanbanTheme.PillStyle {
        CareerKanbanTheme.priorityPill(priority)
    }

    private var priorityLabel: String {
        switch priority {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    private var paneBackground: Color {
        DesignSystem.Colors.bgMain
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: {
                let text = (job.jobDescriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return job.jobDescriptionText ?? "" }
                return job.jobDescriptionHTML ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                job.jobDescriptionText = trimmed.isEmpty ? nil : newValue
                job.jobDescriptionHTML = nil
                job.updatedAt = Date()
                collegePersistence.save()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    LazyVGrid(columns: grid2, spacing: 12) {
                        JobInspectorInfoCard(
                            icon: "mappin.and.ellipse",
                            title: "Location",
                            value: displayLocation
                        )
                        JobInspectorInfoCard(
                            icon: "dollarsign.circle",
                            title: "Compensation",
                            value: displayCompensation,
                            valueColor: displayCompensation == "—" ? .primary : CareerKanbanTheme.payGreen
                        )
                        JobInspectorInfoCard(
                            icon: "clock",
                            title: "Saved",
                            value: savedRelativeCaption
                        )
                        JobInspectorInfoCard(
                            icon: "calendar",
                            title: "Deadline",
                            value: deadlineValueText,
                            valueColor: hasDeadline ? DesignSystem.Colors.error.opacity(0.95) : .primary,
                            titleColor: hasDeadline ? DesignSystem.Colors.error.opacity(0.95) : .secondary
                        )
                    }

                    skillsSection

                    notesSection

                    moveToStageSection
                }
                .padding(24)
            }

            Divider()
                .opacity(0.45)

            footerActionBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(paneBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paneBackground)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(laneAccent)
                        .frame(width: 48, height: 48)
                    Text((job.company ?? "").careerCompanyInitials())
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(laneAccent)
                            .frame(width: 6, height: 6)
                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(laneAccent)
                    }

                    Text(job.title ?? "Role")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text((job.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Company" : (job.company ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        cyclePriority()
                    } label: {
                        Text(priorityLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(priorityStyle.foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(priorityStyle.background, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(priorityStyle.stroke, lineWidth: priorityStyle.stroke == .clear ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel("Priority \(priorityLabel), tap to change")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: 28, height: 28)
            }

            Button {
                persistAndDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Close")
        }
    }

    private func cyclePriority() {
        let next: CareerKanbanTheme.Priority
        switch priority {
        case .low: next = .medium
        case .medium: next = .high
        case .high: next = .low
        }
        collegePersistence.setCareerPriority(next, for: job)
    }

    // MARK: Stats

    private var displayLocation: String {
        let t = (job.locationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }

    private var displayCompensation: String {
        let t = (job.baseSalaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }

    private var savedRelativeCaption: String {
        guard let created = job.createdAt else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: created, relativeTo: Date())
    }

    private var deadlineValueText: String {
        guard let d = job.applicationDeadline else { return "—" }
        return Self.deadlineFormatter.string(from: d)
    }

    private var hasDeadline: Bool {
        job.applicationDeadline != nil
    }

    // MARK: Skills

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skills & Tags")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            let tags = JobInspectorKeywordParser.keywords(from: job.extractedKeywordsJSON)
            if tags.isEmpty {
                Text("No tags yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                JobInspectorFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        keywordPill(tag)
                    }
                }
            }
        }
    }

    private func keywordPill(_ text: String) -> some View {
        let style = CareerKanbanTheme.keywordPill(for: status)
        return Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(style.background, in: Capsule())
            .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 1))
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.caption.weight(.bold))
                Text("Notes")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.brown.opacity(0.75))

            TextEditor(text: notesBinding)
                .font(.callout)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
                )
        }
    }

    // MARK: Move to stage

    private var moveToStageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Move to stage")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("+ Edit") {
                    openEditApplication()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: stageGrid, spacing: 8) {
                ForEach(CareerApplicationStatus.allCases, id: \.self) { st in
                    stageButton(st)
                }
            }
        }
    }

    private func stageButton(_ target: CareerApplicationStatus) -> some View {
        let accent = CareerKanbanTheme.laneAccent(for: target)
        let isActive = job.statusRaw == target.rawValue
        return Button {
            collegePersistence.moveCareerApplication(id: job.id, to: target)
            CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                Text(target.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Color.white : accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? accent : CareerKanbanTheme.laneSurface(for: target))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isActive ? Color.black : accent.opacity(0.55),
                        lineWidth: isActive ? 3 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footerActionBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                collegePersistence.deleteCareerApplication(job)
                selectedJobID = nil
                CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.06), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
            )

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    openEditApplication()
                } label: {
                    Text("+ Edit Role")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    persistAndDismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.11), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func openEditApplication() {
        NotificationCenter.default.post(name: .careerOpenEditApplication, object: job.objectID)
    }

    private func persistAndDismiss() {
        saveContextLight()
        selectedJobID = nil
    }

    private func saveContextLight() {
        collegePersistence.save()
    }
}
