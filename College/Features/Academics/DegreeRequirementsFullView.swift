// DegreeRequirementsFullView.swift
// Feature: Academics
// Purpose: Academics module — DegreeRequirementsFullView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - DegreeRequirementsFullView
// Full-page sheet that lists every requirement category and course for a degree/minor.

struct DegreeRequirementsFullView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    let degree: AcademicsAuditPanel.AuditDegree

    private var collegePersistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) private var dismiss

    // MARK: - Data

    struct FullCategory: Identifiable {
        let id = UUID()
        let title: String
        let creditsRequired: Int
        let items: [FullItem]
    }

    struct FullItem: Identifiable {
        let id = UUID()
        let code: String
        let title: String
        let credits: String
        let isCompleted: Bool
    }

    @State private var categories: [FullCategory] = []
    @State private var expandedCategories: Set<UUID> = []
    @State private var isLoading = true
    @State private var catalogPartialMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "f9fafb")
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading requirements…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let catalogPartialMessage, categories.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(catalogPartialMessage)
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "6b7280"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if categories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 36))
                            .foregroundColor(Color(hex: "d1d5db"))
                        Text("No requirements found.")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "9ca3af"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Summary pill row
                            summaryRow

                            // Requirement categories
                            ForEach(categories) { cat in
                                categoryCard(cat)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(degree.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(degree.color)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Degree Requirements")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "1f2937"))
                        Text(kindLabel)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "6b7280"))
                    }
                }
            }
        }
        .task { await loadFull() }
    }

    // MARK: - Kind label

    private var kindLabel: String {
        switch degree.kind {
        case .minor: return "Minor"
        case .major: return "Major / Concentration"
        }
    }

    // MARK: - Summary row

    private var summaryRow: some View {
        let completed   = categories.flatMap(\.items).filter(\.isCompleted).count
        let total       = categories.flatMap(\.items).count
        let totalCredits = categories.reduce(0) { $0 + $1.creditsRequired }

        return HStack(spacing: 10) {
            pill(
                icon: "checkmark.circle.fill",
                label: "\(completed)/\(total) Courses",
                color: Color(hex: "22c55e")
            )
            if totalCredits > 0 {
                pill(
                    icon: "graduationcap.fill",
                    label: "\(totalCredits) Credits",
                    color: degree.color
                )
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func pill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "374151"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Category card

    @ViewBuilder
    private func categoryCard(_ cat: FullCategory) -> some View {
        let isExpanded = expandedCategories.contains(cat.id)
        let completedCount = cat.items.filter(\.isCompleted).count

        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCategories.remove(cat.id)
                    } else {
                        expandedCategories.insert(cat.id)
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cat.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "1f2937"))
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text("\(completedCount)/\(cat.items.count) courses")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "9ca3af"))
                            if cat.creditsRequired > 0 {
                                Text("·")
                                    .foregroundColor(Color(hex: "d1d5db"))
                                Text("\(cat.creditsRequired) cr required")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "9ca3af"))
                            }
                        }
                    }
                    Spacer()

                    // Mini progress
                    ZStack {
                        Circle()
                            .stroke(Color(hex: "f3f4f6"), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: cat.items.isEmpty ? 0 : CGFloat(completedCount) / CGFloat(cat.items.count))
                            .stroke(degree.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 26, height: 26)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "9ca3af"))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Course list
            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(cat.items) { item in
                        courseRow(item)
                        if item.id != cat.items.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "f3f4f6"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    // MARK: - Course row

    private func courseRow(_ item: FullItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundColor(item.isCompleted ? Color(hex: "22c55e") : Color(hex: "d1d5db"))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.code)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(item.isCompleted ? Color(hex: "9ca3af") : Color(hex: "111827"))
                    .strikethrough(item.isCompleted, color: Color(hex: "9ca3af"))
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 11))
                        .foregroundColor(item.isCompleted ? Color(hex: "b0b7c3") : Color(hex: "6b7280"))
                        .strikethrough(item.isCompleted, color: Color(hex: "b0b7c3"))
                        .lineLimit(1)
                }
            }

            Spacer()

            if !item.credits.isEmpty {
                Text(item.credits)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "9ca3af"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: "f9fafb"))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            item.isCompleted
                ? Color(hex: "f0fdf4").opacity(0.6)
                : Color.clear
        )
    }

    // MARK: - Data loading

    @MainActor
    private func loadFull() async {
        isLoading = true
        catalogPartialMessage = nil

        if let university = collegePersistence.getActiveUniversity()?.name {
            let caps = await collegePersistence.catalogCapabilities(universityName: university)
            if !caps.requirementsReady {
                catalogPartialMessage = caps.requirementsBlockedReason
                isLoading = false
                return
            }
        }

        let today = Date()
        func semesterHasEnded(_ course: CourseEntity) -> Bool {
            guard let sem = course.semester else { return false }
            let yr = Int(sem.year)
            let month: Int
            switch sem.season.lowercased() {
            case "winter": month = 1
            case "spring": month = 5
            case "summer": month = 8
            default:       month = 12
            }
            let end = Calendar.current.date(from: DateComponents(year: yr, month: month, day: 28)) ?? .distantPast
            return end < today
        }
        let completedCodes: Set<String> = {
            let all = collegePersistence.semesters.flatMap { $0.coursesArray }
            return Set(
                all.filter { $0.isCompleted || semesterHasEnded($0) }
                    .map { $0.code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }()

        // Mirrors `AcademicsAuditPanel.loadAudit.buildDegree`: try URL-based first, then fall
        // back to name-based so this view stays in sync with the audit sidebar (no scenario
        // where the sidebar lists the degree but the detail sheet says "No requirements found").
        var reqs: [DegreeRequirementEntity] = []
        if !degree.programURL.isEmpty {
            reqs = collegePersistence.getDegreeRequirements(programURL: degree.programURL, degreeType: degree.degreeType)
        }
        let isMinor = (degree.kind == .minor)
        if reqs.isEmpty, !isMinor {
            let byProfileDT = collegePersistence.getDegreeRequirementsForMajorDisplay(degree.rawName)
            let filtered = byProfileDT.filter { row in
                let dt = row.degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
                return dt.caseInsensitiveCompare("Minor") != .orderedSame
            }
            if !filtered.isEmpty { reqs = filtered }
        }
        if reqs.isEmpty {
            let byName = collegePersistence.getDegreeRequirementsByName(
                degree.rawName,
                requireDegreeType: isMinor ? "Minor" : nil,
                excludeDegreeTypes: isMinor ? [] : ["Minor"]
            )
            if !byName.isEmpty { reqs = byName }
        }

        // Group by requirementCategory preserving sectionOrder
        var orderedKeys: [String] = []
        var groupedCodes: [String: [String]] = [:]
        var groupedCredits: [String: Int] = [:]

        for req in reqs {
            let cat = req.requirementCategory
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if groupedCodes[cat] == nil {
                orderedKeys.append(cat)
                groupedCodes[cat] = []
                groupedCredits[cat] = Int(req.creditsRequired)
            } else if Int(req.creditsRequired) > (groupedCredits[cat] ?? 0) {
                groupedCredits[cat] = Int(req.creditsRequired)
            }

            let codes: [String] = {
                let csvCodes: [String] = {
                    guard let raw = req.requiredCourses, !raw.isEmpty else { return [] }
                    return raw.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                        .filter { !$0.isEmpty }
                }()
                if !csvCodes.isEmpty { return csvCodes }

                if let irNode = RequirementNodeIR.decodeFromDescription(req.descriptionText) {
                    return RequirementNodeIR.collectCourseCodes(from: irNode)
                }
                return []
            }()
            groupedCodes[cat]?.append(contentsOf: codes)
        }

        // De-duplicate codes per category while preserving order
        let built: [FullCategory] = orderedKeys.compactMap { key in
            guard var codes = groupedCodes[key] else { return nil }
            // Deduplicate
            var seen = Set<String>()
            codes = codes.filter { seen.insert($0).inserted }
            guard !codes.isEmpty else { return nil }

            let items: [FullItem] = codes.map { code in
                let catalogEntry = collegePersistence.getCatalogCourseMatching(code: code)
                let courseTitle = catalogEntry?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let credits = catalogEntry.map { c -> String in
                    let t = c.creditsDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? "" : t
                } ?? ""
                return FullItem(
                    code: code,
                    title: courseTitle,
                    credits: credits,
                    isCompleted: completedCodes.contains(code)
                )
            }
            return FullCategory(
                title: key,
                creditsRequired: groupedCredits[key] ?? 0,
                items: items
            )
        }

        // Auto-expand first category
        var initialExpanded = Set<UUID>()
        if let first = built.first { initialExpanded.insert(first.id) }

        categories = built
        expandedCategories = initialExpanded
        isLoading = false
    }
}
