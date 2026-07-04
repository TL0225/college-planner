// AIAssistantView+PendingActions.swift
// Feature: Assistant
// Purpose: Pending action confirmation + NLP parsing (Phase 6 decomposition).

import SwiftUI
import Foundation

extension AIAssistantView {
    func confirmPendingAction(_ action: AssistantPendingAction) {
        switch action.kind {
        case .createTask:
            _ = collegePersistence.addTask(
                title: action.title,
                dueDate: action.dueDate,
                semester: nil,
                course: nil
            )
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I created the task '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .createEvent:
            guard let startDate = action.startDate, let endDate = action.endDate else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not confirm that event because the date/time was incomplete.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            _ = collegePersistence.addCalendarEvent(
                title: action.title,
                startDate: startDate,
                endDate: endDate,
                allDay: action.allDay,
                semester: nil,
                course: nil
            )
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I created the event '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .editTask:
            guard let uri = action.targetObjectURI,
                  let taskID = AssistantTargetReference.id(from: uri),
                  let task = try? collegePersistence.calendarRepository.fetchPlannerTask(id: taskID)
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that task to edit. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.updateTask(
                id: taskID,
                title: action.title,
                dueDate: action.dueDate,
                semester: task.semester,
                course: task.course,
                notes: task.notes,
                priority: task.priority,
                categoryName: task.categoryName,
                gradingCategory: task.gradingCategory,
                categoryWeightPercent: task.categoryWeightPercent,
                weightPercent: task.weightPercent,
                estimatedEffortMinutes: task.estimatedEffortMinutes
            )

            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I updated the task to '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .editEvent:
            guard let uri = action.targetObjectURI,
                  let eventID = AssistantTargetReference.id(from: uri),
                  let event = try? collegePersistence.calendarRepository.fetchCalendarEvent(id: eventID),
                  let startDate = action.startDate,
                  let endDate = action.endDate
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that event to edit. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.updateCalendarEvent(
                id: eventID,
                title: action.title,
                startDate: startDate,
                endDate: endDate,
                allDay: action.allDay,
                semester: event.semester,
                course: event.course,
                notes: event.notes,
                location: event.location
            )

            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I updated the event to '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .deleteTask:
            guard let uri = action.targetObjectURI,
                  let taskID = AssistantTargetReference.id(from: uri)
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that task to delete. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.deleteTask(id: taskID)
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I deleted the task '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .deleteEvent:
            guard let uri = action.targetObjectURI,
                  let eventID = AssistantTargetReference.id(from: uri)
            else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not locate that event to delete. Try a more specific title.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }

            collegePersistence.deleteCalendarEvent(id: eventID)
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I deleted the event '\(action.title)'.",
                    timestamp: Date()
                )
            )

        case .syncSyllabusDeadlines:
            let drafts: [SyllabusDeadlineDraftPayload] = {
                guard let raw = action.webLearningTags?.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode([SyllabusDeadlineDraftPayload].self, from: raw) else {
                    return []
                }
                return decoded
            }()
            guard !drafts.isEmpty else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "No syllabus drafts were available to sync.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }
            var created = 0
            for draft in drafts {
                let due = draft.dueDateISO8601.flatMap { AssistantISO8601Parsing.date(from: $0) }
                _ = collegePersistence.addTask(title: draft.title, dueDate: due, semester: nil, course: nil)
                created += 1
            }
            messages.append(
                AssistantMessage(
                    isUser: false,
                    role: selectedRole,
                    text: "Confirmed. I created \(created) task(s) from your syllabus deadlines.",
                    timestamp: Date()
                )
            )

        case .saveWebLearning:
            let body = (action.webLearningSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !body.isEmpty else {
                messages.append(
                    AssistantMessage(
                        isUser: false,
                        role: selectedRole,
                        text: "I could not save that learning because the title or summary was empty.",
                        timestamp: Date()
                    )
                )
                pendingAction = nil
                return
            }
            let urls = action.webLearningSourceURLs ?? []
            let role = selectedRole
            let embeddingBlob: Data? = {
                guard AssistantWebSearchSettings.isSemanticMemoryEnabled else { return nil }
                let combined = title + "\n" + body
                let vec = AssistantWebMemoryEmbedding.vector(for: String(combined.prefix(4000)))
                return AssistantWebMemoryEmbedding.data(from: vec)
            }()
            Task { @MainActor in
                do {
                    try await AssistantWebMemoryStore.shared.insert(
                        title: title,
                        body: body,
                        sourceURLs: urls,
                        tags: action.webLearningTags,
                        embedding: embeddingBlob
                    )
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: role,
                            text: "Confirmed. I saved '\(title)' to your on-device web learnings.",
                            timestamp: Date()
                        )
                    )
                } catch {
                    messages.append(
                        AssistantMessage(
                            isUser: false,
                            role: role,
                            text: "I could not save that learning: \(error.localizedDescription)",
                            timestamp: Date()
                        )
                    )
                }
            }
        }

        pendingAction = nil
    }

    func cancelPendingAction() {
        pendingAction = nil
        messages.append(
            AssistantMessage(
                isUser: false,
                role: selectedRole,
                text: "Cancelled. I did not make any changes.",
                timestamp: Date()
            )
        )
    }

    func parsePendingAction(from prompt: String) -> AssistantPendingAction? {
        let normalized = prompt.lowercased()

        if normalized.contains("edit task") || normalized.contains("update task") {
            let requested = extractTitle(from: prompt, keywords: ["edit task", "update task"])
            let matched = assistantContextTasks.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            let existingTitle = matched?.title ?? requested
            let newTitle = parseUpdatedTitle(from: prompt, fallbackTitle: existingTitle)
            let newDueDate = parseRelativeDateTime(from: normalized) ?? matched?.dueDate
            return AssistantPendingAction(
                kind: .editTask,
                title: newTitle,
                originalTitle: existingTitle,
                dueDate: newDueDate,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: matched?.dueDate,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("edit event") || normalized.contains("update event") {
            let requested = extractTitle(from: prompt, keywords: ["edit event", "update event"])
            let matched = assistantContextEvents.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            let existingTitle = matched?.title ?? requested
            let newTitle = parseUpdatedTitle(from: prompt, fallbackTitle: existingTitle)
            let allDay = normalized.contains("all day") ? true : (matched?.allDay ?? false)
            let startDate = parseRelativeDateTime(from: normalized) ?? matched?.startDate ?? defaultEventStartDate(from: normalized)
            let endDate = Calendar.current.date(byAdding: .hour, value: allDay ? 24 : 1, to: startDate)
            return AssistantPendingAction(
                kind: .editEvent,
                title: newTitle,
                originalTitle: existingTitle,
                dueDate: nil,
                startDate: startDate,
                endDate: endDate,
                allDay: allDay,
                previousDueDate: nil,
                previousStartDate: matched?.startDate,
                previousEndDate: matched?.endDate,
                previousAllDay: matched?.allDay,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("delete task") || normalized.contains("remove task") {
            let requested = extractTitle(from: prompt, keywords: ["delete task", "remove task"])
            let matched = assistantContextTasks.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            return AssistantPendingAction(
                kind: .deleteTask,
                title: matched?.title ?? requested,
                originalTitle: matched?.title ?? requested,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: matched?.dueDate,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("delete event") || normalized.contains("remove event") {
            let requested = extractTitle(from: prompt, keywords: ["delete event", "remove event"])
            let matched = assistantContextEvents.first { ($0.title).localizedCaseInsensitiveContains(requested) }
            return AssistantPendingAction(
                kind: .deleteEvent,
                title: matched?.title ?? requested,
                originalTitle: matched?.title ?? requested,
                dueDate: nil,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: matched?.startDate,
                previousEndDate: matched?.endDate,
                previousAllDay: matched?.allDay,
                targetObjectURI: matched.map { AssistantTargetReference.uri(for: $0.id) }
            )
        }

        if normalized.contains("create task") || normalized.contains("add task") || normalized.contains("new task") || normalized.contains("create todo") {
            let title = extractTitle(from: prompt, keywords: ["create task", "add task", "new task", "create todo", "add todo"])
            let dueDate = parseRelativeDateTime(from: normalized)
            return AssistantPendingAction(
                kind: .createTask,
                title: title,
                originalTitle: nil,
                dueDate: dueDate,
                startDate: nil,
                endDate: nil,
                allDay: false,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil
            )
        }

        if normalized.contains("create event") ||
            normalized.contains("create an event") ||
            normalized.contains("add event") ||
            normalized.contains("new event") {
            let title = extractTitle(from: prompt, keywords: ["create event", "add event", "new event"])
            let allDay = normalized.contains("all day")
            let startDate = parseRelativeDateTime(from: normalized)
            let resolvedStart = startDate ?? defaultEventStartDate(from: normalized)
            let endDate = Calendar.current.date(byAdding: .hour, value: allDay ? 24 : 1, to: resolvedStart)
            return AssistantPendingAction(
                kind: .createEvent,
                title: title,
                originalTitle: nil,
                dueDate: nil,
                startDate: resolvedStart,
                endDate: endDate,
                allDay: allDay,
                previousDueDate: nil,
                previousStartDate: nil,
                previousEndDate: nil,
                previousAllDay: nil,
                targetObjectURI: nil
            )
        }

        return nil
    }

    func extractTitle(from prompt: String, keywords: [String]) -> String {
        let lowered = prompt.lowercased()
        for keyword in keywords {
            if let range = lowered.range(of: keyword) {
                let suffix = prompt[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = suffix
                    .replacingOccurrences(of: "called", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "named", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "titled", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return "Assistant item"
    }

    func parseUpdatedTitle(from prompt: String, fallbackTitle: String) -> String {
        let parts = prompt.components(separatedBy: " to ")
        if let last = parts.last, parts.count > 1 {
            let updated = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if !updated.isEmpty {
                return updated
            }
        }
        return fallbackTitle
    }

    func defaultEventStartDate(from prompt: String) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let baseDate: Date
        if prompt.contains("tomorrow") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else {
            baseDate = now
        }
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components) ?? now
    }

    func parseRelativeDateTime(from prompt: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var baseDate = now

        if prompt.contains("tomorrow") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else if prompt.contains("today") {
            baseDate = now
        }

        do {
            let regex = try NSRegularExpression(pattern: "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)", options: [.caseInsensitive])
            let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
            if let match = regex.firstMatch(in: prompt, options: [], range: range),
               let hourRange = Range(match.range(at: 1), in: prompt) {
                let minuteRange = Range(match.range(at: 2), in: prompt)
                let periodRange = Range(match.range(at: 3), in: prompt)

                guard var hour = Int(prompt[hourRange]) else { return nil }
                let minute = minuteRange.flatMap { Int(prompt[$0]) } ?? 0
                let period = periodRange.map { prompt[$0].lowercased() } ?? "am"

                if period == "pm" && hour < 12 { hour += 12 }
                if period == "am" && hour == 12 { hour = 0 }

                var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
                components.hour = hour
                components.minute = minute
                return calendar.date(from: components)
            }
        } catch {
            return nil
        }

        return nil
    }
}
