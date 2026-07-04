// JobBoardUnifiedJobsView.swift
// Feature: Career / Job Board
// Purpose: Multi-company smart board list with AI-assisted filtering and ranking.

import SwiftUI
import CollegeCareer

struct JobBoardUnifiedJobsView: View {
    @Environment(AppContainer.self) private var container
    private var notifications: AppNotificationCenter { container.appNotifications }
    private var collegePersistence: CollegePersistence { container.persistence }
    @ObservedObject private var jobBoardCoordinator = JobBoardSyncCoordinator.shared

    let board: JobBoardSmartBoard
    let companies: [JobBoardCompany]

    @Binding var selectedPostingPath: String?
    var onEditBoard: () -> Void
    var onNavigateToApplicationTracker: () -> Void = {}

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var postings: [JobBoardPosting] = []
    @State private var postingsReloadTask: Task<Void, Never>?
    @State private var filteredPostings: [JobBoardFilteredPosting] = []
    @State private var cachedMatchDisplays: [UUID: JobBoardMatchListDisplay] = [:]
    @State private var cachedNewFlags: [UUID: Bool] = [:]
    @State private var cachedViewedFlags: [UUID: Bool] = [:]
    @State private var cachedBoardStatuses: [UUID: CareerApplicationStatus?] = [:]
    @State private var primaryResumeContext: JobBoardResumeMatchContext?
    @State private var hasPendingResumeParse = false
    @State private var matchScoresByPath: [String: Int] = [:]
    @State private var queryEmbedding: [Float]?
    @State private var postingEmbeddings: [UUID: [Float]] = [:]
    @State private var rankingTask: Task<Void, Never>?
    @State private var isRanking = false
    @FocusState private var listFocused: Bool

    @AppStorage("jobList.density") private var listDensityRaw: String = JobListDensity.comfortable.rawValue

    @State private var localSortOrder: JobBoardUnifiedSort = .relevance

