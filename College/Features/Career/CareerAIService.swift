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
        let prompt = """
        You extract structured fields from a job posting.
        Return strict JSON with keys:
        company, title, baseSalary, location, keywords, confidence, jobDescription

        Source URL: \(payload.sourceURL)
        Posting Text:
        \(payload.rawText.prefix(12_000))
        """

        guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker) else {
            return nil
        }
        guard let raw = try? await LocalLLMRunner.shared.generateJSON(
            prompt: prompt,
            modelPath: modelPath
        ) else {
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

    func compareResume(for applicationID: UUID, using collegePersistence: CollegePersistence) async -> CareerResumeCompareResult? {
        guard let application = collegePersistence.jobApplication(id: applicationID) else {
            return nil
        }
        let resumeText = collegePersistence.careerResumeBaselineText()
        let jd = application.jobDescriptionText ?? application.extractedKeywordsJSON ?? ""
        guard !resumeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !jd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return heuristicCompare(application: application, resumeText: resumeText) }

        let prompt = """
        Compare this resume text against the job posting text.
        Return strict JSON:
        {
          "matchingSkills": [String],
          "missingKeywords": [String],
          "tip": String
        }

        Resume:
        \(resumeText.prefix(10_000))

        Job:
        \(jd.prefix(10_000))
        """

        guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker),
              let raw = try? await LocalLLMRunner.shared.generateJSON(prompt: prompt, modelPath: modelPath),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data)
        else {
            return heuristicCompare(application: application, resumeText: resumeText)
        }
        return parsed
    }

    private func heuristicCompare(application: JobApplication, resumeText: String) -> CareerResumeCompareResult? {
        let keywords: [String]
        if let blob = application.extractedKeywordsJSON?.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: blob) {
            keywords = arr
        } else {
            let tokens = (application.jobDescriptionText ?? "")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 4 }
            keywords = Array(tokens.prefix(12))
        }
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
        let tip: String
        if let firstMissing = missing.first {
            tip = "This role emphasizes \(firstMissing). Highlight a concrete project where you used it."
        } else {
            tip = "Your resume aligns well with this posting. Add role-specific outcomes and metrics."
        }
        return CareerResumeCompareResult(matchingSkills: matching, missingKeywords: missing, tip: tip)
    }

    func draftColdOutreach(for applicationID: UUID, using collegePersistence: CollegePersistence) async -> String? {
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

        guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker),
              let raw = try? await LocalLLMRunner.shared.generateJSON(
                  prompt: prompt,
                  modelPath: modelPath
              ),
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

        guard let modelPath = try? await ModelManager.shared.modelDirectoryURL(for: .jsonWorker),
              let raw = try? await LocalLLMRunner.shared.generateJSON(
                  prompt: prompt,
                  modelPath: modelPath
              ),
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
