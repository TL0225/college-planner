// AIAssistantAcademicTools.swift
// Feature: Assistant
// Purpose: Assistant module — GetStudentProfileTool.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

@MainActor
struct GetStudentProfileTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getStudentProfile",
        description: "Return the student's academic profile, declared programs, and current standing.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "name, gpa, creditsEarned, creditsRequired, expectedGraduation, classStanding, majors, minors, activePage",
        sourceLabel: "ProfileEntity + CollegePersistence"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let profile = context.collegePersistence.profile else {
            throw AssistantToolExecutionError.missingProfile
        }

        let core = context.collegePersistence
        let creditsRequired = core.primaryCreditsRequired()
        let payload = StudentProfilePayload(
            name: profile.name ?? "Student",
            gpa: core.primaryGPA(),
            creditsEarned: core.primaryCreditsEarned(),
            creditsRequired: creditsRequired > 0 ? creditsRequired : 120,
            expectedGraduation: core.primaryExpectedGraduation(),
            classStanding: core.primaryClassStanding(),
            majors: context.snapshot.majors,
            minors: context.snapshot.minors,
            activePage: context.activePage.rawValue
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Loaded profile facts for \(payload.name) with \(payload.creditsEarned)/\(payload.creditsRequired) credits and GPA \(String(format: "%.2f", payload.gpa)).",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetProgramProgressTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getProgramProgress",
        description: "Return progress and remaining credits for each declared major or minor.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"programName?\":\"string\"}",
        outputSchemaDescription: "programs[], totalRemainingCredits",
        sourceLabel: "AssistantPlannerSnapshot + CollegePersistence progress helpers"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let requestedName = arguments["programName"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let filtered = context.snapshot.programs.filter { item in
            guard let requestedName, !requestedName.isEmpty else { return true }
            return item.name.lowercased().contains(requestedName)
        }

        let programs = filtered.map { item in
            ProgramPayload(
                name: item.name,
                kind: item.kind == .major ? "major" : "minor",
                completedCredits: Int(item.completedCredits.rounded()),
                requiredCredits: Int(item.requiredCredits.rounded()),
                remainingCredits: Int(item.remainingCredits.rounded()),
                requiredCoreCredits: item.requiredCoreCredits.map { Int($0.rounded()) },
                requiredElectiveCredits: item.requiredElectiveCredits.map { Int($0.rounded()) }
            )
        }
        let payload = ProgramProgressPayload(
            programs: programs,
            totalRemainingCredits: programs.reduce(0) { $0 + $1.remainingCredits }
        )

        let summary: String
        if programs.isEmpty {
            summary = "No declared programs matched the requested filter."
        } else {
            summary = "Loaded progress for \(programs.count) declared program(s) with \(payload.totalRemainingCredits) estimated credits remaining."
        }

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: summary,
            errorMessage: nil
        )
    }
}

