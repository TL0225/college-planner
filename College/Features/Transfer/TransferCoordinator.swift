// TransferCoordinator.swift
// Feature: Transfer
// Purpose: Transfer Database — orchestrates official refresh, community import, and scoring.
// Data: Bridges source engines, TransferRepository, confidence, and academics impact.

import Foundation
import Observation

/// Coordinates the Transfer Database: runs official source refreshes (aggregator-first), imports
/// community datasets, validates proofs, and recomputes scored results + requirement impact.
@Observable
@MainActor
final class TransferCoordinator {
    let persistence: CollegePersistence
    let scene: TransferSceneState
    private let bridge: TransferAcademicsBridge
    private let communityService: CommunityTransferImportService
    private let urlSession: URLSession
    private let proofAcceptanceScore: Double = 0.55

    init(
        persistence: CollegePersistence = .shared,
        scene: TransferSceneState,
        bridge: TransferAcademicsBridge? = nil,
        communityService: CommunityTransferImportService = CommunityTransferImportService(),
        urlSession: URLSession = .shared
    ) {
        self.persistence = persistence
        self.scene = scene
        self.bridge = bridge ?? TransferAcademicsBridge(persistence: persistence)
        self.communityService = communityService
        self.urlSession = urlSession
    }

    // MARK: - Setup

    /// Resolves the target school from the active university and loads any stored results.
    func bootstrap() {
        scene.targetSchool = bridge.resolveTargetSchool()
        reloadResults()
    }

    // MARK: - Official refresh

    /// Runs official source engines in aggregator-first order, persisting deduped equivalencies.
    func refreshOfficial(sourceSchoolName: String? = nil) async {
        await BackgroundServiceOnDemand.run(id: "transfer_refresh") {
            await self.refreshOfficialImpl(sourceSchoolName: sourceSchoolName)
        }
    }

