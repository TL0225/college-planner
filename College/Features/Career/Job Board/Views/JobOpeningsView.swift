// JobOpeningsView.swift
// Feature: Career / Job Board
// Purpose: Browse scraped external job postings by company or smart board.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct JobOpeningsView: View {
    @Environment(AppContainer.self) private var container
    private var lmsCoordinator: LMSWebCoordinator { container.lmsCoordinator }
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @ObservedObject private var jobBoardCoordinator = JobBoardSyncCoordinator.shared
    @ObservedObject private var logoStore = JobBoardCompanyLogoStore.shared

    var onNavigateToApplicationTracker: () -> Void = {}

    private var companiesStore: JobBoardCompaniesStore { JobBoardCompaniesStore.shared }
    private var smartBoardsStore: JobBoardSmartBoardsStore { JobBoardSmartBoardsStore.shared }

    @State private var sidebarSelection: JobBoardSidebarTag?
    @State private var selectedPostingPath: String?
    @State private var showCompanyPicker = false
    @State private var showSmartBoardSheet = false
    @State private var editingSmartBoard: JobBoardSmartBoard?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    private var selectedCompany: JobBoardCompany? {
        guard case .company(let id) = sidebarSelection else { return nil }
        return companiesStore.enabledCompanies.first { $0.id == id }
    }

    private var selectedSmartBoard: JobBoardSmartBoard? {
        guard case .smartBoard(let id) = sidebarSelection else { return nil }
        return smartBoardsStore.board(id: id)
    }

    private var isJobDetailPresented: Bool {
        guard let path = selectedPostingPath,
              let parsed = JobBoardPostingSelectionKey.parse(path),
              JobBoardReadBridge.posting(companySlug: parsed.companySlug, externalPath: parsed.externalPath) != nil
        else { return false }
        return true
    }

    var body: some View {
        Group {
            if companiesStore.enabledCount == 0 {
                emptyNoCompanies
            } else {
                openingsSplitView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .onAppear {
            UserDefaults.standard.set(true, forKey: "career.jobBoards.visited.v1")
            jobBoardCoordinator.rebuildIdleUIState()
            selectDefaultSidebarIfNeeded()
            for company in companiesStore.enabledCompanies {
                logoStore.loadLogoIfNeeded(for: company)
            }
        }
        .onChange(of: companiesStore.enabledCompanies.map(\.id)) { _, _ in
            selectDefaultSidebarIfNeeded()
        }
        .onChange(of: sidebarSelection) { _, _ in
            selectedPostingPath = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .jobBoardImportDidFinish)) { _ in
            jobBoardCoordinator.rebuildIdleUIState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerToggleInspector)) { _ in
            if selectedPostingPath != nil {
                selectedPostingPath = nil
            } else {
                NotificationCenter.default.post(name: .collegeCareerOpenInspectorSelection, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerOpenInspectorSelection)) { _ in
            openFirstPostingIfNeeded()
        }
        .sheet(isPresented: $showCompanyPicker) {
            JobBoardCompanyPickerSheet { company in
                sidebarSelection = .company(company.id)
                JobBoardOpeningsState.markCompanyViewed(slug: company.normalizedSlug)
            }
        }
        .sheet(isPresented: $showSmartBoardSheet) {
            JobBoardSmartBoardSheet(existingBoard: editingSmartBoard) { board in
                if editingSmartBoard != nil {
                    smartBoardsStore.updateBoard(board)
                } else {
                    smartBoardsStore.addBoard(board)
                }
                sidebarSelection = .smartBoard(board.id)
                JobBoardOpeningsState.setLastSelectedSidebarTag(.smartBoard(board.id))
            }
        }
        .onChange(of: showSmartBoardSheet) { _, isPresented in
            if !isPresented { editingSmartBoard = nil }
        }
    }

  // MARK: - Layout

    private var openingsSplitView: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            companySidebarColumn
                .frame(width: JobBoardOpeningsLayout.companySidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            CareerTrailingInspectorLayout(
                isInspectorPresented: Binding(
                    get: { isJobDetailPresented },
                    set: { if !$0 { selectedPostingPath = nil } }
                ),
                inspectorWidth: JobBoardOpeningsLayout.detailIdealWidth,
                reduceMotion: motionReduced
            ) {
                openingsContentColumn
                    .frame(
                        minWidth: JobBoardOpeningsLayout.jobListMinWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
            } inspector: {
                if let path = selectedPostingPath,
                   let parsed = JobBoardPostingSelectionKey.parse(path),
                   let posting = JobBoardReadBridge.posting(
                        companySlug: parsed.companySlug,
                        externalPath: parsed.externalPath
                    ),
                   let company = companiesStore.enabledCompanies.first(where: {
                       $0.normalizedSlug == parsed.companySlug
                   }) {
                    JobBoardJobDetailPane(
                        posting: posting,
                        company: company,
                        onClose: { selectedPostingPath = nil },
                        onInterested: { app in
                            container.careerNavigationRouter.boardJob(id: app.objectID)
                        },
                        onNavigateToApplicationTracker: onNavigateToApplicationTracker,
                        embeddedInNavigationSplit: true
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.top, DesignSystem.Spacing.lg)
        .padding(.bottom, DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var openingsContentColumn: some View {
        if let board = selectedSmartBoard {
            JobBoardUnifiedJobsView(
                board: board,
                companies: smartBoardsStore.resolvedCompanies(for: board),
                selectedPostingPath: $selectedPostingPath,
                onEditBoard: {
                    editingSmartBoard = board
                    showSmartBoardSheet = true
                },
                onNavigateToApplicationTracker: onNavigateToApplicationTracker
            )
            .id("\(board.id)-\(board.updatedAt.timeIntervalSince1970)")
        } else if let company = selectedCompany {
            JobBoardCompanyJobsView(
                company: company,
                selectedPostingPath: $selectedPostingPath,
                onNavigateToApplicationTracker: onNavigateToApplicationTracker
            )
            .id(company.id)
        } else {
            selectCompanyPlaceholder
        }
    }

    private var companySidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.35)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    sidebarSectionHeader(
                        title: "Smart Boards",
                        addHelp: "Create a smart board",
                        onAdd: {
                            editingSmartBoard = nil
                            showSmartBoardSheet = true
                        }
                    )

                    ForEach(smartBoardsStore.boards) { board in
                        Button {
                            sidebarSelection = .smartBoard(board.id)
                        } label: {
                            JobBoardSmartBoardSidebarRow(
                                board: board,
                                companyCount: smartBoardsStore.resolvedCompanies(for: board).count,
                                isSelected: sidebarSelection == .smartBoard(board.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit board") {
                                editingSmartBoard = board
                                showSmartBoardSheet = true
                            }
                            Button("Delete board", role: .destructive) {
                                smartBoardsStore.removeBoard(id: board.id)
                                if sidebarSelection == .smartBoard(board.id) {
                                    selectDefaultSidebarIfNeeded()
                                }
                            }
                        }
                    }

                    sidebarSectionHeader(
                        title: "Companies",
                        addHelp: "Track a company",
                        onAdd: { showCompanyPicker = true },
                        trailing: {
                            Button {
                                Task { await jobBoardCoordinator.scrapeAllEnabledCompanies(force: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .help(refreshAllCompaniesHelp)
                            .disabled(jobBoardCoordinator.uiState.isAnyScrapeInFlight)
                        }
                    )
                    .padding(.top, 10)

                    ForEach(companiesStore.enabledCompanies) { company in
                        Button {
                            sidebarSelection = .company(company.id)
                        } label: {
                            JobBoardCompanySidebarRow(
                                company: company,
                                isSelected: sidebarSelection == .company(company.id),
                                state: jobBoardCoordinator.uiState.companies.first { $0.slug == company.normalizedSlug },
                                newCount: collegePersistence.newOpeningsCount(companySlug: company.normalizedSlug),
                                onScrape: { Task { await jobBoardCoordinator.scrapeCompany(company, force: true) } }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .onChange(of: sidebarSelection) { _, newSelection in
                guard let newSelection else { return }
                JobBoardOpeningsState.setLastSelectedSidebarTag(newSelection)
                if case .company(let id) = newSelection,
                   let company = companiesStore.enabledCompanies.first(where: { $0.id == id }) {
                    JobBoardOpeningsState.setLastSelectedCompanyID(id)
                    JobBoardOpeningsState.markCompanyViewed(slug: company.normalizedSlug)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.bgMain.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sidebarSectionHeader(
        title: String,
        addHelp: String,
        onAdd: @escaping () -> Void,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Spacer(minLength: 0)
            trailing()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(addHelp)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var refreshAllCompaniesHelp: String {
        let interval = JobBoardRefreshScheduler.shared.selectedIntervalSeconds
        let schedule = interval > 0
            ? "Automatic refresh: \(JobBoardRefreshIntervalOption.fromStoredSeconds(Int(interval)).displayName). "
            : "Automatic refresh is off (manual only). "
        return schedule + "Change refresh schedule in Settings → Career. Refreshes all companies now."
    }

    private var selectCompanyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(DesignSystem.Fonts.main(size: 36))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Text("Select a board or company")
                .font(.title3)
            Text("Create a smart board to search across companies, or pick a single company to browse.")
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Create smart board") {
                editingSmartBoard = nil
                showSmartBoardSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyNoCompanies: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(DesignSystem.Fonts.main(size: 40))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Text("Track companies to browse openings")
                .font(.title3)
            Text("Search for employers or paste a careers page URL. College supports Workday, Greenhouse, Lever, and more.")
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textLight)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Select a company") {
                showCompanyPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectDefaultSidebarIfNeeded() {
        let enabled = companiesStore.enabledCompanies
        guard !enabled.isEmpty else {
            sidebarSelection = nil
            JobBoardOpeningsState.setLastSelectedSidebarTag(nil)
            JobBoardOpeningsState.setLastSelectedCompanyID(nil)
            return
        }

        if let sidebarSelection, isSidebarSelectionValid(sidebarSelection) {
            return
        }

        if let restored = JobBoardOpeningsState.lastSelectedSidebarTag(),
           isSidebarSelectionValid(restored) {
            sidebarSelection = restored
            return
        }

        if let restoredCompany = JobBoardOpeningsState.lastSelectedCompanyID(),
           enabled.contains(where: { $0.id == restoredCompany }) {
            sidebarSelection = .company(restoredCompany)
            return
        }

        sidebarSelection = .company(enabled.first!.id)
    }

    private func isSidebarSelectionValid(_ tag: JobBoardSidebarTag) -> Bool {
        switch tag {
        case .company(let id):
            return companiesStore.enabledCompanies.contains { $0.id == id }
        case .smartBoard(let id):
            return smartBoardsStore.board(id: id) != nil
        }
    }

    private func openFirstPostingIfNeeded() {
        guard selectedPostingPath == nil else { return }
        if let board = selectedSmartBoard {
            let companies = smartBoardsStore.resolvedCompanies(for: board)
            let slugs = companies.map(\.normalizedSlug)
            if let first = JobBoardReadBridge.postings(companySlugs: slugs).first {
                selectedPostingPath = JobBoardPostingSelectionKey.tag(
                    companySlug: first.companySlug,
                    externalPath: first.externalPath
                )
            }
            return
        }
        guard let company = selectedCompany,
              let first = JobBoardReadBridge.companyPostings(companySlug: company.normalizedSlug).first
        else { return }
        selectedPostingPath = JobBoardPostingSelectionKey.tag(
            companySlug: company.normalizedSlug,
            externalPath: first.externalPath
        )
    }
}

// MARK: - Sidebar rows

private struct JobBoardSmartBoardSidebarRow: View {
    let board: JobBoardSmartBoard
    let companyCount: Int
    let isSelected: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textLight)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(board.normalizedName)
                    .font(.subheadline.weight(JobBoardSelectionChrome.titleWeight(isSelected: isSelected)))
                    .foregroundStyle(JobBoardSelectionChrome.titleColor(isSelected: isSelected, isMuted: false))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(companyCount) companies")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            JobBoardSidebarSelectionBackground(isSelected: isSelected, isHovered: isHovering)
        )
        .contentShape(RoundedRectangle(cornerRadius: JobBoardSelectionChrome.cornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

private struct JobBoardCompanySidebarRow: View {
    @ObservedObject private var logoStore = JobBoardCompanyLogoStore.shared

    let company: JobBoardCompany
    let isSelected: Bool
    let state: JobBoardSyncUIState.CompanyState?
    let newCount: Int
    let onScrape: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            companyLogo
            VStack(alignment: .leading, spacing: 2) {
                Text(company.displayName)
                    .font(.subheadline.weight(JobBoardSelectionChrome.titleWeight(isSelected: isSelected)))
                    .foregroundStyle(JobBoardSelectionChrome.titleColor(isSelected: isSelected, isMuted: false))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                trailingBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            JobBoardSidebarSelectionBackground(isSelected: isSelected, isHovered: isHovering)
        )
        .contentShape(RoundedRectangle(cornerRadius: JobBoardSelectionChrome.cornerRadius, style: .continuous))
        .help(companyTooltip)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Scrape now", action: onScrape)
        }
        .onAppear {
            logoStore.loadLogoIfNeeded(for: company)
        }
    }

    @ViewBuilder
    private var companyLogo: some View {
        Group {
            if let image = logoStore.image(for: company) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "building.2")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
        }
        .frame(width: 24, height: 24)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.1) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isSelected ? DesignSystem.Colors.primary.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var trailingBadge: some View {
        switch state?.status {
        case .scraping(let progress):
            if let progress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            } else {
                ProgressView().controlSize(.mini)
            }
        case .importing:
            ProgressView().controlSize(.mini)
        case .ok, .error, .idle, .none:
            jobCountBadge
        }
    }

    @ViewBuilder
    private var jobCountBadge: some View {
        HStack(spacing: 6) {
            if newCount > 0 {
                Text("+\(newCount) new")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            Text(JobBoardSyncStatusPresentation.sidebarSubtitle(for: state?.status))
                .font(.caption2)
                .foregroundStyle(state?.status.isError == true ? Color.orange : DesignSystem.Colors.textLight)
        }
    }

    private var companyTooltip: String {
        var lines: [String] = [company.displayName]
        if let status = state?.status {
            lines.append(JobBoardSyncStatusPresentation.bannerTitle(for: status))
            lines.append(JobBoardSyncStatusPresentation.bannerMessage(for: status, companyName: company.displayName))
        } else {
            lines.append("Not scraped yet")
        }
        let interval = JobBoardRefreshScheduler.shared.selectedIntervalSeconds
        if interval > 0 {
            let label = JobBoardRefreshIntervalOption.fromStoredSeconds(Int(interval)).displayName
            lines.append("Scheduled refresh: \(label)")
        } else {
            lines.append("Scheduled refresh: manual only")
        }
        lines.append("Right-click to scrape now.")
        return lines.joined(separator: "\n")
    }
}

private extension JobBoardSyncUIState.CompanyState.Status {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