@MainActor
struct GetUpcomingScheduleTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let days: Int?
    }

    let descriptor = AssistantToolDescriptor(
        name: "getUpcomingSchedule",
        description: "Return upcoming events and open tasks within a date range.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"days?\":7}",
        outputSchemaDescription: "daysRequested, eventCount, taskCount, events[], tasks[]",
        sourceLabel: "CalendarEventEntity + TaskEntity snapshot"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let requestedDays = max(1, min(decoded?.days ?? 7, 30))
        let endDate = Calendar.current.date(byAdding: .day, value: requestedDays, to: context.currentDate) ?? context.currentDate
        let formatter = ISO8601DateFormatter()

        let events = context.snapshot.events
            .filter { $0.startDate >= context.currentDate && $0.startDate <= endDate }
            .sorted { $0.startDate < $1.startDate }
            .prefix(10)
            .map {
                ScheduleEventPayload(
                    title: $0.title,
                    startISO8601: formatter.string(from: $0.startDate),
                    allDay: $0.allDay
                )
            }

        let tasks = context.snapshot.tasks
            .filter {
                guard let dueDate = $0.dueDate else { return false }
                return !$0.isCompleted && dueDate >= context.currentDate && dueDate <= endDate
            }
            .sorted {
                guard let lhs = $0.dueDate, let rhs = $1.dueDate else { return false }
                return lhs < rhs
            }
            .prefix(10)
            .map {
                ScheduleTaskPayload(
                    title: $0.title,
                    dueISO8601: $0.dueDate.map { formatter.string(from: $0) },
                    isCompleted: $0.isCompleted
                )
            }

        let payload = SchedulePayload(
            daysRequested: requestedDays,
            eventCount: events.count,
            taskCount: tasks.count,
            events: Array(events),
            tasks: Array(tasks)
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Loaded \(payload.eventCount) upcoming events and \(payload.taskCount) open tasks across the next \(requestedDays) day(s).",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetSAPStatusTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getSAPStatus",
        description: "Return SAP attempted credits, completed credits, and completion-rate risk.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "attemptedCredits, completedCredits, sapRate, threshold, status",
        sourceLabel: "CollegePersistence.sapStats"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let sap = context.collegePersistence.sapStats()
        let threshold = 0.67
        let status: String
        if sap.attempted == 0 {
            status = "no_history"
        } else if sap.rate < threshold {
            status = "at_risk"
        } else if sap.rate < threshold + 0.05 {
            status = "watch"
        } else {
            status = "good_standing"
        }

        let payload = SAPStatusPayload(
            attemptedCredits: sap.attempted,
            completedCredits: sap.completed,
            sapRate: sap.rate,
            threshold: threshold,
            status: status
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "SAP status is \(status) with \(payload.completedCredits)/\(payload.attemptedCredits) completed attempted credits (\(Int((payload.sapRate * 100).rounded()))%).",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetFullTimeStatusTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let semesterName: String?
    }

    let descriptor = AssistantToolDescriptor(
        name: "getFullTimeStatus",
        description: "Return whether a semester's planned credits meet the school's full-time threshold.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"semesterName?\":\"Fall 2026\"}",
        outputSchemaDescription: "semesterName, plannedCredits, fullTimeThreshold, meetsFullTime, policySource, benchmarkSource, guidance[], policyEvidence[]",
        sourceLabel: "PlanEntity semesters + SchoolPolicies.minCreditsForFullTime"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let plan = try activePlanOrThrow(context.collegePersistence)
        let semesters = plan.semestersArray.sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.seasonOrder < $1.seasonOrder
        }

        let requested = decoded?.semesterName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let semester = semesters.first(where: { item in
            guard let requested, !requested.isEmpty else { return false }
            let name = item.name.lowercased()
            return name.contains(requested)
        }) ?? semesters.last

        guard let semester else {
            throw AssistantToolExecutionError.missingPlan
        }

        let plannedCredits = semester.coursesArray.reduce(0) { $0 + Int($1.credits) }
        let jurisdiction = context.collegePersistence.activeSchoolPolicyMetadata().map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
            ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: context.collegePersistence.getActiveUniversityName())
        let evidence = AssistantPolicyEvidenceStore.evidence(
            for: [.schoolFinancialAid, .enrollmentIntensity, .stateAid],
            jurisdiction: jurisdiction
        )
        let storedThreshold = activePolicies(from: context.collegePersistence)?.minCreditsForFullTime
        let threshold = storedThreshold ?? (jurisdiction.allowsFederalFAFSA ? 12 : nil)
        let meets = threshold.map { plannedCredits >= $0 }
        let source: String = {
            if storedThreshold != nil {
                return "School policy threshold loaded from the active university."
            }
            if threshold != nil {
                return "No stored school threshold was found; using a labeled federal/state planning benchmark."
            }
            return "No stored full-time policy threshold was found."
        }()
        let guidance: [String] = {
            guard let threshold else {
                return ["Ask the school financial-aid office for the official full-time or enrollment-intensity threshold."]
            }
            if plannedCredits >= threshold {
                return [
                    "Planned credits meet the current planning threshold.",
                    "Aid can still depend on program eligibility, SAP, cost of attendance, SAI, and the school's package."
                ]
            }
            return [
                "Planned credits are below the current planning threshold and may reduce or jeopardize aid.",
                "Check school financial-aid policy first, then FAFSA/Pell enrollment intensity and any state aid extra-resource before dropping courses."
            ]
        }()

        let payload = FullTimeStatusPayload(
            semesterName: semester.name.isEmpty ? "Semester" : semester.name,
            plannedCredits: plannedCredits,
            fullTimeThreshold: threshold,
            meetsFullTime: meets,
            policySource: source,
            benchmarkSource: storedThreshold == nil && threshold != nil ? "Federal/state full-time planning benchmark; verify with school." : nil,
            guidance: guidance,
            policyEvidence: evidence
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: threshold == nil
                ? "Loaded \(plannedCredits) planned credits for \(payload.semesterName), but no full-time threshold is stored yet."
                : "Loaded \(plannedCredits) planned credits for \(payload.semesterName) against a full-time planning threshold of \(threshold ?? 0).",
            errorMessage: nil
        )
    }
}

