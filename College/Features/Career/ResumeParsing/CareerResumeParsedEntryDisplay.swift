// CareerResumeParsedEntryDisplay.swift
// Feature: Career / ResumeParsing
// Purpose: Normalize parsed resume entries for Jobright-style review UI.

import Foundation

struct CareerResumeParsedEntryDisplay: Equatable, Sendable {
    var title: String
    var subtitle: String?
    var organization: String?
    var dateLabel: String?
    var bullets: [String]

    static func experience(from entry: CareerResumeStructuredProfile.Entry) -> CareerResumeParsedEntryDisplay {
        let lines = entry.headingLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let combined = lines.joined(separator: " ")
        let dateHeading = lines.last(where: { CareerResumeDateParser.parseDateRange(from: $0) != nil }) ?? combined
        let dateLabel = formattedDateLabel(from: dateHeading)

        var title = lines.first ?? "Role"
        var organization: String?
        var subtitle: String?

        if lines.count > 1, looksLikeJobTitle(lines[1]) {
            organization = stripDates(from: lines[0])
            title = stripDates(from: lines[1])
            if lines.count > 2 {
                subtitle = stripDates(from: lines[2])
            }
        } else if let split = splitTitleOrganization(from: title) {
            title = split.title
            organization = split.organization
            subtitle = split.subtitle
        } else if lines.count > 1 {
            organization = stripDates(from: lines[1])
            if lines.count > 2 {
                subtitle = stripDates(from: lines[2])
            }
        }

        title = stripDates(from: title)
        organization = organization.map(stripDates(from:))
        subtitle = subtitle.map(stripDates(from:))

        if subtitle?.isEmpty == true { subtitle = nil }
        if organization?.isEmpty == true { organization = nil }

        return CareerResumeParsedEntryDisplay(
            title: title,
            subtitle: subtitle,
            organization: organization,
            dateLabel: dateLabel,
            bullets: entry.bullets
        )
    }

    static func project(from entry: CareerResumeStructuredProfile.Entry) -> CareerResumeParsedEntryDisplay {
        let lines = entry.headingLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let combined = lines.joined(separator: " ")
        let title = stripDates(from: lines.first ?? "Project")
        let dateLabel = formattedDateLabel(from: combined)
        let role = lines.count > 1 ? stripDates(from: lines[1]) : nil

        return CareerResumeParsedEntryDisplay(
            title: title,
            subtitle: role,
            organization: nil,
            dateLabel: dateLabel,
            bullets: entry.bullets
        )
    }

    static func education(from entry: CareerResumeStructuredProfile.Entry) -> CareerResumeParsedEntryDisplay {
        let fields = educationFields(from: entry)
        return CareerResumeParsedEntryDisplay(
            title: fields.institution,
            subtitle: fields.degree,
            organization: fields.gpa,
            dateLabel: fields.dateLabel,
            bullets: fields.detailBullets
        )
    }

    struct EducationFields: Equatable, Sendable {
        var institution: String
        var graduation: String?
        var degree: String?
        var gpa: String?
        var honors: String?
        var coursework: String?
        var extras: [String]
        var dateLabel: String?

        var detailBullets: [String] {
            var lines: [String] = []
            if let graduation { lines.append(graduation) }
            if let honors { lines.append(honors) }
            if let coursework { lines.append(coursework) }
            lines.append(contentsOf: extras)
            return lines
        }
    }

    static func educationFields(from entry: CareerResumeStructuredProfile.Entry) -> EducationFields {
        let institution = stripDates(from: entry.headingLines.first ?? "")
        var graduation: String?
        var degree: String?
        var gpa: String?
        var honors: String?
        var coursework: String?
        var extras: [String] = []

        let detailLines = entry.bullets.isEmpty && entry.headingLines.count > 1
            ? Array(entry.headingLines.dropFirst())
            : entry.bullets

        for line in detailLines {
            classifyEducationLine(
                line,
                graduation: &graduation,
                degree: &degree,
                gpa: &gpa,
                honors: &honors,
                coursework: &coursework,
                extras: &extras
            )
        }

        let combined = ([institution] + detailLines).joined(separator: " ")
        return EducationFields(
            institution: institution,
            graduation: graduation,
            degree: degree,
            gpa: gpa,
            honors: honors,
            coursework: coursework,
            extras: extras,
            dateLabel: formattedDateLabel(from: combined)
        )
    }

