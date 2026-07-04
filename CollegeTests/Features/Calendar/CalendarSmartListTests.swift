// CalendarSmartListTests.swift
// Phase 4 — smart list filtering (M30-088).

import Foundation
import Testing
import CollegeCalendar

@Suite("Calendar Smart Lists")
struct CalendarSmartListTests {
  @Test("Study focus detects exam and homework titles")
    func studyFocusKeywords() {
        let exam = CalendarPlannerTaskSummary(id: UUID(), title: "CSE 331 Midterm Exam", dueDate: Date())
        let chore = CalendarPlannerTaskSummary(id: UUID(), title: "Buy groceries", dueDate: Date())
        #expect(CalendarTasksDeadlinesHub.isStudyFocused(exam))
        #expect(!CalendarTasksDeadlinesHub.isStudyFocused(chore))
    }

    @Test("Overdue filter excludes future tasks")
    func overdueFilter() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let tasks = [
            CalendarPlannerTaskSummary(id: UUID(), title: "Late", dueDate: yesterday),
            CalendarPlannerTaskSummary(id: UUID(), title: "Soon", dueDate: tomorrow),
        ]
        let overdue = CalendarTasksDeadlinesHub.filter(tasks, list: .overdue, reference: today, calendar: calendar)
        #expect(overdue.count == 1)
        #expect(overdue.first?.title == "Late")
    }

    @Test("Every smart list has a non-empty description")
    func smartListDescriptions() {
        for list in CalendarSmartList.allCases {
            #expect(!list.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