@MainActor
struct SearchCatalogCoursesTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let query: String?
        let limit: Int?
    }

    let descriptor = AssistantToolDescriptor(
        name: "searchCatalogCourses",
        description: "Search the course catalog by code or title.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"query\":\"MATH 101\",\"limit?\":8}",
        outputSchemaDescription: "query, resultCount, courses[]",
        sourceLabel: "CatalogCourseSearchBridge"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let query = (decoded.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AssistantToolExecutionError.missingCatalogQuery
        }

        let limit = max(1, min(decoded.limit ?? 8, 12))

        let activeUniversityName = context.collegePersistence.getActiveUniversity()?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if activeUniversityName.isEmpty {
            let payload = CatalogSearchPayload(query: query, resultCount: 0, courses: [])
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: "No active catalog university is set yet.",
                errorMessage: nil
            )
        }

        let capabilities = await context.collegePersistence.catalogCapabilities(universityName: activeUniversityName)
        if let assistantMessage = capabilities.assistantCatalogSummary {
            let payload = CatalogSearchPayload(query: query, resultCount: 0, courses: [])
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: assistantMessage,
                errorMessage: nil
            )
        }
        if !capabilities.coursesReady {
            let isProgramOnly = capabilities.programsReady && !capabilities.requirementsReady && !capabilities.coursesReady
            let summary = capabilities.programsReady
                ? (isProgramOnly
                    ? "Catalog programs are indexed, but course listings are still importing. Try again in a moment."
                    : "Catalog is still importing courses. Try again in a moment.")
                : "Catalog is not ready yet. Complete catalog sync first."

            let payload = CatalogSearchPayload(query: query, resultCount: 0, courses: [])
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: summary,
                errorMessage: nil
            )
        }

        let results = CatalogCourseSearchBridge.search(
            query: query,
            limit: limit,
            persistence: context.collegePersistence
        )
        let payload = CatalogSearchPayload(
            query: query,
            resultCount: results.count,
            courses: results.prefix(limit).map {
                CatalogCoursePayload(
                    courseCode: $0.courseCode,
                    title: $0.title,
                    credits: Int($0.credits),
                    description: $0.descriptionText?.assistantNilIfEmpty,
                    prerequisiteCodes: $0.prerequisiteCodes?.assistantNilIfEmpty
                )
            }
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: results.isEmpty
                ? "No catalog courses matched \"\(query)\"."
                : "Found \(payload.resultCount) catalog match(es) for \"\(query)\".",
            errorMessage: nil
        )
    }
}

@MainActor
struct CheckPrerequisitesTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let courseCode: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "checkPrerequisites",
        description: "Check whether the active plan satisfies a course's prerequisites.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"courseCode\":\"CSE 331\"}",
        outputSchemaDescription: "courseCode, met, missingCourses, message",
        sourceLabel: "CollegePersistence.checkPrerequisites"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let requestedCode = decoded.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = try activePlanOrThrow(context.collegePersistence)

        let activeUniversityName = context.collegePersistence.getActiveUniversity()?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if activeUniversityName.isEmpty {
            throw AssistantToolExecutionError.courseNotFound(requestedCode)
        }

        let capabilities = await context.collegePersistence.catalogCapabilities(universityName: activeUniversityName)
        guard capabilities.coursesReady else {
            let summary = capabilities.programsReady
                ? "Catalog programs are indexed, but course listings are still importing. Prerequisite details will be available shortly."
                : "Catalog is not ready yet. Complete catalog sync first."
            let payload = PrerequisiteCheckPayload(
                courseCode: requestedCode,
                met: false,
                missingCourses: [],
                message: summary
            )
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: summary,
                errorMessage: nil
            )
        }

        let catalogMatches = context.collegePersistence.searchCatalogCourses(
            query: requestedCode,
            limit: 6
        )
        guard let course = catalogMatches.first(where: {
            $0.courseCode.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(requestedCode.replacingOccurrences(of: " ", with: "")) == .orderedSame
        }) ?? catalogMatches.first else {
            throw AssistantToolExecutionError.courseNotFound(requestedCode)
        }

        let result = context.collegePersistence.checkPrerequisites(for: course, plan: plan)
        let payload = PrerequisiteCheckPayload(
            courseCode: course.courseCode.isEmpty ? requestedCode : course.courseCode,
            met: result.met,
            missingCourses: result.missingCourses,
            message: result.message
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: result.met
                ? "Prerequisites are satisfied for \(payload.courseCode)."
                : "Prerequisites are not satisfied for \(payload.courseCode). Missing: \(result.missingCourses.joined(separator: ", ")).",
            errorMessage: nil
        )
    }
}