    private var density: JobListDensity { JobListDensity(rawValue: listDensityRaw) ?? .comfortable }
    private var companyBySlug: [String: JobBoardCompany] {
        Dictionary(uniqueKeysWithValues: companies.map { ($0.normalizedSlug, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            boardHeader
            smartFilterBanner
            toolbarRow
            Divider().opacity(0.35)

            Group {
                if filteredPostings.isEmpty {
                    emptyJobs
                } else {
                    List(selection: $selectedPostingPath) {
                        ForEach(filteredPostings) { item in
                            let posting = item.posting
                            let slug = posting.companySlug.lowercased()
                            let company = companyBySlug[slug] ?? companies.first!
                            JobBoardJobListRow(
                                posting: posting,
                                isSelected: selectedPostingPath == selectionTag(for: posting),
                                isNew: cachedNewFlags[posting.id] ?? false,
                                isPreviouslyViewed: cachedViewedFlags[posting.id] ?? false,
                                boardStatus: cachedBoardStatuses[posting.id] ?? nil,
                                matchDisplay: cachedMatchDisplays[posting.id] ?? .hidden,
                                density: density,
                                company: company,
                                companyLabel: company.displayName,
                                onTrack: { trackPosting(posting) },
                                onHide: {
                                    JobBoardOpeningsState.hidePosting(
                                        companySlug: slug,
                                        externalPath: posting.externalPath
                                    )
                                    refreshFilteredList()
                                },
                                onMarkSeen: { markPostingSeen(posting) }
                            )
                            .equatable()
                            .tag(selectionTag(for: posting))
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
            .onKeyPress(.escape) {
                selectedPostingPath = nil
                return .handled
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .id(board.id)
        .onAppear {
            localSortOrder = board.sortOrder
            refreshPostings()
            reloadPrimaryResumeContext()
            selectFirstJobIfNeeded()
        }
        .onChange(of: board.id) { _, _ in
            localSortOrder = board.sortOrder
            selectedPostingPath = nil
            refreshPostings()
            selectFirstJobIfNeeded()
        }
        .onChange(of: board.updatedAt) { _, _ in
            localSortOrder = board.sortOrder
            refreshFilteredList()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            guard !jobBoardCoordinator.uiState.isAnyScrapeInFlight else { return }
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
                    refreshFilteredList()
                }
            }
        }
        .onChange(of: selectedPostingPath) { _, path in
            guard let path,
                  let parsed = JobBoardPostingSelectionKey.parse(path),
                  let posting = postings.first(where: {
                      $0.companySlug.lowercased() == parsed.companySlug && $0.externalPath == parsed.externalPath
                  })
            else { return }
            markPostingSeen(posting)
        }
        .onDisappear {
            rankingTask?.cancel()
            searchDebounceTask?.cancel()
        }
    }

    private var boardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.accent)
            Text(board.normalizedName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .lineLimit(1)
            Text("\(filteredPostings.count) openings · \(companies.count) companies")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
            Spacer(minLength: 8)
            Button(action: onEditBoard) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Edit smart board filters")
            Button {
                Task { await jobBoardCoordinator.scrapeAllEnabledCompanies(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh all companies in this board")
            .disabled(jobBoardCoordinator.uiState.isAnyScrapeInFlight)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var smartFilterBanner: some View {
        if !board.criteria.smartQuery.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(DesignSystem.Colors.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart search")
                        .font(.caption.weight(.semibold))
                    Text(board.criteria.smartQuery)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .fixedSize(horizontal: false, vertical: true)
                    if isRanking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Ranking with resume match + context…")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.textLight)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.accent.opacity(0.06))
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 10) {
            TextField("Search within results", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

            Picker("Sort", selection: $localSortOrder) {
                ForEach(JobBoardUnifiedSort.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .onChange(of: localSortOrder) { _, newValue in
                var updated = board
                updated.sortOrder = newValue
                JobBoardSmartBoardsStore.shared.updateBoard(updated)
                refreshFilteredList()
            }

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
            Text("No matching openings")
                .font(.title3)
            Text("Try editing the smart board, clearing search, or refreshing company data.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Edit smart board", action: onEditBoard)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshPostings() {
        let slugs = companies.map(\.normalizedSlug)
        postingsReloadTask?.cancel()
        postingsReloadTask = Task {
            let fetched = await JobBoardReadBridge.postingsOffMain(companySlugs: slugs)
            guard !Task.isCancelled else { return }
            if fetched.isEmpty, !postings.isEmpty {
                schedulePostingsReloadIfNeeded(slugs: slugs)
                return
            }
            postings = fetched
            rebuildListRowCaches()
            scheduleSemanticRanking()
            refreshFilteredList()
            guard postings.isEmpty else { return }
            schedulePostingsReloadIfNeeded(slugs: slugs)
        }
    }

    private func schedulePostingsReloadIfNeeded(slugs: [String]) {
        postingsReloadTask?.cancel()
        postingsReloadTask = Task {
            ModelMergeCoalescer.flushNow()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            var combined: [JobBoardPosting] = []
            for slug in slugs {
                let batch = await JobBoardReadBridge.companyPostingsOffMain(companySlug: slug)
                combined.append(contentsOf: batch)
            }
            guard !Task.isCancelled else { return }
            guard combined.count >= postings.count else { return }
            guard !combined.isEmpty || postings.isEmpty else { return }
            postings = combined
            rebuildListRowCaches()
            scheduleSemanticRanking()
            refreshFilteredList()
        }
    }

    private func rebuildListRowCaches() {
        let resumeHash = primaryResumeContext?.parsedTextHash
        let hasParsedResume = primaryResumeContext != nil
        matchScoresByPath = JobBoardSmartFilterEngine.buildMatchScoreIndex(
            postings: postings,
            collegePersistence: collegePersistence,
            resumeHash: resumeHash
        )

        var displays: [UUID: JobBoardMatchListDisplay] = [:]
        var newFlags: [UUID: Bool] = [:]
        var viewedFlags: [UUID: Bool] = [:]
        var statuses: [UUID: CareerApplicationStatus?] = [:]

        for posting in postings {
            let slug = posting.companySlug.lowercased()
            let path = posting.externalPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cachedScore = matchScoresByPath["\(slug)|\(path)"]
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

    private func refreshFilteredList() {
        let trackedIDs: Set<UUID> = board.criteria.hideOnBoard
            ? Set(postings.compactMap { collegePersistence.isPostingTracked($0) ? $0.id : nil })
            : []

        var list = postings
        if board.criteria.hideOnBoard {
            list = list.filter { !trackedIDs.contains($0.id) }
        }

        filteredPostings = JobBoardSmartFilterEngine.filterAndRank(
            postings: list,
            companies: companies,
            criteria: board.criteria,
            sortOrder: localSortOrder,
            searchText: debouncedSearchText,
            matchScoresByPath: matchScoresByPath,
            queryEmbedding: queryEmbedding,
            postingEmbeddings: postingEmbeddings
        )
    }

    private func scheduleSemanticRanking() {
        rankingTask?.cancel()
        guard board.criteria.hasSmartRanking else {
            queryEmbedding = nil
            postingEmbeddings = [:]
            refreshFilteredList()
            return
        }
        rankingTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isRanking = true }
            let query = board.criteria.smartQuery
            let snapshots = await MainActor.run {
                JobBoardSmartFilterEngine.embeddingSnapshots(from: postings)
            }
            async let queryVector = JobBoardSmartFilterEngine.embedQueryOffMain(query)
            async let postingVectors = JobBoardSmartFilterEngine.embedPostingsOffMain(snapshots)
            let vectors = await (queryVector, postingVectors)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                queryEmbedding = vectors.0
                postingEmbeddings = vectors.1
                isRanking = false
                refreshFilteredList()
            }
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

    private func selectionTag(for posting: JobBoardPosting) -> String {
        JobBoardPostingSelectionKey.tag(
            companySlug: posting.companySlug,
            externalPath: posting.externalPath
        )
    }

    private func selectPosting(_ posting: JobBoardPosting) {
        selectedPostingPath = selectionTag(for: posting)
    }

    private func selectFirstJobIfNeeded() {
        guard selectedPostingPath == nil, let first = filteredPostings.first else { return }
        selectPosting(first.posting)
    }

    private func moveSelection(delta: Int) {
        guard !filteredPostings.isEmpty else { return }
        let postingsOnly = filteredPostings.map(\.posting)
        if let path = selectedPostingPath,
           let parsed = JobBoardPostingSelectionKey.parse(path),
           let current = postingsOnly.first(where: {
               $0.companySlug.lowercased() == parsed.companySlug && $0.externalPath == parsed.externalPath
           }),
           let idx = postingsOnly.firstIndex(where: { $0.id == current.id }) {
            let next = min(max(0, idx + delta), postingsOnly.count - 1)
            selectPosting(postingsOnly[next])
        } else if delta >= 0 {
            selectPosting(postingsOnly[0])
        } else {
            selectPosting(postingsOnly[postingsOnly.count - 1])
        }
    }

    private func markPostingSeen(_ posting: JobBoardPosting) {
        let slug = posting.companySlug.lowercased()
        JobBoardOpeningsState.markPostingSeen(companySlug: slug, externalPath: posting.externalPath)
        cachedNewFlags[posting.id] = false
        cachedViewedFlags[posting.id] = true
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
        markPostingSeen(posting)
        notifications.post(kind: .success, title: "Added to board", message: app.title ?? "Role")
    }
}
