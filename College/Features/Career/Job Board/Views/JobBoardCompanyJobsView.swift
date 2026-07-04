// JobBoardCompanyJobsView.swift
// Feature: Career
// Purpose: Career module — JobBoardCompanyJobsView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import CollegeCareer

struct JobBoardCompanyJobsView: View {
    @Environment(AppContainer.self) private var container
    private var lmsCoordinator: LMSWebCoordinator { container.lmsCoordinator }
    private var appNotifications: AppNotificationCenter { container.appNotifications }
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
        @ObservedObject private var jobBoardCoordinator = JobBoardSyncCoordinator.shared

    let company: JobBoardCompany

    @Binding var selectedPostingPath: String?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var sortOrder: JobBoardJobListSort = .newest
    @State private var locationFilterKey: String?
    @State private var jobTypeFilterKey: String?
    @State private var timeTypeFilterKey: String?
    @State private var daysPostedFilter: JobBoardDaysPostedFilter = .all
    @State private var hideOnBoard = false
    @State private var showClosed = false
    @State private var closingSoonOnly = false
    @FocusState private var listFocused: Bool

    @State private var cachedFilteredPostings: [JobBoardPosting] = []
    @State private var cachedLocationFilterOptions: [JobBoardPostingParsing.LocationFilterOption] = []
    @State private var cachedJobTypeFilterOptions: [JobBoardPostingParsing.JobTypeFilterOption] = []
    @State private var cachedTimeTypeFilterOptions: [JobBoardPostingParsing.TimeTypeFilterOption] = []
    @State private var cachedTrackedPostingIDs: Set<UUID> = []
    @State private var cachedMatchDisplays: [UUID: JobBoardMatchListDisplay] = [:]
    @State private var cachedNewFlags: [UUID: Bool] = [:]
    @State private var cachedViewedFlags: [UUID: Bool] = [:]
    @State private var cachedBoardStatuses: [UUID: CareerApplicationStatus?] = [:]

    @AppStorage("jobList.density") private var listDensityRaw: String = JobListDensity.comfortable.rawValue

    @State private var postings: [JobBoardPosting] = []
    @State private var postingsReloadTask: Task<Void, Never>?
    @State private var primaryResumeContext: JobBoardResumeMatchContext?
    @State private var hasPendingResumeParse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    private var motionReduced: Bool { reduceMotion || appReduceMotion }
    private var density: JobListDensity { JobListDensity(rawValue: listDensityRaw) ?? .comfortable }

    init(
        company: JobBoardCompany,
        selectedPostingPath: Binding<String?>,
        onNavigateToApplicationTracker: @escaping () -> Void = {}
    ) {
        self.company = company
        _selectedPostingPath = selectedPostingPath
        self.onNavigateToApplicationTracker = onNavigateToApplicationTracker
    }

    private func refreshPostings() {
        postingsReloadTask?.cancel()
        let slug = company.normalizedSlug
        postingsReloadTask = Task {
            let fetched = await JobBoardReadBridge.companyPostingsOffMain(companySlug: slug)
            guard !Task.isCancelled else { return }
            applyFetchedPostings(fetched, slug: slug)
        }
    }

    /// Applies a store read without wiping visible listings on a transient empty fetch.
    private func applyFetchedPostings(_ fetched: [JobBoardPosting], slug: String) {
        if fetched.isEmpty, !postings.isEmpty {
            if case .ok(let count, _) = companySyncStatus, count == 0 {
                postings = []
                refreshMemoizedFiltersAndList()
                return
            }
            schedulePostingsReloadIfNeeded(slug: slug)
            return
        }

        postingsReloadTask?.cancel()
        postings = fetched
        refreshMemoizedFiltersAndList()

        guard postings.isEmpty else { return }
        schedulePostingsReloadIfNeeded(slug: slug)
    }

