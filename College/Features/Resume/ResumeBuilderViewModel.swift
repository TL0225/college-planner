// ResumeBuilderViewModel.swift
// Feature: Resume
// Purpose: Observable state for the Resume Builder window.

import CryptoKit
import Foundation
import Observation
import SwiftUI

enum ResumeCompileState: Equatable, Sendable {
    case idle
    case compiling
    case failed(message: String)
}

@MainActor
@Observable
final class ResumeBuilderViewModel {
    var document: ResumeDocument
    var selectedCategory: ResumeSectionKind = .personal
    var showAdvancedSource = false

    var previewData: Data?
    var compileState: ResumeCompileState = .idle
    var usingFallback = CollegeTypst.isUsingFallbackRenderer
    var profileIsStale = false
    var emptySectionWarnings: [ResumeSectionKind] = []
    var hasUnsavedChanges = false

    private(set) var linkedVaultDocumentID: UUID?
    private var capturedRevisionToken: String
    private var compileTask: Task<Void, Never>?
    private var lastSuccessfulSourceHash: String?
    private var generatedTypstSource = ""
    private let template = StandardATSTemplate()
    private let collegePersistence: CollegePersistence

    init(snapshot: ResumeSnapshot, collegePersistence: CollegePersistence) {
        self.linkedVaultDocumentID = nil
        self.document = ResumeDocument.seed(from: snapshot)
        self.capturedRevisionToken = snapshot.profileRevisionToken
        self.collegePersistence = collegePersistence
        CollegeTypst.assertProductionTypstLinked()
        scheduleCompile(immediate: true)
    }

    init(
        restoredDocument: ResumeDocument,
        collegePersistence: CollegePersistence,
        linkedVaultDocumentID: UUID
    ) {
        self.linkedVaultDocumentID = linkedVaultDocumentID
        self.document = restoredDocument
        self.capturedRevisionToken = restoredDocument.baseSnapshot.profileRevisionToken
        self.collegePersistence = collegePersistence
        self.hasUnsavedChanges = false
        CollegeTypst.assertProductionTypstLinked()
        scheduleCompile(immediate: true)
    }

    var snapshot: ResumeSnapshot {
        ResumeDocumentCompiler.mergedSnapshot(from: document)
    }

    var orderedSections: [ResumeSectionKind] {
        document.sectionOrder
    }

    var addedSections: Set<ResumeSectionKind> {
        Set(document.sectionOrder)
    }

    var paletteSections: [ResumeSectionKind] {
        ResumeSectionKind.orderableCases
    }

    var completedChecklistCount: Int {
        ResumeSectionKind.checklistCases.filter(isSectionComplete).count
    }

    var totalChecklistCount: Int {
        ResumeSectionKind.checklistCases.count
    }

    func sectionCount(for kind: ResumeSectionKind) -> Int {
        let snap = snapshot
        switch kind {
        case .personal: return snap.personal.name.isEmpty ? 0 : 1
        case .summary: return trimmed(snap.summary) == nil ? 0 : 1
        case .education: return snap.education.count
        case .experience: return snap.experiences.count
        case .projects: return snap.projects.count
        case .skills: return snap.skills.count
        case .achievements: return snap.achievements.count
        case .certifications: return snap.certifications.count
        case .extracurriculars: return snap.extracurriculars.count
        }
    }

    func hasEntries(for kind: ResumeSectionKind) -> Bool {
        sectionCount(for: kind) > 0
    }

    func isSectionComplete(_ kind: ResumeSectionKind) -> Bool {
        guard document.isSectionIncluded(kind) else { return false }
        return hasEntries(for: kind)
    }

