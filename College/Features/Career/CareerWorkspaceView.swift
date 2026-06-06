// CareerWorkspaceView.swift
// Feature: Career
// Purpose: Career module — CareerWorkspaceView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import Quartz
enum CareerSubView: String, CaseIterable, Identifiable, Hashable {
    case board = "Board"
    case openings = "Openings"
    case stats = "Stats"
    case resumes = "Resumes"
    case stories = "Stories"
    case networking = "Networking"

    var id: String { rawValue }
}

struct CareerWorkspaceView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject private var notifications: AppNotificationCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false
    @Environment(AppContainer.self) private var appContainer

    private var careerScene: CareerSceneState { appContainer.careerScene }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    @State private var showAddSheet = false
    @State private var toolbarHandlerToken: ToolbarHandlerToken?
    @State private var editingJobID: UUID?
    @State private var selectedJobID: UUID?
    @AppStorage(CareerBoardLayout.storageKey) private var boardLayoutRaw: String = CareerBoardLayout.kanban.rawValue

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    private var boardLayout: CareerBoardLayout {
        CareerBoardLayout(rawValue: boardLayoutRaw) ?? .kanban
    }

    private var activeSubview: CareerSubView {
        careerScene.selectedView
    }

    private func setActiveSubview(_ view: CareerSubView) {
        careerScene.select(view)
    }

    var body: some View {
        careerSubviewContent
        .background(DesignSystem.Colors.bgMain)
        .sheet(isPresented: $showAddSheet, onDismiss: { editingJobID = nil }) {
            Group {
                if let editingJobID {
                    CareerApplicationFormSheet(existingApplicationID: editingJobID)
                        .environmentObject(collegePersistence)
                } else {
                    AddRoleSheet()
                        .environmentObject(collegePersistence)
                }
            }
        }
        .onAppear {
            registerCareerWindowToolbar()
        }
        .onChange(of: careerScene.selectedView) { _, newValue in
            if newValue == .openings {
                WorkdayJobBoardSyncCoordinator.shared.markOpeningsViewed()
            }
        }
        .onChange(of: boardLayoutRaw) { _, _ in
            careerScene.boardLayout = boardLayout
        }
        .onDisappear {
            careerScene.clearHandlers()
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .careerOpenAddApplication)) { _ in
            editingJobID = nil
            showAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .careerOpenEditApplication)) { note in
            guard let jobID = note.object as? UUID else { return }
            editingJobID = jobID
            showAddSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .careerOpenBoardJob)) { note in
            guard let jobID = note.object as? UUID else { return }
            setActiveSubview(.board)
            selectedJobID = jobID
        }
        .onReceive(NotificationCenter.default.publisher(for: .jobBoardOpenOpenings)) { _ in
            setActiveSubview(.openings)
        }
    }

    @ViewBuilder
    private var careerSubviewContent: some View {
        Group {
            switch activeSubview {
            case .board:
                JobBoardView(
                    selectedJobID: $selectedJobID,
                    boardLayout: boardLayout
                )
            case .openings:
                WorkdayJobBoardView(onNavigateToBoard: { setActiveSubview(.board) })
                    .environmentObject(collegePersistence)
            case .stats:
                CareerStatsView()
                    .environmentObject(collegePersistence)
            case .resumes:
                ResumeManagerView(selectedJobID: $selectedJobID)
            case .stories:
                InterviewPrepView()
            case .networking:
                NetworkingTrackerView(selectedJobID: $selectedJobID)
            }
        }
        .id(activeSubview)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: motionReduced ? 1 : 0.98)))
    }

    private func registerCareerWindowToolbar() {
        careerScene.boardLayout = boardLayout
        careerScene.onBoardLayoutChange = { layout in
            boardLayoutRaw = layout.rawValue
        }
        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = toolbarDispatcher.register(owner: .career) { [self] action in
            guard case .career(let careerAction) = action else { return }
            switch careerAction {
            case .addApplication:
                editingJobID = nil
                showAddSheet = true
            case .copyBoardMarkdown:
                let apps = (try? collegePersistence.careerRepository.fetchApplications(limit: 500)) ?? []
                let md = CareerBoardMarkdownExport.table(from: apps)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(md, forType: .string)
            }
        }
    }
}

