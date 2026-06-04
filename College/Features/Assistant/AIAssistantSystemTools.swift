// AIAssistantSystemTools.swift
// Feature: Assistant
// Purpose: Assistant module — CreateTaskTool.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
struct CreateTaskTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let title: String
        let dueDateISO8601: String?
    }

    let descriptor = AssistantToolDescriptor(
        name: "createTask",
        description: "Prepare a new task for confirmation when the user explicitly asks to add a task or reminder.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"title\":\"Submit FAFSA\",\"dueDateISO8601?\":\"2026-05-01T17:00:00Z\"}",
        outputSchemaDescription: "title, dueDateISO8601",
        sourceLabel: "TaskEntity via CollegePersistence.addTask"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PendingTaskPayload(title: decoded.title, dueDateISO8601: decoded.dueDateISO8601)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared task creation request for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct CreateCalendarEventTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let title: String
        let startDateISO8601: String
        let endDateISO8601: String?
        let allDay: Bool?
    }

    let descriptor = AssistantToolDescriptor(
        name: "createCalendarEvent",
        description: "Prepare a new calendar event for confirmation when the user explicitly asks to add an event.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"title\":\"Meet advisor\",\"startDateISO8601\":\"2026-04-20T14:00:00Z\",\"endDateISO8601?\":\"2026-04-20T15:00:00Z\",\"allDay?\":false}",
        outputSchemaDescription: "title, startDateISO8601, endDateISO8601, allDay",
        sourceLabel: "CalendarEventEntity via CollegePersistence.addCalendarEvent"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PendingEventPayload(
            title: decoded.title,
            startDateISO8601: decoded.startDateISO8601,
            endDateISO8601: decoded.endDateISO8601 ?? decoded.startDateISO8601,
            allDay: decoded.allDay ?? false
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared calendar event request for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct UpdateTaskTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let existingTitle: String
        let title: String?
        let dueDateISO8601: String?
    }

    let descriptor = AssistantToolDescriptor(
        name: "updateTask",
        description: "Prepare an existing task edit for confirmation when the user explicitly asks to update a task.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"existingTitle\":\"Essay Draft\",\"title?\":\"Essay Final Draft\",\"dueDateISO8601?\":\"2026-04-22T23:59:00Z\"}",
        outputSchemaDescription: "existingTitle, title?, dueDateISO8601?",
        sourceLabel: "TaskEntity via CollegePersistence.updateTask"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PendingTaskUpdatePayload(
            existingTitle: decoded.existingTitle,
            title: decoded.title,
            dueDateISO8601: decoded.dueDateISO8601
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared task update request for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct UpdateCalendarEventTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let existingTitle: String
        let title: String?
        let startDateISO8601: String?
        let endDateISO8601: String?
        let allDay: Bool?
    }

    let descriptor = AssistantToolDescriptor(
        name: "updateCalendarEvent",
        description: "Prepare an existing calendar event edit for confirmation when the user explicitly asks to update an event.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"existingTitle\":\"Meet advisor\",\"title?\":\"Meet advisor\",\"startDateISO8601?\":\"2026-04-20T15:00:00Z\",\"endDateISO8601?\":\"2026-04-20T16:00:00Z\",\"allDay?\":false}",
        outputSchemaDescription: "existingTitle, title?, startDateISO8601?, endDateISO8601?, allDay?",
        sourceLabel: "CalendarEventEntity via CollegePersistence.updateCalendarEvent"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PendingEventUpdatePayload(
            existingTitle: decoded.existingTitle,
            title: decoded.title,
            startDateISO8601: decoded.startDateISO8601,
            endDateISO8601: decoded.endDateISO8601,
            allDay: decoded.allDay
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared calendar event update request for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct DeleteTaskTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let title: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "deleteTask",
        description: "Prepare a task deletion for confirmation when the user explicitly asks to remove a task.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"title\":\"Essay Draft\"}",
        outputSchemaDescription: "title",
        sourceLabel: "TaskEntity via CollegePersistence.deleteTask"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PendingDeletePayload(title: decoded.title)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared task deletion request for confirmation.",
            errorMessage: nil
        )
    }
}

@MainActor
struct SearxHitRow: Codable {
    let title: String
    let url: String
    let content: String
    let engine: String?
}

struct SearxSearchToolResult: Codable {
    let hits: [SearxHitRow]
}

@MainActor
struct SearxWebSearchTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "searxWebSearch",
        description: "Search the public web via the user's configured SearXNG instance. Use for current events, definitions, or external references not in app data. Always cite result URLs in prose.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"query\":\"string\",\"maxResults\":8}",
        outputSchemaDescription: "hits[{title,url,content,engine}]",
        sourceLabel: "SearXNGClient"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        struct Args: Decodable {
            let query: String
            let maxResults: Int?
        }
        let decoded = try AssistantJSONValue.decodeObject(Args.self, from: arguments)
        let q = decoded.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("query is required")
        }
        let cap = min(12, max(1, decoded.maxResults ?? 8))
        guard await AssistantWebSearchRateLimiter.shared.allowSearch() else {
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: false,
                result: nil,
                source: descriptor.sourceLabel,
                summary: "Web search rate limit reached. Wait briefly and try again.",
                errorMessage: "rate_limited"
            )
        }
        let client = SearXNGClient()
        do {
            let hits = try await client.search(query: q, maxResults: cap)
            let filteredHits: [SearXNGClient.Hit] = {
                guard context.selectedPersona == .financialAdvisor else { return hits }
                let jurisdiction = context.collegePersistence.activeSchoolPolicyMetadata().map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
                    ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: context.collegePersistence.getActiveUniversityName())
                let policyHosts = AssistantFinancialAidPolicy.policyHosts(for: jurisdiction)
                AssistantWebFetchPolicy.registerPolicyHosts(policyHosts)
                guard !policyHosts.isEmpty else { return hits }
                let preferred = hits.filter { hit in
                    guard let host = URL(string: hit.url)?.host?.lowercased() else { return false }
                    return policyHosts.contains(host)
                }
                if preferred.isEmpty { return hits }
                let remaining = hits.filter { hit in
                    guard let host = URL(string: hit.url)?.host?.lowercased() else { return true }
                    return !policyHosts.contains(host)
                }
                return preferred + remaining
            }()
            AssistantWebFetchPolicy.registerRecentSearchHosts(from: filteredHits.map(\.url))
            let rows = filteredHits.map { SearxHitRow(title: $0.title, url: $0.url, content: $0.content, engine: $0.engine) }
            let payload = SearxSearchToolResult(hits: rows)
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: "SearXNG returned \(rows.count) result(s).",
                errorMessage: nil
            )
        } catch {
            await AssistantWebSearchRateLimiter.shared.noteSearchFailure()
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: false,
                result: nil,
                source: descriptor.sourceLabel,
                summary: error.localizedDescription,
                errorMessage: error.localizedDescription
            )
        }
    }
}

