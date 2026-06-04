// AIAssistantToolRouter.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantPlannerSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct AssistantPlannerSnapshot {
    struct ProgramItem {
        struct CourseItem: Sendable {
            let code: String
            let title: String
            let credits: Double
        }

        enum Kind {
            case major
            case minor
        }

        let name: String
        let kind: Kind
        let completedCredits: Double
        let requiredCredits: Double
        let requiredCoreCredits: Double?
        let requiredElectiveCredits: Double?
        let pendingCourses: [CourseItem]

        init(
            name: String,
            kind: Kind,
            completedCredits: Double,
            requiredCredits: Double,
            requiredCoreCredits: Double? = nil,
            requiredElectiveCredits: Double? = nil,
            pendingCourses: [CourseItem] = []
        ) {
            self.name = name
            self.kind = kind
            self.completedCredits = completedCredits
            self.requiredCredits = requiredCredits
            self.requiredCoreCredits = requiredCoreCredits
            self.requiredElectiveCredits = requiredElectiveCredits
            self.pendingCourses = pendingCourses
        }

        var remainingCredits: Double {
            max(0, requiredCredits - completedCredits)
        }
    }

    struct EventItem {
        let title: String
        let startDate: Date
        let allDay: Bool
    }

    struct TaskItem {
        let title: String
        let dueDate: Date?
        let isCompleted: Bool
    }

    let events: [EventItem]
    let tasks: [TaskItem]
    let majors: [String]
    let minors: [String]
    let programs: [ProgramItem]
}

enum AIAssistantToolRouter {
    enum RouteDecision {
        case deterministic(String)
        case llmPreferred(seed: String?)
        case none
    }

    static func routeDecision(
        for message: String,
        role: AIAssistantService.Role,
        snapshot: AssistantPlannerSnapshot,
        activePage: AppPage,
        hasAttachments: Bool = false
    ) -> RouteDecision {
        if hasAttachments {
            // Attachments need the full planner + optional vision path; skip fast deterministic shortcuts.
            return .none
        }

        let normalized = message
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("what model") || normalized.contains("which model") || normalized.contains("ai model") || normalized.contains("model are you") {
            return .deterministic(modelIdentity())
        }

        if normalized.contains("create event") ||
            normalized.contains("create an event") ||
            normalized.contains("add event") ||
            normalized.contains("new event") {
            return .deterministic(eventCreationHelp())
        }

        // Explicit web-search intent should go through the planner/tool path even if
        // words like "deadline" appear, otherwise we incorrectly return local due-items.
        if isExplicitWebSearchQuery(normalized) {
            return .none
        }

        if let semantic = AssistantIntentSemantics.classify(message: message, role: role),
           case .llmPreferred = semantic.decision,
           [
               "financial_aid",
               "fafsa_help",
               "state_aid_help",
               "sap_risk",
               "aid_estimate",
               "award_letter_review",
               "enrollment_intensity"
           ].contains(semantic.matchedIntent) {
            return semantic.decision
        }

        // Open-ended planning and reasoning should use the LLM path with deterministic seed data.
        if AssistantIntentSemantics.isFirstSemesterPlanningPrompt(normalized) {
            return .llmPreferred(seed: firstSemesterPlan(message: normalized, snapshot: snapshot))
        }

        if normalized.contains("next semester") || normalized.contains("next-semester") {
            return .llmPreferred(seed: oneSemesterPlan(message: normalized, snapshot: snapshot))
        }

        if normalized.contains("next 2 semester") || normalized.contains("next two semester") || normalized.contains("next two semesters") || normalized.contains("plan next 2 semesters") || normalized.contains("plan next two semesters") {
            return .llmPreferred(seed: twoSemesterSkeleton(snapshot: snapshot))
        }

        if normalized.contains("summarize") || normalized.contains("analy") || normalized.contains("interpret") || normalized.contains("recite") || normalized.contains("status") {
            return .llmPreferred(seed: integratedAppSummary(snapshot: snapshot, activePage: activePage))
        }

        if normalized.contains("tomorrow") {
            return .deterministic(tomorrowAgenda(role: role, snapshot: snapshot))
        }

        if normalized.contains("this week") || normalized.contains("next 7 day") || normalized.contains("upcoming") {
            return .deterministic(weeklyAgenda(snapshot: snapshot))
        }

        if normalized.contains("what is due") || normalized.contains("what's due") || normalized.contains("deadline") {
            return .deterministic(dueItems(snapshot: snapshot))
        }

        if normalized.contains("major") || normalized.contains("minor") || normalized.contains("program") || normalized.contains("degree") {
            if isReasoningHeavyPrompt(normalized) {
                return .llmPreferred(seed: currentPrograms(snapshot: snapshot))
            }
            return .deterministic(currentPrograms(snapshot: snapshot))
        }

        return .none
    }

