// AssistantCareerReplyGuide.swift
// Feature: Assistant
// Purpose: Career exploration reply structure (Ship A — inline, no separate VoiceGuide file).

import Foundation

enum AssistantCareerReplyGuide {
    static let plannerSeed = """
    Career exploration: call getStudentLearningProfile first when a major is declared.
    Structure the final answer in two parts when personalizationEligible is true:
    1) Typical career paths for the declared major (from catalog program context when available; otherwise general knowledge with disclaimer).
    2) "However, based on courses that appear related to your major..." — cite specific course codes/titles from the learning profile.
    If personalizationEligible is false, give part 1 only plus guided steps to add major-related courses.
    Always end with: "These are planning ideas, not career placement advice."
    Do not claim job placement or salary guarantees.
    """

    static let synthesisRules = """
    Career reply rules:
    - Paragraph 1: 3–5 common roles for the major; note these are typical paths, not guarantees.
    - Paragraph 2 (only if ≥2 major-relevant courses): patterns from a small sample of coursework; use cautious wording.
    - Include disclaimer: planning ideas, not career placement advice.
    """
}
