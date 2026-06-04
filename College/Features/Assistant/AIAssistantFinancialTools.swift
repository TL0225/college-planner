// AIAssistantFinancialTools.swift
// Feature: Assistant
// Purpose: Assistant module — GetAidDeadlinesTool.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
struct GetAidDeadlinesTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "getAidDeadlines",
        description: "Return financial-aid deadline topics and official sources to verify for FAFSA, state aid, and school-specific aid.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"aidYear?\":\"2026-2027\"}",
        outputSchemaDescription: "jurisdiction, deadlines, sourcesToCheck, policyEvidence[], disclaimer",
        sourceLabel: "AssistantFinancialAidPolicy + active university"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let jurisdiction = context.collegePersistence.activeSchoolPolicyMetadata().map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
            ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: context.collegePersistence.getActiveUniversityName())
        let evidence = AssistantPolicyEvidenceStore.evidence(
            for: [.schoolFinancialAid, .fafsa, .stateAid, .verification],
            jurisdiction: jurisdiction
        )
        var deadlines = ["FAFSA federal submission deadline", "School priority aid deadline", "Verification document deadline"]
        if let state = jurisdiction.normalizedStateCode, StateAidRegistry.program(for: state) != nil {
            deadlines.append("\(StateAidRegistry.programLabel(for: state) ?? "\(state) state aid") application deadline")
        }
        let payload = AidDeadlinePayload(
            jurisdiction: jurisdiction.policySummary,
            deadlines: deadlines,
            sourcesToCheck: Array(AssistantFinancialAidPolicy.policyHosts(for: jurisdiction)).sorted(),
            policyEvidence: evidence,
            disclaimer: "Deadlines change by aid year and school. Verify on official sources before relying on a date."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared official-source checklist for \(jurisdiction.policySummary) deadlines.",
            errorMessage: nil
        )
    }
}

@MainActor
struct ScreenAidEligibilityTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let program: String?
        let residencyState: String?
        let plannedCredits: Int?
        let degreeSeeking: Bool?
    }

    let descriptor = AssistantToolDescriptor(
        name: "screenAidEligibility",
        description: "Screen high-level aid eligibility factors without collecting sensitive identifiers.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"program?\":\"FAFSA|state aid|Pell\",\"residencyState?\":\"NY\",\"plannedCredits?\":12,\"degreeSeeking?\":true}",
        outputSchemaDescription: "program, jurisdiction, likelyRelevantChecks, missingInputs, policyEvidence[], sensitiveDataWarning, disclaimer",
        sourceLabel: "Financial aid eligibility screening rules"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        let program = decoded?.program?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? decoded!.program! : "general aid"
        let jurisdiction = context.collegePersistence.activeSchoolPolicyMetadata().map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
            ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: context.collegePersistence.getActiveUniversityName())
        let normalizedProgram = program.lowercased()
        let topics: Set<AssistantPolicyTopic> = {
            if normalizedProgram.contains("tap") {
                return [.stateAid, .enrollmentIntensity, .schoolFinancialAid]
            }
            if normalizedProgram.contains("pell") {
                return [.pell, .enrollmentIntensity]
            }
            if normalizedProgram.contains("fafsa") {
                return [.fafsa, .verification]
            }
            return [.schoolFinancialAid, .fafsa, .stateAid, .enrollmentIntensity]
        }()
        let evidence = AssistantPolicyEvidenceStore.evidence(for: topics, jurisdiction: jurisdiction)
        var checks = ["Degree/certificate-seeking status", "Enrollment intensity", "SAP status", "Official application status"]
        if normalizedProgram.contains("tap") || jurisdiction.allowsStateAidRouting {
            let stateLabel = jurisdiction.normalizedStateCode.flatMap { StateAidRegistry.programLabel(for: $0) } ?? "State aid"
            checks.append(contentsOf: ["Residency for \(stateLabel)", "Eligible state school/program", "\(stateLabel) application status"])
        }
        if decoded?.plannedCredits.map({ $0 < 12 }) == true {
            checks.append("Below-12-credit enrollment risk for federal/state aid")
        }
        var missing: [String] = []
        if decoded?.residencyState == nil { missing.append("residency state") }
        if decoded?.plannedCredits == nil { missing.append("planned credits") }
        if decoded?.degreeSeeking == nil { missing.append("degree-seeking status") }

        let payload = AidEligibilityScreenPayload(
            program: program,
            jurisdiction: jurisdiction.policySummary,
            likelyRelevantChecks: checks,
            missingInputs: missing,
            policyEvidence: evidence,
            sensitiveDataWarning: "Do not enter SSN, FSA ID password, full tax ID, full bank account, or payment card numbers.",
            disclaimer: "This is a screening checklist, not an official eligibility decision."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared a safe eligibility screening checklist for \(program).",
            errorMessage: nil
        )
    }
}