@MainActor
struct FetchWebPageReadableTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "fetchWebPageReadable",
        description: "Fetch readable main text from an HTTPS page the user surfaced via a recent web search (same host) or an explicitly allowlisted host. Do not use for arbitrary URLs.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"url\":\"https://…\"}",
        outputSchemaDescription: "url, textPreview",
        sourceLabel: "AssistantWebPageExtractor"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        struct Args: Decodable {
            let url: String
        }
        let decoded = try AssistantJSONValue.decodeObject(Args.self, from: arguments)
        let raw = decoded.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: raw), pageURL.scheme?.lowercased() == "https" else {
            throw AssistantToolExecutionError.invalidArguments("A valid https URL is required")
        }
        guard await AssistantWebSearchRateLimiter.shared.allowFetch() else {
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: false,
                result: nil,
                source: descriptor.sourceLabel,
                summary: "Page fetch rate limit reached. Wait briefly and try again.",
                errorMessage: "rate_limited"
            )
        }
        do {
            let text = try await AssistantWebPageExtractor.shared.fetchReadableText(from: pageURL)
            struct Out: Codable {
                let url: String
                let textPreview: String
            }
            let preview = """
            <untrusted_web_content source="\(pageURL.absoluteString)">
            \(String(text.prefix(4000)))
            </untrusted_web_content>
            """
            let payload = Out(url: pageURL.absoluteString, textPreview: preview)
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: "Fetched \(preview.count) characters of readable text.",
                errorMessage: nil
            )
        } catch {
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: false,
                result: nil,
                source: descriptor.sourceLabel,
                summary: error.localizedDescription,
                errorMessage: error.localizedDescription
            )
        }
    }
}

