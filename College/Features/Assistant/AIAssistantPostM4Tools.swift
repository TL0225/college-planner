// AIAssistantPostM4Tools.swift
// Feature: Assistant
// Purpose: Post-M4 read-only planning tools (requirement risk, what-if, workload, career bridge, syllabus sync).

import CollegeCareer
import Foundation
import SwiftData

// MARK: - Payloads

struct RequirementRiskItemPayload: Codable, Sendable {
    let courseCode: String
    let title: String
    let riskScore: Int
    let reasons: [String]
}

struct AssessRequirementRiskPayload: Codable, Sendable {
    let summary: String
    let risks: [RequirementRiskItemPayload]
    let disclaimer: String
}

struct CourseSwapDiffPayload: Codable, Sendable {
    let removeCourseCode: String
    let addCourseCode: String
    let beforeThemes: [String]
    let afterThemes: [String]
    let careerParagraph2Delta: String
    let disclaimer: String
}

struct SkillGapCourseSuggestionPayload: Codable, Sendable {
    let skill: String
    let courseCode: String?
    let courseTitle: String?
    let rationale: String
}

struct SuggestCoursesForSkillGapsPayload: Codable, Sendable {
    let suggestions: [SkillGapCourseSuggestionPayload]
    let disclaimer: String
}

struct RegistrationWorkloadPayload: Codable, Sendable {
    let creditLoad: Int
    let workloadLevel: String
    let signals: [String]
    let syllabusCues: [String]
    let disclaimer: String
}

struct SyllabusDeadlineDraftPayload: Codable, Sendable {
    let title: String
    let dueDateISO8601: String?
    let courseCode: String?
    let kind: String
}

struct ProposeSyllabusDeadlineSyncPayload: Codable, Sendable {
    let drafts: [SyllabusDeadlineDraftPayload]
    let disclaimer: String
}

struct SyncSyllabusDeadlinesPayload: Codable, Sendable {
    let createdCount: Int
    let titles: [String]
}

// MARK: - assessRequirementRisk

@MainActor
struct AssessRequirementRiskTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "assessRequirementRisk",
        description: "Rank unmet degree requirements by graduation risk (prerequisite chains, remaining credits, audit blockers). Read-only.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "summary, risks[{courseCode,title,riskScore,reasons}], disclaimer",
        sourceLabel: "AssistantPlannerSnapshot + DegreeAudit + prerequisites"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = arguments
        let plan = try activePlanOrThrow(context.collegePersistence)
        let audit = context.collegePersistence.getGraduationStatus(for: plan)
        let violationCount = audit?.violations.count ?? 0

        var risks: [RequirementRiskItemPayload] = []
        for program in context.snapshot.programs.sorted(by: { $0.remainingCredits > $1.remainingCredits }) {
            for course in program.pendingCourses.prefix(8) {
                var reasons: [String] = []
                var score = 40
                if program.remainingCredits > 30 {
                    score += 15
                    reasons.append("High remaining credits in \(program.name) (\(Int(program.remainingCredits.rounded())) cr).")
                }
                if violationCount > 0 {
                    score += 10
                    reasons.append("Degree audit reports \(violationCount) blocker(s).")
                }
                let prereq = context.collegePersistence.searchCatalogCourses(query: course.code, limit: 1).first
                if let prereq, !(prereq.prerequisiteText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    score += 20
                    reasons.append("Has prerequisites — delay can cascade.")
                } else {
                    reasons.append("Fewer prerequisite dependencies detected.")
                }
                if reasons.isEmpty {
                    reasons.append("Pending requirement on your plan.")
                }
                risks.append(
                    RequirementRiskItemPayload(
                        courseCode: course.code,
                        title: course.title,
                        riskScore: min(100, score),
                        reasons: reasons
                    )
                )
            }
        }
        risks.sort { $0.riskScore > $1.riskScore }
        let top = risks.prefix(5)
        let summary: String
        if top.isEmpty {
            summary = "I don't see pending requirement courses on your plan yet. Add planned courses in Degree, then ask again."
        } else if let first = top.first {
            summary = "Highest-risk unmet requirement right now: \(first.courseCode) (\(first.title)) — score \(first.riskScore)/100."
        } else {
            summary = "Requirement risk assessment complete."
        }
        let payload = AssessRequirementRiskPayload(
            summary: summary,
            risks: Array(top),
            disclaimer: "Read-only analysis from your planner and catalog. Confirm sequencing with your advisor."
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
}

// MARK: - simulateCourseSwap

