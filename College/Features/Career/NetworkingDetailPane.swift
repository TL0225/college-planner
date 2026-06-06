// NetworkingDetailPane.swift
// Feature: Career
// Purpose: Career module — ContactAvatarView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

// MARK: - Avatar

struct ContactAvatarView: View {
    @Bindable var contact: RecruiterContact

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 48, height: 48)
            .overlay {
                Text(initials(from: contact.fullName ?? ""))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).map { String($0.prefix(1)).uppercased() }
        return parts.isEmpty ? "?" : parts.joined()
    }
}

// MARK: - Metric tile (inspector grid)

struct NetworkingInspectorMetricCard: View {
    let title: String
    let value: String
    var isAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isAlert ? Color.red.opacity(0.92) : .secondary)
            Text(value)
                .font(isAlert ? .headline.weight(.bold) : .headline.weight(.medium))
                .foregroundStyle(isAlert ? Color.red : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Timeline

private struct NetworkingTimelineRowContent: Identifiable {
    let id: String
    let icon: String
    let iconTint: Color
    let circleTint: Color
    let title: String
    let dateLabel: String
    let summary: String
}

private struct NetworkingTimelineRow: View {
    let row: NetworkingTimelineRowContent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: row.icon)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundStyle(row.iconTint)
                    .frame(width: 28, height: 28)
                    .background(row.circleTint.opacity(0.18), in: Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 2)
                        .frame(height: 32)
                        .padding(.top, 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                    Text(row.dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(row.summary)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Networking detail (trailing inspector)

@MainActor
struct NetworkingDetailPane: View {
    @Environment(AppContainer.self) private var container
    @Bindable var contact: RecruiterContact
    @Binding var selectedContactID: UUID?
    @Binding var selectedJobID: UUID?

    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) private var dismiss

    @State private var showingLogInteractionSheet = false

    /// Purple capsule tint for role kind (aligned with networking mock).
    private static let roleTagForeground = Color(red: 0.38, green: 0.22, blue: 0.58)

    private var paneBackground: Color {
        DesignSystem.Colors.bgMain
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerSection

                    metricRowSection

                    notesSection

                    linkedApplicationsSection

                    interactionHistorySection
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
        .sheet(isPresented: $showingLogInteractionSheet) {
            LogInteractionSheet(contact: contact)
        }
    }

    // MARK: Header

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 16) {
                ContactAvatarView(contact: contact)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayNameLine)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if contact.isFavorite {
                            Button {
                                contact.isFavorite = false
                                saveContextLight()
                            } label: {
                                ZStack {
                                    Image(systemName: "star.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .scaleEffect(1.18)
                                    Image(systemName: "star.fill")
                                        .font(.title3)
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove favorite")
                        } else {
                            Button {
                                contact.isFavorite = true
                                saveContextLight()
                            } label: {
                                Image(systemName: "star")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(.tertiary.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mark favorite")
                        }
                    }

                    Text(roleAndCompanyLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(contactKindCapsuleTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Self.roleTagForeground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.12), in: Capsule(style: .continuous))

                        Text(viaLinkedInLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Reserve space matching close control so wrapping text aligns with mock proportions.
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

    private var displayNameLine: String {
        let trimmed = contact.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private var roleAndCompanyLine: String {
        let role = contact.roleTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let company = contact.displayCompanyName ?? "Company"
        if role.isEmpty { return company }
        return "\(role) · \(company)"
    }

    private var viaLinkedInLine: String {
        let raw = contact.lastInteractionChannelRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let channel = raw.isEmpty ? "LinkedIn" : raw
        return "via \(channel)"
    }

    private var contactKindCapsuleTitle: String {
        let raw = contact.contactKindRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Recruiter" : raw
    }

    // MARK: Metrics

    private var metricRowSection: some View {
        HStack(spacing: 12) {
            NetworkingInspectorMetricCard(title: "Last Contact", value: lastContactDisplay)
            NetworkingInspectorMetricCard(
                title: "Follow Up",
                value: followUpValueDisplay,
                isAlert: followUpIsOverdue
            )
            NetworkingInspectorMetricCard(title: "Touchpoints", value: "\(touchpointsCount)")
        }
    }

    private var lastContactDisplay: String {
        guard let d = contact.lastContactedAt ?? contact.lastInteractionDetailedAt else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: d, relativeTo: Date())
    }

    private var followUpIsOverdue: Bool {
        guard let last = contact.lastContactedAt ?? contact.lastInteractionDetailedAt else { return false }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: Date()) else { return false }
        return last < cutoff
    }

    private var followUpValueDisplay: String {
        followUpIsOverdue ? "Overdue" : "On track"
    }

    private var touchpointsCount: Int {
        let merged = mergedCareerEvents()
        if !merged.isEmpty { return merged.count }
        let note = contact.lastInteractionSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !note.isEmpty { return 1 }
        if contact.lastContactedAt != nil || contact.lastInteractionDetailedAt != nil { return 1 }
        return 0
    }

    /// Application-scoped events plus contact-scoped networking events (deduped).
    private func mergedCareerEvents() -> [CareerEvent] {
        var byID: [UUID: CareerEvent] = [:]
        if let app = contact.application, let raw = app.events {
            for event in raw { byID[event.id] = event }
        }
        if let raw = contact.networkingEvents {
            for event in raw { byID[event.id] = event }
        }
        return byID.values.sorted {
            ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brown.opacity(0.78))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.orange.opacity(0.82))
                    .padding(.top, 5)

                TextEditor(text: notesBinding)
                    .font(.callout)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 2)
            }
            .padding(14)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { contact.lastInteractionSummary ?? "" },
            set: { newValue in
                contact.lastInteractionSummary = newValue
                contact.lastInteractionDetailedAt = Date()
            }
        )
    }

    // MARK: Linked applications

    private var linkedApplicationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Linked Applications")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let app = contact.application {
                Button {
                    selectedJobID = app.id
                    NotificationCenter.default.post(name: .careerOpenBoardJob, object: app.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "briefcase.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(linkedApplicationCaption(for: app))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("No linked applications yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func linkedApplicationCaption(for app: JobApplication) -> String {
        let company = (app.company ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (app.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch (company.isEmpty, title.isEmpty) {
        case (true, true): return "Untitled Role"
        case (false, true): return company
        case (true, false): return title
        default: return "\(company) \(title)"
        }
    }

    // MARK: Interaction history

    private var interactionHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Interaction History")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("+ Log") {
                    showingLogInteractionSheet = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            }

            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(timelineRows.enumerated()), id: \.element.id) { idx, row in
                    NetworkingTimelineRow(
                        row: row,
                        isLast: idx == timelineRows.count - 1
                    )
                }
            }
        }
    }

    private var timelineRows: [NetworkingTimelineRowContent] {
        buildTimelineRows()
    }

    private func buildTimelineRows() -> [NetworkingTimelineRowContent] {
        var rows: [NetworkingTimelineRowContent] = []

        let merged = mergedCareerEvents()
        if !merged.isEmpty {
            for event in merged {
                let oid = event.objectID.uuidString
                let kind = (event.kindRaw ?? "").lowercased()
                let tints = timelineTints(for: kind)
                rows.append(
                    NetworkingTimelineRowContent(
                        id: "event-\(oid)",
                        icon: timelineIcon(for: kind),
                        iconTint: tints.icon,
                        circleTint: tints.circle,
                        title: timelineTitle(for: kind, fallback: event.title),
                        dateLabel: shortTimelineDate(event.date ?? .distantPast),
                        summary: timelineSummary(for: event)
                    )
                )
            }
            return rows
        }

        if let last = contact.lastInteractionDetailedAt ?? contact.lastContactedAt {
            let via = connectedViaLowercased
            let isPhone = via.contains("phone") || via.contains("call") || via.contains("text")
            rows.append(
                NetworkingTimelineRowContent(
                    id: "contact-roll-\(last.timeIntervalSince1970)",
                    icon: isPhone ? "phone.fill" : "envelope.fill",
                    iconTint: isPhone ? .orange : .blue,
                    circleTint: isPhone ? .orange : .blue,
                    title: isPhone ? "Call" : "Email",
                    dateLabel: shortTimelineDate(last),
                    summary: {
                        let t = contact.lastInteractionSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return t.isEmpty ? "No details captured yet." : t
                    }()
                )
            )
            return rows
        }

        rows.append(
            NetworkingTimelineRowContent(
                id: "placeholder",
                icon: "person.crop.circle",
                iconTint: .secondary,
                circleTint: .blue,
                title: "Get started",
                dateLabel: "—",
                summary: "Log an interaction using + Log or \"+ Log Interaction\" below."
            )
        )

        return rows
    }

    private var connectedViaLowercased: String {
        (contact.lastInteractionChannelRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func timelineTints(for kind: String) -> (icon: Color, circle: Color) {
        if kind.contains("coffee") { return (.brown, Color.orange.opacity(0.85)) }
        if kind.contains("email") || kind.contains("mail") { return (.blue, .blue) }
        if kind.contains("phone") || kind.contains("call") { return (.green, .green) }
        if kind.contains("linkedin") { return (.cyan, .blue) }
        if kind.contains("referral") { return (.purple, .purple) }
        if kind.contains("inperson") || kind.contains("in_person") || kind.contains("person") {
            return (.indigo, .indigo)
        }
        return (.blue, .blue)
    }

    private func timelineIcon(for kind: String) -> String {
        if kind.contains("coffee") { return "cup.and.saucer.fill" }
        if kind.contains("phone") || kind.contains("call") { return "phone.fill" }
        if kind.contains("email") || kind.contains("mail") { return "envelope.fill" }
        if kind.contains("linkedin") { return "arrow.up.right.square.fill" }
        if kind.contains("referral") { return "paperplane.fill" }
        if kind.contains("inperson") || kind.contains("in_person") { return "person.2.fill" }
        if kind.contains("interview") { return "person.2.fill" }
        return "calendar"
    }

    private func timelineTitle(for kind: String, fallback: String?) -> String {
        if let fallback {
            let t = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if kind.contains("coffee") { return "Coffee Chat" }
        if kind.contains("phone") || kind.contains("call") { return "Call" }
        if kind.contains("email") || kind.contains("mail") { return "Email" }
        if kind.contains("linkedin") { return "LinkedIn" }
        if kind.contains("referral") { return "Referral" }
        if kind.contains("inperson") || kind.contains("in_person") { return "In Person" }
        if kind.contains("interview") { return "Interview" }
        return "Event"
    }

    private func timelineSummary(for event: CareerEvent) -> String {
        let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? "No notes captured." : notes
    }

    private func shortTimelineDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: Footer

    private var footerActionBar: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                try? persistence.careerRepository.deleteRecruiterContact(contact)
                saveContextLight()
                selectedContactID = nil
                dismiss()
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
                    showingLogInteractionSheet = true
                } label: {
                    Text("+ Log Interaction")
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

    // MARK: Persistence

    private func persistAndDismiss() {
        saveContextLight()
        selectedContactID = nil
        dismiss()
    }

    private func saveContextLight() {
        persistence.save()
    }
}
