// AssistantGuidedResponse.swift
// Feature: Assistant
// Purpose: Single source for missing-data and humanized simple-lookup copy.

import Foundation

enum AssistantGuidedResponse {
    enum Kind: String, Sendable {
        case missingMajor
        case missingMajorFirstSession
        case missingPlannedCourses
        case missingMajorRelevantCourses
        case missingCatalog
        case missingSyllabi
        case webSearchDisabled
        case simpleProgramLookup
        case agendaEmpty
        case missingOfficialSource
        case programAmbiguous
    }

    private static let majorNudgeShownKey = "assistant.guided.majorNudgeShown.session"

    static func resetSessionNudgeFlag() {
        UserDefaults.standard.removeObject(forKey: majorNudgeShownKey)
    }

    static func markMajorNudgeShown() {
        UserDefaults.standard.set(true, forKey: majorNudgeShownKey)
    }

    private static var showedMajorNudgeThisSession: Bool {
        UserDefaults.standard.bool(forKey: majorNudgeShownKey)
    }

    static func text(
        for kind: Kind,
        snapshot: AssistantPlannerSnapshot,
        catalogURL: String? = nil,
        programCandidates: [String] = []
    ) -> String {
        switch kind {
        case .missingMajor:
            return missingMajor(includeNudge: !showedMajorNudgeThisSession)
        case .missingMajorFirstSession:
            markMajorNudgeShown()
            return missingMajor(includeNudge: true)
        case .missingPlannedCourses:
            return """
            I don't see enough courses on your degree plan yet to personalize this answer.

            Open **Degree** and add planned or completed courses for your major, then ask again. I will look at your course mix, not just your major title.

            Want me to walk you through adding your first semester?
            """
        case .missingMajorRelevantCourses:
            return """
            I can share typical paths for your major, but I don't yet see enough **major-related** courses on your plan to personalize from your coursework.

            Add a few core or elective courses for your major in the Degree planner, then ask again. I will highlight patterns from courses that relate to your program.

            _These are planning ideas, not career placement advice._
            """
        case .missingCatalog:
            let link = catalogURL.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            if let link {
                return """
                Your course catalog isn't synced yet, so I can't cite official degree rules from it.

                Open **Settings → Catalog** and sync your school's catalog, or review the official catalog directly: \(link)

                _Official catalog and registrar information supersede this assistant._
                """
            }
            return """
            Your course catalog isn't synced yet.

            Open **Settings → Catalog** and sync your school's catalog, then ask again once sync completes.

            _Official catalog and registrar information supersede this assistant._
            """
        case .missingSyllabi:
            return """
            I don't have syllabus content linked to your courses yet. I can still use your planned courses and catalog descriptions.

            Upload syllabi to **Documents** and link them to course codes if you want finer detail. Syllabi are optional enrichment—you can ask again anytime.
            """
        case .webSearchDisabled:
            return """
            Web search is turned off, so I can't look up current public references for this question.

            Turn on **Web search** under Settings → AI & Storage if you want live web enrichment. I can still answer from your planner, catalog, and on-device model knowledge where possible.
            """
        case .simpleProgramLookup:
            return wrapSimpleLookupProgram(snapshot: snapshot)
        case .agendaEmpty:
            return wrapSimpleLookupAgendaEmpty(scope: .week)
        case .missingOfficialSource:
            let link = catalogURL ?? "your school's official catalog"
            return """
            I couldn't find an **official** catalog or registrar source for that policy question.

            Check the official catalog: \(link). Contact your registrar or academic advising office for a binding answer.

            _I won't state registrar rules without an official source._
            """
        case .programAmbiguous:
            let list = programCandidates.isEmpty
                ? "Multiple programs match your major name."
                : programCandidates.map { "• \($0)" }.joined(separator: "\n")
            return """
            Your major name matches more than one program in the catalog:

            \(list)

            Confirm your program (school, college, and degree type) in **Profile** or the Degree planner, then ask again. I will scope answers to your declared program.

            _If you're unsure, pick the program you're actually pursuing—requirements can differ._
            """
        }
    }

    static func wrapSimpleLookupProgram(snapshot: AssistantPlannerSnapshot) -> String {
        let majors = snapshot.majors
        let minors = snapshot.minors
        if majors.isEmpty && minors.isEmpty {
            return text(for: .missingMajorFirstSession, snapshot: snapshot)
        }
        let majorLine: String
        if !majors.isEmpty {
            majorLine = "**Majors:** \(majors.joined(separator: ", "))"
        } else {
            majorLine = "**Majors:** None selected yet."
        }
        let minorLine: String
        if !minors.isEmpty {
            minorLine = "**Minors:** \(minors.joined(separator: ", "))"
        } else {
            minorLine = "**Minors:** None selected."
        }
        return """
        Here's what I have for your declared programs:

        \(majorLine)
        \(minorLine)

        Want a semester plan, a requirement check, or career paths based on this program? Just ask.
        """
    }

    enum AgendaScope: Sendable {
        case week
        case tomorrow
        case dueList
    }

    static func wrapSimpleLookupAgendaEmpty(scope: AgendaScope) -> String {
        let opener: String = switch scope {
        case .week:
            "Nothing is on your calendar or task list for the next seven days."
        case .tomorrow:
            "Tomorrow looks clear—no events or due tasks found."
        case .dueList:
            "I don't see open tasks with due dates right now."
        }
        return """
        \(opener)

        If you want a wider window, try asking, "What's due next month?" Or say, "Add an assignment," and I can help you draft a task.

        _I only see what's in your College planner._
        """
    }

    static func wrapSimpleLookupAgendaWithItems(header: String, body: String) -> String {
        """
        \(header)

        \(body)

        Need a different window? Ask about **next month** or a specific date.
        """
    }

    private static func missingMajor(includeNudge: Bool) -> String {
        var blocks: [String] = [
            "I don't see a declared major yet, so I can't tailor degree or career guidance to a specific program.",
            "Open **Profile** (or Degree settings) and set your major. Add planned courses in the **Degree** planner when you can, then ask again—I will use your program and coursework instead of generic guesses."
        ]
        if includeNudge {
            markMajorNudgeShown()
            blocks.append("_Tip: Setting your major unlocks requirement and career answers._")
        }
        return blocks.joined(separator: "\n\n")
    }
}