@MainActor
struct SimulateCourseSwapTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let removeCourseCode: String
        let addCourseCode: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "simulateCourseSwap",
        description: "What-if: compare learning-profile themes before/after swapping two planned courses. Does not modify the planner.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"removeCourseCode\":\"CSE 331\",\"addCourseCode\":\"CSE 484\"}",
        outputSchemaDescription: "removeCourseCode, addCourseCode, beforeThemes, afterThemes, careerParagraph2Delta, disclaimer",
        sourceLabel: "AssistantLearningProfileBuilder (in-memory)"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let remove = decoded.removeCourseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let add = decoded.addCourseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remove.isEmpty, !add.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("removeCourseCode and addCourseCode are required")
        }

        let major = context.snapshot.majors.first ?? ""
        let profile = AssistantLearningProfileBuilder.build(
            persistence: context.collegePersistence,
            majorNames: context.snapshot.majors,
            programURL: context.programIdentity?.programURL
        )
        let beforeThemes = themeLabels(from: profile.courses.filter { $0.code.uppercased() != remove.uppercased() })
        let addTitle = context.collegePersistence.searchCatalogCourses(query: add, limit: 1).first?.title ?? add
        let swappedCourse = AssistantLearningProfileCourse(
            code: add,
            title: addTitle,
            status: "planned",
            semesterLabel: "what-if",
            majorRelevant: AssistantLearningProfileBuilder.isMajorRelevantCourse(
                code: add,
                title: addTitle,
                majorName: major,
                requirementCodes: []
            )
        )
        var afterCourses = profile.courses.filter { $0.code.uppercased() != remove.uppercased() }
        afterCourses.append(swappedCourse)
        let afterThemes = themeLabels(from: afterCourses)

        let delta: String
        let added = Set(afterThemes).subtracting(beforeThemes)
        let removed = Set(beforeThemes).subtracting(afterThemes)
        if added.isEmpty && removed.isEmpty {
            delta = "Career narrative themes stay similar — both courses read as comparable for your current plan."
        } else {
            var parts: [String] = []
            if !added.isEmpty { parts.append("Adds emphasis: \(added.joined(separator: ", ")).") }
            if !removed.isEmpty { parts.append("Softens: \(removed.joined(separator: ", ")).") }
            delta = parts.joined(separator: " ")
        }

        let payload = CourseSwapDiffPayload(
            removeCourseCode: remove,
            addCourseCode: add,
            beforeThemes: beforeThemes,
            afterThemes: afterThemes,
            careerParagraph2Delta: delta,
            disclaimer: "Simulation only — use addCourseToPlan / removeCourseFromPlan with confirmation to persist."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Simulated swap \(remove) → \(add). \(delta)",
            errorMessage: nil
        )
    }

    private func themeLabels(from courses: [AssistantLearningProfileCourse]) -> [String] {
        var themes: [String] = []
        for course in courses where course.majorRelevant {
            let title = course.title.lowercased()
            if title.contains("security") { themes.append("security") }
            if title.contains("data") || title.contains("machine learning") { themes.append("data/ML") }
            if title.contains("systems") || title.contains("operating") { themes.append("systems") }
            if title.contains("web") || title.contains("hci") { themes.append("product/web") }
        }
        if themes.isEmpty, courses.contains(where: \.majorRelevant) {
            themes.append("core major")
        }
        return Array(Set(themes)).sorted()
    }
}

// MARK: - suggestCoursesForSkillGaps

