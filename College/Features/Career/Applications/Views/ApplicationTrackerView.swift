// ApplicationTrackerView.swift
// Feature: Career / Applications
// Purpose: Kanban/list view for tracking job applications through the pipeline.

import SwiftUI
import AppKit
import CollegeCareer

private enum CareerRelativeFormatting {
    static func localized(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ApplicationTrackerView: View {
    @Environment(AppContainer.self) private var appContainer
        private var collegePersistence: CollegePersistence { appContainer.persistence }
    @State private var applications: [JobApplication] = []

    @Binding var selectedJobID: UUID?
    let boardLayout: CareerBoardLayout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false
    @AppStorage("career.board.quickAddEnabled") private var quickAddEnabled = true
    @AppStorage("career.board.keyboardNavigation") private var keyboardNavigationEnabled = true
    @State private var emphasizedStage: CareerApplicationStatus?
    private let laneSpacing: CGFloat = 8
    /// Minimum lane width before the board falls back to horizontal scrolling.
    private let minLaneWidth: CGFloat = 220
    private let boardInspectorWidth: CGFloat = 380

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    private var pipelineMetrics: CollegePersistence.CareerPipelineMetrics {
        CareerReadBridge.pipelineMetrics()
    }

    private var selectedBoardJob: JobApplication? {
        guard let selectedJobID else { return nil }
        return applications.first { $0.id == selectedJobID }
            ?? collegePersistence.jobApplication(id: selectedJobID)
    }

    private func reloadApplications() {
        applications = CareerReadBridge.careerApplications()
    }

    var body: some View {
        CareerTrailingInspectorLayout(
            isInspectorPresented: Binding(
                get: { selectedJobID != nil },
                set: { if !$0 { selectedJobID = nil } }
            ),
            inspectorWidth: boardInspectorWidth,
            reduceMotion: motionReduced
        ) {
            VStack(spacing: 0) {
                CareerFunnelHeaderView(
                    appliedCount: pipelineMetrics.totalApplied,
                    interviewCount: pipelineMetrics.interviews,
                    offerCount: pipelineMetrics.offers
                )

                Divider()
                    .opacity(0.35)

                boardContentSlot
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        } inspector: {
            if let job = selectedBoardJob {
                JobInspectorSidebar(job: job, selectedJobID: $selectedJobID)
                    }
        }
        .onMoveCommand { direction in
            guard boardLayout == .kanban, keyboardNavigationEnabled else { return }
            handleMoveCommand(direction)
        }
        .onAppear {
            reloadApplications()
            registerCareerRouterHandlers()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in reloadApplications() }
        .background {
            CareerQueryHost {
                reloadApplications()
            }
        }
        .onChange(of: applications.count) { _, _ in
            validateSelectionStillExists()
        }
        .onChange(of: selectedJobID) { _, _ in
            validateSelectionStillExists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerOpenInspectorSelection)) { _ in
            guard selectedJobID == nil, let first = applications.first?.id else { return }
            selectedJobID = first
        }
    }

    private func registerCareerRouterHandlers() {
        appContainer.careerNavigationRouter.filterApplicationsByStage = { stage in
            withAnimation(DesignSystem.Motion.standardOrNone(reduceMotion: motionReduced) ?? .easeOut(duration: 0.12)) {
                emphasizedStage = stage
            }
            let laneItems = filtered(for: stage)
            selectedJobID = laneItems.first?.id
        }
    }

    @ViewBuilder
    private var boardContentSlot: some View {
        Group {
            switch boardLayout {
            case .kanban:
                kanbanBoardContent
            case .list:
                GeometryReader { proxy in
                    CareerApplicationsListView(
                        applications: Array(applications),
                        selectedJobID: $selectedJobID,
                        reduceMotion: motionReduced
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { selectedJobID = nil }
                    )
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.bgMain)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: boardLayout)
    }

    @ViewBuilder
    private var kanbanBoardContent: some View {
        GeometryReader { proxy in
                let columnCount = CGFloat(CareerApplicationStatus.allCases.count)
                let horizontalPadding: CGFloat = 32
                let gapTotal = laneSpacing * max(0, columnCount - 1)
                let availableWidth = max(0, proxy.size.width - horizontalPadding - gapTotal)
                let equalLaneWidth = availableWidth / columnCount
                let needsHorizontalScroll = equalLaneWidth < minLaneWidth
                let laneWidth = needsHorizontalScroll ? minLaneWidth : equalLaneWidth

                Group {
                    if needsHorizontalScroll {
                        ScrollView(.horizontal, showsIndicators: false) {
                            kanbanLaneRow(laneWidth: laneWidth)
                                .padding(.horizontal, 16)
                        }
                    } else {
                        kanbanLaneRow(laneWidth: laneWidth)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedJobID = nil
                        }
                )
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
    }

    private func kanbanLaneRow(laneWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: laneSpacing) {
            ForEach(CareerApplicationStatus.allCases, id: \.self) { status in
                laneColumn(for: status, width: laneWidth)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func laneColumn(for status: CareerApplicationStatus, width: CGFloat) -> some View {
        let laneItems = filtered(for: status)
        return CareerLaneColumn(
            status: status,
            items: laneItems,
            selectedJobID: $selectedJobID,
            showQuickAdd: quickAddEnabled && status == .interested,
            isEmphasized: emphasizedStage == status
        )
        .frame(width: width)
    }

    private func filtered(for status: CareerApplicationStatus) -> [JobApplication] {
        applications
            .filter { $0.statusRaw == status.rawValue }
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard let currentID = selectedJobID,
              let current = applications.first(where: { $0.id == currentID }),
              let currentStatus = CareerApplicationStatus(rawValue: current.statusRaw)
        else { return }

        let laneItems = filtered(for: currentStatus)
        guard let currentIndex = laneItems.firstIndex(where: { $0.id == currentID }) else { return }

        switch direction {
        case .up:
            let nextIndex = max(0, currentIndex - 1)
            selectedJobID = laneItems[nextIndex].id
        case .down:
            let nextIndex = min(laneItems.count - 1, currentIndex + 1)
            selectedJobID = laneItems[nextIndex].id
        case .left, .right:
            let all = CareerApplicationStatus.allCases
            guard let statusIndex = all.firstIndex(of: currentStatus) else { return }
            let offset = direction == .left ? -1 : 1
            var target = statusIndex + offset
            while target >= 0 && target < all.count {
                let targetStatus = all[target]
                let targetItems = filtered(for: targetStatus)
                if !targetItems.isEmpty {
                    selectedJobID = targetItems[min(currentIndex, targetItems.count - 1)].id
                    return
                }
                target += offset
            }
        @unknown default:
            break
        }
    }

    private func validateSelectionStillExists() {
        guard let selectedJobID else { return }
        let exists = applications.contains { $0.id == selectedJobID }
        if !exists {
            self.selectedJobID = nil
        }
    }
}

private struct CareerLaneColumn: View {
    @Environment(AppContainer.self) private var appContainer
        private var collegePersistence: CollegePersistence { appContainer.persistence }
        let status: CareerApplicationStatus
    let items: [JobApplication]
    @Binding var selectedJobID: UUID?
    let showQuickAdd: Bool
    var isEmphasized: Bool = false
    @State private var isDropTarget = false
    @State private var quickAddCompany = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if showQuickAdd {
                        quickAddRow
                            .accessibilityIdentifier("career.tracker.quickAdd.\(status.rawValue)")
                    }

                    ForEach(items, id: \.id) { item in
                        let dragID = dragIDEnsuringPersistence(for: item)
                        let card = CareerCardView(item: item, isSelected: selectedJobID == item.id)
                            .onTapGesture(count: 2) {
                                appContainer.careerNavigationRouter.editApplication(id: item.id)
                            }
                            .onTapGesture(count: 1) { selectedJobID = item.id }
                        card.draggable(dragID.uuidString)
                    }

                    addRoleFooter
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isEmphasized ? CareerKanbanTheme.laneAccent(for: status).opacity(0.55) :
                        (isDropTarget ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08)),
                    lineWidth: isEmphasized ? 2 : 1
                )
                .animation(.easeInOut(duration: 0.14), value: isDropTarget)
                .animation(DesignSystem.Motion.cardHover, value: isEmphasized)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isDropTarget ? Color.accentColor.opacity(0.08) : Color.clear)
                .animation(.easeInOut(duration: 0.14), value: isDropTarget)
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard let firstStr = payloads.first, let id = UUID(uuidString: firstStr) else { return false }
            let previousStatus = collegePersistence.jobApplication(id: id)
                .flatMap { CareerApplicationStatus(rawValue: $0.statusRaw) } ?? .interested
            AppUndoCoordinator.shared.performUndoable(
                label: "Move Application",
                forward: { collegePersistence.moveCareerApplication(id: id, to: status) },
                backward: { collegePersistence.moveCareerApplication(id: id, to: previousStatus) }
            )
            CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
            return true
        } isTargeted: { target in
            isDropTarget = target
        }
    }

    private var header: some View {
        Button {
            appContainer.careerNavigationRouter.filterByStage(status)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(CareerKanbanTheme.laneAccent(for: status))
                    .frame(width: 9, height: 9)

                Text(status.displayName)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                Text("\(items.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.45), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.displayName), \(items.count) roles")
        .accessibilityIdentifier("career.tracker.lane.\(status.rawValue)")
    }

    private var quickAddRow: some View {
        CareerQuickAddTextField(text: $quickAddCompany) {
            let value = quickAddCompany.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            let row = collegePersistence.quickAddCareerInterested(companyName: value)
            selectedJobID = row.id
        }
    }

    private var addRoleFooter: some View {
        Button {
            appContainer.careerNavigationRouter.addApplication()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                Text("Add role", comment: "Career board footer button to add a new job application")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.primary.opacity(0.18))
        )
        .accessibilityLabel("Add role")
        .accessibilityHint("Add a new job application in \(status.displayName)")
        .accessibilityIdentifier("career.tracker.addRole.\(status.rawValue)")
    }

    private func dragIDEnsuringPersistence(for item: JobApplication) -> UUID {
        item.id
    }
}

private struct CareerCardView: View {
    @Environment(AppContainer.self) private var appContainer
        private var collegePersistence: CollegePersistence { appContainer.persistence }
    let item: JobApplication
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topAccentBar