private enum CareerRelativeFormatting {
    static func localized(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct JobBoardView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
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
            isInspectorPresented: selectedJobID != nil,
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
                    .environmentObject(collegePersistence)
            }
        }
        .onMoveCommand { direction in
            guard boardLayout == .kanban, keyboardNavigationEnabled else { return }
            handleMoveCommand(direction)
        }
        .onAppear { reloadApplications() }
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
        .onReceive(NotificationCenter.default.publisher(for: .careerFilterByStage)) { note in
            guard let raw = note.userInfo?["status"] as? String,
                  let stage = CareerApplicationStatus(rawValue: raw) else { return }
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
                    .environmentObject(collegePersistence)
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
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject private var notifications: AppNotificationCenter
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
                    }

                    ForEach(items, id: \.id) { item in
                        let dragID = dragIDEnsuringPersistence(for: item)
                        let card = CareerCardView(item: item, isSelected: selectedJobID == item.id)
                            .onTapGesture(count: 2) {
                                NotificationCenter.default.post(name: .careerOpenEditApplication, object: item.id)
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
            collegePersistence.moveCareerApplication(id: id, to: status)
            CareerFollowUpScheduler.shared.reconcile(using: collegePersistence)
            return true
        } isTargeted: { target in
            isDropTarget = target
        }
    }

    private var header: some View {
        Button {
            NotificationCenter.default.post(
                name: .careerFilterByStage,
                object: nil,
                userInfo: ["status": status.rawValue]
            )
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
            NotificationCenter.default.post(name: .careerOpenAddApplication, object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                Text("Add role")
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
    }

    private func dragIDEnsuringPersistence(for item: JobApplication) -> UUID {
        item.id
    }
}

private struct CareerCardView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    let item: JobApplication
    let isSelected: Bool
    @State private var isHovered = false

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
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.86), value: isHovered)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(CareerKanbanTheme.cardBackground)
                .shadow(color: Color.black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 5 : 3, x: 0, y: isHovered ? 2 : 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.primary.opacity(0.22) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 1.25 : 0.75
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
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


private enum ResumeLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case general
    case tailored
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .general: return "General"
        case .tailored: return "Tailored"
        case .archived: return "Archived"
        }
    }
}

struct ResumeManagerView: View {
    @Binding var selectedJobID: UUID?
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @State private var resumes: [VaultDocument] = []
    @State private var showingImporter = false
    @State private var selectedResumeID: UUID?
    @State private var quickLookURL: URL?
    @State private var resumeLibraryFilter: ResumeLibraryFilter = .all
    @State private var isResumeUploadTileHovered = false

