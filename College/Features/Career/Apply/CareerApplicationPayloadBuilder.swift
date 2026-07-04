// CareerApplicationPayloadBuilder.swift
// Feature: Career / Apply
// Purpose: Assemble CareerApplicationAutofillPayload from Profile-first sources.

import Foundation

enum CareerApplicationPayloadBuilderError: Error, Sendable, Equatable {
    case noProfile
    case missingEmail
    case missingResumeDocument
    case criticalParserHealth
}

@MainActor
enum CareerApplicationPayloadBuilder {
    static func build(
        resumeDocumentID: UUID,
        resumeFileURL: URL?,
        resumeFileName: String,
        collegePersistence: CollegePersistence = .shared,
        preferences: CareerApplicationPreferences? = nil
    ) throws -> CareerApplicationAutofillPayload {
        let profileSnapshot = try ResumeSnapshotBuilder.build(collegePersistence: collegePersistence)
        let resumeCanonical = resumeCanonicalProfile(
            resumeDocumentID: resumeDocumentID,
            collegePersistence: collegePersistence
        )
        let canonical = preferredCanonicalProfile(
            resumeCanonical: resumeCanonical,
            profileSnapshot: profileSnapshot
        )

        guard let email = trimmed(canonical.basics?.email ?? profileSnapshot.personal.email),
              !email.isEmpty else {
            throw CareerApplicationPayloadBuilderError.missingEmail
        }

        let profilePrefs = preferences ?? {
            let repo = CareerRepository(context: collegePersistence.profileContext)
            return try? repo.fetchApplicationPreferences()
        }()
        let name = trimmed(canonical.basics?.name) ?? profileSnapshot.personal.name
        let nameParts = splitName(name)
        let links = ResumeSnapshotBuilder.classifyLinks(canonical.basics?.links ?? [])

        return CareerApplicationAutofillPayload(
            personal: ApplyPersonalInfo(
                firstName: nameParts.first,
                lastName: nameParts.last,
                fullName: name,
                email: email,
                phone: trimmed(canonical.basics?.phone) ?? profileSnapshot.personal.phone,
                address: trimmed(canonical.basics?.location) ?? profileSnapshot.personal.address,
                linkedInURL: links.first(where: { $0.kind == .linkedIn })?.url,
                githubURL: links.first(where: { $0.kind == .github })?.url,
                portfolioURL: links.first(where: { $0.kind == .website })?.url,
                pronouns: profileSnapshot.personal.pronouns
            ),
            education: mapEducation(canonical: canonical, fallback: profileSnapshot),
            experienceBlocks: mapExperience(canonical: canonical, fallback: profileSnapshot),
            projects: mapProjects(canonical: canonical, fallback: profileSnapshot),
            skills: canonical.skills.isEmpty ? profileSnapshot.skills : canonical.skills,
            summary: trimmed(canonical.basics?.summary),
            documents: ApplyDocuments(
                resumeDocumentID: resumeDocumentID,
                resumeFileName: resumeFileName,
                resumeFileURL: resumeFileURL,
                coverLetterDocumentID: nil
            ),
            applicationProfile: mapApplicationProfile(profilePrefs),
            approvedAt: Date(),
            sourceRevisionToken: profileSnapshot.profileRevisionToken
        )
    }

    // MARK: - Canonical resolution

    private static func resumeCanonicalProfile(
        resumeDocumentID: UUID,
        collegePersistence: CollegePersistence
    ) -> ResumeCanonicalProfile? {
        guard let doc = try? collegePersistence.vaultRepository.fetchDocument(id: resumeDocumentID) else {
            return nil
        }
        let meta = collegePersistence.careerResumeMetadata(for: doc)
        if let structured = meta.canonicalProfile ?? meta.structuredProfile {
            return ResumeCanonicalProfile.from(structured: structured)
        }
        if let document = ResumeDocument.decode(from: meta.documentJSON) {
            let snapshot = ResumeDocumentCompiler.mergedSnapshot(from: document)
            let canonical = ResumeCanonicalProfile.from(snapshot: snapshot)
            return canonical.hasContent ? canonical : nil
        }
        return nil
    }

    private static func preferredCanonicalProfile(
        resumeCanonical: ResumeCanonicalProfile?,
        profileSnapshot: ResumeSnapshot
    ) -> ResumeCanonicalProfile {
        if let resumeCanonical, resumeCanonical.hasContent {
            return resumeCanonical
        }
        return ResumeCanonicalProfile.from(snapshot: profileSnapshot)
    }

    // MARK: - Mapping

