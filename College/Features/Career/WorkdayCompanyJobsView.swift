// WorkdayCompanyJobsView.swift
// Feature: Career
// Purpose: Career module — WorkdayCompanyJobsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct WorkdayCompanyJobsView: View {
    @Environment(AppContainer.self) private var container
    private var brightspaceCoordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var coordinator: BrightspaceWebCoordinator { container.brightspaceCoordinator }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
        @ObservedObject private var coordinator = WorkdayJobBoardSyncCoordinator.shared

    let company: WorkdayCompanyConfigEntry

    @Binding var selectedPostingPath: String?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var sortOrder: WorkdayJobListSort = .newest
    @State private var locationFilterKey: String?
    @State private var jobTypeFilterKey: String?
    @State private var timeTypeFilterKey: String?
    @State private var daysPostedFilter: WorkdayDaysPostedFilter = .all
    @State private var hideOnBoard = false
    @State private var showClosed = false
    @State private var closingSoonOnly = false
    @FocusState private var listFocused: Bool

    @State private var cachedFilteredPostings: [WorkdayJobPosting] = []
    @State private var cachedLocationFilterOptions: [WorkdayPostingParsing.LocationFilterOption] = []
    @State private var cachedJobTypeFilterOptions: [WorkdayPostingParsing.JobTypeFilterOption] = []
    @State private var cachedTimeTypeFilterOptions: [WorkdayPostingParsing.TimeTypeFilterOption] = []
    @State private var cachedTrackedPostingIDs: Set<UUID> = []

    @AppStorage("jobList.density") private var listDensityRaw: String = JobListDensity.comfortable.rawValue

    @State private var postings: [WorkdayJobPosting] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    private var motionReduced: Bool { reduceMotion || appReduceMotion }
    private var density: JobListDensity { JobListDensity(rawValue: listDensityRaw) ?? .comfortable }

    init(
        company: WorkdayCompanyConfigEntry,
        selectedPostingPath: Binding<String?>,
        onNavigateToBoard: @escaping () -> Void = {}
    ) {
        self.company = company
        _selectedPostingPath = selectedPostingPath
        self.onNavigateToBoard = onNavigateToBoard
    }

    private func refreshPostings() {
        postings = WorkdayReadBridge.companyPostings(
            companySlug: company.normalizedSlug
        )
        refreshMemoizedFiltersAndList()
    }

    private var selectedPosting: WorkdayJobPosting? {
        guard let selectedPostingPath else { return nil }
        return postings.first { $0.externalPath == selectedPostingPath }
    }

    private func filterLocations(for posting: WorkdayJobPosting) -> [String] {
        WorkdayPostingParsing.filterLocations(
            locationText: posting.locationText,
            locationsFilterText: posting.locationsFilterText,
            externalPath: posting.externalPath
        )
    }

    private var locationFilterOptions: [WorkdayPostingParsing.LocationFilterOption] {
        cachedLocationFilterOptions
    }

    private var jobTypeFilterOptions: [WorkdayPostingParsing.JobTypeFilterOption] {
        cachedJobTypeFilterOptions
    }

    private var timeTypeFilterOptions: [WorkdayPostingParsing.TimeTypeFilterOption] {
        cachedTimeTypeFilterOptions
    }

    private var filteredPostings: [WorkdayJobPosting] {
        cachedFilteredPostings
    }

    private func refreshMemoizedFiltersAndList() {
        let labels = postings.flatMap { filterLocations(for: $0) }
        cachedLocationFilterOptions = WorkdayPostingParsing.buildLocationFilterOptions(from: labels)
        cachedJobTypeFilterOptions = WorkdayPostingParsing.buildJobTypeFilterOptions(
            from: postings.compactMap(\.jobTypeText)
        )
        cachedTimeTypeFilterOptions = WorkdayPostingParsing.buildTimeTypeFilterOptions(
            from: postings.compactMap(\.timeType)
        )
        cachedTrackedPostingIDs = Set(
            postings.compactMap { posting in
                collegePersistence.isPostingTracked(posting) ? posting.id : nil
            }
        )
        cachedFilteredPostings = computeFilteredPostings(trackedPostingIDs: cachedTrackedPostingIDs)
    }

    private func computeFilteredPostings(trackedPostingIDs: Set<UUID>) -> [WorkdayJobPosting] {
        let q = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var list = postings.filter { posting in
            if !showClosed {
                guard posting.isActive, posting.closedAt == nil else { return false }
            }
            if WorkdayOpeningsState.isPostingHidden(companySlug: company.normalizedSlug, externalPath: posting.externalPath) {
                return false
            }
            if closingSoonOnly {
                guard let deadline = posting.deadlineAt else { return false }
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: deadline)).day ?? 99
                if days > 7 { return false }
            }
            if hideOnBoard, trackedPostingIDs.contains(posting.id) { return false }
            if !WorkdayPostingParsing.postingMatchesLocationFilter(
                locationText: posting.locationText,
                locationsFilterText: posting.locationsFilterText,
                externalPath: posting.externalPath,
                filterKey: locationFilterKey
            ) { return false }
            if !WorkdayPostingParsing.postingMatchesJobTypeFilter(posting, filterKey: jobTypeFilterKey) {
                return false
            }
            if !WorkdayPostingParsing.postingMatchesTimeTypeFilter(posting, filterKey: timeTypeFilterKey) {
                return false
            }
            if !WorkdayPostingParsing.matchesDaysPostedFilter(posting, filter: daysPostedFilter) { return false }
            guard !q.isEmpty else { return true }
            let hay = [
                posting.title,
                posting.displayJobId,
                posting.locationText,
            ].compactMap { $0?.lowercased() }.joined(separator: " ")
            return hay.contains(q)
        }

        switch sortOrder {
        case .newest:
            list.sort {
                WorkdayPostingParsing.sortDate(for: $0) > WorkdayPostingParsing.sortDate(for: $1)
            }
        case .title:
            list.sort { ($0.title ?? "") < ($1.title ?? "") }
        case .jobID:
            list.sort { ($0.displayJobId ?? "") < ($1.displayJobId ?? "") }
        }
        return list
    }

    var onNavigateToBoard: () -> Void

    var body: some View {
        jobListColumn
        .onChange(of: company.id) { _, _ in
            selectedPostingPath = nil
            locationFilterKey = nil
            jobTypeFilterKey = nil
            timeTypeFilterKey = nil
            refreshPostings()
            selectFirstJobIfNeeded()
        }
        .onAppear {
            refreshPostings()
            selectFirstJobIfNeeded()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            refreshPostings()
        }
        .onChange(of: coordinator.uiState.lastSuccessfulSyncAt) { _, _ in
            refreshPostings()
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    debouncedSearchText = newValue
                    refreshMemoizedFiltersAndList()
                }
            }
        }
        .onChange(of: debouncedSearchText) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: sortOrder) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: locationFilterKey) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: jobTypeFilterKey) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: timeTypeFilterKey) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: daysPostedFilter) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: hideOnBoard) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: showClosed) { _, _ in
            refreshMemoizedFiltersAndList()
        }
        .onChange(of: closingSoonOnly) { _, _ in
            refreshMemoizedFiltersAndList()
        }
    }

    private var jobListColumn: some View {
        VStack(spacing: 0) {
            companyListHeader
            toolbarRow
            Divider().opacity(0.35)

            Group {
                if filteredPostings.isEmpty {
                    emptyJobs
                } else {
                    List(selection: $selectedPostingPath) {
                        ForEach(filteredPostings, id: \.id) { posting in
                            WorkdayJobListRow(
                                posting: posting,
                                isSelected: selectedPostingPath == posting.externalPath,
                                isNew: collegePersistence.isPostingNew(posting),
                                boardStatus: collegePersistence.boardStatus(for: posting),
                                density: density,
                                company: company,
                                onSelect: { selectPosting(posting) },
                                onTrack: { trackPosting(posting) },
                                onHide: {
                                    WorkdayOpeningsState.hidePosting(
                                        companySlug: company.normalizedSlug,
                                        externalPath: posting.externalPath
                                    )
                                }
                            )
                            .tag(posting.externalPath)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.visible)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focused($listFocused)
            .onKeyPress(.upArrow) { moveSelection(delta: -1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(delta: 1); return .handled }
            .onKeyPress(.return) {
                if selectedPosting == nil, let first = filteredPostings.first {
                    selectPosting(first)
                }
                return .handled
            }
            .onKeyPress(.space) {
                if let p = selectedPosting {
                    WorkdayOpeningsState.markPostingSeen(
                        companySlug: company.normalizedSlug,
                        externalPath: p.externalPath
                    )
                }
                return .handled
            }
            .onKeyPress(.escape) {
                selectedPostingPath = nil
                return .handled
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .onChange(of: selectedPostingPath) { _, path in
            guard let path,
                  let posting = postings.first(where: { $0.externalPath == path })
            else { return }
            WorkdayOpeningsState.markPostingSeen(
                companySlug: company.normalizedSlug,
                externalPath: posting.externalPath
            )
        }
    }

    private func selectPosting(_ posting: WorkdayJobPosting) {
        selectedPostingPath = posting.externalPath
        WorkdayOpeningsState.markPostingSeen(
            companySlug: company.normalizedSlug,
            externalPath: posting.externalPath
        )
    }

    /// Opens the first listing when switching companies so the detail column is not an empty third pane.
    private func selectFirstJobIfNeeded() {
        guard selectedPostingPath == nil, let first = filteredPostings.first else { return }
        selectPosting(first)
    }

    private var companyListHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(company.displayName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .lineLimit(1)
            Text("\(filteredPostings.count) openings")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
            Spacer(minLength: 8)
            Button {
                Task { await coordinator.scrapeCompany(company) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(companyRefreshHelp)
            .disabled(coordinator.isScraping(slug: company.normalizedSlug))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var companyRefreshHelp: String {
        let interval = WorkdayRefreshScheduler.shared.selectedIntervalSeconds
        let schedule = interval > 0
            ? "Scheduled refresh: \(WorkdayRefreshIntervalOption.fromStoredSeconds(Int(interval)).displayName). "
            : "Scheduled refresh: manual only. "
        return schedule + "Scrape this company's board now."
    }

    private func moveSelection(delta: Int) {
        guard !filteredPostings.isEmpty else { return }
        if let current = selectedPosting,
           let idx = filteredPostings.firstIndex(where: { $0.id == current.id }) {
            let next = min(max(0, idx + delta), filteredPostings.count - 1)
            selectPosting(filteredPostings[next])
        } else if delta >= 0 {
            selectPosting(filteredPostings[0])
        } else {
            selectPosting(filteredPostings[filteredPostings.count - 1])
        }
    }

    private func trackPosting(_ posting: WorkdayJobPosting) {
        let app = collegePersistence.promoteWorkdayPostingToTracker(posting)
        WorkdayOpeningsState.markPostingSeen(
            companySlug: company.normalizedSlug,
            externalPath: posting.externalPath
        )
        notifications.post(
            kind: .success,
            title: "Added to board",
            message: app.title ?? "Role"
        )
    }

    private var toolbarRow: some View {
        HStack(spacing: 10) {
            TextField("Search title, location, or job ID", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            WorkdaySortFilterMenu(selection: $sortOrder)

            if !locationFilterOptions.isEmpty {
                WorkdayLocationFilterMenu(
                    selectionKey: $locationFilterKey,
                    options: locationFilterOptions
                )
            }

            WorkdayExtraFiltersMenu(
                jobTypeFilterKey: $jobTypeFilterKey,
                timeTypeFilterKey: $timeTypeFilterKey,
                daysPostedFilter: $daysPostedFilter,
                hideOnBoard: $hideOnBoard,
                closingSoonOnly: $closingSoonOnly,
                showClosed: $showClosed,
                jobTypeFilterOptions: jobTypeFilterOptions,
                timeTypeFilterOptions: timeTypeFilterOptions
            )

            Spacer(minLength: 0)

            Picker("Density", selection: $listDensityRaw) {
                Text("Comfortable").tag(JobListDensity.comfortable.rawValue)
                Text("Compact").tag(JobListDensity.compact.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 168)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyJobs: some View {
        VStack(spacing: 10) {
            Text("No openings")
                .font(.title3)
            Text("Try refreshing, clearing filters, or pick a different posted-date range.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum JobListDensity: String {
    case comfortable
    case compact
}

// MARK: - List row

private struct WorkdayJobListRow: View {
    let posting: WorkdayJobPosting
    let isSelected: Bool
    let isNew: Bool
    let boardStatus: CareerApplicationStatus?
    let density: JobListDensity
    let company: WorkdayCompanyConfigEntry
    let onSelect: () -> Void
    let onTrack: () -> Void
    let onHide: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(posting.title ?? "Untitled")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .lineLimit(2)
                    if let posted = WorkdayJobListRow.postedLabel(for: posting) {
                        Text(posted)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                HStack(spacing: 8) {
                    if let jid = posting.displayJobId, !jid.isEmpty {
                        Text(jid)
                            .font(.caption.monospaced())
                            .foregroundStyle(DesignSystem.Colors.textLight)
                    }
                    if let loc = posting.locationText, !loc.isEmpty {
                        Text(loc)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if density == .comfortable {
                    if let boardStatus {
                        WorkdayBoardStatusPill(status: boardStatus)
                    } else if isNew {
                        newBadge
                    }
                }

                if isHovering, boardStatus == nil, density == .comfortable {
                    Button(action: onTrack) {
                        Label("Track", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .padding(density == .compact ? 8 : 12)
        .background(isSelected ? DesignSystem.Colors.accent.opacity(0.08) : DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.accent : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            if let urlString = posting.applyURLString, let url = URL(string: urlString) {
                Button("Copy Job URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urlString, forType: .string)
                }
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
            if boardStatus == nil {
                Button("Add to Board", action: onTrack)
            }
            Button("Mark as Seen") {
                WorkdayOpeningsState.markPostingSeen(
                    companySlug: company.normalizedSlug,
                    externalPath: posting.externalPath
                )
            }
            Button("Hide this job", role: .destructive, action: onHide)
        }
    }

    static func postedLabel(for posting: WorkdayJobPosting) -> String? {
        if let text = posting.postedOnText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        if let date = posting.postedAt {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return nil
    }

    private var newBadge: some View {
        Text("New")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignSystem.Colors.accent.opacity(0.15))
            .foregroundStyle(DesignSystem.Colors.accent)
            .clipShape(Capsule())
            .transition(.opacity)
    }
}

struct WorkdayBoardStatusPill: View {
    let status: CareerApplicationStatus

    var body: some View {
        let style = CareerListTableTheme.stageBadgeStyle(for: status)
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.background, in: Capsule())
    }
}
