// AcademicDegreeTabBar.swift
// Feature: Profile
// Purpose: Profile module — AcademicDegreeTabBar.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import UniformTypeIdentifiers
import CollegeAcademics

// MARK: - Degree scope pill bar

struct AcademicDegreeTabBar: View {
    let profiles: [AcademicProfile]
    @Binding var selectedID: UUID?
    var showOverviewPill: Bool = false
    /// When true, pills are centered in the row (Edit Profile). When false, uses horizontal scroll (Academics toolbar).
    var centersContent: Bool = false
    /// When true, styles controls for `MainWindowToolbar` (native `.buttonStyle(.glass)`).
    var toolbarHosted: Bool = false
    var allowsAdd: Bool = true
    var allowsDelete: Bool = true
    var onAdd: () -> Void
    var onDelete: (AcademicProfile) -> Void
    var onReorder: (([AcademicProfile]) -> Void)?

    @State private var profilePendingDelete: AcademicProfile?
    @State private var draggedProfileID: UUID?

    private var labelMap: [UUID: String] {
        AcademicProfilePresentation.shortLabels(for: profiles)
    }

    var body: some View {
        Group {
            if centersContent {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    pillRow
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    pillRow
                }
            }
        }
        .confirmationDialog(
            String(localized: "academic.profile.delete.confirm.title"),
            isPresented: Binding(
                get: { profilePendingDelete != nil },
                set: { if !$0 { profilePendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: profilePendingDelete
        ) { profile in
            Button(String(localized: "academic.profile.delete.confirm.action"), role: .destructive) {
                onDelete(profile)
                profilePendingDelete = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                profilePendingDelete = nil
            }
        } message: { profile in
            Text(
                String(
                    format: String(localized: "academic.profile.delete.confirm.message"),
                    labelMap[profile.id] ?? ""
                )
            )
        }
    }

    private var pillRow: some View {
        HStack(spacing: 8) {
            if showOverviewPill {
                overviewPill
            }

            ForEach(profiles, id: \.id) { profile in
                degreePill(profile: profile, id: profile.id)
            }

            if allowsAdd && !toolbarHosted {
                addButton
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private var overviewPill: some View {
        pillButton(
            title: String(localized: "academic.profile.scope.overview"),
            isSelected: selectedID == nil,
            accent: .secondary,
            status: .active,
            showsStatusDot: false
        ) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                selectedID = nil
            }
        }
    }

    @ViewBuilder
    private func degreePill(profile: AcademicProfile, id: UUID) -> some View {
        let title = labelMap[id]
            ?? String(format: String(localized: "academic.profile.label.degree_number", defaultValue: "Degree %lld"), 1)
        let isSelected = selectedID == id

        pillButton(
            title: title,
            isSelected: isSelected,
            accent: profile.accentColor,
            status: profile.statusEnum,
            showsStatusDot: true
        ) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                selectedID = id
            }
        }
        .contextMenu {
            if allowsDelete, profiles.count > 1 {
                Button(String(localized: "academic.profile.delete"), role: .destructive) {
                    profilePendingDelete = profile
                }
            }
        }
        .onDrag {
            draggedProfileID = id
            return NSItemProvider(object: id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: AcademicProfileReorderDropDelegate(
            item: profile,
            profiles: profiles,
            draggedID: $draggedProfileID,
            onReorder: { ordered in
                onReorder?(ordered)
            }
        ))
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(ToolbarMetrics.iconFont)
                .frame(width: 28, height: 28)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(String(localized: "academic.profile.add"))
    }

    @ViewBuilder
    private func pillButton(
        title: String,
        isSelected: Bool,
        accent: Color,
        status: AcademicProfileStatus,
        showsStatusDot: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let label = HStack(spacing: 6) {
            Text(title)
                .font(ToolbarMetrics.font(isSelected ? .semibold : .medium))
                .lineLimit(1)

            if showsStatusDot {
                statusDot(status: status, completed: status == .completed)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background {
            Capsule()
                .fill(isSelected ? accent : Color.clear)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    isSelected ? accent.opacity(0.0) : Color.secondary.opacity(0.25),
                    lineWidth: 1
                )
        }

        Button(action: action) { label }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusDot(status: AcademicProfileStatus, completed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)
            if completed {
                Image(systemName: "checkmark")
                    .font(DesignSystem.Fonts.main(size: 5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func statusColor(_ status: AcademicProfileStatus) -> Color {
        switch status {
        case .active: return .green
        case .completed: return .secondary
        case .paused: return .yellow
        case .transferred: return .orange
        }
    }
}

// MARK: - Reorder drop delegate

private struct AcademicProfileReorderDropDelegate: DropDelegate {
    let item: AcademicProfile
    let profiles: [AcademicProfile]
    @Binding var draggedID: UUID?
    let onReorder: ([AcademicProfile]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID, let fromIndex = profiles.firstIndex(where: { $0.id == draggedID }),
              let toIndex = profiles.firstIndex(where: { $0.id == item.id }),
              fromIndex != toIndex else { return }

        var ordered = profiles
        let moved = ordered.remove(at: fromIndex)
        ordered.insert(moved, at: toIndex)
        onReorder(ordered)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

// MARK: - Content transition helper

struct AcademicDegreeContentTransition: ViewModifier {
    let direction: Int

    func body(content: Content) -> some View {
        content
            .transition(
                .asymmetric(
                    insertion: .move(edge: direction >= 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: direction >= 0 ? .leading : .trailing).combined(with: .opacity)
                )
            )
    }
}

extension View {
    func academicDegreeTransition(direction: Int) -> some View {
        modifier(AcademicDegreeContentTransition(direction: direction))
    }
}

// MARK: - Window toolbar profile actions

enum AcademicsToolbarProfileActions {
    @MainActor
    static func addProfile(
        collegePersistence: CollegePersistence,
        academicsScene: AcademicsSceneState
    ) {
        let profiles = AcademicProfileReadBridge.profiles()
        let level = profiles.first(where: { $0.id == academicsScene.selectedAcademicProfileID })?.degreeLevel
            ?? profiles.first?.degreeLevel
            ?? collegePersistence.primaryDegreeLevel(default: DegreeConfiguration.undergraduate)
        if let created = collegePersistence.addAcademicProfile(degreeLevel: level) {
            academicsScene.selectedAcademicProfileID = created.id
        }
    }
}

extension Notification.Name {
    static let selectAcademicProfileForAcademics = Notification.Name("College.selectAcademicProfileForAcademics")
}