    private func schedulePostingsReloadIfNeeded(slug: String) {
        postingsReloadTask?.cancel()
        postingsReloadTask = Task {
            ModelMergeCoalescer.flushNow()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let fetched = await JobBoardReadBridge.companyPostingsOffMain(companySlug: slug)
            guard !Task.isCancelled else { return }
            guard fetched.count >= postings.count else { return }
            guard !fetched.isEmpty || postings.isEmpty else { return }
            postings = fetched
            refreshMemoizedFiltersAndList()
        }
    }

    private var companySyncStatus: JobBoardSyncUIState.CompanyState.Status? {
        jobBoardCoordinator.uiState.companies.first { $0.slug == company.normalizedSlug }?.status
    }

    private var selectedPosting: JobBoardPosting? {
        guard let selectedPostingPath,
              let parsed = JobBoardPostingSelectionKey.parse(selectedPostingPath)
        else { return nil }
        return postings.first {
            $0.companySlug.lowercased() == parsed.companySlug && $0.externalPath == parsed.externalPath
        }
    }

    private func filterLocations(for posting: JobBoardPosting) -> [String] {
        JobBoardPostingParsing.filterLocations(
            locationText: posting.locationText,
            locationsFilterText: posting.locationsFilterText,
            externalPath: posting.externalPath
        )
    }

    private var locationFilterOptions: [JobBoardPostingParsing.LocationFilterOption] {
        cachedLocationFilterOptions
    }

    private var jobTypeFilterOptions: [JobBoardPostingParsing.JobTypeFilterOption] {
        cachedJobTypeFilterOptions
    }

    private var timeTypeFilterOptions: [JobBoardPostingParsing.TimeTypeFilterOption] {
        cachedTimeTypeFilterOptions
    }

    private var filteredPostings: [JobBoardPosting] {
        cachedFilteredPostings
    }

    private func refreshMemoizedFiltersAndList() {
        let labels = postings.flatMap { filterLocations(for: $0) }
        cachedLocationFilterOptions = JobBoardPostingParsing.buildLocationFilterOptions(from: labels)
        cachedJobTypeFilterOptions = JobBoardPostingParsing.buildJobTypeFilterOptions(
            from: postings.compactMap(\.jobTypeText)
        )
        cachedTimeTypeFilterOptions = JobBoardPostingParsing.buildTimeTypeFilterOptions(
            from: postings.compactMap(\.timeType)
        )
        cachedTrackedPostingIDs = Set(
            postings.compactMap { posting in
                collegePersistence.isPostingTracked(posting) ? posting.id : nil
            }
        )
        rebuildListRowCaches()
        cachedFilteredPostings = computeFilteredPostings(trackedPostingIDs: cachedTrackedPostingIDs)
    }

    private func rebuildListRowCaches() {
        let slug = company.normalizedSlug
        let resumeHash = primaryResumeContext?.parsedTextHash
        let hasParsedResume = primaryResumeContext != nil
        let recommendedByPath: [String: CareerResumeJobMatch] = {
            guard let matches = try? collegePersistence.careerRepository.fetchRecommendedMatches(companySlug: slug)
            else { return [:] }
            var index: [String: CareerResumeJobMatch] = [:]
            for match in matches {
                let path = match.postingExternalPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { continue }
                index[path] = match
            }
            return index
        }()

        var displays: [UUID: JobBoardMatchListDisplay] = [:]
        var newFlags: [UUID: Bool] = [:]
        var viewedFlags: [UUID: Bool] = [:]
        var statuses: [UUID: CareerApplicationStatus?] = [:]

        for posting in postings {
            let path = posting.externalPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cachedScore = JobBoardMatchEligibility.recommendedOverallScoreIfValid(
                match: recommendedByPath[path],
                postingDescriptionHash: posting.descriptionHash,
                resumeParsedTextHash: resumeHash
            )
            displays[posting.id] = JobBoardMatchEligibility.listDisplay(
                hasParsedResume: hasParsedResume,
                hasPendingParse: hasPendingResumeParse,
                hasUsableJD: JobBoardMatchEligibility.hasUsableJobDescription(posting),
                cachedOverallScore: cachedScore
            )
            let isNew = collegePersistence.isPostingNew(posting)
            newFlags[posting.id] = isNew
            viewedFlags[posting.id] = !isNew && JobBoardOpeningsState.isPostingSeen(
                companySlug: slug,
                externalPath: posting.externalPath
            )
            statuses[posting.id] = collegePersistence.boardStatus(for: posting)
        }

        cachedMatchDisplays = displays
        cachedNewFlags = newFlags
        cachedViewedFlags = viewedFlags
        cachedBoardStatuses = statuses
    }