@MainActor
struct ComputeArithmeticExpressionTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "computeArithmetic",
        description: "Evaluate a short arithmetic expression using + − × ÷, parentheses, and decimal numbers (no variables, no functions). Use for quick GPA-style math or unit conversions the user states explicitly.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"expression\":\"(3.0 + 4.5) / 2\"}",
        outputSchemaDescription: "expression, value (number or string for display)",
        sourceLabel: "AssistantArithmeticExpression"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        _ = context
        guard let raw = arguments["expression"]?.stringValue else {
            throw AssistantToolExecutionError.invalidArguments("expression string required")
        }
        do {
            let value = try AssistantArithmeticExpression.evaluate(raw)
            let text = AssistantArithmeticExpression.formatResult(value)
            struct Out: Codable {
                let expression: String
                let value: Double
                let display: String
            }
            let payload = Out(expression: raw, value: value, display: text)
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: true,
                result: try resultObject(payload),
                source: descriptor.sourceLabel,
                summary: "\(raw.trimmingCharacters(in: .whitespacesAndNewlines)) = \(text)",
                errorMessage: nil
            )
        } catch {
            return AssistantToolResultEnvelope(
                tool: descriptor.name,
                ok: false,
                result: nil,
                source: descriptor.sourceLabel,
                summary: "Could not evaluate expression safely.",
                errorMessage: String(describing: error)
            )
        }
    }
}

@MainActor
struct SaveWebLearningTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "saveWebLearning",
        description: "Prepare saving a short user-approved web summary into on-device memory (FTS). Only after the user explicitly asks to remember or save information from the web.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"title\":\"string\",\"summaryBody\":\"string\",\"sourceURLs\":[\"https://…\"],\"tags\":\"optional\"}",
        outputSchemaDescription: "title, summaryBody, sourceURLs, tags",
        sourceLabel: "AssistantWebMemoryStore"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        struct Args: Decodable {
            let title: String
            let summaryBody: String
            let sourceURLs: [String]?
            let tags: String?
        }
        let decoded = try AssistantJSONValue.decodeObject(Args.self, from: arguments)
        let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = decoded.summaryBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else {
            throw AssistantToolExecutionError.invalidArguments("title and summaryBody are required")
        }
        let urls = decoded.sourceURLs?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        struct Out: Codable {
            let title: String
            let summaryBody: String
            let sourceURLs: [String]
            let tags: String?
        }
        let tagsTrimmed = decoded.tags?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tagsOut: String? = tagsTrimmed.isEmpty ? nil : tagsTrimmed
        let payload = Out(title: title, summaryBody: body, sourceURLs: urls, tags: tagsOut)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared web learning save for confirmation.",
            errorMessage: nil
        )
    }
}

struct DeleteCalendarEventTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let title: String
    }

    let descriptor = AssistantToolDescriptor(
        name: "deleteCalendarEvent",
        description: "Prepare a calendar event deletion for confirmation when the user explicitly asks to remove an event.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .write,
        requiresConfirmation: true,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"title\":\"Meet advisor\"}",
        outputSchemaDescription: "title",
        sourceLabel: "CalendarEventEntity via CollegePersistence.deleteCalendarEvent"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let payload = PendingDeletePayload(title: decoded.title)
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared calendar event deletion request for confirmation.",
            errorMessage: nil
        )
    }
}