@MainActor
struct GetDegreeAuditTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getDegreeAudit",
        description: "Return graduation readiness, top blockers, and category-level progress.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "ready, overallProgress, violationCount, topViolations, categories[]",
        sourceLabel: "GraduationValidator"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let plan = try activePlanOrThrow(context.collegePersistence)
        guard let audit = context.collegePersistence.getGraduationStatus(for: plan) else {
            throw AssistantToolExecutionError.invalidArguments("Graduation audit could not be generated for the active university.")
        }

        let payload = DegreeAuditPayload(
            ready: audit.ready,
            overallProgress: audit.overallProgress,
            violationCount: audit.violations.count,
            topViolations: Array(audit.violations.prefix(5).map(\.description)),
            categories: audit.categoryResults.prefix(8).map {
                DegreeAuditCategoryPayload(
                    category: $0.category,
                    creditsCompleted: $0.creditsCompleted,
                    creditsRequired: $0.creditsRequired,
                    progress: $0.progress
                )
            }
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: audit.ready
                ? "Graduation audit shows the plan is currently ready with overall progress \(Int((audit.overallProgress * 100).rounded()))%."
                : "Graduation audit found \(audit.violations.count) blocker(s) with overall progress \(Int((audit.overallProgress * 100).rounded()))%.",
            errorMessage: nil
        )
    }
}