    private func markPostingSeenForList(_ posting: JobBoardPosting) {
        JobBoardOpeningsState.markPostingSeen(
            companySlug: company.normalizedSlug,
            externalPath: posting.externalPath
        )
        cachedNewFlags[posting.id] = false
        cachedViewedFlags[posting.id] = true
    }

    private func computeFilteredPostings(trackedPostingIDs: Set<UUID>) -> [JobBoardPosting] {
        let q = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var list = postings.filter { posting in
            if !showClosed {
                guard posting.isActive, posting.closedAt == nil else { return false }
            }
            if JobBoardOpeningsState.isPostingHidden(companySlug: company.normalizedSlug, externalPath: posting.externalPath) {
                return false
            }
            if closingSoonOnly {
                guard let deadline = posting.deadlineAt else { return false }
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: deadline)).day ?? 99
                if days > 7 { return false }
            }
            if hideOnBoard, trackedPostingIDs.contains(posting.id) { return false }
            if !JobBoardPostingParsing.postingMatchesLocationFilter(
                locationText: posting.locationText,
                locationsFilterText: posting.locationsFilterText,
                externalPath: posting.externalPath,
                filterKey: locationFilterKey
            ) { return false }
            if !JobBoardPostingParsing.postingMatchesJobTypeFilter(posting, filterKey: jobTypeFilterKey) {
                return false
            }
            if !JobBoardPostingParsing.postingMatchesTimeTypeFilter(posting, filterKey: timeTypeFilterKey) {
                return false
            }
            if !JobBoardPostingParsing.matchesDaysPostedFilter(posting, filter: daysPostedFilter) { return false }
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
                JobBoardPostingParsing.sortDate(for: $0) > JobBoardPostingParsing.sortDate(for: $1)
            }
        case .title:
            list.sort { ($0.title ?? "") < ($1.title ?? "") }
        case .jobID:
            list.sort { ($0.displayJobId ?? "") < ($1.displayJobId ?? "") }
        }
        return list
    }

    var onNavigateToApplicationTracker: () -> Void

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
            reloadPrimaryResumeContext()
            selectFirstJobIfNeeded()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            guard !jobBoardCoordinator.isScraping(slug: company.normalizedSlug) else { return }
            refreshPostings()
            reloadPrimaryResumeContext()
        }
        .onChange(of: jobBoardCoordinator.uiState.lastSuccessfulSyncAt) { _, _ in
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
            if let status = companySyncStatus, shouldShowSyncBanner(status) {
                companySyncStatusBanner(status)
            }
            toolbarRow
            Divider().opacity(0.35)

            Group {
                if filteredPostings.isEmpty {
                    emptyJobs
                } else {
                    List(selection: $selectedPostingPath) {
                        ForEach(filteredPostings, id: \.id) { posting in
                            JobBoardJobListRow(
                                posting: posting,
                                isSelected: selectedPostingPath == JobBoardPostingSelectionKey.tag(
                                    companySlug: company.normalizedSlug,
                                    externalPath: posting.externalPath
                                ),
                                isNew: cachedNewFlags[posting.id] ?? false,
                                isPreviouslyViewed: cachedViewedFlags[posting.id] ?? false,
                                boardStatus: cachedBoardStatuses[posting.id] ?? nil,
                                matchDisplay: cachedMatchDisplays[posting.id] ?? .hidden,
                                density: density,
                                company: company,
                                onTrack: { trackPosting(posting) },
                                onHide: {
                                    JobBoardOpeningsState.hidePosting(
                                        companySlug: company.normalizedSlug,
                                        externalPath: posting.externalPath
                                    )
                                },
                                onMarkSeen: { markPostingSeenForList(posting) }
                            )
                            .equatable()
                            .tag(JobBoardPostingSelectionKey.tag(
                                companySlug: company.normalizedSlug,
                                externalPath: posting.externalPath
                            ))
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.primary.opacity(0.08))
                            .listRowSeparator(.visible, edges: .bottom)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .tint(DesignSystem.Colors.primary)
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
                    markPostingSeenForList(p)
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
                  let parsed = JobBoardPostingSelectionKey.parse(path),
                  let posting = postings.first(where: {
                      $0.companySlug.lowercased() == parsed.companySlug && $0.externalPath == parsed.externalPath
                  })
            else { return }
            markPostingSeenForList(posting)
        }
    }

    private func selectPosting(_ posting: JobBoardPosting) {
        selectedPostingPath = JobBoardPostingSelectionKey.tag(
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
                Task { await jobBoardCoordinator.scrapeCompany(company, force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(companyRefreshHelp)
            .disabled(jobBoardCoordinator.isScraping(slug: company.normalizedSlug))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var companyRefreshHelp: String {
        let interval = JobBoardRefreshScheduler.shared.selectedIntervalSeconds
        let schedule = interval > 0
            ? "Scheduled refresh: \(JobBoardRefreshIntervalOption.fromStoredSeconds(Int(interval)).displayName). "
            : "Scheduled refresh: manual only. "
        return schedule + "Scrape this company's board now."
    }

    @ViewBuilder
    private func companySyncStatusBanner(_ status: JobBoardSyncUIState.CompanyState.Status) -> some View {
        let isError = JobBoardSyncStatusPresentation.bannerIsError(for: status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? Color.orange : DesignSystem.Colors.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(JobBoardSyncStatusPresentation.bannerTitle(for: status))
                        .font(.subheadline.weight(.semibold))
                    Text(JobBoardSyncStatusPresentation.bannerMessage(for: status, companyName: company.displayName))
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if JobBoardSyncStatusPresentation.bannerShowsAction(for: status) {
                Button("Try syncing now") {
                    Task { await jobBoardCoordinator.scrapeCompany(company, force: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(jobBoardCoordinator.isScraping(slug: company.normalizedSlug))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            (isError ? Color.orange : DesignSystem.Colors.info).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func shouldShowSyncBanner(_ status: JobBoardSyncUIState.CompanyState.Status) -> Bool {
        if case .ok(let count, _) = status, count > 0 { return false }
        return true
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

    private func reloadPrimaryResumeContext() {
        let docs = VaultReadBridge.careerResumeDocuments(collegePersistence: collegePersistence)
            .filter { !collegePersistence.careerResumeMetadata(for: $0).archived }
            .map { (documentID: $0.id, metadata: collegePersistence.careerResumeMetadata(for: $0)) }
        guard let picked = JobBoardMatchEligibility.pickPrimaryResume(documents: docs) else {
            primaryResumeContext = nil
            hasPendingResumeParse = false
            return
        }
        primaryResumeContext = JobBoardMatchEligibility.resumeContext(
            from: picked.metadata,
            documentID: picked.documentID
        )
        hasPendingResumeParse = JobBoardMatchEligibility.hasPendingResumeParse(in: picked.metadata)
            && primaryResumeContext == nil
    }

    private func trackPosting(_ posting: JobBoardPosting) {
        let recommendedID = JobBoardMatchEligibility.recommendedResumeID(
            for: posting,
            collegePersistence: collegePersistence,
            resumeParsedTextHash: primaryResumeContext?.parsedTextHash,
            fallbackDocumentID: primaryResumeContext?.documentID
        )
        let app = collegePersistence.promoteJobBoardPostingToTracker(
            posting,
            recommendedResumeID: recommendedID
        )
        markPostingSeenForList(posting)
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

            JobBoardSortFilterMenu(selection: $sortOrder)

            if !locationFilterOptions.isEmpty {
                JobBoardLocationFilterMenu(
                    selectionKey: $locationFilterKey,
                    options: locationFilterOptions
                )
            }

            JobBoardExtraFiltersMenu(
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

struct JobBoardJobListRow: View, Equatable {
    let posting: JobBoardPosting
    let isSelected: Bool
    let isNew: Bool
    let isPreviouslyViewed: Bool
    let boardStatus: CareerApplicationStatus?
    let matchDisplay: JobBoardMatchListDisplay
    let density: JobListDensity
    let company: JobBoardCompany
    var companyLabel: String? = nil
    let onTrack: () -> Void
    let onHide: () -> Void
    var onMarkSeen: () -> Void = {}

    static func == (lhs: JobBoardJobListRow, rhs: JobBoardJobListRow) -> Bool {
        lhs.posting.id == rhs.posting.id
            && lhs.posting.title == rhs.posting.title
            && lhs.posting.locationText == rhs.posting.locationText
            && lhs.posting.externalPath == rhs.posting.externalPath
            && lhs.isSelected == rhs.isSelected
            && lhs.isNew == rhs.isNew
            && lhs.isPreviouslyViewed == rhs.isPreviouslyViewed
            && lhs.boardStatus == rhs.boardStatus
            && lhs.matchDisplay == rhs.matchDisplay
            && lhs.density == rhs.density
            && lhs.company.slug == rhs.company.slug
            && lhs.companyLabel == rhs.companyLabel
    }

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(posting.title ?? "Untitled")
                        .font(.body.weight(JobBoardSelectionChrome.titleWeight(isSelected: isSelected)))
                        .foregroundStyle(
                            JobBoardSelectionChrome.titleColor(
                                isSelected: isSelected,
                                isMuted: isPreviouslyViewed && !isSelected
                            )
                        )
                        .lineLimit(2)
                    if let posted = JobBoardJobListRow.postedLabel(for: posting) {
                        Text(posted)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                HStack(spacing: 8) {
                    if let companyLabel, !companyLabel.isEmpty {
                        Text(companyLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignSystem.Colors.textLight)
                            .lineLimit(1)
                    }
                    if let jid = posting.displayJobId, !jid.isEmpty {
                        Text(jid)
                            .font(.caption.monospaced())
                            .foregroundStyle(DesignSystem.Colors.textLight.opacity(0.9))
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

            trailingChrome
        }
        .padding(.vertical, density == .compact ? 6 : 9)
        .padding(.horizontal, 4)
        .background(
            JobBoardSelectionRowBackground(isSelected: isSelected, isHovered: isHovering)
        )
        .contentShape(RoundedRectangle(cornerRadius: JobBoardSelectionChrome.cornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
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
                JobBoardOpeningsState.markPostingSeen(
                    companySlug: company.normalizedSlug,
                    externalPath: posting.externalPath
                )
                onMarkSeen()
            }
            Button("Hide this job", role: .destructive, action: onHide)
        }
    }

    @ViewBuilder
    private var trailingChrome: some View {
        HStack(spacing: 6) {
            switch matchDisplay {
            case .hidden:
                EmptyView()
            case .awaitingResumeParse:
                Text("Parsing…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .awaitingDescription:
                EmptyView()
            case .scored(let overall):
                Text("\(overall)%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(CareerResumeLibraryTheme.jobMatchTierColor(for: overall))
            }

            if density == .comfortable, boardStatus == nil, isHovering {
                Button(action: onTrack) {
                    Label("Track", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if density == .comfortable {
                if let boardStatus {
                    JobBoardStatusPill(status: boardStatus)
                } else if isNew {
                    newBadge
                } else if isPreviouslyViewed {
                    previouslyViewedLabel
                }
            }
        }
    }

    private var previouslyViewedLabel: some View {
        Text("Previously Viewed")
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.textLight)
            .lineLimit(1)
    }

    static func postedLabel(for posting: JobBoardPosting) -> String? {
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
            .background(DesignSystem.Colors.primary.opacity(0.12))
            .foregroundStyle(DesignSystem.Colors.primary)
            .clipShape(Capsule())
            .transition(.opacity)
    }
}

struct JobBoardStatusPill: View {
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
