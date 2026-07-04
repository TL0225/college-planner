// CareerResumeLibrary.swift
// Feature: Career
// Purpose: Career module — CareerResumeMetadataV1.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

// MARK: - Resume library theme & metadata (Career workspace)

enum CareerResumeLibraryTheme {
    static var cardBackground: Color {
        DesignSystem.Colors.surface
    }

    static func accent(for kind: CareerResumeMetadataV1.Kind) -> Color {
        switch kind {
        case .general: return .blue
        case .tailored: return .purple
        }
    }

    static func parserHealthTierColor(for percent: Int?) -> Color {
        guard let percent else { return .secondary }
        if percent >= Self.parserHealthGreenMinimum { return .green }
        if percent >= Self.parserHealthYellowMinimum { return .yellow }
        return .red
    }

    static func jobMatchTierColor(for percent: Int?) -> Color {
        parserHealthTierColor(for: percent)
    }

    /// Green tier: ≥ 75, Yellow: 50–74, Red: &lt; 50.
    static let parserHealthGreenMinimum = 75
    static let parserHealthYellowMinimum = 50

    @available(*, deprecated, renamed: "parserHealthTierColor")
    static func atsTierColor(for percent: Int?) -> Color {
        parserHealthTierColor(for: percent)
    }

    static let atsGreenMinimum = parserHealthGreenMinimum
    static let atsYellowMinimum = parserHealthYellowMinimum
}

