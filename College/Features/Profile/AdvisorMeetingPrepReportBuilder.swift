// AdvisorMeetingPrepReportBuilder.swift
// Feature: Profile
// Purpose: Build advisor prep report data from the same Academics planner sources.

import Foundation

@MainActor
struct AdvisorMeetingPrepReport {
    struct CourseRow: Identifiable {
        let id: UUID
        let code: String
        let name: String
        let credits: Int
        let status: String
        let grade: String?
        let isCompleted: Bool
    }

    struct SemesterSection: Identifiable {
        let id: UUID
        let name: String
        let courses: [CourseRow]
    }

    let studentName: String
    let majorLabel: String
    let gpaDisplay: String
    let creditsEarned: Int
    let creditsRequired: Int?
    let creditsDisplay: String
    let gradTargetDisplay: String
    let sapDisplay: String
    let sapIsWarning: Bool
    let semesters: [SemesterSection]
    let generatedAt: Date

    private static func formattedCreditsDisplay(earned: Int, required: Int?) -> String {
        guard let required, required > 0 else {
            return earned > 0 ? "\(earned)" : "—"
        }
        return "\(earned)/\(required)"
    }

    private static func formattedMajorLabel(from majors: [String]) -> String {
        let cleaned = majors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return String(localized: "academics.sidebar.no_major", defaultValue: "Add Your Major")
        }
        return cleaned.joined(separator: ", ")
    }

    static func build(
        collegePersistence: CollegePersistence,
        metricsStore: AcademicMetricsStore
    ) -> AdvisorMeetingPrepReport {
        collegePersistence.fetchSemesters()
        collegePersistence.fetchProfile()
        collegePersistence.fetchAcademicProfiles()
        collegePersistence.reconcileDeclaredProgramDegreeMetadata()
        metricsStore.refresh()

        let profile = collegePersistence.profile
        let academicProfile = collegePersistence.primaryAcademicProfile
        let majors = academicProfile.map { collegePersistence.resolvedMajorNames(for: $0) }
            ?? collegePersistence.resolvedMajorNames()
        let majorLabel = formattedMajorLabel(from: majors)

        let metrics = metricsStore.snapshot
        let gpaDisplay: String = {
            guard let gpa = metrics?.cumulativeGPA else { return "—" }
            return String(format: "%.2f", gpa)
        }()

        let creditsEarned = metrics?.completedCreditsTotal ?? 0
        let creditsRequired = resolvedCreditsRequired(
            collegePersistence: collegePersistence,
            academicProfile: academicProfile,
            metrics: metrics
        )

        let gradTargetDisplay = resolvedGraduationTarget(
            collegePersistence: collegePersistence,
            academicProfile: academicProfile
        )

        let orderedSemesters = orderedPlannerSemesters(collegePersistence: collegePersistence)
        let sap = sapStats(for: orderedSemesters)
        let sapDisplay: String
        let sapIsWarning: Bool
        if let rate = sap.rate {
            sapDisplay = String(format: "%.0f%%", rate * 100)
            sapIsWarning = rate < 0.67
        } else {
            sapDisplay = "—"
            sapIsWarning = false
        }

        let semesterSections = orderedSemesters.map { semester in
            SemesterSection(
                id: semester.id,
                name: semesterDisplayName(semester),
                courses: semester.coursesArray.map { course in
                    CourseRow(
                        id: course.id,
                        code: course.code.trimmingCharacters(in: .whitespacesAndNewlines),
                        name: course.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        credits: course.creditsInt,
                        status: course.status.trimmingCharacters(in: .whitespacesAndNewlines),
                        grade: course.grade?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        isCompleted: course.isCompleted
                    )
                }
            )
        }

        return AdvisorMeetingPrepReport(
            studentName: profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Student",
            majorLabel: majorLabel,
            gpaDisplay: gpaDisplay,
            creditsEarned: creditsEarned,
            creditsRequired: creditsRequired,
            creditsDisplay: formattedCreditsDisplay(earned: creditsEarned, required: creditsRequired),
            gradTargetDisplay: gradTargetDisplay,
            sapDisplay: sapDisplay,
            sapIsWarning: sapIsWarning,
            semesters: semesterSections,
            generatedAt: Date()
        )
    }

    private static func orderedPlannerSemesters(collegePersistence: CollegePersistence) -> [PlannerSemester] {
        let plan = collegePersistence.getActivePlan()
        let raw = plan?.semestersArray ?? collegePersistence.semesters
        return raw.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            return lhs.seasonOrder < rhs.seasonOrder
        }
    }

    private static func resolvedCreditsRequired(
        collegePersistence: CollegePersistence,
        academicProfile: AcademicProfile?,
        metrics: AcademicMetricsSnapshot?
    ) -> Int? {
        if let required = metrics?.creditsRequired, required > 0 {
            return required
        }
        let breakdown = academicProfile.map {
            collegePersistence.declaredProgramsCreditsBreakdown(for: $0)
        } ?? collegePersistence.declaredProgramsCreditsBreakdown()
        let primaryRequired = breakdown.primary.requiredRoundedInt
        if primaryRequired > 0 { return primaryRequired }

        let storedRequired = collegePersistence.primaryCreditsRequired()
        return storedRequired > 0 ? storedRequired : nil
    }

    private static func resolvedGraduationTarget(
        collegePersistence: CollegePersistence,
        academicProfile: AcademicProfile?
    ) -> String {
        if let academicProfile,
           let structured = collegePersistence.structuredExpectedGraduation(for: academicProfile) {
            let season = structured.season.trimmingCharacters(in: .whitespacesAndNewlines)
            if structured.year > 0, !season.isEmpty {
                return "\(season) \(structured.year)"
            }
        }

        let raw = (academicProfile?.expectedGraduation
            ?? collegePersistence.primaryExpectedGraduation()
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "—" : raw
    }

    private static func sapStats(for semesters: [PlannerSemester]) -> (attempted: Int, completed: Int, rate: Double?) {
        let all = semesters.flatMap(\.coursesArray)
        let completedCredits = all.filter(\.isCompleted).reduce(0) { $0 + $1.creditsInt }
        let attemptedStatuses: Set<String> = ["Completed", "Dropped", "Failed", "Transfer"]
        let attemptedCredits = all.filter { course in
            let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
            return attemptedStatuses.contains(status) || course.isCompleted
        }.reduce(0) { $0 + $1.creditsInt }
        guard attemptedCredits > 0 else {
            return (0, completedCredits, nil)
        }
        return (attemptedCredits, completedCredits, Double(completedCredits) / Double(attemptedCredits))
    }

    private static func semesterDisplayName(_ semester: PlannerSemester) -> String {
        let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        let fallback = semester.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if season.isEmpty { return fallback.isEmpty ? "Semester" : fallback }
        if year > 0 { return "\(season) \(year)" }
        return season
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AdvisorMeetingPrepHTMLRenderer {
    @MainActor
    static func render(_ report: AdvisorMeetingPrepReport) -> String {
        let dateStr = DateFormatter.localizedString(
            from: report.generatedAt,
            dateStyle: .medium,
            timeStyle: .short
        )

        var semesterHTML = ""
        if report.semesters.allSatisfy({ $0.courses.isEmpty }) {
            semesterHTML = """
            <tr><td colspan='4' style='padding:12px;color:#6b7280;font-style:italic'>
            No courses in your active plan yet. Add semesters in Academics to populate this summary.
            </td></tr>
            """
        } else {
            for section in report.semesters where !section.courses.isEmpty {
                semesterHTML += "<tr><td colspan='4' style='background:#f3f4f6;font-weight:600;padding:8px 12px;font-size:13px'>\(escape(section.name))</td></tr>"
                for course in section.courses {
                    let statusColor = course.isCompleted ? "#16a34a" : "#6b7280"
                    let gradeText = course.grade ?? "—"
                    let gradeSuffix = gradeText != "—" ? " · \(escape(gradeText))" : ""
                    semesterHTML += """
                    <tr>
                      <td style='padding:6px 12px'>\(escape(course.code))</td>
                      <td style='padding:6px 12px'>\(escape(course.name))</td>
                      <td style='padding:6px 12px;text-align:center'>\(course.credits)</td>
                      <td style='padding:6px 12px;color:\(statusColor);font-weight:500'>\(escape(course.status))\(gradeSuffix)</td>
                    </tr>
                    """
                }
            }
        }

        let sapClass = report.sapIsWarning ? "warn" : ""
        let sapBadge = report.sapIsWarning ? " ⚠️" : ""

        return """
        <!DOCTYPE html><html><head><meta charset='UTF-8'>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#111;margin:0;padding:32px;background:#fff}
        h1{font-size:24px;font-weight:700;margin:0 0 4px}
        .subtitle{color:#6b7280;font-size:14px;margin:0 0 24px}
        .stats{display:flex;gap:16px;margin-bottom:24px}
        .stat{background:#f9fafb;border:1px solid #e5e7eb;border-radius:12px;padding:16px 20px;flex:1}
        .stat-label{font-size:11px;color:#9ca3af;text-transform:uppercase;letter-spacing:.5px}
        .stat-value{font-size:24px;font-weight:700;color:#111;margin-top:4px}
        h2{font-size:16px;font-weight:600;margin:24px 0 12px;color:#374151}
        table{width:100%;border-collapse:collapse;font-size:13px}
        th{background:#f3f4f6;padding:8px 12px;text-align:left;font-weight:600;color:#374151;font-size:12px}
        tr:nth-child(even) td{background:#fafafa}
        .warn{color:#d97706;font-size:11px}
        </style></head><body>
        <h1>\(escape(report.studentName))</h1>
        <p class='subtitle'>Academic Summary · Generated \(escape(dateStr))</p>
        <div class='stats'>
          <div class='stat'><div class='stat-label'>GPA</div><div class='stat-value'>\(escape(report.gpaDisplay))</div></div>
          <div class='stat'><div class='stat-label'>Credits</div><div class='stat-value'>\(escape(report.creditsDisplay))</div></div>
          <div class='stat'><div class='stat-label'>Major</div><div class='stat-value' style='font-size:14px'>\(escape(report.majorLabel))</div></div>
          <div class='stat'><div class='stat-label'>Grad Target</div><div class='stat-value' style='font-size:16px'>\(escape(report.gradTargetDisplay))</div></div>
          <div class='stat'><div class='stat-label'>SAP Rate</div><div class='stat-value \(sapClass)'>\(escape(report.sapDisplay))\(sapBadge)</div></div>
        </div>
        <h2>Course Plan</h2>
        <table><thead><tr><th>Code</th><th>Course</th><th>Cr</th><th>Status</th></tr></thead><tbody>
        \(semesterHTML)
        </tbody></table>
        </body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
