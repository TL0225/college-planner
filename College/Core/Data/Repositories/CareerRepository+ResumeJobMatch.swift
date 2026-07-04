// CareerRepository+ResumeJobMatch.swift
// Feature: Core/Data
// Purpose: CRUD for cached resume ↔ job match scores.

import Foundation
import SwiftData
import CollegeCareer

extension CareerRepository {
    struct PostingMatchKey: Hashable, Sendable {
        let companySlug: String
        let externalPath: String
    }

    enum CareerResumeJobMatchKey {
        static func manualApplicationExternalPath(_ applicationID: UUID) -> String {
            "application:\(applicationID.uuidString)"
        }

        static func companySlug(for application: JobApplication) -> String {
            let company = (application.company ?? "manual")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return company.isEmpty ? "manual" : company
        }
    }

    func fetchResumeJobMatches(
        companySlug: String,
        externalPath: String
    ) throws -> [CareerResumeJobMatch] {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = (externalPath).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !path.isEmpty else { return [] }

        let descriptor = FetchDescriptor<CareerResumeJobMatch>(
            predicate: #Predicate { match in
                match.postingCompanySlug == slug && match.postingExternalPath == path
            },
            sortBy: [SortDescriptor(\.overallScore, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchResumeJobMatch(
        companySlug: String,
        externalPath: String,
        resumeDocumentID: UUID
    ) throws -> CareerResumeJobMatch? {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = externalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<CareerResumeJobMatch>(
            predicate: #Predicate { match in
                match.postingCompanySlug == slug
                    && match.postingExternalPath == path
                    && match.resumeDocumentID == resumeDocumentID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func invalidateResumeJobMatches(resumeDocumentID: UUID) throws {
        let id = resumeDocumentID
        let descriptor = FetchDescriptor<CareerResumeJobMatch>(
            predicate: #Predicate { match in
                match.resumeDocumentID == id
            }
        )
        let matches = try context.fetch(descriptor)
        guard !matches.isEmpty else { return }
        for match in matches {
            context.delete(match)
        }
        ModelMergeCoalescer.scheduleSave(context)
        CollegePersistence.shared.bumpCareerRevision()
    }

    func invalidateResumeJobMatches(
        companySlug: String,
        externalPath: String,
        descriptionHash: String?
    ) throws {
        let matches = try fetchResumeJobMatches(companySlug: companySlug, externalPath: externalPath)
        for match in matches where match.descriptionHashAtScore != descriptionHash {
            context.delete(match)
        }
        if !matches.isEmpty {
            ModelMergeCoalescer.scheduleSave(context)
            CollegePersistence.shared.bumpCareerRevision()
        }
    }

    @discardableResult
    func upsertResumeJobMatch(
        companySlug: String,
        externalPath: String,
        resumeDocumentID: UUID,
        overallScore: Int,
        keywordScore: Int,
        semanticScore: Int,
        experienceScore: Int,
        missingKeywords: [String],
        recommendedForPosting: Bool,
        resultJSON: String?,
        descriptionHash: String?,
        resumeHash: String?
    ) throws -> CareerResumeJobMatch {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = externalPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if recommendedForPosting {
            let existing = try fetchResumeJobMatches(companySlug: slug, externalPath: path)
            for row in existing where row.recommendedForPosting {
                row.recommendedForPosting = false
            }
        }

        let missingJSON: String? = {
            guard let data = try? JSONEncoder().encode(missingKeywords),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()

        let match: CareerResumeJobMatch
        if let existing = try fetchResumeJobMatch(
            companySlug: slug,
            externalPath: path,
            resumeDocumentID: resumeDocumentID
        ) {
            match = existing
        } else {
            match = CareerResumeJobMatch(
                postingCompanySlug: slug,
                postingExternalPath: path,
                resumeDocumentID: resumeDocumentID
            )
            context.insert(match)
        }

        match.overallScore = min(100, max(0, overallScore))
        match.keywordScore = min(100, max(0, keywordScore))
        match.semanticScore = min(100, max(0, semanticScore))
        match.experienceScore = min(100, max(0, experienceScore))
        match.missingKeywordsJSON = missingJSON
        match.recommendedForPosting = recommendedForPosting
        match.resultJSON = resultJSON
        match.scoredAt = .now
        match.descriptionHashAtScore = descriptionHash
        match.resumeHashAtScore = resumeHash

        ModelMergeCoalescer.scheduleSave(context)
        CollegePersistence.shared.bumpCareerRevision()
        return match
    }

    func fetchAllResumeJobMatches(limit: Int = 500) throws -> [CareerResumeJobMatch] {
        var descriptor = FetchDescriptor<CareerResumeJobMatch>(
            sortBy: [SortDescriptor(\.scoredAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func recommendedMatch(
        companySlug: String,
        externalPath: String
    ) throws -> CareerResumeJobMatch? {
        try fetchResumeJobMatches(companySlug: companySlug, externalPath: externalPath)
            .first(where: \.recommendedForPosting)
    }

    /// One fetch for all recommended scores on a company board (list UI hot path).
    func fetchRecommendedMatches(companySlug: String) throws -> [CareerResumeJobMatch] {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CareerResumeJobMatch>(
            predicate: #Predicate { match in
                match.postingCompanySlug == slug && match.recommendedForPosting
            }
        )
        return try context.fetch(descriptor)
    }

    func recommendedMatchIfValid(
        companySlug: String,
        externalPath: String,
        postingDescriptionHash: String?,
        resumeParsedTextHash: String?
    ) throws -> CareerResumeJobMatch? {
        guard let match = try recommendedMatch(companySlug: companySlug, externalPath: externalPath) else {
            return nil
        }
        guard JobBoardMatchEligibility.isMatchCacheValid(
            match: match,
            postingDescriptionHash: postingDescriptionHash,
            resumeParsedTextHash: resumeParsedTextHash
        ) else {
            return nil
        }
        return match
    }
}
