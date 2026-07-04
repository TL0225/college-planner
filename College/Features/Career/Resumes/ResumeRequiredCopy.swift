// ResumeRequiredCopy.swift
// Feature: Career / Resumes
// Purpose: Shared resume CTA copy for library empty states and match panels.

import Foundation

enum ResumeRequiredCopy {
    // MARK: - Library empty state

    static let emptyTitle = "No resumes yet"
    static let emptyDescription = "Upload a PDF or build one from your profile."
    static let uploadButton = "Upload resume"
    static let buildButton = "Build resume"

    // MARK: - Job match panel

    static let matchPanelNoResume = "Upload a resume in the Resumes tab to compare against this role."
    static let awaitingParse = "Finish parsing your resume to see match scores."
    static let awaitingDescriptionLoading = "Loading job description to score match…"
    static let awaitingDescription = "Open this role's description to see how your resume compares."
    static let scoring = "Scoring your resumes against this job…"
}