            HStack(alignment: .top, spacing: 10) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(roleTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(companyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                priorityChip
            }

            if !locationLine.isEmpty || !payLine.isEmpty {
                HStack(spacing: 10) {
                    if !locationLine.isEmpty {
                        Label(locationLine, systemImage: "mappin.and.ellipse")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    if !payLine.isEmpty {
                        Label(payLine, systemImage: "dollarsign.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(CareerKanbanTheme.payGreen)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }

            keywordPillsRow

            footerRow
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(CareerKanbanTheme.cardBackground)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.primary.opacity(0.22) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1.25 : 0.75
                )
        )
        .contentShape(Rectangle())
        .collegeInteractiveSurface(.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("career.tracker.card.\(item.id.uuidString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .careerApplicationContextMenu(for: item, persistence: collegePersistence)
    }

    private var status: CareerApplicationStatus {
        CareerApplicationPresentation.status(for: item)
    }

    private var roleTitle: String {
        CareerApplicationPresentation.roleTitle(for: item)
    }

    private var companyName: String {
        CareerApplicationPresentation.companyName(for: item)
    }

    private var locationLine: String {
        CareerApplicationPresentation.locationLine(for: item)
    }

    private var payLine: String {
        (item.baseSalaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var topAccentBar: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(CareerKanbanTheme.laneAccent(for: status))
            .frame(height: 5)
            .padding(.top, 2)
    }

    private var avatar: some View {
        let initials = CareerApplicationPresentation.companyInitials(companyName)
        let brand = CareerApplicationPresentation.brandColor(for: item)
        return ZStack {
            Circle()
                .fill(brand.opacity(0.16))
            Text(initials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(brand.opacity(0.9))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private var priorityChip: some View {
        let p = priority
        let style = CareerKanbanTheme.priorityPill(p)
        let label: String = switch p {
        case .high: "High"
        case .medium: "Med"
        case .low: "Low"
        }
        return Menu {
            ForEach(CareerKanbanTheme.Priority.allCases, id: \.self) { option in
                Button {
                    collegePersistence.setCareerPriority(option, for: item)
                } label: {
                    if option == p {
                        Label(CareerApplicationPresentation.priorityLabel(option), systemImage: "checkmark")
                    } else {
                        Text(CareerApplicationPresentation.priorityLabel(option))
                    }
                }
            }
        } label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(style.foreground)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(style.background, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(style.stroke, lineWidth: style.stroke == .clear ? 0 : 1)
                )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Priority \(label)")
        .accessibilityHint("Change priority")
        .accessibilityIdentifier("career.tracker.priority.\(item.id.uuidString)")
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            if let applied = item.dateApplied {
                Label(CareerRelativeFormatting.localized(applied), systemImage: "clock")
                    .labelStyle(.titleAndIcon)
            } else if let updated = item.updatedAt {
                Label(CareerRelativeFormatting.localized(updated), systemImage: "clock")
                    .labelStyle(.titleAndIcon)
            }

            if let overdueText {
                Text(overdueText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
            } else if let staleText {
                Text(staleText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.orange.opacity(0.95))
            }

            Spacer(minLength: 0)

            if (item.resumeDisplayName ?? "").isEmpty == false {
                Image(systemName: "doc.fill")
            }
            if (item.postingURLString ?? "").isEmpty == false {
                Image(systemName: "link")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var overdueText: String? {
        guard let deadline = item.applicationDeadline else { return nil }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        guard deadline < startOfToday else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: deadline), to: startOfToday).day ?? 0
        return days <= 0 ? "Overdue" : "Overdue \(days)d"
    }

    private var staleText: String? {
        guard overdueText == nil else { return nil }
        guard let changed = item.lastStatusChangeAt ?? item.updatedAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: changed), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        guard days >= 10 else { return nil }
        return days >= 21 ? "Stale \(days)d" : "Needs touch \(days)d"
    }

    private var keywordPillsRow: some View {
        let keywords = extractedKeywords(limit: 3)
        let overflow = extractedKeywordsOverflowCount(limit: 3)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(keywords, id: \.self) { word in
                    keywordPill(word)
                }
                if overflow > 0 {
                    keywordOverflowPill(overflow)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(keywords, id: \.self) { word in
                    keywordPill(word)
                }
                if overflow > 0 {
                    keywordOverflowPill(overflow)
                }
            }
        }
    }

    private func keywordPill(_ text: String) -> some View {
        let style = CareerKanbanTheme.keywordPill(for: status)
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(style.foreground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.background, in: Capsule())
            .overlay(Capsule().strokeBorder(style.stroke, lineWidth: 1))
    }

    private func keywordOverflowPill(_ count: Int) -> some View {
        Text("+\(count)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.12), lineWidth: 1))
    }

    private var priority: CareerKanbanTheme.Priority {
        collegePersistence.careerPriority(for: item)
    }

    private func extractedKeywords(limit: Int) -> [String] {
        CareerApplicationPresentation.keywords(from: item, limit: limit)
    }

    private func extractedKeywordsOverflowCount(limit: Int) -> Int {
        CareerApplicationPresentation.keywordsOverflowCount(from: item, limit: limit)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append(roleTitle)
        parts.append(companyName)
        if !locationLine.isEmpty { parts.append("Location \(locationLine)") }
        if !payLine.isEmpty { parts.append("Pay \(payLine)") }
        if let overdueText { parts.append(overdueText) }
        return parts.joined(separator: ", ")
    }
}

/// Lightweight horizontal capsule row for Kanban meta tags.
private struct FlowCapsuleMetaRow: View {
    enum CapsuleKind: Hashable {
        case location
        case compensation
        case interview
    }

    let labels: [(CapsuleKind, String)]

    var body: some View {
        if labels.isEmpty {
            EmptyView()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(labels, id: \.0) { pair in
                        capsule(kind: pair.0, body: pair.1)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(labels, id: \.0) { pair in
                        capsule(kind: pair.0, body: pair.1)
                    }
                }
            }
        }
    }

    private func capsule(kind: CapsuleKind, body: String) -> some View {
        let title: String
        switch kind {
        case .location: title = "Location"
        case .compensation: title = "Comp"
        case .interview: title = "Interview"
        }
        return Text("\(title): \(body)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.12), in: Capsule())
    }
}