@MainActor
struct EstimateAidRangeTool: AIAssistantTool {
    private struct Arguments: Decodable {
        let sai: Double?
        let costOfAttendance: Double?
        let enrollmentCredits: Int?
        let grantsKnown: Double?
    }

    let descriptor = AssistantToolDescriptor(
        name: "estimateAidRange",
        description: "Prepare a cautious aid-estimate framework from user-provided inputs. Never returns an official award.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"sai?\":1200,\"costOfAttendance?\":24000,\"enrollmentCredits?\":12,\"grantsKnown?\":5000}",
        outputSchemaDescription: "estimateType, providedInputs, missingInputs, safeEstimateRange, disclaimer",
        sourceLabel: "User-provided estimate inputs"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let decoded = try? AssistantJSONValue.decodeObject(Arguments.self, from: arguments)
        var provided: [String] = []
        var missing: [String] = []
        if decoded?.sai != nil { provided.append("SAI") } else { missing.append("SAI") }
        if decoded?.costOfAttendance != nil { provided.append("cost of attendance") } else { missing.append("cost of attendance") }
        if decoded?.enrollmentCredits != nil { provided.append("enrollment credits") } else { missing.append("enrollment credits") }
        if decoded?.grantsKnown != nil { provided.append("known grants") }

        let safeRange: String
        if let coa = decoded?.costOfAttendance, let sai = decoded?.sai {
            let need = max(0, coa - sai)
            safeRange = "Estimated need framework: up to about \(Int(need.rounded())) before program rules, enrollment intensity, and school packaging."
        } else {
            safeRange = "Not enough inputs for a numeric range. Ask for COA, SAI, enrollment credits, and known grants."
        }

        let payload = AidEstimatePayload(
            estimateType: "planning_estimate",
            providedInputs: provided,
            missingInputs: missing,
            safeEstimateRange: safeRange,
            disclaimer: "This is not an official award, FAFSA result, Pell calculation, state-aid approval, or school package."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared a non-official aid estimate framework with \(provided.count) provided input(s).",
            errorMessage: nil
        )
    }
}