    private static func mapEducation(
        canonical: ResumeCanonicalProfile,
        fallback: ResumeSnapshot
    ) -> [ApplyEducationEntry] {
        guard !canonical.education.isEmpty else {
            return fallback.education.map {
                ApplyEducationEntry(
                    id: $0.id,
                    institution: $0.collegeName,
                    degree: $0.degreeLevel,
                    major: $0.major,
                    graduation: $0.expectedGraduation,
                    gpa: $0.gpa
                )
            }
        }
        return canonical.education.map {
            ApplyEducationEntry(
                id: $0.id,
                institution: $0.institution,
                degree: $0.studyType,
                major: $0.area,
                graduation: $0.endDate,
                gpa: $0.gpa
            )
        }
    }

    private static func mapExperience(
        canonical: ResumeCanonicalProfile,
        fallback: ResumeSnapshot
    ) -> [ApplyExperienceCompanyBlock] {
        guard !canonical.work.isEmpty else {
            return fallback.experiences.map { entry in
                ApplyExperienceCompanyBlock(
                    id: entry.id,
                    company: entry.company,
                    positions: [
                        ApplyExperiencePosition(
                            id: entry.id,
                            title: entry.title,
                            location: entry.location,
                            workArrangement: nil,
                            employmentType: nil,
                            startDate: nil,
                            endDate: nil,
                            isCurrent: entry.dateRange.localizedCaseInsensitiveContains("present"),
                            bullets: bullets(from: entry.descriptionText)
                        )
                    ]
                )
            }
        }

        var grouped: [String: [ResumeCanonicalProfile.WorkEntry]] = [:]
        var order: [String] = []
        for entry in canonical.work {
            let company = trimmed(entry.company) ?? "Company"
            if grouped[company] == nil {
                order.append(company)
                grouped[company] = []
            }
            grouped[company, default: []].append(entry)
        }

        return order.compactMap { company in
            guard let entries = grouped[company] else { return nil }
            return ApplyExperienceCompanyBlock(
                id: entries[0].id,
                company: company,
                positions: entries.map { entry in
                    ApplyExperiencePosition(
                        id: entry.id,
                        title: trimmed(entry.position) ?? "Role",
                        location: entry.location,
                        workArrangement: nil,
                        employmentType: nil,
                        startDate: nil,
                        endDate: nil,
                        isCurrent: entry.dateRange?.localizedCaseInsensitiveContains("present") == true,
                        bullets: entry.highlights
                    )
                }
            )
        }
    }

    private static func mapProjects(
        canonical: ResumeCanonicalProfile,
        fallback: ResumeSnapshot
    ) -> [ApplyProjectEntry] {
        guard !canonical.projects.isEmpty else {
            return fallback.projects.map {
                ApplyProjectEntry(
                    id: $0.id,
                    title: $0.title,
                    role: $0.role,
                    url: $0.projectURL,
                    technologies: $0.technologies,
                    bullets: $0.bullets
                )
            }
        }
        return canonical.projects.map {
            ApplyProjectEntry(
                id: $0.id,
                title: trimmed($0.name) ?? "Project",
                role: $0.role,
                url: $0.url,
                technologies: $0.technologies,
                bullets: $0.highlights
            )
        }
    }

    private static func mapApplicationProfile(_ prefs: CareerApplicationPreferences?) -> ApplyApplicationProfile {
        guard let prefs else {
            return ApplyApplicationProfile(
                workAuthorization: ApplyWorkAuthorization(),
                preferences: ApplyApplicationDefaults(),
                screeningAnswerCache: [:],
                allowEEOAutofill: false
            )
        }
        return ApplyApplicationProfile(
            workAuthorization: ApplyWorkAuthorization(
                usCitizen: prefs.usCitizen,
                usAuthorized: prefs.usAuthorized,
                requiresSponsorshipNow: prefs.requiresSponsorshipNow,
                requiresSponsorshipFuture: prefs.requiresSponsorshipFuture,
                countryOfCitizenship: prefs.countryOfCitizenship,
                visaStatus: prefs.visaStatus
            ),
            preferences: ApplyApplicationDefaults(
                willingToRelocate: prefs.willingToRelocate,
                remotePreference: prefs.remotePreference,
                salaryExpectation: prefs.salaryExpectation,
                earliestStartDate: prefs.earliestStartDate,
                referralSource: prefs.referralSource
            ),
            screeningAnswerCache: prefs.decodedScreeningCache(),
            allowEEOAutofill: prefs.allowEEOAutofill
        )
    }

    private static func splitName(_ fullName: String) -> (first: String, last: String) {
        let parts = fullName.split(separator: " ").map(String.init)
        guard let first = parts.first else { return ("", "") }
        let last = parts.dropFirst().joined(separator: " ")
        return (first, last.isEmpty ? first : last)
    }

    private static func bullets(from descriptionText: String?) -> [String] {
        guard let descriptionText else { return [] }
        return descriptionText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
