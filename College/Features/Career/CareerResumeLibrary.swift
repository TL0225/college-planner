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

    static func atsTierColor(for percent: Int?) -> Color {
        guard let percent else { return .secondary }
        if percent >= Self.atsGreenMinimum { return .green }
        if percent >= Self.atsYellowMinimum { return .yellow }
        return .red
    }

    /// Green tier: ≥ 75, Yellow: 50–74, Red: &lt; 50 (Career workspace mock alignment).
    static let atsGreenMinimum = 75
    static let atsYellowMinimum = 50
}

struct CareerResumeMetadataV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case general
        case tailored
    }

    var kind: Kind
    var targetRole: String?
    var archived: Bool
    var atsScorePercent: Int?
    var atsScoredAt: Date?

    static let `default` = CareerResumeMetadataV1(kind: .general, targetRole: nil, archived: false, atsScorePercent: nil, atsScoredAt: nil)
}

// MARK: - Grid card

struct ResumeLibraryCard: View {
    let resume: VaultDocument
    let metadata: CareerResumeMetadataV1
    let usageCount: Int
    let onScoreATS: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleArchived: () -> Void
    let onSetKind: (CareerResumeMetadataV1.Kind) -> Void
    let onQuickLook: () -> Void

    private var displayTitle: String {
        let raw = resume.customDisplayName ?? resume.fileName
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Resume" : raw
    }

    private var keywordTokens: [String] {
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
                        Text(displayTitle)
                            .font(.headline)
                            .lineLimit(2)
                        if let role = metadata.targetRole?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty {
                            Text(role)
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
                        Text("ATS fit")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let p = metadata.atsScorePercent {
                            Text("\(p)%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(CareerResumeLibraryTheme.atsTierColor(for: p))
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if let p = metadata.atsScorePercent {
                        ProgressView(value: Double(min(100, max(0, p))), total: 100)
                            .tint(CareerResumeLibraryTheme.atsTierColor(for: p))
                    } else {
                        ProgressView(value: 0, total: 100)
                            .tint(.secondary.opacity(0.35))
                    }
                    Button("Score") { onScoreATS() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
            .padding(12)
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