    private static func classifyEducationLine(
        _ line: String,
        graduation: inout String?,
        degree: inout String?,
        gpa: inout String?,
        honors: inout String?,
        coursework: inout String?,
        extras: inout [String]
    ) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("graduated:") {
            graduation = trimmed
            return
        }
        if lower.hasPrefix("gpa:") {
            gpa = trimmed
            return
        }
        if lower.hasPrefix("coursework:") {
            coursework = trimmed
            return
        }
        if lower.contains("bachelor") || lower.contains("master") || lower.contains("associate") || lower.contains("doctor") {
            degree = trimmed
            return
        }
        if lower.contains("dean") || lower.contains("award") || lower.contains("minor") || lower.contains("magna") || lower.contains("cum laude") {
            honors = honors == nil ? trimmed : [honors, trimmed].compactMap { $0 }.joined(separator: " · ")
            return
        }
        extras.append(trimmed)
    }

    // MARK: - Helpers

    private struct TitleOrganizationSplit {
        var title: String
        var organization: String?
        var subtitle: String?
    }

    private static func looksLikeJobTitle(_ line: String) -> Bool {
        let lower = line.lowercased()
        let markers = [
            "intern", "analyst", "engineer", "developer", "manager", "consultant",
            "specialist", "associate", "director", "lead", "coordinator", "assistant",
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func splitTitleOrganization(from line: String) -> TitleOrganizationSplit? {
        let separators = [" – ", " — ", " - ", " | ", " at "]
        for separator in separators where line.contains(separator) {
            let parts = line.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            return TitleOrganizationSplit(
                title: parts[0],
                organization: parts[1],
                subtitle: parts.count > 2 ? parts[2...].joined(separator: " · ") : nil
            )
        }
        return nil
    }

    private static func formattedDateLabel(from heading: String) -> String? {
        if let range = CareerResumeDateParser.parseDateRange(from: heading) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM"
            let start = formatter.string(from: range.start)
            let lower = heading.lowercased()
            if lower.contains("present") || lower.contains("current") {
                return "\(start) → Present"
            }
            let end = formatter.string(from: range.end)
            return start == end ? start : "\(start) → \(end)"
        }
        return seasonYearLabel(from: heading)
    }

    private static func seasonYearLabel(from heading: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(spring|summer|fall|winter)\s+(20\d{2})\b"#
        ) else { return nil }
        let range = NSRange(heading.startIndex..., in: heading)
        guard let match = regex.firstMatch(in: heading, range: range),
              let seasonRange = Range(match.range(at: 1), in: heading),
              let yearRange = Range(match.range(at: 2), in: heading)
        else { return nil }

        let season = heading[seasonRange].lowercased()
        let year = heading[yearRange]
        let month: String
        switch season {
        case "spring": month = "01"
        case "summer": month = "06"
        case "fall": month = "10"
        case "winter": month = "12"
        default: return nil
        }
        return "\(year)-\(month)"
    }

    private static func stripDates(from text: String) -> String {
        var cleaned = text
        let patterns = [
            #"(?i)\s*\(?\d{4}\s*[–\-—]\s*(\d{4}|present|current|now)\)?"#,
            #"(?i)\s*\(?\(?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{4}\s*[–\-—]\s*((jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{4}|present|current|now)\)?"#,
            #"(?i)\s*\b(spring|summer|fall|winter)\s+20\d{2}\b"#,
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,|–—-"))
    }
}
