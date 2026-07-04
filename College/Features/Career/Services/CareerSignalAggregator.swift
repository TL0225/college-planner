// CareerSignalAggregator.swift
// Feature: Career
// Purpose: Aggregate resume-job match cache into career signal insights.

import Foundation
import CollegeCareer

struct CareerSignalSnapshot: Sendable {
    var scoredJobCount: Int
    var strongSkills: [(skill: String, jobPercent: Int)]
    var missingSkills: [(skill: String, jobCount: Int, totalJobs: Int)]
    var topCompanies: [(company: String, avgScore: Int, jobCount: Int)]
    var topCourseBridge: CareerCourseSkillGap?
}

enum CareerSignalAggregator {
    static let minimumScoredJobs = 8

    @MainActor
    static func snapshot(collegePersistence: CollegePersistence = .shared) -> CareerSignalSnapshot {
        let repo = collegePersistence.careerRepository
        let matches = (try? repo.fetchAllResumeJobMatches(limit: 500)) ?? []
        let recommended = matches.filter(\.recommendedForPosting)

        var skillHits: [String: Int] = [:]
        var skillMisses: [String: Int] = [:]
        var companyScores: [String: (sum: Int, count: Int)] = [:]

        for match in recommended {
            if let json = match.missingKeywordsJSON,
               let data = json.data(using: .utf8),
               let missing = try? JSONDecoder().decode([String].self, from: data) {
                for skill in missing {
                    skillMisses[skill.lowercased(), default: 0] += 1
                }
            }
            if let json = match.resultJSON,
               let data = json.data(using: .utf8),
               let result = try? JSONDecoder().decode(CareerResumeCompareResult.self, from: data) {
                for skill in result.matchingSkills {
                    skillHits[skill.lowercased(), default: 0] += 1
                }
            }
            let slug = match.postingCompanySlug
            var entry = companyScores[slug, default: (0, 0)]
            entry.sum += match.overallScore
            entry.count += 1
            companyScores[slug] = entry
        }

        let jobCount = Set(recommended.map { "\($0.postingCompanySlug)|\($0.postingExternalPath)" }).count
        let strong = skillHits
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { (skill: $0.key, jobPercent: jobCount > 0 ? Int((Double($0.value) / Double(jobCount) * 100).rounded()) : 0) }

        let missing = skillMisses
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { (skill: $0.key, jobCount: $0.value, totalJobs: jobCount) }

        let companies = companyScores
            .map { (company: $0.key, avgScore: $0.value.count > 0 ? $0.value.sum / $0.value.count : 0, jobCount: $0.value.count) }
            .sorted { $0.avgScore > $1.avgScore }
            .prefix(5)

        let topMissing = missing.first.map(\.skill)
        let courseBridge = topMissing.map {
            CareerCourseSkillBridge.gaps(for: [$0], collegePersistence: collegePersistence).first
        } ?? nil

        return CareerSignalSnapshot(
            scoredJobCount: jobCount,
            strongSkills: Array(strong),
            missingSkills: Array(missing),
            topCompanies: Array(companies),
            topCourseBridge: courseBridge ?? nil
        )
    }
}
