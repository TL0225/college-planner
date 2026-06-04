// AcademicProgressTypes.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CreditsProgressSummary.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Academic progress value types (Phase 7f — moved off local store)

extension CollegePersistence {
    struct CreditsProgressSummary: Equatable {
        let completed: Double
        let required: Double
        let fraction: Double

        var completedRoundedInt: Int { Int(completed.rounded()) }
        var requiredRoundedInt: Int { Int(required.rounded()) }
    }

    struct RequirementCreditBuckets {
        let requiredCore: Double
        let requiredElective: Double

        var totalRequired: Double {
            requiredCore + requiredElective
        }
    }

    struct GPASummary: Equatable {
        let gpa: Double
        let credits: Double
    }

    struct DeclaredProgramsCreditsBreakdown: Equatable {
        struct AdditionalProgram: Equatable, Identifiable {
            enum Kind: Equatable {
                case major
                case minor
            }

            var id: String { "\(kind)-\(displayName)" }
            let displayName: String
            let kind: Kind
            let progress: CreditsProgressSummary
        }

        let primary: CreditsProgressSummary
        let additionalPrograms: [AdditionalProgram]

        var hasAdditionalPrograms: Bool { !additionalPrograms.isEmpty }

        var allProgramsRequiredTotal: Int {
            let additionalRequired = additionalPrograms.reduce(0.0) { partial, program in
                partial + program.progress.required
            }
            return Int((primary.required + additionalRequired).rounded())
        }

        var optionalProgramsFootnote: String? {
            guard hasAdditionalPrograms else { return nil }
            let names = additionalPrograms.map(\.displayName).filter { !$0.isEmpty }
            guard !names.isEmpty else { return nil }
            return "Also tracking: \(names.joined(separator: ", "))"
        }
    }

    struct ProgramCreditStatusBuckets: Equatable {
        let completed: Int
        let inProgress: Int
        let remaining: Int
    }
}

extension CollegePersistence.CreditsProgressSummary {
    var creditsFractionText: String {
        "\(completedRoundedInt)/\(requiredRoundedInt)"
    }

    var creditsFractionWithSuffixText: String {
        "\(creditsFractionText) credits"
    }
}