@MainActor
struct SuggestCoursesForSkillGapsTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let skills: [String]?
    }

    let descriptor = AssistantToolDescriptor(
        name: "suggestCoursesForSkillGaps",
        description: "Suggest catalog/planner courses that address missing job-match skills. Read-only; add via confirmed plan tools.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"skills?\":[\"security\",\"python\"]}",
        outputSchemaDescription: "suggestions[{skill,courseCode,courseTitle,rationale}], disclaimer",
        sourceLabel: "CareerCourseSkillBridge + catalog"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let skills = decoded?.skills?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            ?? ["communication", "security", "data analysis"]
        let gaps = CareerCourseSkillBridge.gaps(for: skills, collegePersistence: context.collegePersistence)
        let suggestions = gaps.map { gap -> SkillGapCourseSuggestionPayload in
            if let code = gap.courseCode {
                return SkillGapCourseSuggestionPayload(
                    skill: gap.skill,
                    courseCode: code,
                    courseTitle: gap.courseTitle,
                    rationale: "Catalog/planner course matches the skill keyword."
                )
            }
            return SkillGapCourseSuggestionPayload(
                skill: gap.skill,
                courseCode: nil,
                courseTitle: nil,
                rationale: "No catalog match yet — try semanticCatalogSearch or add electives in Degree."
            )
        }
        let payload = SuggestCoursesForSkillGapsPayload(
            suggestions: suggestions,
            disclaimer: "Suggestions only — confirm prerequisites and term availability before registering."
        )
        let summary = suggestions.compactMap(\.courseCode).isEmpty
            ? "No direct course matches found for the listed skills."
            : "Found \(suggestions.filter { $0.courseCode != nil }.count) course suggestion(s) for skill gaps."
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

// MARK: - assessRegistrationWorkload

@MainActor
struct AssessRegistrationWorkloadTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let proposedCredits: Int?
    }

    let descriptor = AssistantToolDescriptor(
        name: "assessRegistrationWorkload",
        description: "Warn if a proposed credit load looks unusually heavy given planner load and syllabus cues.",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"proposedCredits?\":16}",
        outputSchemaDescription: "creditLoad, workloadLevel, signals, syllabusCues, disclaimer",
        sourceLabel: "Planner 30-day load + vault syllabi"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let credits = max(1, min(24, decoded?.proposedCredits ?? 15))
        let now = context.currentDate
        let next30 = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let tasks = context.snapshot.tasks.filter {
            guard let due = $0.dueDate else { return false }
            return !$0.isCompleted && due >= now && due <= next30
        }.count
        let events = context.snapshot.events.filter { $0.startDate >= now && $0.startDate <= next30 }.count

        var signals: [String] = []
        var level = "moderate"
        if credits >= 18 {
            level = "heavy"
            signals.append("\(credits) credits is above a typical 15-credit target.")
        }
        if tasks + events >= 10 {
            level = "heavy"
            signals.append("Busy next 30 days: \(events) events and \(tasks) due tasks.")
        } else {
            signals.append("30-day planner load: \(events) events, \(tasks) due tasks.")
        }

        let profile = AssistantLearningProfileBuilder.build(
            persistence: context.collegePersistence,
            majorNames: context.snapshot.majors,
            programURL: context.programIdentity?.programURL
        )
        var syllabusCues: [String] = []
        if profile.coverage.tier3Available {
            syllabusCues.append("Syllabus notes on file — watch for project-heavy weeks.")
            if level == "moderate" { level = "elevated" }
        }

        let payload = RegistrationWorkloadPayload(
            creditLoad: credits,
            workloadLevel: level,
            signals: signals,
            syllabusCues: syllabusCues,
            disclaimer: "Heuristic only — your syllabus and work schedule may differ."
        )
        let summary = level == "heavy"
            ? "This combination looks unusually heavy for registration planning."
            : "Workload looks \(level) for \(credits) credits."
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

// MARK: - Syllabus deadline sync

@MainActor
enum AssistantSyllabusDeadlineExtractor {
    static func drafts(from persistence: CollegePersistence) -> [SyllabusDeadlineDraftPayload] {
        let syllabiCategory = "Syllabi"
        var out: [SyllabusDeadlineDraftPayload] = []
        for doc in persistence.vaultDocuments where !doc.isFolder && doc.category == syllabiCategory {
            let code = doc.courseCodeLinked?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = doc.summaryText?.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(SyllabusData.self, from: data) {
                for event in parsed.events {
                    guard event.kind == .homework || event.kind == .assignment || event.kind == .project || event.kind == .exam else { continue }
                    out.append(
                        SyllabusDeadlineDraftPayload(
                            title: event.title,
                            dueDateISO8601: event.date,
                            courseCode: code,
                            kind: event.kind.rawValue
                        )
                    )
                }
            }
        }
        return Array(out.prefix(24))
    }
}

@MainActor
struct ProposeSyllabusDeadlineSyncTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "proposeSyllabusDeadlineSync",
        description: "List syllabus-derived due dates as draft planner tasks (no writes).",
        allowedPersonas: [.academicAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "drafts[{title,dueDateISO8601,courseCode,kind}], disclaimer",
        sourceLabel: "Vault syllabi + SyllabusData"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = arguments
        let drafts = AssistantSyllabusDeadlineExtractor.drafts(from: context.collegePersistence)
        let payload = ProposeSyllabusDeadlineSyncPayload(
            drafts: drafts,
            disclaimer: "Drafts only — call syncSyllabusDeadlinesToPlanner after the user confirms."
        )
        let summary = drafts.isEmpty
            ? "No syllabus deadline drafts found. Link syllabi in Documents first."
            : "Prepared \(drafts.count) syllabus deadline draft(s)."
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
struct SyncSyllabusDeadlinesToPlannerTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "syncSyllabusDeadlinesToPlanner",
        description: "Create planner tasks from linked syllabus deadlines. Requires user confirmation.",
        allowedPersonas: [.academicAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "prepared draft count for confirmation",
        sourceLabel: "Vault syllabi → PlannerTask"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = arguments
        let drafts = AssistantSyllabusDeadlineExtractor.drafts(from: context.collegePersistence)
        let payload = ProposeSyllabusDeadlineSyncPayload(
            drafts: drafts,
            disclaimer: "Confirm to create tasks in your planner."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: drafts.isEmpty
                ? "No syllabus deadlines to sync."
                : "Prepared \(drafts.count) syllabus task(s) for confirmation.",
            errorMessage: nil
        )
    }
}