    func sectionSubtitle(for kind: ResumeSectionKind) -> String {
        let count = sectionCount(for: kind)
        switch kind {
        case .personal:
            return snapshot.personal.name.isEmpty ? "No name yet" : snapshot.personal.name
        case .summary:
            return count == 0 ? "No summary yet" : "Summary added"
        case .education:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 school" : "\(count) schools")
        case .experience:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 role" : "\(count) roles")
        case .projects:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 project" : "\(count) projects")
        case .skills:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 skill" : "\(count) skills")
        case .achievements:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 award" : "\(count) awards")
        case .certifications:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 credential" : "\(count) credentials")
        case .extracurriculars:
            return count == 0 ? "No entries yet" : (count == 1 ? "1 activity" : "\(count) activities")
        }
    }

    func selectCategory(_ kind: ResumeSectionKind) {
        selectedCategory = kind
    }

    func updateTitle(_ title: String) {
        document.title = title
        document.touch()
        hasUnsavedChanges = true
    }

    func setFieldOverride(_ value: String?, for key: ResumeFieldKey) {
        document.setFieldOverride(value, for: key)
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func fieldValue(for key: ResumeFieldKey, default defaultValue: String = "") -> String {
        if let override = document.fieldOverride(for: key) {
            return override
        }
        return defaultValue
    }

    func updateStyle(_ transform: (inout ResumeDocumentStyle) -> Void) {
        transform(&document.style)
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func setShowAdvancedSource(_ enabled: Bool) {
        showAdvancedSource = enabled
        if !enabled, document.typstSourceMode == .manual {
            document.typstSourceMode = .generated
            scheduleCompile()
        }
    }

    func setTypstSourceMode(_ mode: TypstSourceMode) {
        document.typstSourceMode = mode
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func updateManualTypstSource(_ source: String) {
        document.manualTypstSource = source
        document.typstSourceMode = .manual
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func resetManualSourceToGenerated() {
        document.typstSourceMode = .generated
        document.manualTypstSource = nil
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func addSection(_ kind: ResumeSectionKind) {
        guard kind != .personal, !document.sectionOrder.contains(kind) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            document.sectionOrder.append(kind)
            if !document.sectionConfigs.contains(where: { $0.kind == kind }) {
                document.sectionConfigs.append(ResumeSectionConfig(kind: kind))
            }
            document.touch()
        }
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func placeSection(_ kind: ResumeSectionKind, before target: ResumeSectionKind?) {
        guard kind != .personal else { return }

        var nextOrder = document.sectionOrder
        nextOrder.removeAll { $0 == kind }

        if let target, let index = nextOrder.firstIndex(of: target) {
            nextOrder.insert(kind, at: index)
        } else {
            nextOrder.append(kind)
        }

        guard nextOrder != document.sectionOrder else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            document.sectionOrder = nextOrder
            if !document.sectionConfigs.contains(where: { $0.kind == kind }) {
                document.sectionConfigs.append(ResumeSectionConfig(kind: kind))
            }
            document.touch()
        }
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func removeSection(_ kind: ResumeSectionKind) {
        guard kind != .personal else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            document.sectionOrder.removeAll { $0 == kind }
            document.sectionConfigs.removeAll { $0.kind == kind }
            document.touch()
        }
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func moveSections(from source: IndexSet, to destination: Int) {
        document.sectionOrder.move(fromOffsets: source, toOffset: destination)
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func resetOrder() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            document.sectionOrder = ResumeSectionKind.orderableCases
            document.sectionConfigs = ResumeSectionKind.orderableCases.map { ResumeSectionConfig(kind: $0) }
            document.touch()
        }
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func moveEntry(in section: ResumeSectionKind, from source: IndexSet, to destination: Int) {
        switch section {
        case .education:
            document.baseSnapshot.education.move(fromOffsets: source, toOffset: destination)
        case .experience:
            document.baseSnapshot.experiences.move(fromOffsets: source, toOffset: destination)
        case .projects:
            document.baseSnapshot.projects.move(fromOffsets: source, toOffset: destination)
        case .achievements:
            document.baseSnapshot.achievements.move(fromOffsets: source, toOffset: destination)
        case .extracurriculars:
            document.baseSnapshot.extracurriculars.move(fromOffsets: source, toOffset: destination)
        default:
            return
        }
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func placeEntry(_ entryID: UUID, in section: ResumeSectionKind, before targetID: UUID?) {
        guard let fromIndex = entryIndex(entryID, in: section) else { return }
        var indices = entryIndices(in: section)
        guard fromIndex < indices.count else { return }
        let moving = indices.remove(at: fromIndex)
        if let targetID, let targetIndex = indices.firstIndex(of: targetID) {
            indices.insert(moving, at: targetIndex)
        } else {
            indices.append(moving)
        }
        applyEntryOrder(indices, in: section)
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    private func entryIndex(_ id: UUID, in section: ResumeSectionKind) -> Int? {
        switch section {
        case .education: return document.baseSnapshot.education.firstIndex(where: { $0.id == id })
        case .experience: return document.baseSnapshot.experiences.firstIndex(where: { $0.id == id })
        case .projects: return document.baseSnapshot.projects.firstIndex(where: { $0.id == id })
        case .achievements: return document.baseSnapshot.achievements.firstIndex(where: { $0.id == id })
        case .extracurriculars: return document.baseSnapshot.extracurriculars.firstIndex(where: { $0.id == id })
        default: return nil
        }
    }

    private func entryIndices(in section: ResumeSectionKind) -> [UUID] {
        switch section {
        case .education: return document.baseSnapshot.education.map(\.id)
        case .experience: return document.baseSnapshot.experiences.map(\.id)
        case .projects: return document.baseSnapshot.projects.map(\.id)
        case .achievements: return document.baseSnapshot.achievements.map(\.id)
        case .extracurriculars: return document.baseSnapshot.extracurriculars.map(\.id)
        default: return []
        }
    }

    private func applyEntryOrder(_ ids: [UUID], in section: ResumeSectionKind) {
        switch section {
        case .education:
            let map = Dictionary(uniqueKeysWithValues: document.baseSnapshot.education.map { ($0.id, $0) })
            document.baseSnapshot.education = ids.compactMap { map[$0] }
        case .experience:
            let map = Dictionary(uniqueKeysWithValues: document.baseSnapshot.experiences.map { ($0.id, $0) })
            document.baseSnapshot.experiences = ids.compactMap { map[$0] }
        case .projects:
            let map = Dictionary(uniqueKeysWithValues: document.baseSnapshot.projects.map { ($0.id, $0) })
            document.baseSnapshot.projects = ids.compactMap { map[$0] }
        case .achievements:
            let map = Dictionary(uniqueKeysWithValues: document.baseSnapshot.achievements.map { ($0.id, $0) })
            document.baseSnapshot.achievements = ids.compactMap { map[$0] }
        case .extracurriculars:
            let map = Dictionary(uniqueKeysWithValues: document.baseSnapshot.extracurriculars.map { ($0.id, $0) })
            document.baseSnapshot.extracurriculars = ids.compactMap { map[$0] }
        default:
            break
        }
    }

    func addCertification() {
        let nextIndex = maxCertificationOverrideIndex() + 1
        document.fieldOverrides[ResumeFieldKey.certification(nextIndex).storageKey] = ""
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func addExtracurricular() {
        let entry = ResumeExtracurricularEntry(
            id: UUID(),
            organization: "Organization",
            role: nil,
            dateRange: nil,
            descriptionText: nil
        )
        document.baseSnapshot.extracurriculars.append(entry)
        document.touch()
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func scheduleCompileFromView() {
        hasUnsavedChanges = true
        scheduleCompile()
    }

    func markSaved() {
        hasUnsavedChanges = false
    }

    func linkVaultDocument(_ documentID: UUID) {
        linkedVaultDocumentID = documentID
        markSaved()
    }

    func savePlatformVariant(
        for platform: JobBoardPlatform,
        collegePersistence: CollegePersistence
    ) async throws {
        let snapshot = ResumeDocumentCompiler.mergedSnapshot(from: document)
        var canonical = ResumeCanonicalProfile.from(snapshot: snapshot)
        let result = ResumePageBudgetEngine.adaptWithBudget(profile: canonical, platform: platform)
        canonical = result.adaptedProfile

        guard let documentID = linkedVaultDocumentID,
              let doc = try? collegePersistence.vaultRepository.fetchDocument(id: documentID)
        else { return }

        var meta = collegePersistence.careerResumeMetadata(for: doc)
        ResumePlatformVariants.save(profile: canonical, platform: platform, metadata: &meta)
        try collegePersistence.setCareerResumeMetadata(meta, for: doc)
        collegePersistence.bumpCareerRevision()
        ProductAnalytics.track(.resumePlatformVariantCreated, properties: ["platform": platform.rawValue])
    }

    func requiresManualResetConfirmation() -> Bool {
        ResumeExportReadiness.requiresManualResetConfirmation(
            typstSourceMode: document.typstSourceMode,
            manualTypstSource: document.manualTypstSource,
            generatedTypstSource: generatedTypstSource
        )
    }

    func refreshSnapshot() {
        guard let fresh = try? ResumeSnapshotBuilder.build(collegePersistence: collegePersistence) else {
            return
        }
        document.baseSnapshot = fresh
        document.sourceProfileID = fresh.sourceProfileID
        capturedRevisionToken = fresh.profileRevisionToken
        profileIsStale = false
        document.touch()
        scheduleCompile(immediate: true)
    }

    func checkProfileStaleness() {
        guard let current = ResumeSnapshotBuilder.currentRevisionToken(collegePersistence: collegePersistence) else {
            return
        }
        profileIsStale = current != capturedRevisionToken
    }

    func currentPDFData() -> Data? {
        previewData
    }

    func currentTypstSource() -> String {
        generatedTypstSource
    }

    func buildMetadata() -> ResumeBuildMetadata {
        ResumeBuildMetadata.make(
            snapshot: snapshot,
            orderedSections: document.sectionOrder,
            templateID: document.templateID,
            typstSource: generatedTypstSource
        )
    }

    func defaultExportFilename() -> String {
        let name = document.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let safeName = name.isEmpty ? "Resume" : name
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Resume_\(safeName)_\(formatter.string(from: Date())).pdf"
    }

    // MARK: - Compile pipeline

    private func scheduleCompile(immediate: Bool = false) {
        compileTask?.cancel()
        compileTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }
            await self.runCompile()
        }
    }

    private func runCompile() async {
        let renderModel = ResumeRenderModel.make(document: document)
        emptySectionWarnings = renderModel.includedEmptySectionKinds

        let source = ResumeDocumentCompiler.typstSource(from: document, template: template)
        generatedTypstSource = source

        let sourceHash = Self.sha256(source)
        if sourceHash == lastSuccessfulSourceHash, previewData != nil {
            compileState = .idle
            return
        }

        compileState = .compiling

        do {
            let pdf = try await Task.detached(priority: .userInitiated) {
                try CollegeTypst.compilePDF(typstSource: source)
            }.value

            guard !Task.isCancelled else { return }
            previewData = pdf
            lastSuccessfulSourceHash = sourceHash
            compileState = .idle
            usingFallback = CollegeTypst.isUsingFallbackRenderer
        } catch let error as ResumeCompileError {
            guard !Task.isCancelled else { return }
            compileState = .failed(message: error.userMessage)
        } catch {
            guard !Task.isCancelled else { return }
            compileState = .failed(message: error.localizedDescription)
        }
    }

    private func maxCertificationOverrideIndex() -> Int {
        document.fieldOverrides.keys
            .filter { $0.hasPrefix("certification.") }
            .compactMap { Int($0.replacingOccurrences(of: "certification.", with: "")) }
            .max() ?? snapshot.certifications.count - 1
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