@MainActor
struct DraftSemesterPlanTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let targetCredits: Int?
        let horizon: String?
        let creditHint: String?
    }

    let descriptor = AssistantToolDescriptor(
        name: "draftSemesterPlan",
        description: "Return a structured next-semester (or two-semester) course load draft. Does not modify the planner.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"targetCredits?\":15,\"horizon?\":\"next|two\",\"creditHint?\":\"16 credits\"}",
        outputSchemaDescription: "horizon, focusSemester*, targetCredits*, candidateCourses[], slots*, workloadNote, disclaimer",
        sourceLabel: "PlanEntity semesters + AssistantPlannerSnapshot"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let twoTerms = isTwoSemesterHorizon(decoded?.horizon)

        let plan = try activePlanOrThrow(context.collegePersistence)
        let semesterList = sortedPlanSemesters(plan)
        let now = context.currentDate

        let remaining = context.snapshot.programs.reduce(0.0) { $0 + $1.remainingCredits }
        let remainingRounded = Int(remaining.rounded())
        let requestedCredits = extractCreditTargetFromArguments(arguments)
            ?? decoded?.targetCredits.map { max(1, min(24, $0)) }

        let defaultPerTerm = 15
        let term1Target: Int = {
            if let requestedCredits {
                return max(3, min(24, requestedCredits))
            }
            return max(12, min(19, remainingRounded > 0 ? remainingRounded : defaultPerTerm))
        }()

        let nextSem = nextSemester(after: now, in: plan) ?? semesterList.last
        let secondSem: PlannerSemester? = {
            guard twoTerms, let nextSem else { return nil }
            return semesterAfter(nextSem, in: semesterList)
        }()

        let focusName = nextSem?.name ?? "Next semester"
        let focusYear = nextSem.map { Int($0.year) } ?? Calendar.current.component(.year, from: now)
        let focusSeason = nextSem?.season ?? "Fall"

        let secondName = secondSem?.name

        let term2Target: Int? = {
            guard twoTerms else { return nil }
            if remainingRounded > term1Target {
                return min(defaultPerTerm, remainingRounded - term1Target)
            }
            return max(9, min(defaultPerTerm, remainingRounded))
        }()
        let term2CreditsResolved = term2Target ?? defaultPerTerm

        let next30 = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let nearTermTasks = context.snapshot.tasks.filter {
            guard let due = $0.dueDate else { return false }
            return !$0.isCompleted && due >= now && due <= next30
        }.count
        let nearTermEvents = context.snapshot.events.filter { $0.startDate >= now && $0.startDate <= next30 }.count
        let workloadNote: String
        if nearTermTasks + nearTermEvents >= 8 {
            workloadNote = "High 30-day planner load (\(nearTermEvents) events, \(nearTermTasks) due tasks). Prefer a slightly lighter term 1 if you chose two terms."
        } else {
            workloadNote = "30-day planner load looks manageable (\(nearTermEvents) events, \(nearTermTasks) due tasks)."
        }

        let priorities = context.snapshot.programs
            .sorted { $0.remainingCredits > $1.remainingCredits }
            .prefix(3)
            .map { item in
                let kind = item.kind == .major ? "Major" : "Minor"
                return "\(kind) \(item.name): \(Int(item.remainingCredits.rounded())) credits remaining"
            }

        let candidates = context.snapshot.programs
            .sorted { $0.remainingCredits > $1.remainingCredits }
            .flatMap { program in
                program.pendingCourses.prefix(6).map { course in
                    SemesterCourseCandidatePayload(
                        program: program.name,
                        courseCode: course.code,
                        title: course.title,
                        credits: Int(course.credits.rounded())
                    )
                }
            }
            .prefix(12)

        var rationale: [String] = []
        rationale.append("Target ~\(term1Target) credits for \(focusName) based on remaining requirement estimate (\(remainingRounded) cr) and your planner snapshot.")
        if twoTerms, let term2Target {
            rationale.append("Second term draft targets ~\(term2Target) credits to keep pacing toward completion.")
        }
        rationale.append("Sequence rule: prioritize prerequisite-gating and core major requirements before electives.")
        if candidates.isEmpty {
            rationale.append("Exact course names are missing because no pending requirement course candidates were available in the planner snapshot.")
        } else {
            rationale.append("Use candidateCourses as the first pool to verify against prerequisites, placement, transfer/AP credit, and term availability.")
        }
        rationale.append(workloadNote)

        let slots1 = buildSemesterDraftSlots(targetCredits: term1Target)
        let slots2: [SemesterDraftSlot]? = twoTerms ? buildSemesterDraftSlots(targetCredits: term2CreditsResolved) : nil

        let payload = DraftSemesterPlanPayload(
            horizon: twoTerms ? "two_semesters" : "next_semester",
            focusSemesterName: focusName,
            focusSemesterYear: focusYear,
            focusSemesterSeason: focusSeason,
            secondSemesterName: secondName,
            targetCreditsTerm1: term1Target,
            targetCreditsTerm2: twoTerms ? term2CreditsResolved : nil,
            totalRemainingCreditsEstimate: remainingRounded,
            programPriorities: Array(priorities),
            candidateCourses: Array(candidates),
            rationale: rationale,
            slotsTerm1: slots1,
            slotsTerm2: slots2,
            workloadNote: workloadNote,
            disclaimer: "Draft only. This tool does not add, drop, or reschedule courses. Confirm any real schedule changes in your Degree planner or with your advisor."
        )

        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: twoTerms
                ? "Drafted a two-semester pacing template for \(focusName) with ~\(term1Target) credits in term 1."
                : "Drafted a next-semester load template for \(focusName) targeting ~\(term1Target) credits.",
            errorMessage: nil
        )
    }
}

