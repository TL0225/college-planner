// CourseLeafCourselistHTMLParser.swift
// Feature: Catalog
// Purpose: Catalog module — CourseLeafCourselistHTMLParser.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftSoup

/// Parses CourseLeaf `table.sc_courselist` grids from HTML (including CDATA from index.xml).
enum CourseLeafCourselistHTMLParser {

    static func parse(doc: Document, logger: DebugLogger) throws -> [DegreeRequirement]? {
        let allTables = try doc.select("table.sc_courselist").array()
        guard !allTables.isEmpty else { return nil }

        func normalizeCategory(_ raw: String) -> String {
            var s = raw.normalizedCatalogText()
            guard !s.isEmpty else { return s }
            s = s.replacingOccurrences(of: "\\s*:+\\s*$", with: "", options: .regularExpression)
            return s.normalizedCatalogText()
        }

        func parseChooseCount(from text: String) -> Int? {
            let s = text.normalizedCatalogText().lowercased()
            if let match = s.firstMatch(of: /(?:choose|select|complete)\s+at\s+least\s+(\d+)/) {
                return Int(match.1)
            }
            if let match = s.firstMatch(of: /(\d+)\s+of\s+the\s+following/) {
                return Int(match.1)
            }
            if let match = s.firstMatch(of: /(?:choose|select|complete)\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)/) {
                let token = String(match.1)
                let spelled: [String: Int] = [
                    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                ]
                return Int(token) ?? spelled[token]
            }
            if s.contains("one of the following") { return 1 }
            return nil
        }

        func creditsFromHourscol(_ row: Element) -> String? {
            if let cell = try? row.select("td.hourscol").first(),
               let raw = try? cell.text() {
                let t = raw.normalizedCatalogText()
                if !t.isEmpty, t != "0" { return t }
            }
            return nil
        }

        func creditsIntFromHourscol(_ row: Element) -> Int {
            guard let text = creditsFromHourscol(row) else { return 0 }
            if let rangeMatch = text.range(
                of: #"(\d+)\s*-\s*(\d+)"#,
                options: .regularExpression
            ) {
                let slice = String(text[rangeMatch])
                let parts = slice.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if let first = parts.first { return first }
            }
            let digits = text.replacingOccurrences(
                of: "[^0-9]",
                with: "",
                options: .regularExpression
            )
            return Int(digits) ?? 0
        }

        func isTableHeaderRow(_ row: Element) -> Bool {
            if (try? row.select("th").first()) != nil { return true }
            let text = ((try? row.text()) ?? "").normalizedCatalogText().lowercased()
            return text == "course title credits" || text == "code title credits"
        }

        func isAreaHeaderRow(_ row: Element) -> String? {
            if let span = try? row.select("span.courselistcomment.areaheader, span.areaheader").first(),
               let text = try? span.text() {
                let normalized = text.normalizedCatalogText()
                return normalized.isEmpty ? nil : normalized
            }
            if row.hasClass("areaheader"),
               let text = try? row.select("span.courselistcomment, td").first()?.text() {
                let normalized = text.normalizedCatalogText()
                return normalized.isEmpty ? nil : normalized
            }
            return nil
        }

        func isAreaSubheaderRow(_ row: Element) -> String? {
            if let span = try? row.select("span.courselistcomment.areasubheader, span.areasubheader").first(),
               let text = try? span.text() {
                let normalized = text.normalizedCatalogText()
                return normalized.isEmpty ? nil : normalized
            }
            if row.hasClass("areasubheader"),
               let text = try? row.select("span.courselistcomment, td").first()?.text() {
                let normalized = text.normalizedCatalogText()
                return normalized.isEmpty ? nil : normalized
            }
            return nil
        }

