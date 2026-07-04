// CatalogImportTransforms.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogImportTransforms.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Pure transforms for catalog course import (local store-only path).
enum CatalogImportTransforms {
    static func normalize(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func catalogLookupCandidates(for raw: String) -> [String] {
        let trimmed = normalize(raw)
        guard !trimmed.isEmpty else { return [] }
        var candidates: [String] = []
        func append(_ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { return }
            candidates.append(v)
        }
        append(trimmed)
        append(trimmed.uppercased())
        append(normalizeCourseCode(trimmed))
        let upper = trimmed.uppercased()
        if let regex = try? NSRegularExpression(pattern: #"^([A-Z]{2,6})-([A-Z]{2,6})\s*(\d+)$"#),
           let match = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           match.numberOfRanges >= 4,
           let r1 = Range(match.range(at: 1), in: upper),
           let r2 = Range(match.range(at: 2), in: upper),
           let r3 = Range(match.range(at: 3), in: upper) {
            append("\(upper[r1])-\(upper[r2]) \(upper[r3])")
        }
        let spaced = upper.replacingOccurrences(
            of: "([A-Za-z]+)(\\d+)",
            with: "$1 $2",
            options: .regularExpression
        )
        append(spaced)
        append(upper.replacingOccurrences(of: " ", with: ""))
        return candidates
    }

    static func normalizeCourseCode(_ raw: String) -> String {
        let cleaned = normalize(raw).uppercased()
        if let match = cleaned.range(of: #"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#, options: .regularExpression) {
            let token = String(cleaned[match])
            return token.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "–", with: " ")
        }
        return cleaned
    }

    static func isInvalidCatalogDescription(_ value: String) -> Bool {
        let lower = normalize(value).lowercased()
        if lower.isEmpty { return true }
        if lower.contains("resource not found"),
           lower.contains("unable to locate") {
            return true
        }
        if lower.contains("home page"), lower.contains("search page"), lower.contains("unable to locate") {
            return true
        }
        if lower.contains("print-friendly page"),
           lower.contains("catalog") {
            return true
        }
        return false
    }

    static func sanitizeCatalogDescription(_ value: String, courseCode: String, title: String) -> String {
        var cleaned = normalize(value)
        guard !cleaned.isEmpty else { return "" }

        let normalizedTitle = normalize(title)
        let normalizedCode = normalize(courseCode)

        if !normalizedCode.isEmpty,
           let codeRange = cleaned.range(of: normalizedCode, options: [.caseInsensitive, .anchored]) {
            let afterCode = cleaned[codeRange.upperBound...]
            if !normalizedTitle.isEmpty,
               let titleRange = afterCode.range(of: normalizedTitle, options: [.caseInsensitive]) {
                cleaned = String(afterCode[titleRange.upperBound...])
                    .replacingOccurrences(of: "^[\\s:;.,-–—]+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                cleaned = String(afterCode)
                    .replacingOccurrences(of: "^[\\s:;.,-–—]+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if !normalizedTitle.isEmpty,
           let titleRange = cleaned.range(of: normalizedTitle, options: [.caseInsensitive, .anchored]) {
            cleaned = String(cleaned[titleRange.upperBound...])
                .replacingOccurrences(of: "^[\\s:;.,-–—]+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    static func extractCreditsFromTitleAndClean(_ rawTitle: String) -> (cleanTitle: String, extractedCredits: Double?) {
        var title = normalize(rawTitle)
        guard !title.isEmpty else { return ("", nil) }

        let patterns = [
            #"(?i)\(\s*(\d+\.5)\s*(credits?|cr\.?|units?)?\s*\)$"#,
            #"(?i)\b(\d+\.5)\b\s*(credits?|cr\.?|units?)?\s*$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: title,
                    range: NSRange(title.startIndex..<title.endIndex, in: title)
                  ),
                  match.numberOfRanges >= 2,
                  let valRange = Range(match.range(at: 1), in: title),
                  let val = Double(title[valRange]) else {
                continue
            }
            if let fullRange = Range(match.range(at: 0), in: title) {
                title.removeSubrange(fullRange)
            }
            title = normalize(title)
            return (title, val)
        }
        return (title, nil)
    }

    static func incomingCourseQuality(_ course: CatalogCourse) -> Int {
        var score = 0
        if !normalize(course.title).isEmpty { score += 2 }
        if course.credits > 0 { score += 2 }
        if !normalize(course.description).isEmpty { score += 2 }
        if course.prerequisites != nil || !normalize(course.prerequisiteText).isEmpty { score += 1 }
        if !normalize(course.department).isEmpty { score += 1 }
        return score
    }

    static func deduplicatedCourses(_ courses: [CatalogCourse]) -> [CatalogCourse] {
        var incomingByCode: [String: CatalogCourse] = [:]
        incomingByCode.reserveCapacity(courses.count)
        for course in courses {
            let key = normalizeCourseCode(course.courseCode)
            guard !key.isEmpty else { continue }
            if let existing = incomingByCode[key] {
                if incomingCourseQuality(course) > incomingCourseQuality(existing) {
                    incomingByCode[key] = course
                }
            } else {
                incomingByCode[key] = course
            }
        }
        return Array(incomingByCode.values)
    }

    private static let prerequisiteEncoder = JSONEncoder()

    static func buildCourseImportInputs(
        from courses: [CatalogCourse],
        departmentIDByKey: [String: UUID]
    ) -> [CatalogRepository.CourseImportInput] {
        let dedupedCourses = deduplicatedCourses(courses)
        var inputs: [CatalogRepository.CourseImportInput] = []
        inputs.reserveCapacity(dedupedCourses.count)

        for catalogCourse in dedupedCourses {
            let courseKey = normalizeCourseCode(catalogCourse.courseCode)
            let extracted = extractCreditsFromTitleAndClean(catalogCourse.title)
            let incomingTitle = normalize(extracted.cleanTitle)
            let incomingDescriptionRaw = normalize(catalogCourse.description)
            let incomingDescription = sanitizeCatalogDescription(
                incomingDescriptionRaw,
                courseCode: catalogCourse.courseCode,
                title: catalogCourse.title
            )
            let incomingDepartment = normalize(catalogCourse.department)
            let incomingCredits = catalogCourse.credits
            let finalTitle: String = {
                if !incomingTitle.isEmpty, incomingTitle.caseInsensitiveCompare(courseKey) != .orderedSame {
                    return incomingTitle
                }
                return courseKey
            }()
            let descriptionIsInvalid = isInvalidCatalogDescription(incomingDescription)
            let finalDescription = descriptionIsInvalid ? nil : incomingDescription
            let finalDepartment = incomingDepartment.isEmpty ? nil : incomingDepartment
            let finalCredits = Int16(max(0, incomingCredits))

            var departmentID: UUID?
            if let finalDepartment {
                departmentID = departmentIDByKey[finalDepartment.lowercased()]
            }

            inputs.append(
                CatalogRepository.CourseImportInput(
                    courseCode: courseKey,
                    title: finalTitle,
                    credits: finalCredits > 0 ? finalCredits : 3,
                    descriptionText: finalDescription,
                    department: finalDepartment,
                    departmentID: departmentID,
                    isArchived: false,
                    catalogStableID: nil,
                    provenanceJSON: nil,
                    prerequisiteRulesJSON: {
                        guard let rule = catalogCourse.prerequisites,
                              let data = try? prerequisiteEncoder.encode(rule) else { return nil }
                        return String(data: data, encoding: .utf8)
                    }(),
                    extractionConfidence: nil,
                    signalSource: nil,
                    parserVersion: CatalogParserCapability.version,
                    departmentLinkConfidence: nil
                )
            )
        }
        return inputs
    }
}