    private func refreshOfficialImpl(sourceSchoolName: String? = nil) async {
        let sourceName = (sourceSchoolName ?? scene.sourceSchoolName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        scene.sourceSchoolName = sourceName

        guard let target = scene.targetSchool ?? bridge.resolveTargetSchool() else {
            scene.refreshStatus = .failed
            scene.lastErrorMessage = TransferError.missingTargetSchool.localizedDescription
            return
        }
        scene.targetSchool = target

        guard !sourceName.isEmpty else {
            scene.refreshStatus = .failed
            scene.lastErrorMessage = TransferError.missingSourceSchool.localizedDescription
            return
        }

        let sourceManifest = bridge.matchManifest(named: sourceName)
        let sourceID = sourceManifest?.id ?? TransferNormalization.normalizeSchoolID(sourceName)
        let input = TransferEvaluationInput(
            sourceSchoolID: sourceID,
            sourceSchoolName: sourceManifest?.name ?? sourceName,
            targetSchoolID: target.id,
            targetSchoolName: target.name,
            degreeLevel: persistence.primaryDegreeLevel(default: "undergraduate"),
            mode: scene.mode
        )

        let availability = bridge.targetAvailability()
        let engines = OfficialTransferSourceRouter.engines(for: availability, session: urlSession)
        scene.routesAttempted = OfficialTransferSourceRouter.orderedRoutes(for: availability)
        scene.refreshStatus = .running
        scene.lastErrorMessage = nil

        let session = TransferScrapeSession(mode: input.mode)
        var collected: [TransferEquivalencyDTO] = []
        var failures = 0
        var throttled = false

        for engine in engines {
            do {
                let dtos = try await engine.fetchEquivalencies(input: input, session: session)
                collected.append(contentsOf: dtos)
            } catch TransferError.throttled {
                throttled = true
                failures += 1
                AppLogger.shared.error("Transfer source \(engine.sourceKind.rawValue) throttled", category: .network)
            } catch {
                failures += 1
                AppLogger.shared.error(
                    "Transfer source \(engine.sourceKind.rawValue) failed: \(error.localizedDescription)",
                    category: .network
                )
            }
        }

        if !collected.isEmpty {
            persistence.upsertTransferEquivalencies(collected)
        }

        reloadResults()
        scene.lastRefreshedAt = .now

        if throttled {
            scene.refreshStatus = .throttled
        } else if collected.isEmpty {
            scene.refreshStatus = failures > 0 ? .failed : .success
            if failures > 0 { scene.lastErrorMessage = TransferError.emptyResult.localizedDescription }
        } else {
            scene.refreshStatus = failures > 0 ? .partial : .success
        }
    }

    // MARK: - Community import

    @discardableResult
    func importCommunity(fileURL: URL) async -> Int {
        await BackgroundServiceOnDemand.runReturning(id: "community_transfer_import") {
            self.importCommunityImpl(fileURL: fileURL)
        }
    }

    @discardableResult
    private func importCommunityImpl(fileURL: URL) -> Int {
        do {
            let dtos = try communityService.decode(fileURL: fileURL)
            let count = persistence.upsertTransferEquivalencies(dtos)
            reloadResults()
            return count
        } catch {
            scene.lastErrorMessage = error.localizedDescription
            AppLogger.shared.error("Community transfer import failed: \(error.localizedDescription)", category: .persistence)
            return 0
        }
    }

    @discardableResult
    func importBundledCommunitySample() async -> Int {
        await BackgroundServiceOnDemand.runReturning(id: "community_transfer_import") {
            self.importBundledCommunitySampleImpl()
        }
    }

    @discardableResult
    private func importBundledCommunitySampleImpl() -> Int {
        do {
            let dtos = try communityService.loadBundledFixture()
            let count = persistence.upsertTransferEquivalencies(dtos)
            reloadResults()
            return count
        } catch {
            scene.lastErrorMessage = error.localizedDescription
            return 0
        }
    }

    func exportLocalDataset() -> Data? {
        let dtos = persistence.transferEquivalencyDTOs(targetSchoolID: scene.targetSchool?.id)
        return try? communityService.export(dtos)
    }

    // MARK: - Proof

    @discardableResult
    func validateAndAttachProof(
        equivalencyID: UUID,
        proofDocumentID: UUID,
        pdfURL: URL
    ) -> TransferProofValidationResult {
        let result = TransferProofValidator.validate(
            pdfAt: pdfURL,
            expectedUniversityName: scene.targetSchool?.name
        )
        persistence.recordTransferProof(
            equivalencyID: equivalencyID,
            proofDocumentID: proofDocumentID,
            validation: result
        )
        reloadResults()
        return result
    }

    // MARK: - Recompute

    /// Reloads stored equivalencies, recomputes scored results, and rebuilds requirement impact.
    func reloadResults() {
        let target = scene.targetSchool
        let sourceID = scene.sourceSchoolName.isEmpty
            ? nil
            : (bridge.matchManifest(named: scene.sourceSchoolName)?.id
                ?? TransferNormalization.normalizeSchoolID(scene.sourceSchoolName))

        let models = persistence.fetchTransferEquivalencies(
            targetSchoolID: target?.id,
            sourceSchoolID: sourceID
        )
        let repo = persistence.transferRepository
        let dtos = models.map(repo.makeDTO(from:))

        // Build per-equivalency proof + override signals from the stored records.
        var proofByID: [UUID: TransferCourseMatcher.ProofSignal] = [:]
        var overridesByKey: [String: Int] = [:]
        for model in models {
            if let override = model.confidenceOverride {
                overridesByKey[model.dedupeKey] = Int(override)
            }
            guard model.proofDocumentID != nil else { continue }
            if let proof = (try? repo.fetchProofRecords(equivalencyID: model.id))?.first {
                proofByID[model.id] = TransferCourseMatcher.ProofSignal(
                    hasValidatedProof: proof.validationScore >= proofAcceptanceScore,
                    score: proof.validationScore
                )
            }
        }

        let results = TransferCourseMatcher.results(
            from: dtos,
            proofSignal: { proofByID[$0.id] ?? .none },
            overrides: overridesByKey
        )
        scene.results = results

        let impact = TransferRequirementsImpactBuilder.build(
            requirements: bridge.requirementTargets(),
            planCourses: bridge.planCourses(),
            results: results
        )
        scene.impactRows = impact
    }

    // MARK: - Submission

    enum ManualEntrySaveResult: Equatable {
        case saved(proofNote: String?)
        case validationFailed(String)
        case missingTargetSchool
    }

    @discardableResult
    func saveManualEntry(_ draft: TransferManualEntryDraft, proofPDFURL: URL?) async -> ManualEntrySaveResult {
        if let error = draft.validationError() {
            return .validationFailed(error)
        }

        let trimmedSource = draft.sourceSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        scene.sourceSchoolName = trimmedSource

        let targetName = draft.targetSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifest = bridge.matchManifest(named: targetName)
        scene.targetSchool = TransferTargetSchool(
            id: manifest?.id ?? TransferNormalization.normalizeSchoolID(targetName),
            name: manifest?.name ?? targetName
        )

        let dto = draft.makeDTO(degreeLevel: persistence.primaryDegreeLevel(default: "undergraduate"))
        _ = persistence.upsertTransferEquivalencies([dto])

        var proofNote: String?
        if let proofPDFURL {
            proofNote = await attachProofPDF(proofPDFURL, for: dto)
        }

        reloadResults()
        scene.lastErrorMessage = nil
        return .saved(proofNote: proofNote)
    }

    @MainActor
    private func attachProofPDF(_ url: URL, for dto: TransferEquivalencyDTO) async -> String? {
        let dedupeKey = TransferNormalization.dedupeKey(for: dto)
        guard let equivalency = try? persistence.transferRepository.fetchEquivalency(dedupeKey: dedupeKey) else {
            return "Equivalency saved, but the proof PDF could not be linked."
        }

        do {
            let document = try await persistence.addVaultDocumentReturning(
                fromSelectedURL: url,
                category: .transferProof,
                source: "transfer-manual-entry"
            )
            guard let pdfURL = persistence.decryptedTempURLForStoredRelativePath(
                document.localRelativePath,
                displayFileName: document.fileName
            ) else {
                return "Proof PDF saved to Documents."
            }
            let validation = validateAndAttachProof(
                equivalencyID: equivalency.id,
                proofDocumentID: document.id,
                pdfURL: pdfURL
            )
            if validation.isAcceptable {
                return "Proof PDF validated and attached."
            }
            let score = Int((validation.score * 100).rounded())
            return "Proof PDF attached (validation score \(score)%)."
        } catch {
            AppLogger.shared.error(
                "Transfer manual entry proof import failed: \(error.localizedDescription)",
                category: .persistence
            )
            return "Equivalency saved, but proof PDF import failed: \(error.localizedDescription)"
        }
    }

    func deleteManualEntry(dedupeKey: String) {
        guard let model = try? persistence.transferRepository.fetchEquivalency(dedupeKey: dedupeKey) else {
            return
        }
        persistence.deleteTransferEquivalency(id: model.id)
        reloadResults()
    }

    func submissionURL(for result: TransferCourseResult) -> URL? {
        communitySubmissionURL(for: result)
    }

    func batchSubmissionURL() -> URL? {
        guard let target = scene.targetSchool else { return nil }
        let sourceID = scene.sourceSchoolName.isEmpty
            ? nil
            : (bridge.matchManifest(named: scene.sourceSchoolName)?.id
                ?? TransferNormalization.normalizeSchoolID(scene.sourceSchoolName))
        let dtos = persistence.transferEquivalencyDTOs(targetSchoolID: target.id)
            .filter { dto in
                guard let sourceID else { return true }
                return dto.sourceSchoolID == sourceID
            }
        return TransferSubmissionURLBuilder.batchIssueURL(for: dtos)
    }

    func communitySubmissionURL(for result: TransferCourseResult) -> URL? {
        guard let target = scene.targetSchool else { return nil }
        let dto = TransferEquivalencyDTO(
            sourceSchoolID: TransferNormalization.normalizeSchoolID(scene.sourceSchoolName),
            sourceSchoolName: scene.sourceSchoolName,
            sourceCourseCode: result.sourceCourseCode,
            sourceCourseTitle: result.sourceCourseTitle,
            sourceCredits: result.sourceCredits,
            targetSchoolID: target.id,
            targetSchoolName: target.name,
            targetCourseCode: result.targetCourseCode,
            targetCourseTitle: result.targetCourseTitle,
            targetCredits: result.targetCredits,
            equivalencyKind: result.equivalencyKind,
            degreeLevel: persistence.primaryDegreeLevel(default: "undergraduate"),
            sourceTier: .community,
            sourceKind: .communityImport,
            externalID: result.dedupeKey
        )
        return TransferSubmissionURLBuilder.issueURL(for: dto)
    }
}
