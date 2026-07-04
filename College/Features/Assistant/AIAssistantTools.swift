// AIAssistantTools.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantToolDescriptor.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

enum AssistantPersona: String, Codable, Sendable {
    case academicAdvisor
    case financialAdvisor
}

enum AssistantToolMode: String, Codable, Sendable {
    case read
    case write
}

enum AssistantJSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AssistantJSONValue])
    case array([AssistantJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AssistantJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AssistantJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == floor(value) ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null, .object, .array:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "true" { return true }
            if normalized == "false" { return false }
            return nil
        default:
            return nil
        }
    }

    var objectValue: [String: AssistantJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    static func fromEncodable<T: Encodable>(_ value: T) throws -> AssistantJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AssistantJSONValue.self, from: data)
    }

    static func decodeObject<T: Decodable>(_ type: T.Type, from object: [String: AssistantJSONValue]) throws -> T {
        let data = try JSONEncoder().encode(AssistantJSONValue.object(object))
        return try JSONDecoder().decode(type, from: data)
    }
}

struct AssistantToolDescriptor: Codable, Sendable {
    let name: String
    let description: String
    let allowedPersonas: [AssistantPersona]
    let mode: AssistantToolMode
    let requiresConfirmation: Bool
    let confirmationStyle: AssistantConfirmationStyle
    let inputSchemaDescription: String
    let outputSchemaDescription: String
    let sourceLabel: String

    /// Minimal fields for the planner prompt (smaller than full ``AssistantToolDescriptor`` JSON).
    var planningRepresentation: AssistantPlanningToolDescriptor {
        AssistantPlanningToolDescriptor(
            name: name,
            description: description,
            mode: mode,
            requiresConfirmation: requiresConfirmation,
            inputSchemaDescription: inputSchemaDescription
        )
    }
}

/// Tool catalog entry for planning hops only (drops output schema and source labels).
struct AssistantPlanningToolDescriptor: Codable, Sendable {
    let name: String
    let description: String
    let mode: AssistantToolMode
    let requiresConfirmation: Bool
    let inputSchemaDescription: String
}

struct AssistantToolCallEnvelope: Codable, Sendable {
    let tool: String
    let arguments: [String: AssistantJSONValue]
}

struct AssistantToolResultEnvelope: Codable, Sendable {
    let tool: String
    let ok: Bool
    let result: [String: AssistantJSONValue]?
    let source: String
    let summary: String
    let errorMessage: String?
}

enum AssistantModelAction: Sendable {
    case toolCall(AssistantToolCallEnvelope)
    case finalAnswer(String)
}

@MainActor
struct AssistantToolExecutionContext {
    let collegePersistence: CollegePersistence
    let activePage: AppPage
    let selectedPersona: AssistantPersona
    let snapshot: AssistantPlannerSnapshot
    let currentDate: Date
    var activeIntent: String?
    var programIdentity: AssistantProgramIdentityContext?
    var navigate: ((AppPage) -> Bool)?
    var highlightVaultDocument: ((UUID) -> Void)?
    var askCollegeSessionID: UUID?
    var openSettings: ((SettingsNavSection) -> Bool)?
}

enum AssistantToolExecutionError: LocalizedError {
    case toolNotFound(String)
    case personaNotAllowed(String)
    case invalidArguments(String)
    case confirmationRequired(String)
    case missingPlan
    case missingProfile
    case missingCatalogQuery
    case courseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .personaNotAllowed(let name):
            return "This persona cannot use \(name)."
        case .invalidArguments(let reason):
            return "Tool arguments were invalid: \(reason)"
        case .confirmationRequired(let name):
            return "Tool \(name) requires confirmation before execution."
        case .missingPlan:
            return "No active academic plan is available."
        case .missingProfile:
            return "The student profile is missing."
        case .missingCatalogQuery:
            return "A course search query is required."
        case .courseNotFound(let code):
            return "No catalog course matched \(code)."
        }
    }
}

@MainActor
protocol AIAssistantTool {
    var descriptor: AssistantToolDescriptor { get }
    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope
}

