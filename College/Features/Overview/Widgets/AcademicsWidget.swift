// AcademicsWidget.swift
// Feature: Overview
// Purpose: Overview module — AcademicsWidget.
// Data: CollegePersistence / repositories when applicable.

//
//  AcademicsWidget.swift
//  College
//
//  Credit-ring progress widget for majors and minors.
//

import SwiftUI

struct AcademicsWidget: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    var activePage: Binding<AppPage>

    @State private var majorProgressSummaries: [String: CollegePersistence.CreditsProgressSummary] = [:]
    @State private var minorProgressSummaries: [String: CollegePersistence.CreditsProgressSummary] = [:]
    @State private var suggestedCourses: [(code: String, title: String)] = []

    private var profile: Profile? { ProfileReadBridge.primaryProfile(collegePersistence: collegePersistence) }

    private var displayMajors: [(label: String, progress: CollegePersistence.CreditsProgressSummary)] {
        var result: [(String, CollegePersistence.CreditsProgressSummary)] = []
        for major in collegePersistence.resolvedMajorNames() {
            if let p = majorProgressSummaries[major] { result.append((major, p)) }
        }
        if result.isEmpty {
            let earned = Double(collegePersistence.primaryCreditsEarned())
            let stored = collegePersistence.primaryCreditsRequired()
            let req = Double(stored == 0 ? 120 : stored)
            let frac = req > 0 ? min(1.0, earned / req) : 0
            let summary = CollegePersistence.CreditsProgressSummary(completed: earned, required: req, fraction: frac)
            let label = collegePersistence.primaryMajorDisplay() ?? "Degree Progress"
            result.append((label, summary))
        }
        return result
    }

    private var displayMinors: [(label: String, progress: CollegePersistence.CreditsProgressSummary)] {
        var result: [(String, CollegePersistence.CreditsProgressSummary)] = []
        for minor in collegePersistence.resolvedMinorNames() {
            if let p = minorProgressSummaries[minor] { result.append((minor, p)) }
        }
        return result
    }

    var body: some View {
        OverviewCard {
            HStack {
                Text("Academic Journey")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
                Button("View Full Planner") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        activePage.wrappedValue = .academics
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "6366f1"))
                .buttonStyle(.plain)
            }

            Color.clear.frame(height: 20)

            let majors = displayMajors
            let minors = displayMinors
            if majors.isEmpty && minors.isEmpty {
                Text("No degree configured. Add your major in Profile.")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !majors.isEmpty {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(majors.prefix(2).enumerated()), id: \.offset) { idx, item in
                                if idx > 0 { Divider().frame(height: 80).padding(.horizontal, 20) }
                                VStack(spacing: 12) {
                                    creditRing(fraction: item.progress.fraction,
                                               completed: item.progress.completedRoundedInt,
                                               required: item.progress.requiredRoundedInt,
                                               color: idx == 0 ? Color(hex: "6366f1") : Color(hex: "10b981"))
                                    VStack(spacing: 3) {
                                        Text(item.label)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.textMain)
                                            .multilineTextAlignment(.center)
                                        Text("\(item.progress.completedRoundedInt)/\(item.progress.requiredRoundedInt) Credits")
                                            .font(.system(size: 11))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    if !minors.isEmpty {
                        if !majors.isEmpty { Divider().padding(.horizontal, 4) }
                        VStack(spacing: 8) {
                            ForEach(Array(minors.enumerated()), id: \.offset) { _, item in
                                minorProgressRow(label: item.label, progress: item.progress)
                            }
                        }
                    }
                }
            }

            if profile != nil, collegePersistence.primaryGPA() > 0 {
                Divider().padding(.horizontal, 4)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cumulative GPA")
                            .font(DesignSystem.Fonts.main(size: 10))
                            .foregroundColor(Color(hex: "9ca3af"))
                        Text(String(format: "%.2f", collegePersistence.primaryGPA()))
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .foregroundColor(collegePersistence.primaryGPA() >= 3.5 ? Color(hex: "22c55e") : collegePersistence.primaryGPA() >= 2.0 ? Color(hex: "6366f1") : Color(hex: "ef4444"))
                    }
                    Spacer()
                    if collegePersistence.primaryCreditsEarned() > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Credits Earned")
                                .font(DesignSystem.Fonts.main(size: 10))
                                .foregroundColor(Color(hex: "9ca3af"))
                            Text("\(collegePersistence.primaryCreditsEarned())")
                                .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "374151"))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if !suggestedCourses.isEmpty {
                Divider().padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested Next")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "6366f1"))
                        .padding(.horizontal, 16)

                    ForEach(suggestedCourses, id: \.code) { course in
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "6366f1"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(course.code)
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "374151"))
                                Text(course.title)
                                    .font(DesignSystem.Fonts.main(size: 11))
                                    .foregroundColor(Color(hex: "6b7280"))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .task {
            await computeProgress()
            await loadSuggestions()
        }
        .onChange(of: collegePersistence.resolvedMajorNames().joined(separator: "|")) { _, _ in
            Task { await computeProgress(); await loadSuggestions() }
        }
        .onChange(of: collegePersistence.resolvedMinorNames().joined(separator: "|")) { _, _ in
            Task { await computeProgress(); await loadSuggestions() }
        }
        .onChange(of: collegePersistence.plannerChangeToken) { _, _ in Task { await computeProgress(); await loadSuggestions() } }
    }

    // MARK: - Helpers

    @MainActor
    private func loadSuggestions() async {
        let completedCodes = Set(collegePersistence.semesters
            .flatMap { $0.coursesArray }
            .filter { $0.isCompleted }
            .map { $0.code.replacingOccurrences(of: " ", with: "").uppercased() })

        let plannedCodes = Set(collegePersistence.semesters
            .flatMap { $0.coursesArray }
            .map { $0.code.replacingOccurrences(of: " ", with: "").uppercased() })

        // Get degree requirements
        guard let primaryURL = collegePersistence.resolveSelectedMajorProgramURL() else { return }
        let profileDegreeType = (collegePersistence.primaryDegreeType() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reqs = collegePersistence.getDegreeRequirements(programURL: primaryURL, degreeType: profileDegreeType)

        // Find unfulfilled required courses
        var candidates: [(code: String, title: String, order: Int)] = []
        for req in reqs {
            let order = Int(req.sectionOrder)
            let codes = (req.requiredCourses ?? "").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
            for code in codes {
                let norm = code.replacingOccurrences(of: " ", with: "").uppercased()
                if !completedCodes.contains(norm) && !plannedCodes.contains(norm) {
                    let title = collegePersistence.getCatalogCourse(code: code)?.title ?? code
                    candidates.append((code: code, title: title, order: order))
                }
            }
        }

        // Show first 3 candidates sorted by section order
        let sorted = candidates.sorted { $0.order < $1.order }
        suggestedCourses = sorted.prefix(3).map { (code: $0.code, title: $0.title) }
    }

    // MARK: - Ring / Row helpers

    private func creditRing(fraction: Double, completed: Int, required: Int, color: Color) -> some View {
        let f = max(0, min(1, fraction))
        return ZStack {
            Circle().stroke(Color(hex: "F3F4F6"), lineWidth: 7).frame(width: 100, height: 100)
            Circle().trim(from: 0, to: f)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
            Text("\(Int((f * 100).rounded()))%")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
        }
    }

    private func minorProgressRow(label: String, progress: CollegePersistence.CreditsProgressSummary) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("MINOR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "F97316"))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(hex: "FFF7ED"))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                    Spacer()
                    Text("\(progress.completedRoundedInt)/\(progress.requiredRoundedInt) cr")
                        .font(.system(size: 11)).foregroundColor(DesignSystem.Colors.textLight)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: "FFF7ED")).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: "F97316"))
                            .frame(width: g.size.width * CGFloat(max(0, min(1, progress.fraction))), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 4)
    }

    private func computeProgress() async {
        guard let plan = collegePersistence.getActivePlan() else { return }
        let majors = collegePersistence.resolvedMajorNames()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolved = await collegePersistence.computeMajorRequirementsCreditsProgressSummariesAsync(
            majorDisplays: majors, degreeTypeRaw: plan.type
        )
        let minorName = (collegePersistence.resolvedMinorNames().first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var minorResults: [String: CollegePersistence.CreditsProgressSummary] = [:]
        if !minorName.isEmpty {
            let p = await MainActor.run {
                collegePersistence.minorRequirementsCreditsProgress(forMinorDisplay: minorName)
            }
            minorResults[minorName] = p
        }
        await MainActor.run {
            majorProgressSummaries = resolved
            minorProgressSummaries = minorResults
        }
    }

    // MARK: - Descriptor

    static var descriptor: WidgetDescriptor {
        WidgetDescriptor(
            id:            "academics",
            displayName:   "Academic Journey",
            description:   "Credit progress rings for your major, double major and minor.",
            category:      .academic,
            iconName:      "graduationcap.fill",
            accentColor:   Color(hex: "6366F1"),
            defaultHeight: 210,
            minHeight:     150,
            makePreview: {
                AcademicsWidgetPreview()
            }
        )
    }
}

// MARK: - Preview

private struct AcademicsWidgetPreview: View {
    var body: some View {
        OverviewCard {
            Text("Academic Journey")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(DesignSystem.Colors.textMain)
            Color.clear.frame(height: 12)
            HStack(spacing: 0) {
                ForEach([(Color(hex: "6366f1"), "CS Major", "78%"),
                         (Color(hex: "10b981"), "Math Minor", "55%")], id: \.2) { color, label, pct in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().stroke(Color(hex: "F3F4F6"), lineWidth: 6).frame(width: 70, height: 70)
                            Circle().trim(from: 0, to: label == "CS Major" ? 0.78 : 0.55)
                                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 70, height: 70).rotationEffect(.degrees(-90))
                            Text(pct).font(.system(size: 14, weight: .bold)).foregroundColor(DesignSystem.Colors.textMain)
                        }
                        Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(DesignSystem.Colors.textMain)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}