@MainActor
struct ExplainSAPPolicyTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "explainSAPPolicy",
        description: "Explain SAP completion-rate status and next steps using app-backed SAP data.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "completionRateThreshold, status, explanation, nextSteps, policyEvidence[]",
        sourceLabel: "CollegePersistence.sapStats"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let sap = context.collegePersistence.sapStats()
        let threshold = 0.67
        let rate = sap.attempted == 0 ? 0 : sap.rate
        let status = sap.attempted == 0 ? "no_history" : (rate < threshold ? "at_risk" : "meeting_completion_rate")
        let jurisdiction = context.collegePersistence.activeSchoolPolicyMetadata().map { AssistantFinancialAidPolicy.resolveJurisdiction(metadata: $0) }
            ?? AssistantFinancialAidPolicy.resolveJurisdiction(activeUniversityName: context.collegePersistence.getActiveUniversityName())
        let evidence = AssistantPolicyEvidenceStore.evidence(for: [.schoolFinancialAid, .sap], jurisdiction: jurisdiction)
        let payload = SAPPolicyExplanationPayload(
            completionRateThreshold: threshold,
            status: status,
            explanation: [
                "SAP usually includes pace/completion rate, GPA, and maximum timeframe.",
                "This app can calculate completion-rate pace from attempted/completed credits when data exists.",
                "Official SAP status comes from the school's financial-aid office."
            ],
            nextSteps: [
                "Confirm GPA and maximum-timeframe rules with the school.",
                "Ask about appeal options if there were documented circumstances.",
                "Avoid withdrawals that would lower completed/attempted credit pace."
            ],
            policyEvidence: evidence
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Explained SAP policy using completion-rate status \(status).",
            errorMessage: nil
        )
    }
}

@MainActor
struct ExtractAidDocumentFactsTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "extractAidDocumentFacts",
        description: "Tell the model which financial-aid document facts to extract from local attachments.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{\"documentType?\":\"award letter|bill|verification request|FAFSA summary|state-aid notice\"}",
        outputSchemaDescription: "supportedDocumentTypes, factsToExtract, privacyNote, nextPrompt",
        sourceLabel: "AssistantAttachmentIngestor local attachment text"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let payload = AidDocumentFactsPayload(
            supportedDocumentTypes: ["award letter", "student bill", "verification request", "FAFSA summary", "state-aid notice"],
            factsToExtract: ["aid year", "grants/scholarships", "loans", "work-study", "estimated cost", "missing documents", "deadlines", "required action"],
            privacyNote: "Attachments are processed locally for assistant context; do not upload passwords or full government IDs.",
            nextPrompt: "Attach the document and ask what each aid item means or what action is required."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared local aid-document extraction checklist.",
            errorMessage: nil
        )
    }
}

@MainActor
struct CompareAwardLetterToPlannerTool: AIAssistantTool {
    let descriptor = AssistantToolDescriptor(
        name: "compareAwardLetterToPlanner",
        description: "Compare award-letter review questions against planner signals such as credits, SAP, and active program.",
        allowedPersonas: [.financialAdvisor],
        mode: .read,
        requiresConfirmation: false,
        confirmationStyle: .none,
        inputSchemaDescription: "{}",
        outputSchemaDescription: "checks, plannerSignals, questionsForAidOffice, disclaimer",
        sourceLabel: "AssistantPlannerSnapshot + SAP/full-time policy"
    )

    func execute(
        arguments: [String : AssistantJSONValue],
        context: AssistantToolExecutionContext
    ) async throws -> AssistantToolResultEnvelope {
        let sap = context.collegePersistence.sapStats()
        let programs = context.snapshot.programs.map(\.name)
        let payload = AwardPlannerComparisonPayload(
            checks: [
                "Does the award assume full-time enrollment?",
                "Are loans separated from grants and scholarships?",
                "Are any documents or verification steps still missing?",
                "Does the aid year match the planned semester?"
            ],
            plannerSignals: [
                "Declared programs: \(programs.isEmpty ? "not found in snapshot" : programs.joined(separator: ", "))",
                "SAP completion rate: \(sap.attempted == 0 ? "not enough history" : "\(Int((sap.rate * 100).rounded()))%")"
            ],
            questionsForAidOffice: [
                "Is this award final or estimated?",
                "What changes if credits or housing status change?",
                "Are there pending verification or SAP requirements?"
            ],
            disclaimer: "The assistant can compare visible planner signals, but the school determines the official package."
        )
        return AssistantToolResultEnvelope(
            tool: descriptor.name,
            ok: true,
            result: try resultObject(payload),
            source: descriptor.sourceLabel,
            summary: "Prepared award-letter comparison checks against planner and SAP signals.",
            errorMessage: nil
        )
    }
}

