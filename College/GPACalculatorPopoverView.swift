import SwiftUI
import Combine

struct GPACalculatorPopoverView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager

    private enum Tab: String, CaseIterable {
        case gpa = "GPA"
        case gpaTable = "GPA Table"
    }

    private let universityID: UUID?
    @StateObject private var scaleStore: GPAGradeScaleStore

    @State private var selectedTab: Tab = .gpa

    init(universityID: UUID?) {
        self.universityID = universityID
        _scaleStore = StateObject(wrappedValue: GPAGradeScaleStore(universityID: universityID))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("GPA Calculator")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                Spacer()
            }

            tabBar

            ZStack {
                switch selectedTab {
                case .gpaTable:
                    gpaTableTab
                        .transition(.opacity)
                case .gpa:
                    gpaBreakdownTab
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedTab)
        }
        .padding(14)
        .frame(width: 420, height: 420)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(16)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.gpa)
            tabButton(.gpaTable)
        }
        .padding(4)
        .background(DesignSystem.Colors.bgMain)
        .cornerRadius(12)
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button(action: {
            selectedTab = tab
        }) {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                    .foregroundColor(selectedTab == tab ? DesignSystem.Colors.textMain : DesignSystem.Colors.textLight)

                Rectangle()
                    .fill(selectedTab == tab ? DesignSystem.Colors.primary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var gpaTableTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your university’s grade-to-points system.")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)

            gradePointsTable

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var gradePointsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Grade")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Points")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(width: 90, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.bgMain)

            VStack(spacing: 0) {
                ForEach(scaleStore.rows.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        TextField("", text: Binding(
                            get: { scaleStore.rows[i].grade },
                            set: { newValue in
                                scaleStore.rows[i].grade = newValue
                                scaleStore.save()
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                        )

                        TextField("", text: Binding(
                            get: { scaleStore.rows[i].pointsText },
                            set: { newValue in
                                scaleStore.rows[i].pointsText = GPAGradeScaleStore.sanitizePointsText(newValue)
                                scaleStore.save()
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(width: 90)
                        .background(DesignSystem.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
        )
    }

    private var gpaBreakdownTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current GPA (completed, letter-graded courses).")
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)

            let mapping = scaleStore.gradePointsMapping
            let summary = cumulativeGPASummary(mapping: mapping)

            HStack(alignment: .lastTextBaseline) {
                Text(summary.map { String(format: "%.2f", $0.gpa) } ?? "—")
                    .font(DesignSystem.Fonts.main(size: 28, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Credits: \(String(format: "%.1f", summary?.creditsCounted ?? 0.0))")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    Text("Courses: \(summary?.coursesCounted ?? 0)")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            .padding(14)
            .background(DesignSystem.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(14)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func cumulativeGPASummary(mapping: [String: Double]) -> GPASemesterSummary? {
        var qualityPoints: Double = 0
        var creditsCounted: Double = 0
        var coursesCounted: Int = 0

        for semester in semestersSorted {
            for course in semester.coursesArray {
                guard course.isCompleted else { continue }
                guard coreDataManager.isLetterGradedForGPA(course.gradingType) else { continue }
                guard let grade = course.grade else { continue }
                guard let gp = gradePointsFromScale(grade, mapping: mapping) else { continue }

                let credits = Double(course.creditsInt)
                guard credits > 0 else { continue }

                qualityPoints += gp * credits
                creditsCounted += credits
                coursesCounted += 1
            }
        }

        guard creditsCounted > 0 else { return nil }
        return GPASemesterSummary(gpa: qualityPoints / creditsCounted, creditsCounted: creditsCounted, coursesCounted: coursesCounted)
    }

    private func gpaSemesterRow(semester: SemesterEntity, summary: GPASemesterSummary?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(semesterDisplayName(semester))
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                Spacer()

                Text(summary.map { String(format: "%.2f", $0.gpa) } ?? "—")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }

            HStack {
                Text("Credits: \(String(format: "%.1f", summary?.creditsCounted ?? 0.0))")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)

                Spacer()

                Text("Courses: \(summary?.coursesCounted ?? 0)")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private struct GPASemesterSummary: Equatable {
        let gpa: Double
        let creditsCounted: Double
        let coursesCounted: Int
    }

    private var semestersSorted: [SemesterEntity] {
        let semesters = coreDataManager.getActivePlan()?.semestersArray ?? coreDataManager.plans.flatMap { $0.semestersArray }
        return semesters.sorted { a, b in
            if a.year != b.year { return a.year < b.year }
            if a.seasonOrder != b.seasonOrder { return a.seasonOrder < b.seasonOrder }
            return (a.name ?? "") < (b.name ?? "")
        }
    }

    private func semesterDisplayName(_ semester: SemesterEntity) -> String {
        let season = (semester.season ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        if season.isEmpty { return semester.name ?? "Semester" }
        if year > 0 { return "\(season) \(year)" }
        return season
    }

    private func semesterGPASummary(semester: SemesterEntity, mapping: [String: Double]) -> GPASemesterSummary? {
        var qualityPoints: Double = 0
        var creditsCounted: Double = 0
        var coursesCounted: Int = 0

        for course in semester.coursesArray {
            guard course.isCompleted else { continue }
            guard coreDataManager.isLetterGradedForGPA(course.gradingType) else { continue }
            guard let grade = course.grade else { continue }
            guard let gp = gradePointsFromScale(grade, mapping: mapping) else { continue }

            let credits = Double(course.creditsInt)
            guard credits > 0 else { continue }

            qualityPoints += gp * credits
            creditsCounted += credits
            coursesCounted += 1
        }

        guard creditsCounted > 0 else { return nil }
        return GPASemesterSummary(gpa: qualityPoints / creditsCounted, creditsCounted: creditsCounted, coursesCounted: coursesCounted)
    }

    private func gradePointsFromScale(_ rawGrade: String, mapping: [String: Double]) -> Double? {
        let normalized = rawGrade
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalized.isEmpty else { return nil }

        if ["P", "PASS", "S", "SAT", "SATISFACTORY"].contains(normalized) { return nil }
        if ["W", "WITHDRAW", "WD", "I", "INC", "INCOMPLETE"].contains(normalized) { return nil }

        return mapping[normalized]
    }
}

final class GPAGradeScaleStore: ObservableObject {
    struct Row: Codable, Hashable {
        var grade: String
        var pointsText: String
    }

    @Published var rows: [Row]

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(universityID: UUID?, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let suffix = universityID?.uuidString ?? "global"
        self.storageKey = "gpa.gradeScale.v1.\(suffix)"

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Row].self, from: data),
           decoded.count == 12 {
            self.rows = decoded
        } else {
            self.rows = Self.defaultRows
            save()
        }

        if rows.count != 12 {
            rows = Array(rows.prefix(12))
            if rows.count < 12 {
                rows.append(contentsOf: Array(Self.defaultRows.dropFirst(rows.count)))
            }
            save()
        }
    }

    var gradePointsMapping: [String: Double] {
        var map: [String: Double] = [:]
        for row in rows {
            let key = row.grade
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            guard !key.isEmpty else { continue }
            guard let points = Double(row.pointsText.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            map[key] = points
        }
        return map
    }

    func save() {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    static func sanitizePointsText(_ raw: String) -> String {
        // Keep digits + at most one decimal point.
        let filtered = raw.filter { $0.isNumber || $0 == "." }
        var out = ""
        var sawDot = false
        for ch in filtered {
            if ch == "." {
                if sawDot { continue }
                sawDot = true
            }
            out.append(ch)
        }
        return out
    }

    private static var defaultRows: [Row] {
        [
            Row(grade: "A+", pointsText: "4.0"),
            Row(grade: "A", pointsText: "4.0"),
            Row(grade: "A-", pointsText: "3.7"),
            Row(grade: "B+", pointsText: "3.3"),
            Row(grade: "B", pointsText: "3.0"),
            Row(grade: "B-", pointsText: "2.7"),
            Row(grade: "C+", pointsText: "2.3"),
            Row(grade: "C", pointsText: "2.0"),
            Row(grade: "C-", pointsText: "1.7"),
            Row(grade: "D+", pointsText: "1.3"),
            Row(grade: "D", pointsText: "1.0"),
            Row(grade: "F", pointsText: "0.0")
        ]
    }
}
