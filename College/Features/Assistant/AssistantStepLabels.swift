// AssistantStepLabels.swift
// Feature: Assistant
// Purpose: User-facing tool step labels for loading strip (Ship B).

import Foundation

enum AssistantStepLabels {
    static func label(for toolName: String?) -> String {
        guard let toolName else { return "Thinking…" }
        switch toolName {
        case "getStudentLearningProfile", "getStudentProfile":
            return "Checking your course plan…"
        case "semanticCatalogSearch", "searchCatalogCourses":
            return "Searching the catalog…"
        case "explainRequirements", "getDegreeAudit":
            return "Reviewing degree requirements…"
        case "searxWebSearch":
            return "Searching the web…"
        case "fetchWebPageReadable":
            return "Reading a source page…"
        case "draftSemesterPlan":
            return "Drafting a semester plan…"
        default:
            return "Working…"
        }
    }
}
