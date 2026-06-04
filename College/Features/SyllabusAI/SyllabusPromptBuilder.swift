// SyllabusPromptBuilder.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — SyllabusPromptBuilder.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum SyllabusPromptBuilder {
    static func systemPromptJSONSchema(courseCode: String, courseName: String, semesterText: String?) -> String {
        let semesterLine: String = {
            let t = (semesterText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "" : "Semester: \(t)\n"
        }()

        return """
        You are an expert college course assistant.

        TASK:
        Analyze the following syllabus text and extract:
        1) A grading breakdown (each item with an optional weight percent).
        2) A list of key calendar items students care about (exams, midterms, final, quizzes, homework, assignments, projects, labs, presentations, major milestones).
        3) The course meeting schedule, if explicitly stated (date range + meeting days + times).
        4) Instructor/professor contact details (name, email, preferred contact method, office hours), if present.

        CONTEXT:
        Course Code: \(courseCode)
        Course Name: \(courseName)
        \(semesterLine)

        OUTPUT RULES (STRICT):
        - Output ONLY valid JSON. No markdown, no code fences, no explanation.
        - Prefer ISO dates: YYYY-MM-DD.
        - If an item spans multiple days (e.g., Spring Break), encode the date as a range: YYYY-MM-DD..YYYY-MM-DD.
        - If time is known, include time as HH:mm (24-hour). If not known, set time to null.
        - Always include a short evidence snippet in notes (max ~200 chars) copied from the syllabus text.

        IMPORTANT ABOUT DATES:
        - If the syllabus provides an explicit date for an item, include it in `date`.
        - If the syllabus is week-based and the item does NOT list an explicit date, still include the item,
          but set `date` to null and populate `week` (1-based). If the weekday is implied (e.g., "Wed" discussion),
          also populate `weekday` (mon/tue/wed/thu/fri/sat/sun).
        - Do NOT invent weeks. Only include `week` when the syllabus explicitly labels weeks ("Week 3", "Wk 3").

        EVENT CLASSIFICATION RULES:
        - Only use kind="midterm" if the syllabus explicitly contains the word "midterm" for that item.
        - "Spring Break", "No class", "Holiday" are NOT exams. Use kind="other" and allDay=true.
        - When kind="other" is used for a lecture/week schedule item, set title to the topic being taught (e.g., "Pointers & Memory", "Recursion", "Intro to SQL"). Do NOT use generic titles like "Syllabus Date", "Other", or "Topic".
        - Prefer course-related milestones (exams, due dates, major quizzes/projects). Avoid generic administrative dates unless clearly emphasized in the syllabus.

        TABLES / SCHEDULES:
        - If a schedule table contains a date column (e.g., 3/9) and a topic cell (e.g., "Midterm Exam"), pair the topic with the date from the same row.
        - If the syllabus includes a date written as a month name (e.g., "Monday, March 9"), use that exact day.
        - If meeting days are written as space-separated letters such as "M W F" or "T Th", expand them into the full meetingDays array: "M W F" → ["mon","wed","fri"], "T Th" → ["tue","thu"], "M W" → ["mon","wed"], "M W Th" → ["mon","wed","thu"]. Single "M", "W", "F", "T", "Th" tokens should be mapped the same way.
        - If the course calendar uses a stacked multi-line format like:
            Week 1
            Course overview, Boolean Logic
            1/21
          treat the topic line as the event title (kind="other"), set week=1, and convert the M/DD date to YYYY-MM-DD using the semester year for the `date` field. If the same Week block contains a milestone line such as "Midterm Exam, Monday, March 9", extract it as a separate event (kind="midterm") with the explicit date. Each Week block may contribute multiple events.

        JSON SCHEMA:
        {
          "instructor": {
            "name": "Dr. Jane Doe",
            "email": "jdoe@university.edu",
            "contactMethod": "Email",
            "officeHours": "Mon 2-4pm, Wed 10-11am (by appointment)"
          },
          "schedule": {
            "startDate": "2026-01-26",
            "endDate": "2026-05-08",
            "meetingDays": ["mon", "wed"],
            "startTime": "14:00",
            "endTime": "15:20",
            "timeZone": "America/New_York"
          },
          "grading": [
            {"id": "<uuid>", "name": "Midterm 1", "weightPercent": 20, "notes": "..."}
          ],
          "events": [
            {
              "id": "<uuid>",
              "title": "Midterm 1",
              "kind": "midterm",
              "date": "2026-03-12",
              "time": "18:00",
              "allDay": false,
              "notes": "Covers chapters 1-5",
              "week": 7,
              "weekday": "wed",
              "meetingNumber": 12,
              "dateInferred": false,
              "sourcePage": 2
            }
          ],
          "warnings": ["..."]
        }

        IMPORTANT:
        - Deduplicate repeated items.
        - Use kind values: exam, midterm, final, quiz, homework, assignment, project, lab, reading, discussion, presentation, other.
        - If a grading breakdown exists (percent weights in bullets/table/parentheses like "Homework (30%)"), populate grading items.
        - If a grade scale table exists (letter grade cutoffs), include a grading item named "Letter Grade Scale" with weightPercent=null and notes containing a brief summary.
        - Only include `schedule` fields when explicitly supported by the syllabus text.
        - Only include `instructor` fields when explicitly supported by the syllabus text. Do NOT guess emails or office hours.
        - IGNORE non-course administrative/commercial dates such as subscriptions, access-code purchase windows, textbook fees, pricing, or registration cutoffs. Do NOT include those as events.
        """
    }

    static func makePrompt(courseCode: String, courseName: String, semesterText: String?, syllabusText: String) -> String {
        let sys = systemPromptJSONSchema(courseCode: courseCode, courseName: courseName, semesterText: semesterText)
        let processed = preprocessSyllabusText(syllabusText)
        return sys + "\n\nSYLLABUS TEXT:\n" + processed
    }

    // MARK: - Private helpers

    private static let maxSyllabusChars = 6_000

    /// Deduplicates near-identical repeated paragraphs, then smart-truncates to ~6 000 chars.
    private static func preprocessSyllabusText(_ text: String) -> String {
        // ── Step 1: paragraph deduplication ──────────────────────────────────
        // Split on one or more blank lines (regex: \n{2,}).
        let blankLines = try! NSRegularExpression(pattern: "\\n{2,}")
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var paragraphs: [String] = []
        var lastEnd = 0
        for match in blankLines.matches(in: text, range: fullRange) {
            let segRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            paragraphs.append(nsText.substring(with: segRange))
            lastEnd = match.range.location + match.range.length
        }
        paragraphs.append(nsText.substring(from: lastEnd))

        var seen = Set<Substring>()
        var deduplicated: [String] = []
        for paragraph in paragraphs {
            // Normalised key: lowercase, no whitespace, first 120 chars.
            let stripped = paragraph.lowercased()
                .filter { !$0.isWhitespace }
            let key = stripped.prefix(120)
            if key.isEmpty || seen.insert(key).inserted {
                deduplicated.append(paragraph)
            }
        }
        let deduped = deduplicated.joined(separator: "\n\n")

        // ── Step 2: smart truncation ──────────────────────────────────────────
        guard deduped.count > maxSyllabusChars else { return deduped }

        let headCount = 4_000
        let tailCount = 1_500

        let startIndex = deduped.startIndex
        let headEnd = deduped.index(startIndex, offsetBy: headCount)
        let tailStart = deduped.index(deduped.endIndex, offsetBy: -tailCount)

        let head = String(deduped[startIndex..<headEnd])
        let tail = String(deduped[tailStart...])

        return head + "\n\n[... middle content omitted for brevity ...]\n\n" + tail
    }
}
