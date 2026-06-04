// AIAssistantNavigationTools.swift
// Feature: Assistant
// Purpose: Assistant module — NavigateToPageTool.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
struct NavigateToPageTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "navigateToPage",
        description: "Navigate the main app sidebar to a page (degree, academics, calendar, career, documents, profile, assistant). Brightspace is not available via this tool.",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"page\":\"calendar|degree|academics|career|documents|profile|assistant|settings\"}",
        outputSchemaDescription: "page, navigated, suggestionQueued",
        sourceLabel: "AppPage navigation"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let raw = arguments["page"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let page = AppPage.fromAssistantNavigationToken(raw) else {
            throw AssistantToolExecutionError.invalidArguments("page is required")
        }
        if page == .brightspace {
            throw AssistantToolExecutionError.invalidArguments("Use the Brightspace item in the sidebar for LMS access.")
        }
        let navigated = context.navigate?(page) ?? false
        let payload: [String: AssistantJSONValue] = [
            "page": .string(page.rawValue),
            "navigated": .bool(navigated),
            "askCollegeSessionID": context.askCollegeSessionID.map { .string($0.uuidString) } ?? .null,
        ]
        let summary = navigated
            ? "Opened \(page.rawValue)."
            : "Queued navigation to \(page.rawValue) — tap Go when ready."
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: payload,
            source: descriptor.sourceLabel,
            summary: summary,
            errorMessage: nil
        )
    }
}

@MainActor
struct OpenSettingsSectionTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "openSettingsSection",
        description: "Open the Settings window to a section (general, privacy, appearance, calendar, documents, career).",
        allowedPersonas: [.academicAdvisor, .financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: AssistantConfirmationStyle.none,
        inputSchemaDescription: "{\"section\":\"general|privacy|appearance|calendar|documents|career\"}",
        outputSchemaDescription: "section, opened",
        sourceLabel: "Settings navigation"
    )

    func execute(
        arguments: [String: AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        guard let raw = arguments["section"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let section = SettingsNavSection.fromAssistantToken(raw) else {
            throw AssistantToolExecutionError.invalidArguments("section is required")
        }
        let opened = context.openSettings?(section) ?? false
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: [
                "section": .string(section.rawValue),
                "opened": .bool(opened),
            ],
            source: descriptor.sourceLabel,
            summary: opened ? "Opened Settings (\(section.rawValue))." : "Queued Settings (\(section.rawValue)).",
            errorMessage: nil
        )
    }
}

extension AppPage {
    static func fromAssistantNavigationToken(_ raw: String) -> AppPage? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "degree", "overview": return .degree
        case "academics", "plan": return .academics
        case "calendar": return .calendar
        case "assistant", "askcollege", "ask_college": return .assistant
        case "career": return .career
        case "profile": return .profile
        case "settings": return .settings
        case "documents", "vault": return .documents
        case "brightspace": return .brightspace
        default: return AppPage(rawValue: raw)
        }
    }
}

