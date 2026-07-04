// JobBoardSmartBoardSheet.swift
// Feature: Career / Job Board
// Purpose: Create or edit a smart board combining companies with AI-assisted filters.

import SwiftUI

struct JobBoardSmartBoardSheet: View {
    var existingBoard: JobBoardSmartBoard?
    var onSave: (JobBoardSmartBoard) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedCompanyIDs: Set<UUID> = []
    @State private var smartQuery = ""
    @State private var criteria = JobBoardSmartFilterCriteria()
    @State private var sortOrder: JobBoardUnifiedSort = .relevance
    @State private var interpretation: JobBoardSmartFilterInterpretation?
    @State private var isInterpreting = false
    @State private var previewCount: Int?
    @State private var previewTask: Task<Void, Never>?

    private var companiesStore: JobBoardCompaniesStore { JobBoardCompaniesStore.shared }
    private var enabledCompanies: [JobBoardCompany] { companiesStore.enabledCompanies }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedCompanyIDs.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameSection
                    companiesSection
                    smartQuerySection
                    if let interpretation {
                        interpretationSection(interpretation)
                    }
                    optionsSection
                    if let previewCount {
                        previewSection(previewCount)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            footer
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 680)
        .background(DesignSystem.Colors.surface)
        .onAppear(perform: loadExisting)
        .onChange(of: name) { _, _ in schedulePreview() }
        .onChange(of: selectedCompanyIDs) { _, _ in schedulePreview() }
        .onChange(of: smartQuery) { _, _ in schedulePreview() }
        .onChange(of: criteria) { _, _ in schedulePreview() }
        .onDisappear { previewTask?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingBoard == nil ? "Create Smart Board" : "Edit Smart Board")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignSystem.Colors.textMain)
                Text("Combine companies into one tab with AI-assisted filters.")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Board name")
                .font(.subheadline.weight(.semibold))
            TextField("e.g. Remote SWE internships", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var companiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Companies")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !enabledCompanies.isEmpty {
                    Button(selectedCompanyIDs.count == enabledCompanies.count ? "Clear all" : "Select all") {
                        if selectedCompanyIDs.count == enabledCompanies.count {
                            selectedCompanyIDs = []
                        } else {
                            selectedCompanyIDs = Set(enabledCompanies.map(\.id))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            if enabledCompanies.isEmpty {
                Text("Track at least one company before creating a smart board.")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            } else {
                VStack(spacing: 0) {
                    ForEach(enabledCompanies) { company in
                        Toggle(isOn: companyBinding(company.id)) {
                            HStack(spacing: 10) {
                                Text(company.displayName)
                                    .font(.body)
                                Text(company.platform.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 6)
                        if company.id != enabledCompanies.last?.id {
                            Divider().opacity(0.25)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DesignSystem.Colors.bgMain.opacity(0.5))
                )
            }
        }
    }

    private var smartQuerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you looking for?")
                .font(.subheadline.weight(.semibold))
            Text("Describe roles, skills, schedule, and context. College uses AI plus resume match data to rank results.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
            TextEditor(text: $smartQuery)
                .font(.body)
                .frame(minHeight: 88, maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
            HStack(spacing: 10) {
                Button {
                    Task { await refineWithAI() }
                } label: {
                    Label(isInterpreting ? "Refining…" : "Refine filters with AI", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(smartQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInterpreting)
                if isInterpreting {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func interpretationSection(_ interpretation: JobBoardSmartFilterInterpretation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI interpretation")
                .font(.subheadline.weight(.semibold))
            if let explanation = interpretation.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            FlowLayoutChips(items: chipLabels(from: interpretation))
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.subheadline.weight(.semibold))
            Picker("Sort by", selection: $sortOrder) {
                ForEach(JobBoardUnifiedSort.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            Toggle("Remote only", isOn: $criteria.remoteOnly)
                .toggleStyle(.checkbox)
            Toggle("Hide roles already on my board", isOn: $criteria.hideOnBoard)
                .toggleStyle(.checkbox)
            HStack {
                Text("Minimum resume match")
                    .font(.body)
                Spacer()
                Text(criteria.minMatchScore.map { "\($0)%" } ?? "Any")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }
            Slider(
                value: Binding(
                    get: { Double(criteria.minMatchScore ?? 0) },
                    set: { criteria.minMatchScore = $0 <= 0 ? nil : Int($0.rounded()) }
                ),
                in: 0...90,
                step: 5
            )
        }
    }

    private func previewSection(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("\(count) opening\(count == 1 ? "" : "s") match this board right now")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignSystem.Colors.textMain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignSystem.Colors.accent.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(existingBoard == nil ? "Create board" : "Save changes") {
                saveBoard()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(DesignSystem.Colors.bgMain.opacity(0.4))
    }

    private func companyBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedCompanyIDs.contains(id) },
            set: { isOn in
                if isOn { selectedCompanyIDs.insert(id) }
                else { selectedCompanyIDs.remove(id) }
            }
        )
    }

    private func loadExisting() {
        guard let existingBoard else {
            selectedCompanyIDs = Set(enabledCompanies.map(\.id))
            return
        }
        name = existingBoard.name
        selectedCompanyIDs = Set(existingBoard.companyIDs)
        smartQuery = existingBoard.criteria.smartQuery
        criteria = existingBoard.criteria
        sortOrder = existingBoard.sortOrder
        schedulePreview()
    }

    private func refineWithAI() async {
        isInterpreting = true
        defer { isInterpreting = false }
        let query = smartQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let result = await JobBoardSmartFilterEngine.interpretQuery(query)
        interpretation = result
        criteria = result.merged(into: criteria, query: query)
    }

    private func saveBoard() {
        var board = existingBoard ?? JobBoardSmartBoard(name: name, companyIDs: Array(selectedCompanyIDs))
        board.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        board.companyIDs = Array(selectedCompanyIDs)
        board.criteria = criteria
        board.criteria.smartQuery = smartQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        board.sortOrder = sortOrder
        board.updatedAt = Date()
        onSave(board)
        dismiss()
    }

    private func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await updatePreview()
        }
    }

    @MainActor
    private func updatePreview() async {
        let companies = enabledCompanies.filter { selectedCompanyIDs.contains($0.id) }
        guard !companies.isEmpty else {
            previewCount = nil
            return
        }
        let slugs = companies.map(\.normalizedSlug)
        let postings = JobBoardReadBridge.postings(companySlugs: slugs)
        var draftCriteria = criteria
        draftCriteria.smartQuery = smartQuery
        let queryEmbedding = await JobBoardSmartFilterEngine.embedQueryOffMain(draftCriteria.smartQuery)
        let filtered = JobBoardSmartFilterEngine.filterAndRank(
            postings: postings,
            companies: companies,
            criteria: draftCriteria,
            sortOrder: sortOrder,
            searchText: "",
            matchScoresByPath: [:],
            queryEmbedding: queryEmbedding,
            postingEmbeddings: [:]
        )
        previewCount = filtered.count
    }

    private func chipLabels(from interpretation: JobBoardSmartFilterInterpretation) -> [String] {
        var chips: [String] = []
        chips.append(contentsOf: interpretation.keywords.map { "Keyword: \($0)" })
        chips.append(contentsOf: interpretation.requiredSkills.map { "Skill: \($0)" })
        chips.append(contentsOf: interpretation.jobTypes.map { "Type: \($0)" })
        chips.append(contentsOf: interpretation.scheduleTypes.map { "Schedule: \($0)" })
        chips.append(contentsOf: interpretation.locations.map { "Location: \($0)" })
        if interpretation.remoteOnly == true { chips.append("Remote only") }
        if let min = interpretation.minMatchScore { chips.append("Match ≥ \(min)%") }
        return chips
    }
}

/// Simple horizontal chip flow for interpreted filter tags.
private struct FlowLayoutChips: View {
    let items: [String]

    var body: some View {
        if items.isEmpty {
            Text("No structured filters extracted yet.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textLight)
        } else {
            FlexibleChipWrap(items: items)
        }
    }
}

private struct FlexibleChipWrap: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chunked(items, size: 3), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(DesignSystem.Colors.accent.opacity(0.12)))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [items] }
        var rows: [[String]] = []
        var index = 0
        while index < items.count {
            let end = min(index + size, items.count)
            rows.append(Array(items[index..<end]))
            index = end
        }
        return rows
    }
}