@MainActor
enum AIAssistantToolRegistry {
    static let all: [any AIAssistantTool] = [
        GetStudentProfileTool(),
        GetProgramProgressTool(),
        GetUpcomingScheduleTool(),
        GetSAPStatusTool(),
        GetFullTimeStatusTool(),
        SearchCatalogCoursesTool(),
        SemanticCatalogSearchTool(),
        ProgramsUnderDepartmentTool(),
        CheckPrerequisitesTool(),
        GetDegreeAuditTool(),
        DraftSemesterPlanTool(),
        ExplainRequirementsTool(),
        AssessRegistrationReadinessTool(),
        GetStudentLearningProfileTool(),
        DraftWeeklyScheduleTool(),
        GetAidDeadlinesTool(),
        ScreenAidEligibilityTool(),
        EstimateAidRangeTool(),
        ExplainSAPPolicyTool(),
        ExtractAidDocumentFactsTool(),
        CompareAwardLetterToPlannerTool(),
        CreateTaskTool(),
        CreateCalendarEventTool(),
        UpdateTaskTool(),
        UpdateCalendarEventTool(),
        DeleteTaskTool(),
        DeleteCalendarEventTool(),
        ComputeArithmeticExpressionTool(),
        SearxWebSearchTool(),
        FetchWebPageReadableTool(),
        SaveWebLearningTool(),
        NavigateToPageTool(),
        OpenSettingsSectionTool(),
        ResolveEventLocationTool(),
        SearchDocumentsTool(),
        GetDocumentExcerptTool(),
        OpenDocumentTool(),
        AddSemesterTool(),
        AddCourseToPlanTool(),
        RemoveCourseFromPlanTool(),
        GetAppSettingTool(),
        UpdateAppSettingTool(),
        GetProfileTool(),
        UpdateProfileTool(),
        ListJobApplicationsTool(),
        UpdateJobApplicationStatusTool(),
        ListCareerResumesTool(),
        OpenResumeBuilderTool(),
        GetJobResumeMatchTool(),
        GetJobApplicationDetailTool(),
        AssessRequirementRiskTool(),
        SimulateCourseSwapTool(),
        SuggestCoursesForSkillGapsTool(),
        AssessRegistrationWorkloadTool(),
        ProposeSyllabusDeadlineSyncTool(),
        SyncSyllabusDeadlinesToPlannerTool(),
    ]

    static func descriptors(for persona: AssistantPersona) -> [AssistantToolDescriptor] {
        all.map(\.descriptor)
            .filter { $0.allowedPersonas.contains(persona) }
            .sorted { $0.name < $1.name }
    }

    static func tool(named name: String) -> (any AIAssistantTool)? {
        all.first { $0.descriptor.name == name }
    }

    static func descriptor(named name: String) -> AssistantToolDescriptor? {
        tool(named: name)?.descriptor
    }