struct CareerResumeMetadataV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case general
        case tailored
    }

    var kind: Kind
    var targetRole: String?
    var archived: Bool
    var parserHealthPercent: Int?
    var parserScoredAt: Date?
    var parsedTextHash: String?
    var parserComplianceRaw: String?
    var parserIssuesJSON: String?
    var detectedDomainsJSON: String?
    var structuredSectionsJSON: String?
    var staleSkillsJSON: String?
    var ingestCompletedAt: Date?
    var ingestFailedAt: Date?
    /// JSON-encoded `ResumeBuildMetadata` when the resume was produced by the builder.
    var buildMetadataJSON: String?
    /// Full builder draft state (`ResumeDocument` JSON).
    var documentJSON: String?
    /// Structured profile interchange for match/apply fast-path.
    var canonicalProfileJSON: String?
    /// ATS platform hint for tailoring variants.
    var platformTarget: String?
    /// JSON map of platform rawValue → canonical profile JSON sidecar.
    var platformVariantsJSON: String?
    /// Source vault resume when this draft was forked (builder or tailor).
    var derivedFromDocumentID: UUID?

    enum CodingKeys: String, CodingKey {
        case kind, targetRole, archived
        case parserHealthPercent
        case parserScoredAt
        case atsScorePercent
        case atsScoredAt
        case parsedTextHash
        case parserComplianceRaw
        case parserIssuesJSON
        case detectedDomainsJSON
        case structuredSectionsJSON
        case staleSkillsJSON
        case ingestCompletedAt
        case ingestFailedAt
        case buildMetadataJSON
        case documentJSON
        case canonicalProfileJSON
        case platformTarget
        case platformVariantsJSON
        case derivedFromDocumentID
    }

    init(
        kind: Kind = .general,
        targetRole: String? = nil,
        archived: Bool = false,
        parserHealthPercent: Int? = nil,
        parserScoredAt: Date? = nil,
        parsedTextHash: String? = nil,
        parserComplianceRaw: String? = nil,
        parserIssuesJSON: String? = nil,
        detectedDomainsJSON: String? = nil,
        structuredSectionsJSON: String? = nil,
        staleSkillsJSON: String? = nil,
        ingestCompletedAt: Date? = nil,
        ingestFailedAt: Date? = nil,
        buildMetadataJSON: String? = nil,
        documentJSON: String? = nil,
        canonicalProfileJSON: String? = nil,
        platformTarget: String? = nil,
        platformVariantsJSON: String? = nil,
        derivedFromDocumentID: UUID? = nil
    ) {
        self.kind = kind
        self.targetRole = targetRole
        self.archived = archived
        self.parserHealthPercent = parserHealthPercent
        self.parserScoredAt = parserScoredAt
        self.parsedTextHash = parsedTextHash
        self.parserComplianceRaw = parserComplianceRaw
        self.parserIssuesJSON = parserIssuesJSON
        self.detectedDomainsJSON = detectedDomainsJSON
        self.structuredSectionsJSON = structuredSectionsJSON
        self.staleSkillsJSON = staleSkillsJSON
        self.ingestCompletedAt = ingestCompletedAt
        self.ingestFailedAt = ingestFailedAt
        self.buildMetadataJSON = buildMetadataJSON
        self.documentJSON = documentJSON
        self.canonicalProfileJSON = canonicalProfileJSON
        self.platformTarget = platformTarget
        self.platformVariantsJSON = platformVariantsJSON
        self.derivedFromDocumentID = derivedFromDocumentID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .general
        targetRole = try c.decodeIfPresent(String.self, forKey: .targetRole)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        parserHealthPercent = try c.decodeIfPresent(Int.self, forKey: .parserHealthPercent)
            ?? c.decodeIfPresent(Int.self, forKey: .atsScorePercent)
        parserScoredAt = try c.decodeIfPresent(Date.self, forKey: .parserScoredAt)
            ?? c.decodeIfPresent(Date.self, forKey: .atsScoredAt)
        parsedTextHash = try c.decodeIfPresent(String.self, forKey: .parsedTextHash)
        parserComplianceRaw = try c.decodeIfPresent(String.self, forKey: .parserComplianceRaw)
        parserIssuesJSON = try c.decodeIfPresent(String.self, forKey: .parserIssuesJSON)
        detectedDomainsJSON = try c.decodeIfPresent(String.self, forKey: .detectedDomainsJSON)
        structuredSectionsJSON = try c.decodeIfPresent(String.self, forKey: .structuredSectionsJSON)
        staleSkillsJSON = try c.decodeIfPresent(String.self, forKey: .staleSkillsJSON)
        ingestCompletedAt = try c.decodeIfPresent(Date.self, forKey: .ingestCompletedAt)
        ingestFailedAt = try c.decodeIfPresent(Date.self, forKey: .ingestFailedAt)
        buildMetadataJSON = try c.decodeIfPresent(String.self, forKey: .buildMetadataJSON)
        documentJSON = try c.decodeIfPresent(String.self, forKey: .documentJSON)
        canonicalProfileJSON = try c.decodeIfPresent(String.self, forKey: .canonicalProfileJSON)
        platformTarget = try c.decodeIfPresent(String.self, forKey: .platformTarget)
        platformVariantsJSON = try c.decodeIfPresent(String.self, forKey: .platformVariantsJSON)
        derivedFromDocumentID = try c.decodeIfPresent(UUID.self, forKey: .derivedFromDocumentID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(targetRole, forKey: .targetRole)
        try c.encode(archived, forKey: .archived)
        try c.encodeIfPresent(parserHealthPercent, forKey: .parserHealthPercent)
        try c.encodeIfPresent(parserScoredAt, forKey: .parserScoredAt)
        try c.encodeIfPresent(parsedTextHash, forKey: .parsedTextHash)
        try c.encodeIfPresent(parserComplianceRaw, forKey: .parserComplianceRaw)
        try c.encodeIfPresent(parserIssuesJSON, forKey: .parserIssuesJSON)
        try c.encodeIfPresent(detectedDomainsJSON, forKey: .detectedDomainsJSON)
        try c.encodeIfPresent(structuredSectionsJSON, forKey: .structuredSectionsJSON)
        try c.encodeIfPresent(staleSkillsJSON, forKey: .staleSkillsJSON)
        try c.encodeIfPresent(ingestCompletedAt, forKey: .ingestCompletedAt)
        try c.encodeIfPresent(ingestFailedAt, forKey: .ingestFailedAt)
        try c.encodeIfPresent(buildMetadataJSON, forKey: .buildMetadataJSON)
        try c.encodeIfPresent(documentJSON, forKey: .documentJSON)
        try c.encodeIfPresent(canonicalProfileJSON, forKey: .canonicalProfileJSON)
        try c.encodeIfPresent(platformTarget, forKey: .platformTarget)
        try c.encodeIfPresent(platformVariantsJSON, forKey: .platformVariantsJSON)
        try c.encodeIfPresent(derivedFromDocumentID, forKey: .derivedFromDocumentID)
    }

    static let `default` = CareerResumeMetadataV1()

    var buildMetadata: ResumeBuildMetadata? {
        guard let json = buildMetadataJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ResumeBuildMetadata.self, from: data)
        else { return nil }
        return decoded
    }

    /// Decodes the structured fields the resume parser recovered, if any.
    var structuredProfile: CareerResumeStructuredProfile? {
        guard let json = structuredSectionsJSON,
              let data = json.data(using: .utf8),
              let profile = try? JSONDecoder().decode(CareerResumeStructuredProfile.self, from: data),
              profile.hasContent
        else { return nil }
        return profile
    }

    /// Canonical structured profile for match/apply fast-path.
    var canonicalProfile: CareerResumeStructuredProfile? {
        if let json = canonicalProfileJSON,
           let data = json.data(using: .utf8),
           let profile = try? JSONDecoder().decode(CareerResumeStructuredProfile.self, from: data),
           profile.hasContent {
            return profile
        }
        return structuredProfile
    }
}