    private let resumeGridColumns = [GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 16)]

    var body: some View {
        resumePane
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf, .plainText, .rtf], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    if let doc = try collegePersistence.importCareerResume(from: url) {
                        let id = doc.id
                        selectedResumeID = id
                    }
                } catch { }
            }
        }
        .onAppear {
            reloadResumes()
            validateResumeSelection()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in reloadResumes() }
        .background {
            CareerQueryHost {
                reloadResumes()
            }
        }
        .task {
            _ = collegePersistence.ensureCareerResumesVaultFolder()
        }
        .onChange(of: resumeLibraryFilter) { _, _ in
            validateResumeSelection()
        }
        .onChange(of: resumes.count) { _, _ in
            validateResumeSelection()
        }
        .quickLookPreview($quickLookURL)
    }

    private func reloadResumes() {
        resumes = CareerReadBridge.careerResumeDocuments()
    }

    private func validateResumeSelection() {
        guard let id = selectedResumeID else { return }
        if !filteredResumeDocuments.contains(where: { $0.id == id }) {
            selectedResumeID = filteredResumeDocuments.first?.id
        }
    }

    private var resumeLibraryStats: CollegePersistence.CareerResumeLibraryStats {
        collegePersistence.careerResumeLibraryStats(for: Array(resumes))
    }

    private var filteredResumeDocuments: [VaultDocument] {
        let rows = Array(resumes)
        return rows.filter(resumeLibraryRowMatchesFilter)
    }

    private func resumeLibraryRowMatchesFilter(_ doc: VaultDocument) -> Bool {
        let meta = collegePersistence.careerResumeMetadata(for: doc)
        switch resumeLibraryFilter {
        case .all:
            return true
        case .general:
            return !meta.archived && meta.kind == .general
        case .tailored:
            return !meta.archived && meta.kind == .tailored
        case .archived:
            return meta.archived
        }
    }

    @ViewBuilder
    private var resumePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                resumeLibraryFilterRow
                Spacer()
                resumeLibraryPrimaryHeader
            }
                .padding(.bottom, 16)

            if selectedResume == nil {
                ZStack {
                    resumeGridPane
                    resumeInspector
                }
                .frame(maxHeight: .infinity)
            } else {
                HSplitView {
                    resumeGridPane
                    resumeInspector
                        .frame(minWidth: 340)
                        .background(resumeSurfaceBackground)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(resumeSurfaceBackground)
    }

    private var resumeGridPane: some View {
        ScrollView {
            if filteredResumeDocuments.isEmpty, !resumes.isEmpty {
                ContentUnavailableView {
                    Label(resumeGridEmptyTitle, systemImage: "doc.richtext")
                } description: {
                    Text(resumeGridEmptyDescription)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.top, 24)
            } else if !filteredResumeDocuments.isEmpty {
                LazyVGrid(columns: resumeGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(filteredResumeDocuments, id: \.id) { resume in
                        resumeLibraryCard(for: resume)
                            .overlay(selectionOutline(for: resume))
                            .onTapGesture {
                                selectedResumeID = resume.id
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(resumeSurfaceBackground)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            do {
                if let doc = try collegePersistence.importCareerResume(from: first) {
                    selectedResumeID = doc.id
                }
                return true
            } catch {
                return false
            }
        }
    }

    private var resumeGridEmptyTitle: String {
        "Nothing in this filter"
    }

    private var resumeGridEmptyDescription: String {
        "Try another filter tab."
    }

    @ViewBuilder
    private var resumeUploadTileLabel: some View {
        VStack(spacing: 10) {
            Image(systemName: resumes.isEmpty ? "doc.richtext" : "square.and.arrow.up")
                .font(DesignSystem.Fonts.main(size: resumes.isEmpty ? 28 : 26, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.85))

            if resumes.isEmpty {
                Text("No resumes yet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Drag a PDF here or use Upload Resume above.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
            } else {
                Text("Upload Resume")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, resumes.isEmpty ? 20 : 12)
        .padding(.horizontal, 16)
    }

    private var resumeSurfaceBackground: Color {
        DesignSystem.Colors.bgMain
    }

    private var resumeLibraryPrimaryHeader: some View {
        HStack(spacing: 12) {
            statPill(dot: .purple, label: "Versions", value: "\(resumeLibraryStats.versions)")
            statPill(dot: .orange, label: "Tailored", value: "\(resumeLibraryStats.tailored)")
            statPill(dot: .green, label: "Avg ATS", value: resumeLibraryStats.avgATS.map { "\($0)%" } ?? "—")

            Button {
                showingImporter = true
            } label: {
                Text("Upload Resume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(DesignSystem.Colors.primary, in: Capsule(style: .continuous))
        }
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1), in: Capsule(style: .continuous))
    }

    private var resumeLibraryFilterRow: some View {
        HStack(spacing: 4) {
            ForEach(ResumeLibraryFilter.allCases) { tab in
                let isSelected = resumeLibraryFilter == tab
                Button {
                    resumeLibraryFilter = tab
                } label: {
                    Text(tab.title)
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
        .padding(4)
        .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))
    }

    @ViewBuilder
    private func selectionOutline(for resume: VaultDocument) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                selectedResumeID == resume.id ? Color.accentColor.opacity(0.65) : Color.clear,
                lineWidth: 2
            )
    }

    private func resumeLibraryCard(for resume: VaultDocument) -> some View {
        let meta = collegePersistence.careerResumeMetadata(for: resume)
        return ResumeLibraryCard(
            resume: resume,
            metadata: meta,
            usageCount: collegePersistence.careerResumeUsageCount(for: resume),
            onScoreATS: {
                let score = collegePersistence.scoreCareerResumeHeuristic(for: resume)
                collegePersistence.persistCareerResumeATSScore(score, for: resume)
            },
            onToggleFavorite: {
                collegePersistence.setCareerResumeFavorite(!resume.isFavorite, for: resume)
            },
            onToggleArchived: {
                var m = collegePersistence.careerResumeMetadata(for: resume)
                m.archived.toggle()
                collegePersistence.setCareerResumeMetadata(m, for: resume)
            },
            onSetKind: { kind in
                var m = collegePersistence.careerResumeMetadata(for: resume)
                m.kind = kind
                collegePersistence.setCareerResumeMetadata(m, for: resume)
            },
            onQuickLook: {
                if let url = VaultDocumentAccess.urlForDocument(id: resume.id, collegePersistence: collegePersistence) {
                    quickLookURL = nil
                    DispatchQueue.main.async {
                        quickLookURL = url
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var resumeInspector: some View {
        if let selected = selectedResume {
            VStack(alignment: .leading, spacing: 12) {
                Text(selected.customDisplayName ?? selected.fileName)
                    .font(.title3.bold())
                Text("Used in \(collegePersistence.careerResumeUsageCount(for: selected)) applications")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target role")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Staff iOS Engineer", text: targetRoleBinding(for: selected))
                        .textFieldStyle(.roundedBorder)
                }

                if let linked = selected.submittedApplications,
                   !linked.isEmpty {
                    List(Array(linked).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }, id: \.id) { app in
                        Button("\(app.company ?? "Company") - \(app.title ?? "Role")") {
                            selectedJobID = app.id
                            NotificationCenter.default.post(name: .careerOpenBoardJob, object: app.id)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No linked jobs", systemImage: "tray", description: Text("Attach this resume from a job card inspector."))
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(14)
        } else {
            VStack {
                Button {
                    showingImporter = true
                } label: {
                    resumeUploadTileLabel
                        .frame(maxWidth: 320, minHeight: resumes.isEmpty ? 200 : 180)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isResumeUploadTileHovered ? Color.secondary.opacity(0.06) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                                .foregroundStyle(isResumeUploadTileHovered ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.35))
                        )
                        .scaleEffect(isResumeUploadTileHovered ? 1.01 : 1)
                        .animation(.easeOut(duration: 0.15), value: isResumeUploadTileHovered)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onHover { hovering in
                    isResumeUploadTileHovered = hovering
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func targetRoleBinding(for doc: VaultDocument) -> Binding<String> {
        Binding(
            get: { collegePersistence.careerResumeMetadata(for: doc).targetRole ?? "" },
            set: { newValue in
                var m = collegePersistence.careerResumeMetadata(for: doc)
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                m.targetRole = trimmed.isEmpty ? nil : trimmed
                collegePersistence.setCareerResumeMetadata(m, for: doc)
            }
        )
    }

    private var selectedResume: VaultDocument? {
        let list = filteredResumeDocuments
        guard let id = selectedResumeID else { return list.first }
        return list.first(where: { $0.id == id }) ?? list.first
    }

}

// MARK: - Networking hybrid grid (jobs + orphan contacts)

private enum NetworkingContactFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case recruiters = "Recruiters"
    case alumni = "Alumni"
    case hiringManagers = "Hiring Managers"
    case peers = "Peers"

    var id: String { rawValue }
}

struct NetworkingTrackerView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
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
                    isInspectorPresented: selectedContactID != nil,
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
        .padding(24)
        .background(DesignSystem.Colors.bgMain)
        .onAppear { refreshNetworkingKPIs() }
        .sheet(isPresented: $showAddContactSheet) {
            NetworkingAddContactSheet()
                .environmentObject(collegePersistence)
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            store?.refresh()
            networkingGridEpoch &+= 1
            networkingKPIs = collegePersistence.careerNetworkingKPIs()
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 340, maximum: 420), spacing: 16)]

    @ViewBuilder
    private func networkingContactGrid(store: NetworkingFollowUpStore) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                ForEach(filteredNetworkingItems(from: store.items)) { item in
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
        .padding(4)
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
                .padding(12)
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
            .padding(12)
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
    @State private var isHovered = false

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
                    .fill(isHovered ? Color.secondary.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(isHovered ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.5))
            )
            .scaleEffect(isHovered ? 1.01 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct NetworkingHybridFollowUpDetailPane: View {
    @Binding var selection: NetworkingFollowUpItem?
    @Binding var selectedJobID: UUID?
    @EnvironmentObject private var collegePersistence: CollegePersistence
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
                        .padding(8)
                        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 11))
                        .onChange(of: activityNotes) { _, newValue in
                            collegePersistence.setCareerNetworkingNotes(newValue, for: app)
                        }

                    if !draftText.isEmpty {
                        draftPreviewBlock
                    }
                }
                .padding(20)
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
                        .padding(8)
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
                .padding(20)
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
                .padding(12)
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

private struct CareerApplicationFormSheet: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @Environment(\.dismiss) private var dismiss
    let existingApplicationID: UUID?

    @State private var title = ""
    @State private var company = ""
    @State private var postingURL = ""
    @State private var descriptionText = ""
    @State private var deadline = Date()
    @State private var status: CareerApplicationStatus = .interested
    @State private var interviewStatus = ""
    /// Maps to local store `baseSalaryText` (AI ingest · offer inspector share this field).
    @State private var baseSalaryText = ""
    /// Maps to local store `locationText` — job location string, unrelated to bonuses.
    @State private var locationText = ""
    @State private var offerBonusText = ""
    @State private var offerSigningText = ""
    @State private var offerEquityText = ""
    @State private var isExtracting = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case title, company, url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Job Title", text: $title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .company }
                    TextField("Company", text: $company)
                        .focused($focusedField, equals: .company)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                    TextField("Interview Status", text: $interviewStatus)
                    Picker("Pipeline", selection: $status) {
                        ForEach(CareerApplicationStatus.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }
                Section("Details") {
                    DatePicker("Application Deadline", selection: $deadline, displayedComponents: .date)
                    TextField("Posting URL", text: $postingURL)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.done)
                        .onSubmit { saveAndDismiss() }
                    TextField("Location", text: $locationText, prompt: Text("City / region (from posting)"))
                    TextField("Base compensation (optional)", text: $baseSalaryText, prompt: Text("e.g. 175000 or $175k /yr"))
                    if isExtracting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 120)
                }

                if status == .offer {
                    Section("Offer breakdown") {
                        TextField("Annual bonus target (optional)", text: $offerBonusText)
                        TextField("Signing bonus (optional)", text: $offerSigningText)
                        TextField("Equity notes (optional)", text: $offerEquityText, axis: .vertical)
                            .lineLimit(3...10)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Application")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
        .onAppear {
            focusedField = .title
            hydrateExistingIfNeeded()
        }
        .task(id: postingURL) {
            let trimmed = postingURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URL(string: trimmed) != nil, !trimmed.isEmpty else {
                isExtracting = false
                return
            }
            isExtracting = true
            do {
                try await Task.sleep(for: .milliseconds(500))
                if company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    company = inferCompany(from: trimmed)
                }
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = inferTitle(from: trimmed)
                }
            } catch { }
            isExtracting = false
        }
    }

    private func saveAndDismiss() {
        if let existingApplicationID,
           let app = collegePersistence.jobApplication(id: existingApplicationID) {
            let baseTrim = baseSalaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            let locationTrim = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
            app.title = title
            app.company = company
            app.postingURLString = postingURL
            app.jobDescriptionText = descriptionText
            app.interviewStatus = interviewStatus
            app.applicationDeadline = deadline
            app.statusRaw = status.rawValue
            app.updatedAt = Date()
            app.baseSalaryText = baseTrim.isEmpty ? nil : baseTrim
            app.locationText = locationTrim.isEmpty ? nil : locationTrim
            persistOfferTexts(to: app)
            collegePersistence.save()
        } else {
            let row = collegePersistence.addCareerApplication(
                title: title,
                company: company,
                postingURLString: postingURL,
                jobDescriptionText: descriptionText,
                interviewStatus: interviewStatus,
                applicationDeadline: deadline,
                status: status
            )
            let baseTrim = baseSalaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            let locationTrim = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
            row.baseSalaryText = baseTrim.isEmpty ? nil : baseTrim
            row.locationText = locationTrim.isEmpty ? nil : locationTrim
            persistOfferTexts(to: row)
            row.updatedAt = Date()
            collegePersistence.save()
        }
        dismiss()
    }

    private func hydrateExistingIfNeeded() {
        guard let existingApplicationID,
              let app = collegePersistence.jobApplication(id: existingApplicationID)
        else { return }
        title = app.title ?? ""
        company = app.company ?? ""
        postingURL = app.postingURLString ?? ""
        descriptionText = app.jobDescriptionText ?? ""
        interviewStatus = app.interviewStatus ?? ""
        deadline = app.applicationDeadline ?? Date()
        status = CareerApplicationStatus(rawValue: app.statusRaw) ?? .interested
        baseSalaryText = app.baseSalaryText ?? ""
        locationText = app.locationText ?? ""
        let offerPkg = collegePersistence.careerOfferCompensationPackage(for: app)
        offerBonusText = offerPkg.bonusText
        offerSigningText = offerPkg.signingText
        offerEquityText = offerPkg.equityText
    }

    private func persistOfferTexts(to app: JobApplication) {
        let pkg = CareerOfferCompensationPackage(
            bonusText: offerBonusText.trimmingCharacters(in: .whitespacesAndNewlines),
            signingText: offerSigningText.trimmingCharacters(in: .whitespacesAndNewlines),
            equityText: offerEquityText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        collegePersistence.setCareerOfferCompensationPackage(pkg, for: app)
    }

    private func inferCompany(from urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first?.capitalized ?? ""
    }

    private func inferTitle(from urlString: String) -> String {
        guard let path = URL(string: urlString)?.pathComponents.last else { return "New Role" }
        return path.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct LegacyQuickLookPreviewBridge: NSViewRepresentable {
    @Binding var url: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(url: $url)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.presentIfNeeded(with: url)
    }

    @MainActor
    final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        @Binding private var url: URL?

        init(url: Binding<URL?>) {
            self._url = url
        }

        func presentIfNeeded(with candidate: URL?) {
            guard let panel = QLPreviewPanel.shared() else { return }
            if let candidate {
                url = candidate
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            } else if panel.isVisible {
                panel.orderOut(nil)
            }
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            url == nil ? 0 : 1
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            (url ?? URL(fileURLWithPath: "/")) as NSURL
        }

        func previewPanelWillClose(_ panel: QLPreviewPanel!) {
            url = nil
        }
    }
}

private extension View {
    func quickLookPreview(_ url: Binding<URL?>) -> some View {
        background(LegacyQuickLookPreviewBridge(url: url))
    }
}