    static func catalogJSON(for persona: AssistantPersona) -> String {
        let descriptors = descriptors(for: persona)
        guard let data = try? JSONEncoder().encode(descriptors),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    /// Compact tool list for ``AIAssistantService/planResponse`` to reduce planner prompt size.
    static func planningCatalogJSON(for persona: AssistantPersona) -> String {
        let slim = descriptors(for: persona).map(\.planningRepresentation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(slim),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    /// Names allowed in planner `tool_call` output for a persona (planning catalog only).
    static func planningToolNames(for persona: AssistantPersona) -> Set<String> {
        Set(descriptors(for: persona).map(\.name))
    }
}

@MainActor
struct AIAssistantToolExecutor {
    let context: AssistantToolExecutionContext

    func execute(call: AssistantToolCallEnvelope) async -> AssistantToolResultEnvelope {
        guard let tool = AIAssistantToolRegistry.tool(named: call.tool) else {
            return failureEnvelope(tool: call.tool, error: AssistantToolExecutionError.toolNotFound(call.tool))
        }

        guard tool.descriptor.allowedPersonas.contains(context.selectedPersona) else {
            return failureEnvelope(tool: call.tool, error: AssistantToolExecutionError.personaNotAllowed(call.tool))
        }

        guard !tool.descriptor.requiresConfirmation else {
            return failureEnvelope(tool: call.tool, error: AssistantToolExecutionError.confirmationRequired(call.tool))
        }

        do {
            return try await tool.execute(arguments: call.arguments, context: context)
        } catch {
            return failureEnvelope(tool: call.tool, error: error)
        }
    }

    private func failureEnvelope(tool: String, error: Error) -> AssistantToolResultEnvelope {
        AssistantToolResultEnvelope(
            tool: tool,
            ok: false,
            result: nil,
            source: "assistant.tooling",
            summary: error.localizedDescription,
            errorMessage: error.localizedDescription
        )
    }
}

@MainActor
func activePlanOrThrow(_ collegePersistence: CollegePersistence) throws -> PlannerPlan {
    guard let plan = collegePersistence.getActivePlan() else {
        throw AssistantToolExecutionError.missingPlan
    }
    return plan
}

@MainActor
func activePolicies(from collegePersistence: CollegePersistence) -> SchoolPolicies? {
    collegePersistence.activeSchoolPolicies()
}

@MainActor
func semesterSummaries(from plan: PlannerPlan) -> [SemesterSummaryPayload] {
    plan.semestersArray
        .sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.seasonOrder < $1.seasonOrder
        }
        .map { semester in
            let courses = semester.coursesArray.sorted {
                $0.code.localizedCaseInsensitiveCompare($1.code) == .orderedAscending
            }
            return SemesterSummaryPayload(
                name: semester.name,
                year: Int(semester.year),
                season: semester.season,
                totalCredits: courses.reduce(0) { $0 + Int($1.credits) },
                courses: courses.map {
                    CoursePlanPayload(
                        code: $0.code,
                        name: $0.name,
                        credits: Int($0.credits),
                        status: $0.status.isEmpty ? ($0.isCompleted ? "Completed" : "Planned") : $0.status,
                        grade: $0.grade
                    )
                }
            )
        }
}

func semesterApproxStartDate(year: Int, season: String?) -> Date {
    let calendar = Calendar.current
    let month: Int
    switch (season ?? "").lowercased() {
    case "spring":
        month = 1
    case "summer":
        month = 5
    case "fall":
        month = 8
    default:
        month = 12
    }
    return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
}

func sortedPlanSemesters(_ plan: PlannerPlan) -> [PlannerSemester] {
    plan.semestersArray
}

func nextSemester(after date: Date, in plan: PlannerPlan) -> PlannerSemester? {
    let list = sortedPlanSemesters(plan)
    return list.first { semesterApproxStartDate(year: Int($0.year), season: $0.season) > date }
}

func indexOfSemester(_ semester: PlannerSemester, in list: [PlannerSemester]) -> Int? {
    list.firstIndex { $0.id == semester.id }
}

func semesterAfter(_ semester: PlannerSemester, in list: [PlannerSemester]) -> PlannerSemester? {
    guard let idx = indexOfSemester(semester, in: list), idx + 1 < list.count else { return nil }
    return list[idx + 1]
}

func extractCreditTargetFromArguments(_ arguments: [String: AssistantJSONValue]) -> Int? {
    if let direct = arguments["targetCredits"]?.intValue {
        return max(1, min(24, direct))
    }
    if let text = arguments["creditHint"]?.stringValue {
        return extractCreditTarget(from: text.lowercased())
    }
    return nil
}

func extractCreditTarget(from message: String) -> Int? {
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

func buildSemesterDraftSlots(targetCredits: Int) -> [SemesterDraftSlot] {
    let cappedTarget = max(3, min(targetCredits, 24))
    let slotCount = min(6, max(3, cappedTarget / 4 + (cappedTarget % 4 == 0 ? 0 : 1)))
    var credits = Array(repeating: cappedTarget / slotCount, count: slotCount)
    var remainder = cappedTarget % slotCount
    for i in credits.indices where remainder > 0 {
        credits[i] += 1
        remainder -= 1
    }
    return credits.enumerated().map { index, credit in
        let role: String
        switch index {
        case 0:
            role = "major_core_or_prereq_gate"
        case 1:
            role = "major_core"
        case 2:
            role = "minor_or_distribution"
        case credits.count - 1:
            role = "elective_buffer"
        default:
            role = "flexible_elective"
        }
        return SemesterDraftSlot(slot: index + 1, suggestedRole: role, suggestedCredits: max(1, min(credit, 6)))
    }
}

func isTwoSemesterHorizon(_ raw: String?) -> Bool {
    guard let raw else { return false }
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "two"
        || normalized == "2"
        || normalized == "two_semesters"
        || normalized == "two_semester"
        || normalized.contains("two term")
        || normalized.contains("2 term")
}

struct StudentProfilePayload: Codable {
    let name: String
    let gpa: Double
    let creditsEarned: Int
    let creditsRequired: Int
    let expectedGraduation: String?
    let classStanding: String?
    let majors: [String]
    let minors: [String]
    let activePage: String
}

struct ProgramProgressPayload: Codable {
    let programs: [ProgramPayload]
    let totalRemainingCredits: Int
}

struct ProgramPayload: Codable {
    let name: String
    let kind: String
    let completedCredits: Int
    let requiredCredits: Int
    let remainingCredits: Int
    let requiredCoreCredits: Int?
    let requiredElectiveCredits: Int?
}

struct SchedulePayload: Codable {
    let daysRequested: Int
    let eventCount: Int
    let taskCount: Int
    let events: [ScheduleEventPayload]
    let tasks: [ScheduleTaskPayload]
}

struct ScheduleEventPayload: Codable {
    let title: String
    let startISO8601: String
    let allDay: Bool
}

struct ScheduleTaskPayload: Codable {
    let title: String
    let dueISO8601: String?
    let isCompleted: Bool
}

struct SAPStatusPayload: Codable {
    let attemptedCredits: Int
    let completedCredits: Int
    let sapRate: Double
    let threshold: Double
    let status: String
}

struct FullTimeStatusPayload: Codable {
    let semesterName: String
    let plannedCredits: Int
    let fullTimeThreshold: Int?
    let meetsFullTime: Bool?
    let policySource: String
    let benchmarkSource: String?
    let guidance: [String]
    let policyEvidence: [AssistantPolicyEvidence]
}

struct CatalogCoursePayload: Codable {
    let courseCode: String
    let title: String
    let credits: Int
    let description: String?
    let prerequisiteCodes: String?
}

struct CatalogSearchPayload: Codable {
    let query: String
    let resultCount: Int
    let courses: [CatalogCoursePayload]
}

struct PrerequisiteCheckPayload: Codable {
    let courseCode: String
    let met: Bool
    let missingCourses: [String]
    let message: String
}

struct DegreeAuditPayload: Codable {
    let ready: Bool
    let overallProgress: Double
    let violationCount: Int
    let topViolations: [String]
    let categories: [DegreeAuditCategoryPayload]
}

struct PendingTaskPayload: Codable {
    let title: String
    let dueDateISO8601: String?
}

struct PendingEventPayload: Codable {
    let title: String
    let startDateISO8601: String
    let endDateISO8601: String
    let allDay: Bool
}

struct PendingTaskUpdatePayload: Codable {
    let existingTitle: String
    let title: String?
    let dueDateISO8601: String?
}

struct PendingEventUpdatePayload: Codable {
    let existingTitle: String
    let title: String?
    let startDateISO8601: String?
    let endDateISO8601: String?
    let allDay: Bool?
}

struct PendingDeletePayload: Codable {
    let title: String
}

struct SemesterDraftSlot: Codable {
    let slot: Int
    let suggestedRole: String
    let suggestedCredits: Int
}

struct SemesterCourseCandidatePayload: Codable {
    let program: String
    let courseCode: String
    let title: String
    let credits: Int
}

struct DraftSemesterPlanPayload: Codable {
    let horizon: String
    let focusSemesterName: String
    let focusSemesterYear: Int
    let focusSemesterSeason: String
    let secondSemesterName: String?
    let targetCreditsTerm1: Int
    let targetCreditsTerm2: Int?
    let totalRemainingCreditsEstimate: Int
    let programPriorities: [String]
    let candidateCourses: [SemesterCourseCandidatePayload]
    let rationale: [String]
    let slotsTerm1: [SemesterDraftSlot]
    let slotsTerm2: [SemesterDraftSlot]?
    let workloadNote: String
    let disclaimer: String
}

struct RequirementsExplanationPayload: Codable {
    let summary: String
    let programPriorities: [String]
    let categories: [DegreeAuditCategoryPayload]
    let disclaimer: String
}

struct RegistrationReadinessPayload: Codable {
    let ready: Bool
    let blockers: [String]
    let warnings: [String]
    let nextSteps: [String]
}

struct WeeklyScheduleDraftPayload: Codable {
    let days: [String]
    let eventCount: Int
    let taskCount: Int
    let suggestedBlocks: [String]
    let caveats: [String]
}

struct AidDeadlinePayload: Codable {
    let jurisdiction: String
    let deadlines: [String]
    let sourcesToCheck: [String]
    let policyEvidence: [AssistantPolicyEvidence]
    let disclaimer: String
}

struct AidEligibilityScreenPayload: Codable {
    let program: String
    let jurisdiction: String
    let likelyRelevantChecks: [String]
    let missingInputs: [String]
    let policyEvidence: [AssistantPolicyEvidence]
    let sensitiveDataWarning: String
    let disclaimer: String
}

struct AidEstimatePayload: Codable {
    let estimateType: String
    let providedInputs: [String]
    let missingInputs: [String]
    let safeEstimateRange: String
    let disclaimer: String
}

struct SAPPolicyExplanationPayload: Codable {
    let completionRateThreshold: Double
    let status: String
    let explanation: [String]
    let nextSteps: [String]
    let policyEvidence: [AssistantPolicyEvidence]
}

struct AidDocumentFactsPayload: Codable {
    let supportedDocumentTypes: [String]
    let factsToExtract: [String]
    let privacyNote: String
    let nextPrompt: String
}

struct AwardPlannerComparisonPayload: Codable {
    let checks: [String]
    let plannerSignals: [String]
    let questionsForAidOffice: [String]
    let disclaimer: String
}

struct DegreeAuditCategoryPayload: Codable {
    let category: String
    let creditsCompleted: Int
    let creditsRequired: Int
    let progress: Double
}

struct SemesterSummaryPayload: Codable {
    let name: String
    let year: Int
    let season: String
    let totalCredits: Int
    let courses: [CoursePlanPayload]
}

struct CoursePlanPayload: Codable {
    let code: String
    let name: String
    let credits: Int
    let status: String
    let grade: String?
}

@MainActor
func resultObject<T: Encodable>(_ payload: T) throws -> [String: AssistantJSONValue] {
    guard case .object(let object) = try AssistantJSONValue.fromEncodable(payload) else {
        throw AssistantToolExecutionError.invalidArguments("Tool payload could not be encoded as an object.")
    }
    return object
}

extension String {
    var assistantNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