// MARK: - Grid card

struct ResumeLibraryCard: View {
    let resume: VaultDocument
    let metadata: CareerResumeMetadataV1
    let usageCount: Int
    let onReingest: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleArchived: () -> Void
    let onSetKind: (CareerResumeMetadataV1.Kind) -> Void
    let onQuickLook: () -> Void

    private var isIngesting: Bool {
        metadata.ingestCompletedAt == nil
    }

    private var displayTitle: String {
        let raw = resume.customDisplayName ?? resume.fileName
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Resume" : raw
    }

    private var keywordTokens: [String] {
        if let json = metadata.detectedDomainsJSON,
           let data = json.data(using: .utf8),
           let domains = try? JSONDecoder().decode([String].self, from: data),
           !domains.isEmpty {
            return Array(domains.prefix(4))
        }
        let raw = resume.tags ?? ""
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(parts.prefix(4))
    }

    private var lastUpdated: Date { resume.lastOpenedAt ?? resume.addedAt }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CareerResumeLibraryTheme.accent(for: metadata.kind)
                .frame(height: 4)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "doc.richtext")
                        .font(.title2)
                        .foregroundStyle(CareerResumeLibraryTheme.accent(for: metadata.kind))

                    VStack(alignment: .leading, spacing: 4) {
                        TranslatableText(text: displayTitle)
                            .font(.headline)
                            .lineLimit(2)
                        if let role = metadata.targetRole?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
                            TranslatableText(text: role)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: resume.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(resume.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(resume.isFavorite ? "Remove favorite" : "Mark favorite")

                    Menu {
                        Button("General") { onSetKind(.general) }
                        Button("Tailored") { onSetKind(.tailored) }
                        Divider()
                        Button(metadata.archived ? "Unarchive" : "Archive") { onToggleArchived() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 26)
                }

                HStack(spacing: 6) {
                    Text(metadata.kind == .general ? "General" : "Tailored")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CareerResumeLibraryTheme.accent(for: metadata.kind).opacity(0.12), in: Capsule())
                    if metadata.archived {
                        Text("Archived")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                    }
                }

                if !keywordTokens.isEmpty {
                    FlowKeywordRow(tokens: keywordTokens)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Parser health")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if isIngesting {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Analyzing…")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let p = metadata.parserHealthPercent {
                            Text("\(p)%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(CareerResumeLibraryTheme.parserHealthTierColor(for: p))
                        }
                    }
                    if let p = metadata.parserHealthPercent, !isIngesting {
                        ProgressView(value: Double(min(100, max(0, p))), total: 100)
                            .tint(CareerResumeLibraryTheme.parserHealthTierColor(for: p))
                    } else if isIngesting {
                        ProgressView(value: 0, total: 100)
                            .tint(.secondary.opacity(0.35))
                    }
                    if !isIngesting {
                        Button("Re-analyze") { onReingest() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Text("Updated \(Self.relative(lastUpdated))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Used ×\(usageCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
        .background(CareerResumeLibraryTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2) { onQuickLook() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTitle), \(metadata.kind.rawValue) resume")
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

private struct FlowKeywordRow: View {
    let tokens: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(tokens, id: \.self) { t in
                    Text(t)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tokens, id: \.self) { t in
                    Text(t)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
        }
    }
}