        func commentText(in row: Element) -> String? {
            if (try? row.select("a.bubblelink.code, a[onclick*=showCourse], td.codecol .code_bubble").first()) != nil {
                return nil
            }
            if let span = try? row.select("span.courselistcomment").first(),
               let text = try? span.text() {
                let normalized = text.normalizedCatalogText()
                return normalized.isEmpty ? nil : normalized
            }
            if (try? row.select("td[colspan]").first()) != nil,
               (try? row.select("td.codecol").first()) == nil {
                let text = ((try? row.text()) ?? "").normalizedCatalogText()
                return text.isEmpty ? nil : text
            }
            return nil
        }

        func isElectiveProse(_ text: String) -> Bool {
            let lower = text.normalizedCatalogText().lowercased()
            if lower.contains("see list below") || lower.contains("see note") && lower.contains("complete") {
                return true
            }
            let patterns = [
                "complete ",
                "choose ",
                "select ",
                "one of the following",
                "pick ",
                "enough courses to reach",
            ]
            return patterns.contains(where: { lower.contains($0) })
        }

        func isSubsectionTitleComment(_ text: String) -> Bool {
            let t = text.normalizedCatalogText()
            guard !t.isEmpty, t.count <= 72 else { return false }
            let lower = t.lowercased()
            if isElectiveProse(t) { return false }
            if lower.contains("(") && lower.contains("course") { return false }
            if lower.range(of: "\\d", options: .regularExpression) != nil { return false }
            return true
        }

        func implicitTableLeadCategory(_ table: Element) -> String? {
            if let bare = try? table.select("> td[colspan]").first() {
                let text = ((try? bare.text()) ?? "").normalizedCatalogText()
                if !text.isEmpty { return text }
            }
            return nil
        }

        func tableHasAreaHeader(_ table: Element) -> Bool {
            (try? table.select("span.courselistcomment.areaheader, span.areaheader, tr.areaheader").first()) != nil
        }

        func tableHasColspanCategoryLead(_ table: Element) -> Bool {
            if let lead = try? table.select("> tbody > tr:first-child td[colspan], > tr:first-child td[colspan]").first(),
               (try? lead.select("a.bubblelink.code, a[onclick*=showCourse]").first()) == nil {
                let text = ((try? lead.text()) ?? "").normalizedCatalogText()
                return !text.isEmpty && !isTableHeaderRow(lead.parent() ?? lead)
            }
            return false
        }

        func isReferenceOnlyTable(_ table: Element) -> Bool {
            guard !tableHasAreaHeader(table), !tableHasColspanCategoryLead(table) else { return false }
            let rows = (try? table.select("tr"))?.array() ?? []
            let bodyRows = rows.filter { !isTableHeaderRow($0) && !($0.hasClass("listsum")) }
            guard !bodyRows.isEmpty else { return false }
            return bodyRows.allSatisfy { row in
                courseDetailFromStructuredRow(row) != nil
            }
        }

        func courseDetailFromStructuredRow(_ row: Element) -> CourseDetail? {
            if isTableHeaderRow(row) { return nil }
            if row.hasClass("listsum") { return nil }

            if let anchor = try? row.select("a.bubblelink.code, a.code[onclick*=showCourse], a[onclick*=showCourse]").first() {
                let onclick = (try? anchor.attr("onclick")) ?? ""
                var quotedCode: String?
                if let re = UniversalCatalogScraper.cachedRegex("showCourse\\([^,]+,\\s*['\"]([^'\"]+)['\"]"),
                   let m = re.firstMatch(in: onclick, range: NSRange(onclick.startIndex..<onclick.endIndex, in: onclick)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: onclick) {
                    quotedCode = String(onclick[r]).normalizedCatalogText()
                }
                let titleAttr = (try? anchor.attr("title"))?.normalizedCatalogText() ?? ""
                let linkText = (try? anchor.text())?.normalizedCatalogText() ?? ""
                let code = [quotedCode, titleAttr, linkText]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !UniversalCatalogScraper.extractCourseDetails(from: $0).isEmpty })
                if let code,
                   let detail = UniversalCatalogScraper.extractBestCourseDetail(from: code) ?? UniversalCatalogScraper.extractCourseDetails(from: code).first {
                    let titleCell = (try? row.select("td.titlecol").first())
                        ?? (try? row.select("td").array().dropFirst().first)
                    let titleText = (try? titleCell?.text())?.normalizedCatalogText() ?? ""
                    let cleanedTitle = titleText
                        .replacingOccurrences(of: "(?i)^view course details for\\s+", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let rowCredits = creditsFromHourscol(row)
                    return CourseDetail(
                        code: detail.code,
                        title: cleanedTitle.isEmpty ? detail.title : cleanedTitle,
                        credits: detail.credits ?? rowCredits
                    )
                }
            }