@MainActor
struct ExplainRequirementsTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "explainRequirements",
        description: "Explain remaining degree requirements in student-friendly language using the active degree audit snapshot.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "summary, programPriorities, categories, disclaimer",
        sourceLabel: "CollegePersistence.degreeAudit + AssistantPlannerSnapshot"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let plan = try activePlanOrThrow(context.collegePersistence)
        guard let audit = context.collegePersistence.getGraduationStatus(for: plan) else {
            throw AssistantToolExecutionError.invalidArguments("Graduation audit could not be generated for the active university.")
        }
        let categories = audit.categoryResults.prefix(8).map {
            DegreeAuditCategoryPayload(
                category: $0.category,
                creditsCompleted: $0.creditsCompleted,
                creditsRequired: $0.creditsRequired,
                progress: $0.progress
            )
        }
        let priorities = context.snapshot.programs
            .sorted { $0.remainingCredits > $1.remainingCredits }
            .map { "\($0.name): \(Int($0.remainingCredits.rounded())) credits remaining" }
        let payload = RequirementsExplanationPayload(
            summary: audit.ready
                ? "Your planner snapshot appears close to graduation readiness."
                : "Your planner snapshot still has remaining or blocked requirements to review.",
            programPriorities: priorities,
            categories: categories,
            disclaimer: "This is planner guidance only, not an official registrar degree audit."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared a plain-language requirement explanation with \(categories.count) category rows.",
            errorMessage: nil
        )
    }
}

@MainActor
struct AssessRegistrationReadinessTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "assessRegistrationReadiness",
        description: "Identify planner-based registration readiness blockers such as missing plan data, low/high credits, and graduation blockers.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "ready, blockers, warnings, nextSteps",
        sourceLabel: "PlanEntity semesters + DegreeAudit"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let plan = try activePlanOrThrow(context.collegePersistence)
        let semesters = sortedPlanSemesters(plan)
        let audit = context.collegePersistence.getGraduationStatus(for: plan)
        var blockers: [String] = []
        var warnings: [String] = []

        if semesters.isEmpty {
            blockers.append("No semesters are present in the active plan.")
        }
        if let audit, !audit.violations.isEmpty {
            blockers.append(contentsOf: audit.violations.prefix(5).map(\.description))
        }
        if let next = nextSemester(after: context.currentDate, in: plan) ?? semesters.last {
            let credits = next.coursesArray.reduce(0) { $0 + Int($1.credits) }
            if credits < 12 {
                warnings.append("\(next.name.isEmpty ? "Next semester" : next.name) has \(credits) planned credits, which may be low for full-time pacing or aid.")
            } else if credits > 18 {
                warnings.append("\(next.name.isEmpty ? "Next semester" : next.name) has \(credits) planned credits, which may be an overload.")
            }
        } else {
            warnings.append("No upcoming semester was found to evaluate credit load.")
        }

        let payload = RegistrationReadinessPayload(
            ready: blockers.isEmpty,
            blockers: blockers,
            warnings: warnings,
            nextSteps: [
                "Confirm prerequisite-sensitive courses before registration.",
                "Compare planned credits with financial-aid enrollment requirements.",
                "Review official registration holds in the student portal."
            ]
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: blockers.isEmpty ? "No planner-based registration blockers found." : "Found \(blockers.count) registration readiness blocker(s).",
            errorMessage: nil
        )
    }
}

@MainActor
struct DraftWeeklyScheduleTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "draftWeeklySchedule",
        description: "Draft a study/week planning template from upcoming events and tasks. Does not create calendar events.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"focus?\":\"exam week|regular week\"}",
        outputSchemaDescription: "days, eventCount, taskCount, suggestedBlocks, caveats",
        sourceLabel: "AssistantPlannerSnapshot events/tasks"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let calendar = Calendar.current
        let now = context.currentDate
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let events = context.snapshot.events.filter { $0.startDate >= now && $0.startDate <= weekEnd }
        let tasks = context.snapshot.tasks.filter {
            guard let due = $0.dueDate else { return !$0.isCompleted }
            return !$0.isCompleted && due <= weekEnd
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let days = Array(Set(events.map { formatter.string(from: $0.startDate) })).sorted()
        let blocks = [
            "Reserve two 60-90 minute study blocks for the hardest active course.",
            "Put due-soon tasks before optional review work.",
            "Leave a buffer block for commute, meals, or catch-up work."
        ]
        let payload = WeeklyScheduleDraftPayload(
            days: days.isEmpty ? ["No dated events found this week"] : days,
            eventCount: events.count,
            taskCount: tasks.count,
            suggestedBlocks: blocks,
            caveats: ["Draft only. Use createCalendarEvent after the student confirms exact times."]
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Drafted a weekly planning template from \(events.count) event(s) and \(tasks.count) task(s).",
            errorMessage: nil
        )
    }
}

