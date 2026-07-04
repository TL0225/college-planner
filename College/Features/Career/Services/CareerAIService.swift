// CareerAIService.swift
// Feature: Career
// Purpose: Career module — ParseResponse.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CollegeCareer

@MainActor
final class CareerAIService {
    static let shared = CareerAIService()

    func parseJobPosting(_ payload: CareerIngestPayload) async -> CareerParseResult? {
        await BackgroundServiceOnDemand.runReturning(id: "career_ai_parse") {
            await CareerAIService.shared.parseJobPostingImpl(payload)
        }
    }

    private func parseJobPostingImpl(_ payload: CareerIngestPayload) async -> CareerParseResult? {
        let prompt = """
        You extract structured fields from a job posting.
        Return strict JSON with keys:
        company, title, baseSalary, location, keywords, confidence, jobDescription

        Source URL: \(payload.sourceURL)
        Posting Text:
        \(payload.rawText.prefix(12_000))
        """

        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt) else {
            return nil
        }
        struct ParseResponse: Codable {
            var company: String?
            var title: String?
            var baseSalary: String?
            var location: String?
            var keywords: [String]?
            var confidence: Double?
            var jobDescription: String?
        }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ParseResponse.self, from: data)
        else {
            return nil
        }
        return CareerParseResult(
            requestId: payload.requestId,
            company: decoded.company ?? "",
            title: decoded.title ?? "",
            baseSalary: decoded.baseSalary ?? "",
            location: decoded.location ?? "",
            keywords: decoded.keywords ?? [],
            confidence: decoded.confidence ?? 0.5,
            jobDescription: decoded.jobDescription ?? payload.rawText
        )
    }

    func compareResume(
        resumeDocumentID: UUID,
        jobDescriptionText: String,
        jobTitle: String = "",
        platform: JobBoardPlatform = .workday,
        context: CareerResumeCompareContext? = nil,
        using collegePersistence: CollegePersistence
    ) async -> CareerResumeCompareResult? {
        await BackgroundServiceOnDemand.runReturning(id: "career_ai_parse") {
            await CareerAIService.shared.compareResumeImpl(
                resumeDocumentID: resumeDocumentID,
                jobDescriptionText: jobDescriptionText,
                jobTitle: jobTitle,
                platform: platform,
                context: context,
                using: collegePersistence
            )
        }
    }

    private func compareResumeImpl(
        resumeDocumentID: UUID,
        jobDescriptionText: String,
        jobTitle: String = "",
        platform: JobBoardPlatform = .workday,
        context: CareerResumeCompareContext? = nil,
        using collegePersistence: CollegePersistence
    ) async -> CareerResumeCompareResult? {
        guard let document = try? collegePersistence.vaultRepository.fetchDocument(id: resumeDocumentID) else {
            return nil
        }
        let resumeText = await collegePersistence.careerRepository.careerResumePlainText(
            for: document,
            vaultRepository: collegePersistence.vaultRepository
        )
        let jd = jobDescriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !jd.isEmpty else {
            return heuristicCompare(jobDescription: jd, jobTitle: jobTitle, resumeText: resumeText)
        }

        let scoringProfile = context?.scoringProfile ?? CareerATSScoringProfile.profile(for: platform)
        let structuredProfile = context?.structuredProfile
            ?? collegePersistence.careerResumeMetadata(for: document).structuredProfile
        let experienceAnalysis = context?.experienceAnalysis
            ?? CareerExperienceAnalyzer.analyze(jdText: jd, structuredProfile: structuredProfile)
        let skillsGap = context?.skillsGap
            ?? CareerTransferableSkillsExpander.analyze(
                requiredSkills: Array(jd.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 4 }.prefix(16)),
                profile: structuredProfile,
                resumeText: resumeText
            )
        let achievementAnalysis = context?.achievementAnalysis
            ?? CareerAchievementScorer.analyze(profile: structuredProfile)

        let recentBullets = (structuredProfile?.experience ?? [])
            .prefix(2)
            .map { entry in
                let heading = entry.headingLines.joined(separator: " · ")
                let bullets = entry.bullets.prefix(4).map { "  • \($0)" }.joined(separator: "\n")
                return "\(heading)\n\(bullets)"
            }
            .joined(separator: "\n\n")

        let skillsTaxonomySummary = skillsGap.entries
            .map { "\($0.skill): \($0.status)\($0.evidenceBullet.map { " — \($0)" } ?? "")" }
            .joined(separator: "\n")

        let transferableNoted = skillsGap.entries
            .filter { $0.status == "transferable" }
            .map(\.skill)

        let prompt = """
        You are a senior HR recruiter evaluating resume fit for an ATS on \(scoringProfile.name).
        Scoring strategy: \(scoringProfile.platformExplanation)
        Tailoring guidance: \(scoringProfile.tailoringAdvice)

        Evaluate transferable skills generously when adjacent experience is documented — note them in transferableSkillsNoted.
        If years-of-experience is short of the JD requirement, write a honest, actionable experienceGapExplanation (1-2 sentences).

        Pre-computed signals (use as context, you may adjust scores slightly):
        - Candidate experience: \(experienceAnalysis.candidateYearsMonthsLabel)
        - Required years: \(experienceAnalysis.requiredYearsMin.map { "\($0)+" } ?? "not specified")
        - Experience score: \(experienceAnalysis.score)/100
        - Achievement score: \(achievementAnalysis.achievementScore)/100
        - Transferable skills score: \(skillsGap.transferableScore)/100
        - Skills taxonomy:
        \(skillsTaxonomySummary.prefix(2_000))

        Return strict JSON:
        {
          "matchingSkills": [String],
          "missingKeywords": [String],
          "tip": String,
          "overallScore": Int,
          "keywordScore": Int,
          "semanticScore": Int,
          "experienceScore": Int,
          "formattingScore": Int,
          "experienceGapExplanation": String,
          "transferableSkillsNoted": [String]
        }

        Job title: \(jobTitle)

        Recent experience bullets:
        \(recentBullets.isEmpty ? String(resumeText.prefix(4_000)) : recentBullets)

        Job description:
        \(jd.prefix(8_000))
        """

        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data)
        else {
            return heuristicCompare(
                jobDescription: jd,
                jobTitle: jobTitle,
                resumeText: resumeText,
                experienceAnalysis: experienceAnalysis,
                transferableSkills: transferableNoted
            )
        }
        var enriched = parsed
        let gaps = CareerCourseSkillBridge.gaps(for: parsed.missingKeywords, collegePersistence: collegePersistence)
        enriched.courseSkillGaps = gaps.isEmpty ? nil : gaps
        enriched.tip = CareerATSAdviceValidator.validatedTip(parsed.tip) ?? parsed.tip
        if enriched.experienceGapExplanation == nil, let note = experienceAnalysis.gapNote {
            enriched.experienceGapExplanation = note
        }
        if enriched.transferableSkillsNoted?.isEmpty != false, !transferableNoted.isEmpty {
            enriched.transferableSkillsNoted = transferableNoted
        }
        let parserIssues: [ParserComplianceIssue] = {
            guard let json = collegePersistence.careerResumeMetadata(for: document).parserIssuesJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([ParserComplianceIssue].self, from: data)
            else { return [] }
            return decoded
        }()
        let portalTips = CareerATSPortalGuide.tips(for: platform, parserIssues: parserIssues)
        enriched.portalTips = portalTips.isEmpty ? nil : portalTips
        return enriched
    }

    func compareResume(for applicationID: UUID, using collegePersistence: CollegePersistence) async -> CareerResumeCompareResult? {
        guard let application = collegePersistence.jobApplication(id: applicationID) else {
            return nil
        }
        let jd = application.jobDescriptionText ?? application.extractedKeywordsJSON ?? ""
        let repo = collegePersistence.careerRepository

        if let posting = application.workdaySourcePosting,
           let path = posting.externalPath,
           let match = try? repo.recommendedMatch(companySlug: posting.companySlug, externalPath: path),
           let json = match.resultJSON,
           let data = json.data(using: .utf8),
           let cached = try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data) {
            return cached
        }

        let manualSlug = CareerRepository.CareerResumeJobMatchKey.companySlug(for: application)
        let manualPath = CareerRepository.CareerResumeJobMatchKey.manualApplicationExternalPath(applicationID)
        if let match = try? repo.recommendedMatch(companySlug: manualSlug, externalPath: manualPath),
           let json = match.resultJSON,
           let data = json.data(using: .utf8),
           let cached = try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data) {
            return cached
        }

        if let resume = application.submittedResume {
            return await compareResume(
                resumeDocumentID: resume.id,
                jobDescriptionText: jd,
                jobTitle: application.title ?? "",
                platform: JobBoardPlatform(rawValue: application.source ?? "") ?? .workday,
                using: collegePersistence
            )
        }
        let resumeText = collegePersistence.careerResumeBaselineText()
        return heuristicCompare(
            jobDescription: jd,
            jobTitle: application.title ?? "",
            resumeText: resumeText
        )
    }

    func draftGapParagraph(
        resumeDocumentID: UUID,
        jobDescriptionText: String,
        missingKeywords: [String],
        using collegePersistence: CollegePersistence
    ) async -> String? {
        await BackgroundServiceOnDemand.runReturning(id: "career_ai_parse") {
            await CareerAIService.shared.draftGapParagraphImpl(
                resumeDocumentID: resumeDocumentID,
                jobDescriptionText: jobDescriptionText,
                missingKeywords: missingKeywords,
                using: collegePersistence
            )
        }
    }

    private func draftGapParagraphImpl(
        resumeDocumentID: UUID,
        jobDescriptionText: String,
        missingKeywords: [String],
        using collegePersistence: CollegePersistence
    ) async -> String? {
        guard !missingKeywords.isEmpty else { return nil }
        guard let document = try? collegePersistence.vaultRepository.fetchDocument(id: resumeDocumentID) else { return nil }
        let resumeText = await collegePersistence.careerRepository.careerResumePlainText(
            for: document,
            vaultRepository: collegePersistence.vaultRepository
        )

        let prompt = """
        Write 2-3 sentences for a cover letter that honestly bridges a skill gap.
        Name the exact missing terms and connect to adjacent experience from the resume.
        Return strict JSON: { "paragraph": String }
        Missing: \(missingKeywords.prefix(6).joined(separator: ", "))
        Resume excerpt: \(resumeText.prefix(4_000))
        Job excerpt: \(jobDescriptionText.prefix(4_000))
        """

        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else { return nil }

        struct GapResponse: Codable { var paragraph: String? }
        if let decoded = try? JSONDecoder().decode(GapResponse.self, from: data) {
            return CareerATSAdviceValidator.validatedGapParagraph(decoded.paragraph)
        }
        return nil
    }

    private func heuristicCompare(
        jobDescription: String,
        jobTitle: String,
        resumeText: String,
        experienceAnalysis: ExperienceAnalysis? = nil,
        transferableSkills: [String] = []
    ) -> CareerResumeCompareResult? {
        let tokens = jobDescription
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }
        let keywords = Array(tokens.prefix(12))
        guard !keywords.isEmpty else { return nil }
        let resumeLower = resumeText.lowercased()
        var matching: [String] = []
        var missing: [String] = []
        for keyword in keywords {
            if resumeLower.contains(keyword.lowercased()) {
                matching.append(keyword)
            } else {
                missing.append(keyword)
            }
        }
        let keywordScore = Int((Double(matching.count) / Double(keywords.count) * 100).rounded())
        let tip: String
        if let firstMissing = missing.first {
            tip = "This role emphasizes \(firstMissing). Highlight a concrete project where you used it."
        } else {
            tip = "Your resume aligns well with this posting. Add role-specific outcomes and metrics."
        }
        return CareerResumeCompareResult(
            matchingSkills: matching,
            missingKeywords: missing,
            tip: tip,
            overallScore: keywordScore,
            keywordScore: keywordScore,
            semanticScore: nil,
            experienceScore: experienceAnalysis?.score,
            experienceGapExplanation: experienceAnalysis?.gapNote,
            transferableSkillsNoted: transferableSkills.isEmpty ? nil : transferableSkills
        )
    }

    func draftColdOutreach(for applicationID: UUID, using collegePersistence: CollegePersistence) async -> String? {
        await BackgroundServiceOnDemand.runReturning(id: "career_ai_parse") {
            await CareerAIService.shared.draftColdOutreachImpl(for: applicationID, using: collegePersistence)
        }
    }

    private func draftColdOutreachImpl(for applicationID: UUID, using collegePersistence: CollegePersistence) async -> String? {
        guard let application = collegePersistence.jobApplication(id: applicationID) else {
            return nil
        }
        let company = application.company ?? "the team"
        let title = application.title ?? "this role"
        let jdSnippet = String((application.jobDescriptionText ?? application.extractedKeywordsJSON ?? "").prefix(3_000))

        let prompt = """
        Write a concise, professional recruiter follow-up or cold outreach email body (plain text, no subject line).
        Tone: respectful, enthusiastic, concrete. Mention the role title and company. Reference one relevant qualification from typical candidate background if job text allows.
        Avoid clichés and keep under 220 words.

        Role: \(title)
        Company: \(company)

        Job excerpt:
        \(jdSnippet.isEmpty ? "(No description saved.)" : jdSnippet)
        """

        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else {
            return heuristicColdOutreach(company: company, title: title)
        }
        struct OutreachResponse: Codable {
            var body: String?
            var email: String?
        }
        if let decoded = try? JSONDecoder().decode(OutreachResponse.self, from: data),
           let body = decoded.body ?? decoded.email, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data),
           let body = decoded["body"] ?? decoded["draft"] ?? decoded["text"], !body.isEmpty {
            return body
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.hasPrefix("{") {
            return trimmed
        }
        return heuristicColdOutreach(company: company, title: title)
    }

    private func heuristicColdOutreach(company: String, title: String) -> String {
        """
        Hi,

        I'm writing to express my continued interest in the \(title) opportunity at \(company). I've applied and remain very enthusiastic about contributing to your team.

        I'd welcome the chance to discuss how my experience aligns with your needs—please let me know if there's anything further I can share or schedule a brief conversation.

        Thank you for your time.

        Best regards
        """
    }

    func draftContactOutreach(for contactID: UUID, using collegePersistence: CollegePersistence) async -> String? {
        await BackgroundServiceOnDemand.runReturning(id: "career_ai_parse") {
            await CareerAIService.shared.draftContactOutreachImpl(for: contactID, using: collegePersistence)
        }
    }

    private func draftContactOutreachImpl(for contactID: UUID, using collegePersistence: CollegePersistence) async -> String? {
        guard let contact = collegePersistence.recruiterContact(id: contactID) else {
            return nil
        }
        let company = contact.displayCompanyName ?? "your team"
        let name = contact.fullName ?? "there"
        let role = contact.roleTitle ?? ""

        let prompt = """
        Write a concise, professional networking follow-up email body (plain text, no subject line).
        Tone: warm, specific, not salesy. Mention you appreciated any prior context if implied. Under 200 words.
        Recipient name: \(name)
        Organization: \(company)
        Role context (optional): \(role.isEmpty ? "(none)" : role)
        """

        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else {
            return heuristicContactOutreach(name: name, company: company)
        }
        struct OutreachResponse: Codable {
            var body: String?
        }
        if let decoded = try? JSONDecoder().decode(OutreachResponse.self, from: data),
           let body = decoded.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        if let decoded = try? JSONDecoder().decode([String: String].self, from: data),
           let body = decoded["body"] ?? decoded["draft"], !body.isEmpty {
            return body
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !trimmed.hasPrefix("{") {
            return trimmed
        }
        return heuristicContactOutreach(name: name, company: company)
    }

    private func heuristicContactOutreach(name: String, company: String) -> String {
        """
        Hi \(name),

        I hope you are doing well. I wanted to reconnect regarding opportunities at \(company) and share a brief update on my recent work that aligns with the roles we have discussed.

        If you have a few minutes in the coming weeks, I would appreciate the chance to catch up and hear how things are going on your side.

        Thank you for your time and guidance.

        Best regards
        """
    }
}