            let codeBubbles = (try? row.select("td.codecol .code_bubble[data-code-bubble], .code_bubble[data-code-bubble]").array()) ?? []

            if let bubble = codeBubbles.first,
               let rawCode = try? bubble.attr("data-code-bubble") {
                let code = rawCode.normalizedCatalogText()
                guard !code.isEmpty else { return nil }
                let titleCell = (try? row.select("td.titlecol").first())
                    ?? (try? row.select("td").array().dropFirst().first)
                let titleText = (try? titleCell?.text())?.normalizedCatalogText() ?? ""
                let rowCredits = creditsFromHourscol(row)
                return CourseDetail(
                    code: code,
                    title: titleText.isEmpty ? nil : titleText,
                    credits: rowCredits
                )
            }

            let rowText = ((try? row.text()) ?? "").normalizedCatalogText()
            guard !rowText.isEmpty else { return nil }
            if rowText.localizedCaseInsensitiveContains("total credits") { return nil }
            if let detail = UniversalCatalogScraper.extractBestCourseDetail(from: rowText) {
                let rowCredits = creditsFromHourscol(row)
                if detail.credits == nil, let rowCredits, !rowCredits.isEmpty {
                    return CourseDetail(code: detail.code, title: detail.title, credits: rowCredits)
                }
                return detail
            }
            return nil
        }

        let tablesToParse = allTables.filter { !isReferenceOnlyTable($0) }
        guard !tablesToParse.isEmpty else { return nil }

        var results: [DegreeRequirement] = []
        var programTotalCredits: Int?

        for table in tablesToParse {
            var currentCategory = ""
            var currentSubsection = ""
            var requiredDetailed: [CourseDetail] = []
            var selectFromDetailed: [CourseDetail] = []
            var descriptionLines: [String] = []
            var currentDescription: String?
            var currentSelectCount: Int?
            var pickingSelectFrom = false
            var sawExplicitCourseListInstruction = false
            var pendingChooseOneCredits = 0
            var inChooseOneBlock = false
            var pendingLabeledBucketCredits = 0
            var orGroupCounter = 0

            func displayCategory() -> String {
                let parent = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                let child = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                if parent.isEmpty { return child }
                if child.isEmpty { return parent }
                return "\(parent) — \(child)"
            }

            func chooseRowTitle(subsection: String, chooseTitle: String) -> String {
                let sub = subsection.trimmingCharacters(in: .whitespacesAndNewlines)
                let choose = chooseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sub.isEmpty else {
                    return choose.isEmpty ? "Select one of the following" : choose
                }
                let useSubsection = choose.localizedCaseInsensitiveContains("at least")
                    || choose.range(
                        of: #"following\s+\d+"#,
                        options: [.regularExpression, .caseInsensitive]
                    ) != nil
                if useSubsection { return sub }
                return choose.isEmpty ? sub : choose
            }

            func appendRequirement(
                category: String,
                required: [CourseDetail] = [],
                selectFrom: [CourseDetail] = [],
                creditsRequired: Int = 0,
                description: String? = nil,
                selectCount: Int? = nil,
                kind: RequirementKind? = nil,
                parentCategory: String? = nil,
                displayTitle: String? = nil
            ) {
                let cat = normalizeCategory(category)
                guard !cat.isEmpty else { return }
                let catLower = cat.lowercased()
                if catLower.contains("total credits") || catLower.contains("sample plan") { return }

                let requiredUnique = Array(Set(required)).sorted { $0.code < $1.code }
                let selectUnique = Array(Set(selectFrom)).sorted { $0.code < $1.code }
                let split = RequirementRowNormalizer.splitCategoryPath(cat)
                let resolvedParent = parentCategory ?? split.parent ?? cat
                let resolvedTitle = displayTitle ?? (split.parent == nil ? split.title : split.title)
                let resolvedKind = kind ?? RequirementRowNormalizer.inferKind(
                    required: requiredUnique,
                    selectFrom: selectUnique,
                    selectCount: selectCount,
                    creditsRequired: creditsRequired,
                    description: description
                )

                if !requiredUnique.isEmpty {
                    results.append(
                        RequirementRowNormalizer.makeRequirement(
                            parentCategory: resolvedParent,
                            displayTitle: resolvedTitle.isEmpty ? resolvedParent : resolvedTitle,
                            kind: resolvedKind == .prose ? .courseList : resolvedKind,
                            required: requiredUnique,
                            creditsRequired: creditsRequired,
                            description: description
                        )
                    )
                    logger.scraper("🧩 CourseLeaf category=\(cat) required=\(requiredUnique.count)")
                } else if !selectUnique.isEmpty {
                    results.append(
                        RequirementRowNormalizer.makeRequirement(
                            parentCategory: resolvedParent,
                            displayTitle: resolvedTitle.isEmpty ? "Select one of the following" : resolvedTitle,
                            kind: .chooseOne,
                            selectFrom: selectUnique,
                            creditsRequired: creditsRequired,
                            description: description,
                            selectCount: selectCount ?? 1
                        )
                    )
                    logger.scraper("🧩 CourseLeaf category=\(cat) selectFrom=\(selectUnique.count) pick=\(selectCount ?? 1)")
                } else if creditsRequired > 0 || !(description?.isEmpty ?? true) {
                    results.append(
                        RequirementRowNormalizer.makeRequirement(
                            parentCategory: resolvedParent,
                            displayTitle: resolvedTitle.isEmpty ? resolvedParent : resolvedTitle,
                            kind: resolvedKind,
                            creditsRequired: creditsRequired,
                            description: description,
                            selectCount: selectCount
                        )
                    )
                    logger.scraper("📝 CourseLeaf prose category=\(cat) credits=\(creditsRequired)")
                }
            }

            func rowHasCourseCodeFollowing(from rowIndex: Int, in rows: [Element]) -> Bool {
                var idx = rowIndex + 1
                while idx < rows.count {
                    let candidate = rows[idx]
                    if isTableHeaderRow(candidate) || candidate.hasClass("listsum") {
                        idx += 1
                        continue
                    }
                    if isAreaHeaderRow(candidate) != nil || isAreaSubheaderRow(candidate) != nil {
                        return false
                    }
                    if commentText(in: candidate) != nil, courseDetailFromStructuredRow(candidate) == nil {
                        return false
                    }
                    return courseDetailFromStructuredRow(candidate) != nil
                }
                return false
            }

            func flushCategory(rowIndex: Int = -1, allRows: [Element] = []) {
                let category = displayCategory()
                let description: String? = {
                    if let currentDescription, !currentDescription.isEmpty {
                        if descriptionLines.isEmpty { return currentDescription }
                        return (descriptionLines + [currentDescription]).joined(separator: "\n")
                    }
                    if !descriptionLines.isEmpty {
                        return descriptionLines.joined(separator: "\n")
                    }
                    return currentDescription
                }()

                let listTitle = {
                    let sub = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parent = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sub.isEmpty { return sub }
                    if !parent.isEmpty { return parent }
                    return category
                }()

                let labeledBucketCredits = pendingLabeledBucketCredits

                if inChooseOneBlock,
                   !requiredDetailed.isEmpty, selectFromDetailed.isEmpty {
                    selectFromDetailed.append(contentsOf: requiredDetailed)
                    requiredDetailed.removeAll(keepingCapacity: true)
                }

                if !requiredDetailed.isEmpty {
                    let parent = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    let subsection = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                    let requiredUnique = Array(Set(requiredDetailed)).sorted { $0.code < $1.code }
                    let credits = pendingLabeledBucketCredits > 0
                        ? pendingLabeledBucketCredits
                        : parsedCreditsRequired(from: category)
                    let resolvedParent = !parent.isEmpty ? parent : category
                    let resolvedTitle: String = {
                        if !subsection.isEmpty { return subsection }
                        if requiredUnique.count == 1,
                           let lone = requiredUnique.first {
                            let title = (lone.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !title.isEmpty { return title }
                            return lone.code
                        }
                        return listTitle
                    }()
                    appendRequirement(
                        category: category,
                        required: requiredDetailed,
                        creditsRequired: credits,
                        description: description,
                        kind: .courseList,
                        parentCategory: resolvedParent,
                        displayTitle: resolvedTitle
                    )
                } else if !descriptionLines.isEmpty || !(currentDescription?.isEmpty ?? true) {
                    if inChooseOneBlock == false, requiredDetailed.isEmpty, selectFromDetailed.isEmpty {
                        appendRequirement(
                            category: category,
                            creditsRequired: parsedCreditsRequired(from: category),
                            description: description,
                            kind: .prose
                        )
                    }
                }

                if inChooseOneBlock,
                   selectFromDetailed.isEmpty,
                   requiredDetailed.isEmpty,
                   (currentSelectCount ?? 0) > 0 {
                    let chooseTitle = (currentDescription ?? "Select from following")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let subsection = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parent = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rowTitle = chooseRowTitle(subsection: subsection, chooseTitle: chooseTitle)
                    let resolvedParent = parent.isEmpty ? rowTitle : parent
                    let bucketCredits = max(pendingChooseOneCredits, pendingLabeledBucketCredits, labeledBucketCredits)
                    appendRequirement(
                        category: category.isEmpty ? rowTitle : category,
                        creditsRequired: bucketCredits,
                        description: chooseTitle,
                        selectCount: currentSelectCount,
                        kind: .chooseOne,
                        parentCategory: resolvedParent,
                        displayTitle: rowTitle
                    )
                } else if inChooseOneBlock, !selectFromDetailed.isEmpty {
                    let chooseTitle = (currentDescription ?? "Select one of the following")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let subsection = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parent = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rowTitle = chooseRowTitle(subsection: subsection, chooseTitle: chooseTitle)
                    let resolvedParent = parent.isEmpty ? rowTitle : parent
                    let bucketCredits = max(pendingChooseOneCredits, pendingLabeledBucketCredits, labeledBucketCredits)
                    appendRequirement(
                        category: category.isEmpty
                            ? rowTitle
                            : RequirementRowNormalizer.categoryPath(parent: resolvedParent, title: rowTitle),
                        selectFrom: selectFromDetailed,
                        creditsRequired: bucketCredits,
                        description: chooseTitle,
                        selectCount: currentSelectCount ?? 1,
                        kind: .chooseOne,
                        parentCategory: resolvedParent,
                        displayTitle: rowTitle
                    )
                } else if inChooseOneBlock, (currentSelectCount ?? 0) > 0, !selectFromDetailed.isEmpty {
                    let chooseTitle = (currentDescription ?? "Select from following")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let subsection = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                    let rowTitle = chooseRowTitle(subsection: subsection, chooseTitle: chooseTitle)
                    appendRequirement(
                        category: category.isEmpty ? rowTitle : category,
                        creditsRequired: pendingChooseOneCredits,
                        description: chooseTitle,
                        selectCount: currentSelectCount,
                        kind: .chooseOne,
                        parentCategory: category.isEmpty ? rowTitle : category,
                        displayTitle: rowTitle
                    )
                } else if !selectFromDetailed.isEmpty {
                    let credits = pendingLabeledBucketCredits > 0
                        ? pendingLabeledBucketCredits
                        : parsedCreditsRequired(from: category)
                    let subsection = currentSubsection.trimmingCharacters(in: .whitespacesAndNewlines)
                    let parent = currentCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    let chooseTitle = (currentDescription ?? listTitle)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let rowTitle = chooseRowTitle(subsection: subsection, chooseTitle: chooseTitle)
                    appendRequirement(
                        category: category,
                        selectFrom: selectFromDetailed,
                        creditsRequired: credits,
                        description: currentDescription ?? description,
                        selectCount: currentSelectCount,
                        kind: .chooseOne,
                        parentCategory: parent.isEmpty ? rowTitle : parent,
                        displayTitle: rowTitle
                    )
                }

                requiredDetailed.removeAll(keepingCapacity: true)
                selectFromDetailed.removeAll(keepingCapacity: true)
                descriptionLines.removeAll(keepingCapacity: true)
                currentDescription = nil
                currentSelectCount = nil
                pickingSelectFrom = false
                sawExplicitCourseListInstruction = false
                pendingChooseOneCredits = 0
                inChooseOneBlock = false
                pendingLabeledBucketCredits = 0
                if labeledBucketCredits > 0 {
                    currentSubsection = ""
                }
            }

            let rows = (try? table.select("tr"))?.array() ?? []

            if !tableHasAreaHeader(table), let lead = implicitTableLeadCategory(table) {
                flushCategory()
                currentCategory = lead
                currentDescription = lead
                currentSelectCount = parseChooseCount(from: lead)
                if lead.localizedCaseInsensitiveContains("see list below") {
                    appendRequirement(
                        category: lead,
                        creditsRequired: 0,
                        description: lead,
                        selectCount: currentSelectCount
                    )
                    currentDescription = nil
                    currentSelectCount = nil
                } else if isElectiveProse(lead) {
                    pickingSelectFrom = true
                    sawExplicitCourseListInstruction = true
                }
            }

            if !tableHasAreaHeader(table), implicitTableLeadCategory(table) == nil,
               let firstRow = rows.first(where: { !isTableHeaderRow($0) }),
               let leadText = try? firstRow.text(),
               let lead = commentText(in: firstRow) ?? Optional(leadText.normalizedCatalogText()),
               !lead.isEmpty, courseDetailFromStructuredRow(firstRow) == nil {
                flushCategory()
                currentCategory = lead
                if isElectiveProse(lead) {
                    currentDescription = lead
                    currentSelectCount = parseChooseCount(from: lead)
                    sawExplicitCourseListInstruction = lead.localizedCaseInsensitiveContains("following")
                        || lead.localizedCaseInsensitiveContains("all of the following")
                }
            }

            for (rowIndex, row) in rows.enumerated() {
                if isTableHeaderRow(row) { continue }

                if row.hasClass("listsum") {
                    let summary = ((try? row.text()) ?? "").normalizedCatalogText().lowercased()
                    if summary.contains("total credits") {
                        let value = creditsIntFromHourscol(row)
                        if value > 0 {
                            programTotalCredits = value
                        }
                        flushCategory(rowIndex: rowIndex, allRows: rows)
                        break
                    }
                    continue
                }

                if let header = isAreaHeaderRow(row) {
                    flushCategory(rowIndex: rowIndex, allRows: rows)
                    currentCategory = header
                    currentSubsection = ""
                    continue
                }

                if let subheader = isAreaSubheaderRow(row) {
                    flushCategory(rowIndex: rowIndex, allRows: rows)
                    currentSubsection = subheader
                    continue
                }

                if let comment = commentText(in: row) {
                    if let chooseCount = parseChooseCount(from: comment),
                       comment.localizedCaseInsensitiveContains("following") {
                        flushCategory(rowIndex: rowIndex, allRows: rows)
                        currentDescription = comment
                        currentSelectCount = chooseCount
                        pendingChooseOneCredits = creditsIntFromHourscol(row)
                        pendingLabeledBucketCredits = pendingChooseOneCredits
                        pickingSelectFrom = true
                        sawExplicitCourseListInstruction = true
                        inChooseOneBlock = true
                        continue
                    }

                    if isElectiveProse(comment) {
                        flushCategory(rowIndex: rowIndex, allRows: rows)
                        currentDescription = comment
                        currentSelectCount = parseChooseCount(from: comment)
                        let rowCredits = creditsIntFromHourscol(row)
                        let referencesExternalList = comment.localizedCaseInsensitiveContains("see list below")
                        let hasFollowingCourses = rowHasCourseCodeFollowing(from: rowIndex, in: rows)
                        if rowCredits > 0, hasFollowingCourses {
                            pendingLabeledBucketCredits = rowCredits
                            pendingChooseOneCredits = rowCredits
                            pickingSelectFrom = true
                            sawExplicitCourseListInstruction = true
                            inChooseOneBlock = comment.localizedCaseInsensitiveContains("following")
                            continue
                        }
                        if rowCredits > 0, !referencesExternalList {
                            if hasFollowingCourses {
                                pendingLabeledBucketCredits = rowCredits
                                pendingChooseOneCredits = rowCredits
                                pickingSelectFrom = true
                                sawExplicitCourseListInstruction = true
                                inChooseOneBlock = comment.localizedCaseInsensitiveContains("following")
                                continue
                            }
                            let parent = displayCategory().isEmpty ? currentCategory : displayCategory()
                            appendRequirement(
                                category: RequirementRowNormalizer.categoryPath(parent: parent, title: comment),
                                creditsRequired: rowCredits,
                                description: comment,
                                selectCount: currentSelectCount,
                                kind: .ruleBucket,
                                parentCategory: parent,
                                displayTitle: comment
                            )
                            currentDescription = nil
                            currentSelectCount = nil
                            pickingSelectFrom = false
                            sawExplicitCourseListInstruction = false
                        } else if referencesExternalList {
                            appendRequirement(
                                category: displayCategory().isEmpty ? comment : displayCategory(),
                                creditsRequired: rowCredits,
                                description: comment,
                                selectCount: currentSelectCount,
                                kind: .ruleBucket
                            )
                            currentDescription = nil
                            currentSelectCount = nil
                            pickingSelectFrom = false
                            sawExplicitCourseListInstruction = false
                        } else {
                            pickingSelectFrom = true
                            sawExplicitCourseListInstruction = true
                        }
                        continue
                    }

                    let rowCredits = creditsIntFromHourscol(row)
                    if rowCredits > 0, rowHasCourseCodeFollowing(from: rowIndex, in: rows) {
                        flushCategory(rowIndex: rowIndex, allRows: rows)
                        currentSubsection = comment
                        pendingLabeledBucketCredits = rowCredits
                        continue
                    }
                    if rowCredits > 0, !rowHasCourseCodeFollowing(from: rowIndex, in: rows) {
                        flushCategory(rowIndex: rowIndex, allRows: rows)
                        let parent = displayCategory().isEmpty ? currentCategory : displayCategory()
                        let kind: RequirementKind = parent.localizedCaseInsensitiveContains("electives")
                            ? .ruleBucket
                            : .distributionBucket
                        appendRequirement(
                            category: RequirementRowNormalizer.categoryPath(parent: parent, title: comment),
                            creditsRequired: rowCredits,
                            description: comment,
                            kind: kind,
                            parentCategory: parent,
                            displayTitle: comment
                        )
                        currentSubsection = ""
                        continue
                    }

                    if rowCredits > 0 {
                        descriptionLines.append("\(comment) (\(rowCredits) cr)")
                    } else {
                        descriptionLines.append(comment)
                    }
                    continue
                }

                let codeBubbles = (try? row.select("td.codecol .code_bubble[data-code-bubble], .code_bubble[data-code-bubble]").array()) ?? []
                if codeBubbles.count >= 2 {
                    var orDetails: [CourseDetail] = []
                    for bubble in codeBubbles {
                        guard let rawCode = try? bubble.attr("data-code-bubble") else { continue }
                        let code = rawCode.normalizedCatalogText()
                        guard !code.isEmpty else { continue }
                        orDetails.append(CourseDetail(code: code, title: nil, credits: creditsFromHourscol(row)))
                    }
                    if !orDetails.isEmpty {
                        selectFromDetailed.append(contentsOf: orDetails)
                        if currentSelectCount == nil { currentSelectCount = 1 }
                        pickingSelectFrom = true
                        continue
                    }
                }

                if row.hasClass("orclass") {
                    if let detail = courseDetailFromStructuredRow(row) {
                        orGroupCounter += 1
                        let groupKey = "or-\(orGroupCounter)"
                        if pickingSelectFrom && sawExplicitCourseListInstruction {
                            if let prev = selectFromDetailed.popLast() {
                                selectFromDetailed.append(
                                    CourseDetail(
                                        code: prev.code,
                                        title: prev.title,
                                        credits: prev.credits,
                                        alternativeGroupKey: groupKey
                                    )
                                )
                            }
                            selectFromDetailed.append(
                                CourseDetail(
                                    code: detail.code,
                                    title: detail.title,
                                    credits: detail.credits,
                                    alternativeGroupKey: groupKey
                                )
                            )
                        } else if let prev = requiredDetailed.popLast() {
                            requiredDetailed.append(
                                CourseDetail(
                                    code: prev.code,
                                    title: prev.title,
                                    credits: prev.credits,
                                    alternativeGroupKey: groupKey
                                )
                            )
                            requiredDetailed.append(
                                CourseDetail(
                                    code: detail.code,
                                    title: detail.title,
                                    credits: detail.credits,
                                    alternativeGroupKey: groupKey
                                )
                            )
                            if currentSelectCount == nil { currentSelectCount = 1 }
                        } else {
                            requiredDetailed.append(detail)
                        }
                    }
                    continue
                }

                if let detail = courseDetailFromStructuredRow(row) {
                    if pickingSelectFrom && sawExplicitCourseListInstruction {
                        selectFromDetailed.append(detail)
                    } else {
                        requiredDetailed.append(detail)
                    }
                }
            }

            flushCategory(allRows: rows)
        }

        if let programTotalCredits, programTotalCredits > 0 {
            results.append(
                DegreeRequirement(
                    degreeType: "Unknown",
                    major: "Unknown",
                    category: "__PROGRAM_TOTAL_CREDITS__",
                    requiredCourses: [],
                    requiredCoursesDetailed: [],
                    creditsRequired: programTotalCredits,
                    description: "Authoritative program total from catalog table footer.",
                    selectFrom: nil,
                    selectFromDetailed: nil,
                    selectCount: nil
                )
            )
        }

        return results.isEmpty ? nil : results
    }

    private static func parsedCreditsRequired(from category: String) -> Int {
        let s = category.normalizedCatalogText()
        guard let re = UniversalCatalogScraper.cachedRegex("(?i)\\b(\\d+)\\s*credits?\\b") else { return 0 }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, range: nsRange), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: s)
        else { return 0 }
        return Int(s[r]) ?? 0
    }
}
