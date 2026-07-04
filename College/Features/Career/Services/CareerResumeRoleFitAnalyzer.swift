// CareerResumeRoleFitAnalyzer.swift
// Feature: Career
// Purpose: Infer resume career track vs job track for alignment scoring.

import Foundation

struct CareerRoleFitAnalysis: Sendable {
    var resumeTrack: String
    var jobTrack: String
    var alignmentScore: Int
    var mismatchNote: String?
    var resumeTargetRole: String?
}

enum CareerResumeRoleFitAnalyzer {
    private struct TrackProfile {
        let id: String
        let label: String
        let titleTokens: [String]
        let bodyTokens: [String]
    }

    private static let tracks: [TrackProfile] = [
        TrackProfile(
            id: "cybersecurity",
            label: "Cybersecurity / InfoSec",
            titleTokens: ["security", "cybersecurity", "soc", "analyst", "infosec", "incident"],
            bodyTokens: ["siem", "vulnerability", "penetration", "firewall", "rapid7", "sentinel", "compliance", "threat"]
        ),
        TrackProfile(
            id: "software_engineering",
            label: "Software Engineering",
            titleTokens: ["engineer", "developer", "software", "ios", "backend", "frontend", "full stack"],
            bodyTokens: ["swift", "python", "api", "git", "deploy", "architecture", "code review"]
        ),
        TrackProfile(
            id: "sales_commercial",
            label: "Sales / Commercial",
            titleTokens: ["specialist", "representative", "account executive", "sales", "territory", "commercial"],
            bodyTokens: ["quota", "revenue", "hcp", "pharma", "biotech", "product promotion", "launch", "pipeline", "crm"]
        ),
        TrackProfile(
            id: "data_analytics",
            label: "Data & Analytics",
            titleTokens: ["data analyst", "data scientist", "analytics", "business intelligence"],
            bodyTokens: ["sql", "tableau", "visualization", "statistics", "machine learning", "reporting"]
        ),
        TrackProfile(
            id: "it_support",
            label: "IT / Desktop Support",
            titleTokens: ["support", "help desk", "desktop", "technical support"],
            bodyTokens: ["troubleshoot", "ticketing", "active directory", "end user"]
        ),
        TrackProfile(
            id: "product",
            label: "Product Management",
            titleTokens: ["product manager", "product owner", "program manager"],
            bodyTokens: ["roadmap", "stakeholder", "prd", "user research"]
        ),
    ]

    static func analyze(
        jobTitle: String,
        jobDescription: String,
        profile: CareerResumeStructuredProfile?,
        targetRole: String?,
        detectedDomains: [String]
    ) -> CareerRoleFitAnalysis {
        let resumeCorpus = resumeCorpus(profile: profile, targetRole: targetRole, domains: detectedDomains)
        let jobCorpus = "\(jobTitle) \(jobDescription)".lowercased()

        let resumeTrack = classify(corpus: resumeCorpus, profile: profile, domains: detectedDomains)
        let jobTrack = classify(corpus: jobCorpus, profile: nil, domains: [])

        let alignment = alignmentScore(resumeTrack: resumeTrack, jobTrack: jobTrack, resumeCorpus: resumeCorpus, jobCorpus: jobCorpus)

        var note: String?
        if alignment < 45, resumeTrack.id != jobTrack.id {
            let target = targetRole?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let target, !target.isEmpty {
                note = "Your resume targets \(target) (\(resumeTrack.label)). This role is \(jobTrack.label) — likely a poor fit."
            } else {
                note = "Your background reads as \(resumeTrack.label). This role is \(jobTrack.label) — likely a poor fit."
            }
        }

        return CareerRoleFitAnalysis(
            resumeTrack: resumeTrack.label,
            jobTrack: jobTrack.label,
            alignmentScore: alignment,
            mismatchNote: note,
            resumeTargetRole: targetRole
        )
    }

    /// Fast alignment check for job list rows without full ATS scoring.
    static func quickAlignment(
        jobTitle: String,
        jobDescription: String?,
        profile: CareerResumeStructuredProfile?,
        targetRole: String?,
        detectedDomains: [String]
    ) -> Int {
        analyze(
            jobTitle: jobTitle,
            jobDescription: jobDescription ?? "",
            profile: profile,
            targetRole: targetRole,
            detectedDomains: detectedDomains
        ).alignmentScore
    }

    private static func resumeCorpus(
        profile: CareerResumeStructuredProfile?,
        targetRole: String?,
        domains: [String]
    ) -> String {
        var parts: [String] = []
        if let targetRole, !targetRole.isEmpty { parts.append(targetRole.lowercased()) }
        parts.append(contentsOf: domains.map { $0.lowercased() })
        if let profile {
            parts.append(profile.experience.flatMap(\.headingLines).joined(separator: " ").lowercased())
            parts.append(profile.skills.joined(separator: " ").lowercased())
            parts.append((profile.summary ?? "").lowercased())
        }
        return parts.joined(separator: " ")
    }

    private static func classify(
        corpus: String,
        profile: CareerResumeStructuredProfile?,
        domains: [String]
    ) -> TrackProfile {
        var best = tracks[0]
        var bestScore = -1
        for track in tracks {
            var score = 0
            for token in track.titleTokens where corpus.contains(token) { score += 3 }
            for token in track.bodyTokens where corpus.contains(token) { score += 1 }
            for domain in domains where domain.lowercased().contains(track.label.lowercased().prefix(8)) {
                score += 4
            }
            if let profile {
                let titles = profile.experience.flatMap(\.headingLines).joined(separator: " ").lowercased()
                for token in track.titleTokens where titles.contains(token) { score += 2 }
            }
            if score > bestScore {
                bestScore = score
                best = track
            }
        }
        let general = TrackProfile(id: "general", label: "General", titleTokens: [], bodyTokens: [])
        return bestScore > 0 ? best : general
    }

    private static func alignmentScore(
        resumeTrack: TrackProfile,
        jobTrack: TrackProfile,
        resumeCorpus: String,
        jobCorpus: String
    ) -> Int {
        if resumeTrack.id == jobTrack.id { return 90 }

        let incompatible: Set<Set<String>> = [
            ["cybersecurity", "sales_commercial"],
            ["software_engineering", "sales_commercial"],
            ["it_support", "sales_commercial"],
            ["cybersecurity", "product"],
        ]
        let pair: Set<String> = [resumeTrack.id, jobTrack.id]
        if incompatible.contains(pair) { return 20 }

        let sharedBody = jobTrack.bodyTokens.filter { resumeCorpus.contains($0) }.count
        let sharedTitle = jobTrack.titleTokens.filter { resumeCorpus.contains($0) }.count
        let base = 35 + sharedBody * 8 + sharedTitle * 12
        return min(85, max(15, base))
    }
}
