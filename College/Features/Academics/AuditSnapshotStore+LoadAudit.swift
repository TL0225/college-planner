// AuditSnapshotStore+LoadAudit.swift
// Feature: Academics
// Purpose: Academics module — SelectDetail.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import SwiftData

private enum AuditLoadAuditDecoders {
    static let selectDetail = JSONDecoder()
    static let stringArray = JSONDecoder()
}

extension AuditSnapshotStore {
    /// Builds declared-program audit degrees (MainActor; invoked from `reloadAudit`).
    @MainActor
    func buildAuditDegrees(
        collegePersistence: CollegePersistence,
        majors: [String],
        minors: [String],
        academicProfile: AcademicProfile?,
        previousAuditDegrees: [AcademicsAuditPanel.AuditDegree]
    ) async -> (degrees: [AcademicsAuditPanel.AuditDegree], expandedCategoryIDs: Set<UUID>) {
        await LoadOperationTrace.withSpan(
            name: "LoadAudit",
            category: .audit,
            budgetMs: LaunchPerformanceAcceptance.academicsAuditWarnThresholdMs,
            executionContext: .mainThread,
            metadata: [
                "majors": "\(majors.count)",
                "minors": "\(minors.count)"
            ]
        ) {
            await buildAuditDegreesWork(
                collegePersistence: collegePersistence,
                majors: majors,
                minors: minors,
                academicProfile: academicProfile,
                previousAuditDegrees: previousAuditDegrees
            )
        }
    }