    static func reply(
        for message: String,
        role: AIAssistantService.Role,
        snapshot: AssistantPlannerSnapshot,
        activePage: AppPage,
        hasAttachments: Bool = false
    ) -> String? {
        switch routeDecision(for: message, role: role, snapshot: snapshot, activePage: activePage, hasAttachments: hasAttachments) {
        case .deterministic(let text):
            return text
        case .llmPreferred(let seed):
            // Preserve deterministic seed replies for callers that still use `reply(...)`
            // while the runtime path can prefer the LLM using the same seeded context.
            return seed
        case .none:
            return nil
        }
    }

    private static func isReasoningHeavyPrompt(_ normalizedMessage: String) -> Bool {
        let markers = [
            "why", "how", "explain", "compare", "tradeoff", "strategy", "optimi", "best way", "recommend"
        ]
        return markers.contains { normalizedMessage.contains($0) }
    }

    private static func isExplicitWebSearchQuery(_ normalizedMessage: String) -> Bool {
        let webMarkers = [
            "search the web",
            "search web",
            "web search",
            "look up on the web",
            "look up online",
            "search online",
            "search the internet",
            "find online",
            "find on the web"
        ]
        return webMarkers.contains { normalizedMessage.contains($0) }
    }

    private static func tomorrowAgenda(role: AIAssistantService.Role, snapshot: AssistantPlannerSnapshot) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        guard let start = calendar.dateInterval(of: .day, for: tomorrow)?.start,
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return "I couldn't resolve tomorrow's date range."
        }

        let tomorrowEvents = snapshot.events
            .filter { $0.startDate >= start && $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }

        let tomorrowTasks = snapshot.tasks
            .filter {
                guard let due = $0.dueDate else { return false }
                return due >= start && due < end && !$0.isCompleted
            }
            .sorted {
                guard let lhs = $0.dueDate, let rhs = $1.dueDate else { return false }
                return lhs < rhs
            }

        if tomorrowEvents.isEmpty && tomorrowTasks.isEmpty {
            return role == .financialAid
                ? "Tomorrow looks clear in your planner. No pending due items or scheduled events were found."
                : "You're clear for tomorrow. I didn't find any events or due tasks on your calendar."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        var lines: [String] = ["Tomorrow's agenda:"]
        for event in tomorrowEvents {
            let time = event.allDay ? "All day" : formatter.string(from: event.startDate)
            lines.append("- Event: \(event.title) (\(time))")
        }
        for task in tomorrowTasks {
            let dueText = task.dueDate.map { formatter.string(from: $0) } ?? "No due time"
            lines.append("- Task: \(task.title) (due \(dueText))")
        }

        return lines.joined(separator: "\n")
    }

    private static func weeklyAgenda(snapshot: AssistantPlannerSnapshot) -> String {
        let now = Date()
        let sevenDays = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        let events = snapshot.events
            .filter { $0.startDate >= now && $0.startDate <= sevenDays }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)

        let tasks = snapshot.tasks
            .filter {
                guard let due = $0.dueDate else { return false }
                return due >= now && due <= sevenDays && !$0.isCompleted
            }
            .sorted {
                guard let lhs = $0.dueDate, let rhs = $1.dueDate else { return false }
                return lhs < rhs
            }
            .prefix(6)

        if events.isEmpty && tasks.isEmpty {
            return "No upcoming events or open tasks were found in the next 7 days."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        var lines: [String] = ["Upcoming 7-day snapshot:"]
        for event in events {
            let when = event.allDay ? "All day" : formatter.string(from: event.startDate)
            lines.append("- Event: \(event.title) @ \(when)")
        }
        for task in tasks {
            let dueText = task.dueDate.map { formatter.string(from: $0) } ?? "No due time"
            lines.append("- Task: \(task.title) due \(dueText)")
        }
        return lines.joined(separator: "\n")
    }

    private static func dueItems(snapshot: AssistantPlannerSnapshot) -> String {
        let now = Date()
        let tasks = snapshot.tasks
            .filter { !$0.isCompleted }
            .sorted {
                guard let lhs = $0.dueDate, let rhs = $1.dueDate else { return false }
                return lhs < rhs
            }
            .prefix(8)

        if tasks.isEmpty {
            return "I don't see any open tasks with due dates right now."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"

        var lines: [String] = ["Open due items:"]
        for task in tasks {
            let dueText: String
            if let due = task.dueDate {
                dueText = formatter.string(from: due)
            } else {
                dueText = "No due time"
            }

            let status = (task.dueDate != nil && task.dueDate! < now) ? "overdue" : "upcoming"
            lines.append("- \(task.title) (\(status), \(dueText))")
        }
        return lines.joined(separator: "\n")
    }

    private static func currentPrograms(snapshot: AssistantPlannerSnapshot) -> String {
        let majorText = snapshot.majors.isEmpty ? "None selected" : snapshot.majors.joined(separator: ", ")
        let minorText = snapshot.minors.isEmpty ? "None selected" : snapshot.minors.joined(separator: ", ")
        return "Current programs:\n- Majors: \(majorText)\n- Minors: \(minorText)"
    }

    private static func modelIdentity() -> String {
        "I run on a local on-device Qwen JSON model (via MLX) when installed, with deterministic planner tools for schedule, task, and program lookups."
    }

    private static func eventCreationHelp() -> String {
        "Yes. I can help you draft the event details first. Tell me: 1) title, 2) date, 3) start time, 4) duration, and 5) location/notes, and I will format it as a ready-to-enter event."
    }

    private static func oneSemesterPlan(message: String, snapshot: AssistantPlannerSnapshot) -> String {
        let requestedCredits = extractCreditTarget(from: message)

        let remaining = snapshot.programs.reduce(0.0) { $0 + $1.remainingCredits }
        let remainingRounded = Int(remaining.rounded())
        let suggestedCredits = requestedCredits ?? max(12, min(19, remainingRounded > 0 ? remainingRounded : 15))

        let priorities = snapshot.programs
            .sorted { $0.remainingCredits > $1.remainingCredits }
            .prefix(3)
            .map { item in
                let kind = item.kind == .major ? "Major" : "Minor"
                return "- \(kind) \(item.name): \(Int(item.remainingCredits.rounded())) credits remaining"
            }

        let priorityText = priorities.isEmpty
            ? "- No remaining requirement credits were detected."
            : priorities.joined(separator: "\n")
        let candidateText = candidateCourseLines(from: snapshot, limit: 8)

        let planHint = requestedCredits != nil
            ? "You asked for \(suggestedCredits) credits."
            : "A balanced target is \(suggestedCredits) credits."

        return """
Next-semester deterministic planning draft:
\(planHint)
- Target load: \(suggestedCredits) credits
- Requirement-first sequencing: place prerequisite-gating/core courses first.
- Keep 1 flexible/elective slot for schedule pressure.

Program priorities:
\(priorityText)

Candidate courses from pending requirements:
\(candidateText)

If you share your available course options, I can turn this into a concrete course-by-course schedule.
"""
    }

    private static func firstSemesterPlan(message: String, snapshot: AssistantPlannerSnapshot) -> String {
        let requestedCredits = extractCreditTarget(from: message)
        let suggestedCredits = requestedCredits ?? 15
        let majorText = snapshot.majors.isEmpty ? "your declared major" : snapshot.majors.joined(separator: ", ")
        let minorText = snapshot.minors.isEmpty ? "" : "\n- Consider 1 light course connected to: \(snapshot.minors.joined(separator: ", "))"

        let priorities = snapshot.programs
            .sorted { $0.remainingCredits > $1.remainingCredits }
            .prefix(3)
            .map { item -> String in
                let kind = item.kind == .major ? "Major" : "Minor"
                let remaining = Int(item.remainingCredits.rounded())
                return "- \(kind) \(item.name): \(remaining) credits remaining"
            }

        let priorityText = priorities.isEmpty
            ? "- No detailed remaining requirement credits were detected yet."
            : priorities.joined(separator: "\n")
        let candidateText = candidateCourseLines(from: snapshot, limit: 8)

        return """
First-semester starter planning draft:
- Target load: \(suggestedCredits) credits
- Start with 1 intro/core course for \(majorText).
- Add 1 math, quantitative, business, or technology foundation course if required.
- Add 1 writing/communication or general education course.
- Add 1 lighter elective, seminar, or exploration course to avoid overloading the first term.\(minorText)
- Keep one slot flexible until placement, transfer/AP credits, and course availability are confirmed.

Program priorities:
\(priorityText)

Candidate courses from pending requirements:
\(candidateText)

Missing data for exact course names:
- Placement or transfer/AP credit
- Available first-semester course list
- Preferred days/times or work schedule
- Advisor or registration constraints
"""
    }

    private static func candidateCourseLines(from snapshot: AssistantPlannerSnapshot, limit: Int) -> String {
        var lines: [String] = []
        var seen = Set<String>()
        for program in snapshot.programs.sorted(by: { $0.remainingCredits > $1.remainingCredits }) {
            for course in program.pendingCourses {
                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { continue }
                let normalized = code.uppercased()
                guard seen.insert(normalized).inserted else { continue }
                let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let credits = Int(course.credits.rounded())
                lines.append("- \(normalized): \(title.isEmpty ? "Requirement course" : title) (\(credits) cr) [\(program.name)]")
                if lines.count >= limit { return lines.joined(separator: "\n") }
            }
        }
        return "- No concrete pending requirement course candidates were found in the current planner snapshot."
    }

    private static func extractCreditTarget(from message: String) -> Int? {
        do {
            let regex = try NSRegularExpression(pattern: "(\\d{1,2})\\s*credits?", options: [])
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            guard let match = regex.firstMatch(in: message, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: message),
                  let value = Int(message[valueRange])
            else {
                return nil
            }

            return max(1, min(24, value))
        } catch {
            return nil
        }
    }

    private static func twoSemesterSkeleton(snapshot: AssistantPlannerSnapshot) -> String {
        let majors = snapshot.majors.joined(separator: ", ")
        let minors = snapshot.minors.joined(separator: ", ")
        let majorPart = majors.isEmpty ? "your declared program" : majors
        let minorPart = minors.isEmpty ? "" : " | Minors: \(minors)"

        let remaining = snapshot.programs.reduce(0.0) { $0 + $1.remainingCredits }
        let remainingRounded = Int(remaining.rounded())

        let defaultPerTerm = 15
        let dynamicPerTerm = max(9, min(defaultPerTerm, Int(ceil(remaining / 2.0))))
        let term1Target = remainingRounded > 0 ? dynamicPerTerm : defaultPerTerm
        let term2Target = remainingRounded > term1Target ? min(defaultPerTerm, remainingRounded - term1Target) : max(9, min(defaultPerTerm, remainingRounded))

        let now = Date()
        let next30 = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let nearTermTasks = snapshot.tasks.filter {
            guard let due = $0.dueDate else { return false }
            return !$0.isCompleted && due >= now && due <= next30
        }.count

        let nearTermEvents = snapshot.events.filter { $0.startDate >= now && $0.startDate <= next30 }.count
        let loadHint: String
        if nearTermTasks + nearTermEvents >= 8 {
            loadHint = "Current 30-day load is high, so keep term 1 lighter and push optional electives to term 2."
        } else {
            loadHint = "Current 30-day load is manageable; standard pacing should be fine."
        }

        let topPrograms = snapshot.programs
            .sorted { $0.remainingCredits > $1.remainingCredits }
            .prefix(3)

        var programLines: [String] = []
        for program in topPrograms {
            let label = program.kind == .major ? "Major" : "Minor"
            programLines.append("- \(label) \(program.name): \(Int(program.completedCredits.rounded()))/\(Int(program.requiredCredits.rounded())) cr complete")
        }

        var bucketLines: [String] = []
        for program in topPrograms {
            let remainingForProgram = Int(program.remainingCredits.rounded())
            guard remainingForProgram > 0 else { continue }

            let categoryDrivenRequiredShare: Double? = {
                guard let core = program.requiredCoreCredits,
                      let elective = program.requiredElectiveCredits,
                      program.requiredCredits > 0 else { return nil }
                let totalFromBuckets = max(0, core) + max(0, elective)
                guard totalFromBuckets > 0 else { return nil }
                return min(max(core / totalFromBuckets, 0), 1)
            }()

            let requiredShare: Double = categoryDrivenRequiredShare ?? (program.kind == .major ? 0.7 : 0.5)
            let requiredBucket = Int((Double(remainingForProgram) * requiredShare).rounded())
            let electiveBucket = max(0, remainingForProgram - requiredBucket)
            let label = program.kind == .major ? "Major" : "Minor"

            bucketLines.append("- \(label) \(program.name): Required/core ~\(requiredBucket) cr, Elective/flex ~\(electiveBucket) cr")
        }

        let bucketsBlock = bucketLines.isEmpty
            ? "- No remaining requirement credits were detected in the current snapshot."
            : bucketLines.joined(separator: "\n")

        struct PlannedCourse {
            let code: String
            let title: String
            let credits: Int
        }

        var plannedPool: [PlannedCourse] = []
        var seenCodes: Set<String> = []
        for program in topPrograms {
            for course in program.pendingCourses {
                let normalizedCode = course.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !normalizedCode.isEmpty, !seenCodes.contains(normalizedCode) else { continue }
                seenCodes.insert(normalizedCode)
                let credits = max(1, Int(course.credits.rounded()))
                plannedPool.append(
                    PlannedCourse(
                        code: normalizedCode,
                        title: course.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        credits: credits
                    )
                )
            }
        }

        func takeCourses(targetCredits: Int) -> [PlannedCourse] {
            guard targetCredits > 0 else { return [] }
            var taken: [PlannedCourse] = []
            var running = 0
            while !plannedPool.isEmpty, running < targetCredits {
                let next = plannedPool.removeFirst()
                taken.append(next)
                running += next.credits
            }
            return taken
        }

        let semester1Courses = takeCourses(targetCredits: term1Target)
        let semester2Courses = takeCourses(targetCredits: term2Target)
        func semesterLines(_ courses: [PlannedCourse]) -> String {
            guard !courses.isEmpty else {
                return "- No concrete requirement courses were available in the current local requirement snapshot."
            }
            return courses.enumerated().map { idx, item in
                "\(idx + 1)) \(item.code) - \(item.title) (\(item.credits) cr)"
            }.joined(separator: "\n")
        }

        return """
Two-semester deterministic draft for \(majorPart)\(minorPart):
\(programLines.joined(separator: "\n"))
- Remaining requirement credits (estimated): \(remainingRounded)

Semester 1 target:
- Requirement-aligned credits: \(term1Target)
- Prioritize prerequisite-gating and core requirement categories first.

Semester 2 target:
- Requirement-aligned credits: \(term2Target)
- Fill remaining requirements, then use electives for balance.

Course buckets (deterministic estimate):
\(bucketsBlock)

Semester 1 suggested courses:
\(semesterLines(semester1Courses))

Semester 2 suggested courses:
\(semesterLines(semester2Courses))

Load check:
- Upcoming events (30d): \(nearTermEvents)
- Upcoming due tasks (30d): \(nearTermTasks)
- Recommendation: \(loadHint)
"""
    }

    private static func integratedAppSummary(snapshot: AssistantPlannerSnapshot, activePage: AppPage) -> String {
        let totalRemainingCredits = Int(snapshot.programs.reduce(0.0) { $0 + $1.remainingCredits }.rounded())
        let upcomingOpenTasks = snapshot.tasks.filter { !$0.isCompleted }.count

        let pageContext: String = {
            switch activePage {
            case .academics:
                return "Academics view is active, so requirement completion and sequencing are the primary context."
            case .calendar:
                return "Calendar view is active, so scheduling pressure and deadline timing are the primary context."
            case .documents:
                return "Documents view is active, so supporting artifacts and source materials are the primary context."
            case .brightspace:
                return "Brightspace view is active, so LMS-linked workload and timeline risk are the primary context."
            default:
                return "General planner context is active across academics, calendar, and tasks."
            }
        }()

        let majorText = snapshot.majors.isEmpty ? "None selected" : snapshot.majors.joined(separator: ", ")
        let minorText = snapshot.minors.isEmpty ? "None selected" : snapshot.minors.joined(separator: ", ")

        let riskSignal: String = {
            if upcomingOpenTasks >= 8 {
                return "High short-term workload pressure detected from open tasks."
            }
            if totalRemainingCredits > 45 {
                return "High long-range completion pressure detected from remaining credits."
            }
            return "Current workload and completion trajectory appear manageable."
        }()

        return """
What I Found
- Active context: \(activePage.rawValue)
- Majors: \(majorText)
- Minors: \(minorText)
- Open tasks: \(upcomingOpenTasks)
- Remaining requirement credits (estimated): \(totalRemainingCredits)

What It Means
- \(pageContext)
- \(riskSignal)

What You Should Do Next
- Prioritize prerequisite-gating requirements first, then fill with elective/flex items.
- Keep one buffer slot in your next plan for workload spikes.
- Ask for a targeted action, for example: "build me a 16-credit next semester plan".

Data Provenance
- Sources: Program snapshot (majors/minors/requirements), TaskEntity list, active page context.
- Scope: local planner data only (current workspace/session state).
"""
    }
}