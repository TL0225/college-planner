// NetworkingTrackerView.swift
// Feature: Career / Networking
// Purpose: Networking contacts tracker in the Career workspace.

// Feature: Career
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import CollegeCareer

struct NetworkingTrackerView: View {
    @Environment(AppContainer.self) private var appContainer
        private var collegePersistence: CollegePersistence { appContainer.persistence }
    @Binding var selectedJobID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    @State private var store: NetworkingFollowUpStore?
    @State private var networkingKPIs: CollegePersistence.CareerNetworkingKPIs = .zero
    @State private var contactFilter: NetworkingContactFilter = .all
    @State private var showAddContactSheet: Bool = false
    @State private var selectedContactID: UUID?
    /// Bumps when local store merges so LazyVGrid repopulates immediately (fixes stale All-tab list).
    @State private var networkingGridEpoch = 0

    private let networkingInspectorWidth: CGFloat = 380
    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                networkingFilterRow
                Spacer()
                networkingPrimaryHeader
            }
                .padding(.bottom, 16)

            if let store {
                CareerTrailingInspectorLayout(
                    isInspectorPresented: Binding(
                        get: { selectedContactID != nil },
                        set: { if !$0 { selectedContactID = nil } }
                    ),
                    inspectorWidth: networkingInspectorWidth,
                    reduceMotion: motionReduced
                ) {
                    networkingContactGrid(store: store)
                } inspector: {
                    if let selectedContactID,
                       let contact = collegePersistence.recruiterContact(id: selectedContactID) {
                        NetworkingDetailPane(
                            contact: contact,
                            selectedContactID: $selectedContactID,
                            selectedJobID: $selectedJobID
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: store.items) { _, _ in
                    networkingGridEpoch &+= 1
                    refreshNetworkingKPIs()
                    // Only orphan contacts appear in `store.items` as `.contact`. Linked contacts are omitted
                    // (see NetworkingFollowUpStore contacts predicate), so never clear selection just because
                    // the chosen contact isn’t in the grid list.
                    guard let id = selectedContactID,
                          let person = collegePersistence.recruiterContact(id: id)
                    else { return }
                    if person.application != nil { return }
                    if !store.items.contains(.contact(id)) {
                        self.selectedContactID = nil
                    }
                }
                .onChange(of: selectedContactID) { _, newID in
                    guard let newID else { return }
                    if collegePersistence.recruiterContact(id: newID) == nil {
                        selectedContactID = nil
                    }
                }
            } else {
                ProgressView("Loading networking…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        store = NetworkingFollowUpStore()
                        refreshNetworkingKPIs()
                    }
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .background(DesignSystem.Colors.bgMain)
        .onAppear { refreshNetworkingKPIs() }
        .sheet(isPresented: $showAddContactSheet) {
            NetworkingAddContactSheet()
                }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            store?.refresh()
            networkingGridEpoch &+= 1
            networkingKPIs = collegePersistence.careerNetworkingKPIs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerToggleInspector)) { _ in
            if selectedContactID != nil || selectedJobID != nil {
                selectedContactID = nil
                selectedJobID = nil
            } else {
                NotificationCenter.default.post(name: .collegeCareerOpenInspectorSelection, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerOpenInspectorSelection)) { _ in
            guard selectedContactID == nil, selectedJobID == nil,
                  let store, let first = filteredNetworkingItems(from: store.items).first
            else { return }
            switch first {
            case .job(let oid):
                selectedJobID = oid
            case .contact(let oid):
                selectedContactID = oid
            }
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 340, maximum: 420), spacing: 16)]

    @ViewBuilder
    private func networkingContactGrid(store: NetworkingFollowUpStore) -> some View {
        let items = filteredNetworkingItems(from: store.items)
        if items.isEmpty {
            networkingEmptyState(hasAnyItems: !store.items.isEmpty)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("\(networkingGridEpoch)-empty")
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        NetworkingPersonCard(
                            item: item,
                            collegePersistence: collegePersistence,
                            onDelete: { deleteNetworkingItem(item, store: store) }
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                switch item {
                                case .job(let oid):
                                    selectedJobID = oid
                                    if let app = collegePersistence.jobApplication(id: oid),
                                       let contactOID = primaryRecruiterContactObjectID(for: app) {
                                        selectedContactID = contactOID
                                    } else {
                                        selectedContactID = nil
                                    }
                                case .contact(let oid):
                                    selectedContactID = oid
                                    if let person = collegePersistence.recruiterContact(id: oid) {
                                        selectedJobID = person.application?.id
                                    }
                                }
                            }
                            .contextMenu {
                                networkingContextMenu(for: item)
                            }
                    }
                    NetworkingAddContactTile {
                        showAddContactSheet = true
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id("\(networkingGridEpoch)-\(store.items.count)")
        }
    }

    @ViewBuilder
    private func networkingEmptyState(hasAnyItems: Bool) -> some View {
        ContentUnavailableView {
            Label(
                hasAnyItems ? "No matching contacts" : "No contacts yet",
                systemImage: hasAnyItems ? "line.3.horizontal.decrease.circle" : "person.2"
            )
        } description: {
            Text(
                hasAnyItems
                    ? "No contacts match the “\(contactFilter.rawValue)” filter."
                    : "Track recruiters, alumni, hiring managers, and peers. Add your first contact to start building your network."
            )
        } actions: {
            Button {
                showAddContactSheet = true
            } label: {
                Text(hasAnyItems ? "Add Contact" : "Add Your First Contact")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func deleteNetworkingItem(_ item: NetworkingFollowUpItem, store _: NetworkingFollowUpStore) {
        switch item {
        case .contact(let oid):
            if selectedContactID == oid { selectedContactID = nil }
            if let contact = collegePersistence.recruiterContact(id: oid) {
                try? collegePersistence.careerRepository.deleteRecruiterContact(contact)
                CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
            }
        case .job(let oid):
            if selectedJobID == oid { selectedJobID = nil }
            guard let app = collegePersistence.jobApplication(id: oid) else { return }
            if let contacts = app.contacts,
               let sid = selectedContactID,
               contacts.contains(where: { $0.id == sid }) {
                selectedContactID = nil
            }
            collegePersistence.deleteCareerApplication(app)
            CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
        }
        networkingGridEpoch &+= 1
    }

    private var networkingPrimaryHeader: some View {
        HStack(spacing: 12) {
            statPill(dot: .blue, label: "Contacts", value: "\(networkingKPIs.contacts)")
            statPill(dot: .orange, label: "Coffee Chats", value: "\(networkingKPIs.coffeeEvents)")
            statPill(dot: .red, label: "Follow-ups", value: "\(networkingKPIs.followUpsQueued)")

            Button("+ Add Contact") {
                showAddContactSheet = true
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.primary, in: Capsule(style: .continuous))
        }
    }

    private func refreshNetworkingKPIs() {
        networkingKPIs = collegePersistence.careerNetworkingKPIs()
    }

    /// Prefer opening the linked recruiter when the user taps a job follow-up card.
    private func primaryRecruiterContactObjectID(for application: JobApplication) -> UUID? {
        guard let raw = application.contacts, !raw.isEmpty else { return nil }
        let sorted = raw.sorted {
            let da = $0.lastInteractionDetailedAt ?? $0.lastContactedAt ?? .distantPast
            let db = $1.lastInteractionDetailedAt ?? $1.lastContactedAt ?? .distantPast
            if da != db { return da > db }
            return ($0.fullName ?? "") < ($1.fullName ?? "")
        }
        return sorted.first?.id
    }

    private var networkingFilterRow: some View {
        HStack(spacing: 4) {
            ForEach(NetworkingContactFilter.allCases) { tab in
                let isSelected = tab == contactFilter
                Button {
                    contactFilter = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(DesignSystem.Colors.surface)
                                    .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.xs)
        .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))
    }

    private func statPill(dot: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: Capsule(style: .continuous))
    }

    private func filteredNetworkingItems(from items: [NetworkingFollowUpItem]) -> [NetworkingFollowUpItem] {
        items.filter(matchesFilter)
    }

    private func matchesFilter(_ item: NetworkingFollowUpItem) -> Bool {
        guard contactFilter != .all else { return true }
        guard case .contact(let oid) = item,
              let person = collegePersistence.recruiterContact(id: oid) else {
            return false
        }

        let role = (person.roleTitle ?? "").lowercased()
        switch contactFilter {
        case .all: return true
        case .recruiters: return role.contains("recruit")
        case .alumni: return role.contains("alumni")
        case .hiringManagers: return role.contains("hiring manager") || role.contains("manager")
        case .peers: return role.contains("peer")
        }
    }

    @ViewBuilder
    private func networkingContextMenu(for item: NetworkingFollowUpItem) -> some View {
        switch item {
        case .job(let oid):
            if let app = collegePersistence.jobApplication(id: oid) {
                Button("Snooze 3 Days") { collegePersistence.snoozeCareerFollowUp(for: app) }
                Button("Follow-up Complete") { collegePersistence.markCareerFollowUpComplete(for: app) }
            }
        case .contact:
            EmptyView()
        }
    }
}

private struct NetworkingPersonCard: View {
    let item: NetworkingFollowUpItem
    let collegePersistence: CollegePersistence
    let onDelete: () -> Void

    var body: some View {
        if let model = cardModel {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(model.accent)
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(model.accent)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text(model.initials)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(model.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.red.opacity(0.92))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete")

                    Image(systemName: model.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(model.isFavorite ? .yellow : .secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.tags, id: \.self) { tag in
                            tagPill(tag)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.tags, id: \.self) { tag in
                            tagPill(tag)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: model.channelSymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.channelLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(model.noteSummary)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                .padding(DesignSystem.Spacing.md)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    Label(model.relativeTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isOverdue {
                        Label("Overdue", systemImage: "calendar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
            .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        } else {
            Text("Missing contact")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private struct CardTag: Hashable {
        let text: String
        let kind: Kind
        enum Kind: Hashable { case company, relationship }
    }

    private struct CardModel {
        let name: String
        let role: String
        let initials: String
        let accent: Color
        let isFavorite: Bool
        let tags: [CardTag]
        let channelSymbol: String
        let channelLine: String
        let noteSummary: String
        let relativeTime: String
        let isOverdue: Bool
    }

    private var cardModel: CardModel? {
        switch item {
        case .contact(let oid):
            guard let person = collegePersistence.recruiterContact(id: oid) else { return nil }
            let name = (person.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? person.fullName! : "Unnamed"
            let role = (person.roleTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? person.roleTitle! : "Contact"
            let company = person.displayCompanyName ?? "No company"
            let anchor = person.lastInteractionDetailedAt ?? person.lastContactedAt ?? .distantPast
            let channelSymbol = (person.email?.isEmpty == false) ? "envelope" : "phone"
            let dateLabel = shortDate(anchor)
            let rel = relationshipLabel(from: role)
            return CardModel(
                name: name,
                role: role,
                initials: initials(from: name),
                accent: accentColor(seed: company + name),
                isFavorite: person.isFavorite,
                tags: [
                    CardTag(text: company, kind: .company),
                    CardTag(text: rel, kind: .relationship)
                ],
                channelSymbol: channelSymbol,
                channelLine: "\(channelSymbol == "envelope" ? "Email" : "Phone") • \(dateLabel)",
                noteSummary: person.lastInteractionSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (person.lastInteractionSummary ?? "")
                    : "No interaction summary yet.",
                relativeTime: relative(anchor),
                isOverdue: isOlderThanDays(anchor, days: 30)
            )
        case .job(let oid):
            guard let app = collegePersistence.jobApplication(id: oid) else { return nil }
            let company = app.company ?? "Company"
            let title = app.title ?? "Role"
            let anchor = app.lastStatusChangeAt ?? app.updatedAt ?? app.createdAt ?? .distantPast
            let deadline = app.applicationDeadline
            return CardModel(
                name: company,
                role: title,
                initials: initials(from: company),
                accent: accentColor(seed: company + title),
                isFavorite: false,
                tags: [
                    CardTag(text: company, kind: .company),
                    CardTag(text: "Follow-up", kind: .relationship)
                ],
                channelSymbol: "envelope",
                channelLine: "Application • \(shortDate(anchor))",
                noteSummary: app.interviewStatus?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (app.interviewStatus ?? "")
                    : "Follow up on this application.",
                relativeTime: relative(anchor),
                isOverdue: (deadline ?? .distantFuture) < Date()
            )
        }
    }

    private func tagPill(_ tag: CardTag) -> some View {
        let fill: Color
        switch tag.kind {
        case .company: fill = cardModel?.accent.opacity(0.14) ?? Color.secondary.opacity(0.1)
        case .relationship: fill = Color.blue.opacity(0.12)
        }
        return Text(tag.text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fill, in: Capsule(style: .continuous))
    }

    private func initials(from name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        return parts.isEmpty ? "?" : parts.joined()
    }

    private func accentColor(seed: String) -> Color {
        let palette: [Color] = [.blue, .red, .green, .orange]
        let idx = abs(seed.hashValue) % palette.count
        return palette[idx]
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private func relationshipLabel(from role: String) -> String {
        let lower = role.lowercased()
        if lower.contains("recruit") { return "Recruiter" }
        if lower.contains("alumni") { return "Alumni" }
        if lower.contains("hiring manager") || lower.contains("manager") { return "Hiring Manager" }
        if lower.contains("peer") { return "Peer" }
        return "Contact"
    }

    private func isOlderThanDays(_ date: Date, days: Int) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return false }
        return date < cutoff
    }
}

private struct NetworkingAddContactTile: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                Text("Add New Contact")
                    .font(.headline)
                Text("Create a networking profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 230)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            )
            .collegeInteractiveSurface(.cta)
        }
        .buttonStyle(.plain)
    }
}

private struct NetworkingHybridFollowUpDetailPane: View {
    @Environment(AppContainer.self) private var appContainer
        @Binding var selection: NetworkingFollowUpItem?
    @Binding var selectedJobID: UUID?
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    @AppStorage("career.networking.outreachDrafts.v1") private var outreachDraftsJSON = "{}"

    @State private var draftText = ""
    @State private var isGenerating = false
    @State private var activityNotes = ""
    @State private var copiedDraft = false
    @State private var contactInteractionNotes = ""

    private var selectedApp: JobApplication? {
        guard let selection,
              case .job(let oid) = selection else { return nil }
        return collegePersistence.jobApplication(id: oid)
    }

    private var selectedContact: RecruiterContact? {
        guard let selection,
              case .contact(let oid) = selection else { return nil }
        return collegePersistence.recruiterContact(id: oid)
    }

    private var draftStorageKey: String? { selection?.id }

    var body: some View {
        Group {
            if let app = selectedApp {
                jobDetail(app)
            } else if let person = selectedContact {
                contactDetail(person)
            } else {
                ContentUnavailableView(
                    "Select an item",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Choose a follow-up application or a standalone contact.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selection?.id) { _, _ in
            isGenerating = false
            copiedDraft = false
            loadDraftFromStorage()
            if let app = selectedApp {
                activityNotes = collegePersistence.careerNetworkingNotes(for: app)
                contactInteractionNotes = ""
            } else if let person = selectedContact {
                activityNotes = ""
                contactInteractionNotes = person.lastInteractionSummary ?? ""
            } else {
                activityNotes = ""
                contactInteractionNotes = ""
                draftText = ""
            }
        }
        .onAppear {
            loadDraftFromStorage()
            if let app = selectedApp {
                activityNotes = collegePersistence.careerNetworkingNotes(for: app)
            } else if let person = selectedContact {
                contactInteractionNotes = person.lastInteractionSummary ?? ""
            }
        }
        .onChange(of: draftText) { _, newValue in
            persistDraftToStorage(newValue)
        }
    }

    @ViewBuilder
    private func jobDetail(_ app: JobApplication) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.title ?? "Role")
                            .font(.title2.weight(.semibold))
                        Text(app.company ?? "Company")
                            .foregroundStyle(.secondary)
                    }

                    timelineSection(for: app)
                    Divider()
                    contactSection(for: app)
                    Divider()
                    Text("Notes & Activity")
                        .font(.headline)
                    TextEditor(text: $activityNotes)
                        .frame(minHeight: 300, maxHeight: .infinity)
                        .padding(DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 11))
                        .onChange(of: activityNotes) { _, newValue in
                            collegePersistence.setCareerNetworkingNotes(newValue, for: app)
                        }

                    if !draftText.isEmpty {
                        draftPreviewBlock
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .frame(maxWidth: 600, alignment: .topLeading)
            }
            Divider()
            HStack {
                Button {
                    Task { await generateJobDraft(for: app) }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Draft outreach", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func contactDetail(_ person: RecruiterContact) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.fullName ?? "Contact")
                            .font(.title2.weight(.semibold))
                        if let company = person.displayCompanyName {
                            Text(company).foregroundStyle(.secondary)
                        }
                        if let email = person.email, !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                        }
                        if let li = person.linkedInURL, !li.isEmpty {
                            Text(li)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Interaction notes")
                        .font(.headline)
                    TextEditor(text: $contactInteractionNotes)
                        .frame(minHeight: 160, maxHeight: 280)
                        .padding(DesignSystem.Spacing.sm)
                        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 11))
                        .onChange(of: contactInteractionNotes) { _, newValue in
                            person.lastInteractionSummary = newValue
                            person.lastInteractionDetailedAt = Date()
                            collegePersistence.save()
                        }

                    if !draftText.isEmpty {
                        draftPreviewBlock
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .frame(maxWidth: 600, alignment: .topLeading)
            }
            Divider()
            HStack {
                Button {
                    Task { await generateContactDraft(for: person) }
                } label: {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Draft outreach", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var draftPreviewBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Draft")
                    .font(.headline)
                Spacer()
                Button(copiedDraft ? "Copied" : "Copy to Clipboard") {
                    copyToPasteboard(draftText)
                    copiedDraft = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        copiedDraft = false
                    }
                }
            }
            Text(draftText)
                .font(.body)
                .textSelection(.enabled)
                .padding(DesignSystem.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func loadDraftFromStorage() {
        guard let key = draftStorageKey else {
            draftText = ""
            return
        }
        draftText = networkingDraftMap()[key] ?? ""
    }

    private func persistDraftToStorage(_ text: String) {
        guard let key = draftStorageKey else { return }
        var map = networkingDraftMap()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = text
        }
        if let data = try? JSONEncoder().encode(map),
           let json = String(data: data, encoding: .utf8) {
            outreachDraftsJSON = json
        }
    }

    private func networkingDraftMap() -> [String: String] {
        guard let data = outreachDraftsJSON.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    private func networkingDetailRelativeCaption(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func timelineSection(for app: JobApplication) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Timeline")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                timelineRow("Applied", app.dateApplied)
                timelineRow("Last touch", app.lastStatusChangeAt)
                timelineRow("Follow-up due", app.applicationDeadline)
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ title: String, _ date: Date?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().frame(width: 8, height: 8).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                if let date {
                    Text(networkingDetailRelativeCaption(for: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func contactSection(for app: JobApplication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recruiters")
                .font(.headline)

            if let raw = app.contacts, !raw.isEmpty {
                let contacts = raw.sorted { ($0.lastContactedAt ?? .distantPast) > ($1.lastContactedAt ?? .distantPast) }

                ForEach(contacts, id: \.id) { person in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.fullName ?? "Contact")
                            .font(.subheadline.weight(.semibold))
                        if let company = person.displayCompanyName {
                            Text(company)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let email = person.email, email.isEmpty == false {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let last = person.lastContactedAt {
                            Text(networkingDetailRelativeCaption(for: last))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No contacts linked yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func generateJobDraft(for application: JobApplication) async {
        isGenerating = true
        let text = await CareerAIService.shared.draftColdOutreach(for: application.id, using: collegePersistence)
        draftText = text ?? ""
        isGenerating = false
    }

    @MainActor
    private func generateContactDraft(for contact: RecruiterContact) async {
        isGenerating = true
        let text = await CareerAIService.shared.draftContactOutreach(for: contact.id, using: collegePersistence)
        draftText = text ?? ""
        isGenerating = false
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private enum NetworkingContactFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case recruiters = "Recruiters"
    case alumni = "Alumni"
    case hiringManagers = "Hiring Managers"
    case peers = "Peers"

    var id: String { rawValue }
}