    @MainActor
    private func buildAuditDegreesWork(
        collegePersistence: CollegePersistence,
        majors: [String],
        minors: [String],
        academicProfile: AcademicProfile?,
        previousAuditDegrees: [AcademicsAuditPanel.AuditDegree]
    ) async -> (degrees: [AcademicsAuditPanel.AuditDegree], expandedCategoryIDs: Set<UUID>) {
        var expandedCategoryIDs = Set<UUID>()
        let auditSignpost = PerformanceSignposts.beginLoadAudit()
        defer { PerformanceSignposts.endLoadAudit(auditSignpost) }


        // Planner progress by normalized course code — same rules as `AcademicsCourseRow` / `AcademicsCourseSchedule`.
        let today = Date()
        // Normalise a code by stripping trailing section suffixes (LEC/LAB/…) and spaces
        // so that enrolled code "CSE191" matches requirement code "CSE 191" or "CSE 191LEC".
        func normaliseCode(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        /// Drop duplicate course codes (by `normaliseCode`) while preserving first-seen order.
        func dedupeCodesPreservingOrder(_ codes: [String]) -> [String] {
            var seen = Set<String>()
            var out: [String] = []
            out.reserveCapacity(codes.count)
            for c in codes {
                let t = c.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                let key = normaliseCode(t)
                if seen.contains(key) { continue }
                seen.insert(key)
                out.append(t)
            }
            return out
        }
        let planCourses = collegePersistence.semesters.flatMap(\.coursesArray)
        var planProgressByNormCode: [String: RequirementPlanProgress] = [:]
        // Latest semester a course is scheduled in, so the breakdown can tag the row with the
        // term (e.g. "Fall 2026"). Keyed by normalized code; ties broken by (year, seasonOrder).
        var scheduledTermByNormCode: [String: (label: String, sortKey: (Int, Int))] = [:]
        for c in planCourses {
            let raw = c.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let k = normaliseCode(raw)
            let piece = AcademicsCourseSchedule.singleCoursePlanProgress(c, asOf: today)
            planProgressByNormCode[k] = AcademicsCourseSchedule.mergeProgress(planProgressByNormCode[k], piece)

            if let semester = c.semester {
                let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
                let year = Int(semester.year)
                let label = season.isEmpty ? "Semester \(year)" : "\(season) \(year)"
                let sortKey = (year, Int(semester.seasonOrder))
                if let existing = scheduledTermByNormCode[k] {
                    if sortKey > existing.sortKey {
                        scheduledTermByNormCode[k] = (label, sortKey)
                    }
                } else {
                    scheduledTermByNormCode[k] = (label, sortKey)
                }
            }
        }

        func planProgress(forRequirementCode code: String) -> RequirementPlanProgress {
            planProgressByNormCode[normaliseCode(code)] ?? .notOnPlan
        }

        func scheduledTerm(forRequirementCode code: String) -> String? {
            scheduledTermByNormCode[normaliseCode(code)]?.label
        }

        // Resolve requirements via programURL so that:
        //  • Complex major names like "Business Administration BS - MIS Concentration, BS" resolve correctly.
        //  • Minor requirements are fetched with degreeType "Minor", not the student's major degree type.
        //
        // `programURL` may be empty: when `resolveSelectedMajorProgramURL()` can't find a
        // matching `MajorEntity` (e.g., the catalog enumerated the program with a stored name
        // that differs from the user's profile display, or the user has two `MajorEntity`
        // rows for the same name and the disambiguator picked the wrong one), URL-based
        // lookup is impossible — but name-based fallback still works against the saved rows.
        let profileDegreeLevel = (
            academicProfile?.degreeLevel
                ?? collegePersistence.primaryDegreeLevel(default: "")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let profileDegreeType = (
            academicProfile?.degreeType
                ?? collegePersistence.primaryDegreeType()
                ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        func buildDegree(label: String, rawName: String, kind: AcademicsAuditPanel.AuditDegreeKind, color: Color, programURL: String, degreeType: String) async -> AcademicsAuditPanel.AuditDegree? {
            // Bulletproof requirement resolution for every degree type (Bachelor's, Master's,
            // PhD, Certificate, Minor, …). The chain walks from strictest (URL + degreeType)
            // to loosest (name only) and filters on `degreeType ==[c] "Minor"` (include/exclude)
            // so that a major and a minor sharing a canonical name (e.g., Mathematics) never
            // leak into each other's audit.
            //
            // Why each step exists:
            // 1. URL + degreeType: the happy path — matches when the saved row was scraped
            //    under the same MajorEntity the audit resolves.
            // 2. URL only (handled inside `getDegreeRequirements` as its tier-3 fallback):
            //    catches degreeType-token drift like "M.S." vs "Master of Science".
            // 3. Name-based with degreeType filter: covers URL drift between the picker's
            //    chosen `MajorEntity` and the audit's resolved one (the original bug).
            // 4. Whitespace-/case-tolerant raw-major lookup: catches legacy rows still on
            //    disk that were written with `entity.major` = raw display string before
            //    this commit normalized the save path.
            var reqs: [DegreeRequirementEntity] = []
            if !programURL.isEmpty {
                reqs = collegePersistence.getDegreeRequirements(programURL: programURL, degreeType: degreeType)
            }
            #if DEBUG
            if reqs.isEmpty {
                print("[Audit] URL lookup empty for '\(rawName)' kind=\(kind) url='\(programURL)' degreeType='\(degreeType)' — falling back to name-based lookup")
            }
            #endif

            let isMinor = (kind == .minor)
            let nameRequireDT: String? = isMinor ? "Minor" : nil
            let nameExcludeDT: [String] = isMinor ? [] : ["Minor"]

            if reqs.isEmpty, !isMinor {
                let byProfileDT = collegePersistence.getDegreeRequirementsForMajorDisplay(
                    rawName,
                    degreeType: degreeType.isEmpty ? profileDegreeType : degreeType,
                    degreeLevel: profileDegreeLevel.isEmpty ? nil : profileDegreeLevel
                )
                let filtered = byProfileDT.filter { row in
                    let dt = row.degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
                    return dt.caseInsensitiveCompare("Minor") != .orderedSame
                }
                if !filtered.isEmpty { reqs = filtered }
            }

            if !programURL.isEmpty, !reqs.isEmpty {
                let canonical = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let urlMatched = reqs.filter {
                    let stored = ($0.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return !stored.isEmpty && stored == canonical
                }
                if !urlMatched.isEmpty { reqs = urlMatched }
            }

            if reqs.isEmpty || isMinor {
                let byName = collegePersistence.getDegreeRequirementsByName(
                    rawName,
                    requireDegreeType: nameRequireDT,
                    excludeDegreeTypes: nameExcludeDT
                )
                if byName.count > reqs.count {
                    reqs = byName
                } else if reqs.isEmpty, !byName.isEmpty {
                    reqs = byName
                }
            }

            #if DEBUG
            print("[Audit] '\(rawName)' resolved \(reqs.count) requirement rows (kind=\(kind))")
            #endif
            guard !reqs.isEmpty else { return nil }

            // One AcademicsAuditPanel.AuditCategory per persisted requirement row (no merge by category title).
            struct SelectDetail: Decodable { let code: String }

            let sortedReqs = reqs.sorted { $0.sectionOrder < $1.sectionOrder }
            let universityName = (
                academicProfile?.collegeName
                    ?? collegePersistence.getActiveUniversity()?.name
                    ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalProgramURL = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let fulfillments = RequirementFulfillmentStore.allAssignments(
                context: collegePersistence.profileContext,
                university: universityName,
                programURL: canonicalProgramURL.isEmpty
                    ? (sortedReqs.first?.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    : canonicalProgramURL
            )

            var creditsByCode: [String: String] = [:]
            var titleByCode: [String: String] = [:]
            var alternativeGroupByCode: [String: String] = [:]
            func absorbDetail(_ detail: CourseDetail) {
                let code = detail.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !code.isEmpty else { return }
                let rawCredits = (detail.credits ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawCredits.isEmpty, (creditsByCode[code]?.isEmpty ?? true) {
                    creditsByCode[code] = rawCredits
                }
                let rawTitle = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawTitle.isEmpty, (titleByCode[code]?.isEmpty ?? true) {
                    titleByCode[code] = rawTitle
                }
                if let group = detail.alternativeGroupKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !group.isEmpty {
                    alternativeGroupByCode[code] = group
                }
            }

            var completionByCode: [String: RequirementCompletionInfo] = [:]
            for course in planCourses {
                let code = (course.code).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !code.isEmpty else { continue }
                let completed = AcademicsCourseSchedule.singleCoursePlanProgress(course, asOf: today) == .completed
                let credits = Int(course.credits)
                completionByCode[code] = RequirementCompletionInfo(isCompleted: completed, credits: credits)
            }

            var categories: [AcademicsAuditPanel.AuditCategory] = []
            categories.reserveCapacity(sortedReqs.count)
            var categoryDescriptions: [String: String] = [:]

            for (reqIndex, req) in sortedReqs.enumerated() {
                if reqIndex > 0, reqIndex.isMultiple(of: 8) {
                    await Task.yield()
                }
                let cat = req.requirementCategory
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cat.lowercased() == "__program_total_credits__" { continue }

                let rowDescription = (req.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                categoryDescriptions[cat] = rowDescription

                if let detailed = collegePersistence.decodeDetailedCourseList(req.requiredCoursesDetailedJSON) {
                    detailed.forEach(absorbDetail)
                }
                if let selectDetailed = collegePersistence.decodeDetailedCourseList(req.selectFromDetailedJSON) {
                    selectDetailed.forEach(absorbDetail)
                }

                let kind = RequirementKind(rawValue: req.requirementKind ?? "")
                    ?? RequirementProgressEngine.inferredKind(from: req)
                let selectN = Int(req.selectCount)
                let storedCredits = max(0, Int(req.creditsRequired))
                let proseCredits = RequirementBreakdownCredits.creditsMentionedInProse(rowDescription)
                let effectiveDescriptionCredits = max(proseCredits, kind == .chooseOne ? storedCredits : proseCredits)

                let codes: [String] = {
                    var out: [String] = []
                    if let raw = req.requiredCourses, !raw.isEmpty {
                        out.append(contentsOf: raw.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                            .filter { !$0.isEmpty })
                    }
                    if let detailed = collegePersistence.decodeDetailedCourseList(req.requiredCoursesDetailedJSON) {
                        out.append(contentsOf: detailed.map {
                            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        }.filter { !$0.isEmpty })
                    }
                    return dedupeCodesPreservingOrder(out)
                }()
                let electiveCodes: [String] = {
                    if let detailed = req.selectFromDetailedJSON, !detailed.isEmpty,
                       let data = detailed.data(using: .utf8),
                       let arr = try? AuditLoadAuditDecoders.selectDetail.decode([SelectDetail].self, from: data) {
                        return dedupeCodesPreservingOrder(
                            arr.map { $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                                .filter { !$0.isEmpty }
                        )
                    }
                    if let raw = req.selectFromJSON, !raw.isEmpty,
                       let data = raw.data(using: .utf8),
                       let arr = try? AuditLoadAuditDecoders.stringArray.decode([String].self, from: data) {
                        return dedupeCodesPreservingOrder(
                            arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty }
                        )
                    }
                    return []
                }()

                let assignedCodes = fulfillments
                    .filter { $0.requirementCategory.caseInsensitiveCompare(cat) == .orderedSame }
                    .compactMap { $0.courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                    .filter { !$0.isEmpty }

                guard !codes.isEmpty || !electiveCodes.isEmpty || !assignedCodes.isEmpty
                    || storedCredits > 0 || proseCredits > 0 else { continue }

                var catalogCreditsByUpperCode: [String: String] = [:]
                var catalogTitleByUpperCode: [String: String] = [:]
                var gradeByNormCode: [String: String] = [:]
                let allLookupCodes = Set(codes + electiveCodes + assignedCodes)
                let catalogBatch: [String: AuditCatalogCourseSnapshot]
                if let universityID = collegePersistence.getActiveUniversity()?.id {
                    catalogBatch = await AuditCatalogLookupBridge.batchMatchingOffMain(
                        universityID: universityID,
                        codes: Array(allLookupCodes)
                    )
                } else {
                    catalogBatch = [:]
                }
                for code in allLookupCodes {
                    let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if let fromScrape = creditsByCode[upper]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !fromScrape.isEmpty {
                        catalogCreditsByUpperCode[upper] = fromScrape
                    } else if let snap = catalogBatch[upper] {
                        let t = snap.creditsDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { catalogCreditsByUpperCode[upper] = t }
                    }
                    if let fromScrape = titleByCode[upper]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !fromScrape.isEmpty {
                        catalogTitleByUpperCode[upper] = fromScrape
                    } else if let snap = catalogBatch[upper] {
                        let raw = snap.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !raw.isEmpty {
                            let normalized = raw.replacingOccurrences(of: " ", with: "").uppercased()
                            if normalized != upper { catalogTitleByUpperCode[upper] = raw }
                        }
                    }
                    let norm = normaliseCode(code)
                    if gradeByNormCode[norm] != nil { continue }
                    if let match = planCourses.first(where: { normaliseCode($0.code) == norm }),
                       let g = match.grade?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !g.isEmpty {
                        gradeByNormCode[norm] = g
                        continue
                    }
                    let rawCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rawCode.isEmpty,
                       let override = collegePersistence.getCourseOverride(courseCode: rawCode),
                       let g = override.grade?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !g.isEmpty {
                        gradeByNormCode[norm] = g
                    }
                }

                func resolveCredits(forCode code: String) -> String {
                    let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if let cached = catalogCreditsByUpperCode[upper], !cached.isEmpty { return cached }
                    if let snap = catalogBatch[upper] {
                        let t = snap.creditsDisplayText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty {
                            catalogCreditsByUpperCode[upper] = t
                            return t
                        }
                    }
                    return ""
                }
                func resolveTitle(forCode code: String) -> String {
                    catalogTitleByUpperCode[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] ?? ""
                }
                func resolveGrade(forCode code: String) -> String? {
                    gradeByNormCode[normaliseCode(code)]
                }

                func alternativeGroup(forCode code: String) -> String? {
                    alternativeGroupByCode[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
                }

                let requiredItems = codes.map { code -> AcademicsAuditPanel.AuditItem in
                    AcademicsAuditPanel.AuditItem(
                        code: code,
                        credits: resolveCredits(forCode: code),
                        title: resolveTitle(forCode: code),
                        grade: resolveGrade(forCode: code),
                        planProgress: planProgress(forRequirementCode: code),
                        isElective: false,
                        alternativeGroupKey: alternativeGroup(forCode: code),
                        scheduledTermLabel: scheduledTerm(forRequirementCode: code)
                    )
                }
                let electiveItems = electiveCodes.map { code -> AcademicsAuditPanel.AuditItem in
                    AcademicsAuditPanel.AuditItem(
                        code: code,
                        credits: resolveCredits(forCode: code),
                        title: resolveTitle(forCode: code),
                        grade: resolveGrade(forCode: code),
                        planProgress: planProgress(forRequirementCode: code),
                        isElective: true,
                        alternativeGroupKey: alternativeGroup(forCode: code),
                        scheduledTermLabel: scheduledTerm(forRequirementCode: code)
                    )
                }
                let assignedItems = assignedCodes.map { code -> AcademicsAuditPanel.AuditItem in
                    AcademicsAuditPanel.AuditItem(
                        code: code,
                        credits: resolveCredits(forCode: code),
                        title: resolveTitle(forCode: code),
                        grade: resolveGrade(forCode: code),
                        planProgress: planProgress(forRequirementCode: code),
                        isElective: true,
                        alternativeGroupKey: alternativeGroup(forCode: code),
                        scheduledTermLabel: scheduledTerm(forRequirementCode: code)
                    )
                }

                var mergedItems: [AcademicsAuditPanel.AuditItem] = []
                for item in requiredItems + electiveItems + assignedItems {
                    let k = normaliseCode(item.code)
                    if let idx = mergedItems.firstIndex(where: { normaliseCode($0.code) == k }) {
                        let existing = mergedItems[idx]
                        mergedItems[idx] = AcademicsAuditPanel.AuditItem(
                            code: existing.code,
                            credits: existing.credits.isEmpty ? item.credits : existing.credits,
                            title: existing.title.isEmpty ? item.title : existing.title,
                            grade: existing.grade ?? item.grade,
                            planProgress: AcademicsCourseSchedule.mergeProgress(existing.planProgress, item.planProgress),
                            isElective: existing.isElective || item.isElective,
                            alternativeGroupKey: existing.alternativeGroupKey ?? item.alternativeGroupKey,
                            scheduledTermLabel: existing.scheduledTermLabel ?? item.scheduledTermLabel
                        )
                    } else {
                        mergedItems.append(item)
                    }
                }

                let rowFulfillments = fulfillments.filter {
                    $0.requirementCategory.caseInsensitiveCompare(cat) == .orderedSame
                }
                let snapshot = RequirementProgressEngine.buildSnapshot(
                    from: req,
                    fulfillments: rowFulfillments,
                    completionByCode: completionByCode
                )
                let appTarget = RequirementProgressEngine.target(for: snapshot)
                let parentTitle = (req.parentCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitleRaw = (req.displayTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let hierarchy = RequirementRowNormalizer.displayHierarchy(
                    categoryPath: cat,
                    displayTitle: displayTitleRaw.isEmpty ? nil : displayTitleRaw,
                    rowKind: kind
                )
                let indent = parentTitle.isEmpty ? 0 : 1
                let allowsManual = kind == .distributionBucket || kind == .ruleBucket || kind == .chooseOne
                let rowDisplayTitle: String? = {
                    let t = hierarchy.rowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }()

                categories.append(
                    AcademicsAuditPanel.AuditCategory(
                        title: cat,
                        items: mergedItems,
                        selectCount: selectN,
                        creditsRequired: appTarget,
                        catalogCreditsRequired: storedCredits,
                        descriptionCredits: effectiveDescriptionCredits,
                        headerCredits: kind == .chooseOne ? storedCredits : 0,
                        rowKind: kind,
                        parentSectionTitle: parentTitle.isEmpty ? nil : parentTitle,
                        displayTitle: rowDisplayTitle,
                        sectionHeader: hierarchy.sectionHeader,
                        indentLevel: indent,
                        allowsManualFulfillment: allowsManual,
                        specializationGroupKey: nil,
                        specializationGroupTitle: nil
                    )
                )
            }

            let hasDistributionBuckets = categories.contains { $0.rowKind == .distributionBucket }
            categories = categories.filter { cat in
                let parts = cat.title
                    .components(separatedBy: RequirementRowNormalizer.categorySeparator)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if parts.count == 2, parts[0].caseInsensitiveCompare(parts[1]) == .orderedSame {
                    return false
                }
                if cat.rowKind == .prose, hasDistributionBuckets {
                    let section = cat.sectionHeader ?? parts.first ?? ""
                    let row = cat.displayTitle ?? parts.last ?? ""
                    if !section.isEmpty, section.caseInsensitiveCompare(row) == .orderedSame {
                        return false
                    }
                }
                return true
            }

            guard !categories.isEmpty else { return nil }
            // Walk the categories after building them and stamp `specializationGroupKey` on
            // any that the heuristic flags as XOR options. The descriptions captured above
            // feed into this detection so a "Choose one of the following specializations"
            // banner on the catalog page reliably groups the right rows.
            let tagged = SpecializationGroupDetector.tagSpecializations(
                categories: categories,
                groupDescriptions: categoryDescriptions
            )
            return AcademicsAuditPanel.AuditDegree(
                label: label,
                rawName: rawName,
                kind: kind,
                color: color,
                categories: tagged,
                programURL: programURL,
                degreeType: degreeType,
                isGraduationRequirement: false
            )
        }

        var degrees: [AcademicsAuditPanel.AuditDegree] = []

        let majorList = majors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let majorColors: [Color] = [Color.accentColor, .green, .orange, .cyan, .pink]

        for (idx, name) in majorList.enumerated() {
            if idx > 0 { await Task.yield() }
            let resolvedURL: String? = collegePersistence.resolveMajorProgramURL(
                display: name,
                degreeLevel: profileDegreeLevel.isEmpty ? nil : profileDegreeLevel,
                degreeType: profileDegreeType.isEmpty ? nil : profileDegreeType
            )
            let url = resolvedURL ?? ""
            let color = majorColors[idx % majorColors.count]
            let majorDegreeType: String = {
                if let inferred = DeclaredProgramDegreeMetadata.infer(fromProgramDisplay: name) {
                    return inferred.fullDegreeType
                }
                return profileDegreeType
            }()
            if var d = await buildDegree(
                label: name,
                rawName: name,
                kind: .major,
                color: color,
                programURL: url,
                degreeType: majorDegreeType
            ) {
                d.isGraduationRequirement = idx == 0
                degrees.append(d)
            }
        }

        let minorList = minors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let minorColors: [Color] = [.teal, .purple, .indigo]
        for (idx, minName) in minorList.enumerated() {
            if idx > 0 { await Task.yield() }
            // Same rationale as the major loop above: don't gate on URL resolution.
            let minURL = collegePersistence.resolveProgramProgramURL(programDisplay: minName, isMinor: true) ?? ""
            let color = minorColors[idx % minorColors.count]
            if let d = await buildDegree(
                label: "Minor: \(minName)",
                rawName: minName,
                kind: .minor,
                color: color,
                programURL: minURL,
                degreeType: "Minor"
            ) {
                degrees.append(d)
            }
        }

        // Auto-expand the first *incomplete* category per degree on first load (met requirements stay collapsed).
        if previousAuditDegrees.isEmpty, !degrees.isEmpty {
            for degree in degrees {
                guard let first = degree.categories.first else { continue }
                if !RequirementBreakdownParser.isCategoryDone(category: first) {
                    expandedCategoryIDs.insert(first.id)
                }
            }
        }

        // GenEd section — suppressed when scraped distribution buckets exist on any declared degree.
        let hasDistributionBuckets = degrees.contains { degree in
            degree.categories.contains { $0.rowKind == .distributionBucket }
        }
        let genEdCourses = planCourses.filter { $0.countsTowardGenEd }
        if !hasDistributionBuckets, !genEdCourses.isEmpty {
            let genEdItems = genEdCourses.map { c -> AcademicsAuditPanel.AuditItem in
                let resolvedTitle: String = {
                    let raw = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !raw.isEmpty,
                       raw.replacingOccurrences(of: " ", with: "").uppercased()
                          != c.code.replacingOccurrences(of: " ", with: "").uppercased() {
                        return raw
                    }
                    if let catalog = collegePersistence.getCatalogCourseMatching(code: c.code) {
                        let catalogTitle = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !catalogTitle.isEmpty { return catalogTitle }
                    }
                    return ""
                }()
                let resolvedGrade = c.grade?.trimmingCharacters(in: .whitespacesAndNewlines)
                let termLabel: String? = {
                    guard let semester = c.semester else { return nil }
                    let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
                    return season.isEmpty ? "Semester \(Int(semester.year))" : "\(season) \(Int(semester.year))"
                }()
                return AcademicsAuditPanel.AuditItem(
                    code: c.code.isEmpty ? "—" : c.code,
                    credits: "\(c.credits)",
                    title: resolvedTitle,
                    grade: (resolvedGrade?.isEmpty == false) ? resolvedGrade : nil,
                    planProgress: AcademicsCourseSchedule.singleCoursePlanProgress(c, asOf: today),
                    isElective: false,
                    scheduledTermLabel: termLabel
                )
            }
            let genEdCategory = AcademicsAuditPanel.AuditCategory(
                title: "General Education Courses",
                items: genEdItems,
                selectCount: 0,
                creditsRequired: RequirementBreakdownCredits.sumCreditsAll(items: genEdItems),
                descriptionCredits: 0
            )
            let genEdDegree = AcademicsAuditPanel.AuditDegree(
                label: "General Education",
                rawName: "General Education",
                kind: .major,
                color: .orange,
                categories: [genEdCategory],
                programURL: "",
                degreeType: ""
            )
            degrees.append(genEdDegree)
        }

        return (degrees, expandedCategoryIDs)
    }
}
