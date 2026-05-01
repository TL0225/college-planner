//
//  AcademicsWidget.swift
//  College
//
//  Credit-ring progress widget for majors and minors.
//

import SwiftUI
import CoreData

struct AcademicsWidget: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    var activePage: Binding<AppPage>

    @State private var majorProgressSummaries: [String: CoreDataManager.CreditsProgressSummary] = [:]
    @State private var minorProgressSummaries: [String: CoreDataManager.CreditsProgressSummary] = [:]
    @State private var suggestedCourses: [(code: String, title: String)] = []

    private var profile: ProfileEntity? { coreDataManager.profile }

    private var displayMajors: [(label: String, progress: CoreDataManager.CreditsProgressSummary)] {
        var result: [(String, CoreDataManager.CreditsProgressSummary)] = []
        if let m = profile?.major, !m.isEmpty, let p = majorProgressSummaries[m] { result.append((m, p)) }
        if let m = profile?.secondaryMajor, !m.isEmpty, let p = majorProgressSummaries[m] { result.append((m, p)) }
        if result.isEmpty {
            let earned = Double(profile?.creditsEarned ?? 0)
            let req    = Double((profile?.creditsRequired ?? 0) == 0 ? 120 : (profile?.creditsRequired ?? 120))
            let frac   = req > 0 ? min(1.0, earned / req) : 0
            let summary = CoreDataManager.CreditsProgressSummary(completed: earned, required: req, fraction: frac)
            let label   = profile?.major.flatMap { $0.isEmpty ? nil : $0 } ?? "Degree Progress"
            result.append((label, summary))
        }
        return result
    }

    private var displayMinors: [(label: String, progress: CoreDataManager.CreditsProgressSummary)] {
        var result: [(String, CoreDataManager.CreditsProgressSummary)] = []
        if let m = profile?.minor, !m.isEmpty, let p = minorProgressSummaries[m] { result.append((m, p)) }
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

            if let profile = profile, profile.gpa > 0 {
                Divider().padding(.horizontal, 4)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cumulative GPA")
                            .font(DesignSystem.Fonts.main(size: 10))
                            .foregroundColor(Color(hex: "9ca3af"))
                        Text(String(format: "%.2f", profile.gpa))
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .foregroundColor(profile.gpa >= 3.5 ? Color(hex: "22c55e") : profile.gpa >= 2.0 ? Color(hex: "6366f1") : Color(hex: "ef4444"))
                    }
                    Spacer()
                    if profile.creditsEarned > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Credits Earned")
                                .font(DesignSystem.Fonts.main(size: 10))
                                .foregroundColor(Color(hex: "9ca3af"))
                            Text("\(profile.creditsEarned)")
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
        .onChange(of: profile?.major) { _, _ in Task { await computeProgress(); await loadSuggestions() } }
        .onChange(of: profile?.secondaryMajor) { _, _ in Task { await computeProgress(); await loadSuggestions() } }
        .onChange(of: profile?.minor) { _, _ in Task { await computeProgress(); await loadSuggestions() } }
        .onChange(of: coreDataManager.plannerChangeToken) { _, _ in Task { await computeProgress(); await loadSuggestions() } }
    }

    // MARK: - Helpers

    @MainActor
    private func loadSuggestions() async {
        // Get completed course codes
        let completedCodes = Set(coreDataManager.semesters
            .flatMap { $0.coursesArray }
            .filter { $0.isCompleted }
            .compactMap { c -> String? in
                guard let code = c.code else { return nil }
                return code.replacingOccurrences(of: " ", with: "").uppercased()
            })

        // Get all planned codes (don't suggest things already planned)
        let plannedCodes = Set(coreDataManager.semesters
            .flatMap { $0.coursesArray }
            .compactMap { $0.code?.replacingOccurrences(of: " ", with: "").uppercased() })

        // Get degree requirements
        guard let primaryURL = coreDataManager.resolveSelectedMajorProgramURL() else { return }
        let profileDegreeType = (coreDataManager.profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reqs = coreDataManager.getDegreeRequirements(programURL: primaryURL, degreeType: profileDegreeType)

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
                    let title = coreDataManager.getCatalogCourse(code: code)?.title ?? code
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

    private func minorProgressRow(label: String, progress: CoreDataManager.CreditsProgressSummary) -> some View {
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
        guard let planEntity = coreDataManager.getActivePlan() else { return }
        let majors = [profile?.major, profile?.secondaryMajor]
            .compactMap { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolved = await coreDataManager.computeMajorRequirementsCreditsProgressSummariesAsync(
            majorDisplays: majors, degreeTypeRaw: planEntity.type ?? ""
        )
        let minorName = (profile?.minor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var minorResults: [String: CoreDataManager.CreditsProgressSummary] = [:]
        if !minorName.isEmpty {
            let p = await MainActor.run {
                coreDataManager.minorRequirementsCreditsProgress(forMinorDisplay: minorName)
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
