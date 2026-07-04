// VaultUploadSheet.swift
// Feature: Core
// Purpose: Core module — VaultUploadMetadata.
// Data: CollegePersistence / repositories when applicable.

// VaultUploadSheet.swift
// Category, tag, and color-label picker shown when a user imports a new file into the vault.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Upload metadata model

struct VaultUploadMetadata {
    var category: VaultDocumentCategory
    var customDisplayName: String
    var tags: [String]
    var colorLabel: VaultColorLabel
    var notes: String
}

// MARK: - Color label model

enum VaultColorLabel: String, CaseIterable, Identifiable {
    case none    = "None"
    case red     = "Red"
    case orange  = "Orange"
    case yellow  = "Yellow"
    case green   = "Green"
    case blue    = "Blue"
    case purple  = "Purple"
    case gray    = "Gray"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .none:   return .clear
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return DesignSystem.Colors.success
        case .blue:   return .blue
        case .purple: return .purple
        case .gray:   return .gray
        }
    }

    var systemIcon: String {
        self == .none ? "circle.dashed" : "circle.fill"
    }
}

// MARK: - Category model (separate from CollegePersistenceLegacy.VaultDocumentCategory for UI use)

enum VaultDocumentCategory: String, CaseIterable, Identifiable {
    case syllabi     = "Syllabi"
    case transcripts = "Transcripts"
    case calendar    = "Calendar"
    case other       = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .syllabi:     return "doc.text.fill"
        case .transcripts: return "graduationcap.fill"
        case .calendar:    return "calendar"
        case .other:       return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .syllabi:     return DesignSystem.Colors.primary
        case .transcripts: return DesignSystem.Colors.accent
        case .calendar:    return DesignSystem.Colors.success
        case .other:       return DesignSystem.Colors.secondary
        }
    }
}

// MARK: - Sheet view

struct VaultUploadSheet: View {
    let fileName: String
    let fileSize: Int64
    let fileExtension: String
    let onConfirm: (VaultUploadMetadata) -> Void
    let onCancel: () -> Void

    @State private var category: VaultDocumentCategory = Self.inferCategory(from: "")
    @State private var customName: String = ""
    @State private var tagsText: String = ""
    @State private var colorLabel: VaultColorLabel = .none
    @State private var notes: String = ""
    @State private var focusTag: Bool = false

    private let accentPink = Color(hex: "FF1A7F")
    private var parsedTags: [String] {
        tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fileIconColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: fileIcon)
                        .font(DesignSystem.Fonts.main(size: 24))
                        .foregroundStyle(fileIconColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(fileName)
                        .font(DesignSystem.Fonts.main(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .lineLimit(1)
                    Text(formatBytes(fileSize))
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(hex: "e2e8f0")), alignment: .bottom)

            // Body
            ScrollView {
                VStack(spacing: 20) {

                    // Custom name
                    fieldGroup(title: "Display Name") {
                        TextField("Leave blank to use file name", text: $customName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Category
                    fieldGroup(title: "Category") {
                        HStack(spacing: 8) {
                            ForEach(VaultDocumentCategory.allCases) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: cat.icon)
                                            .font(DesignSystem.Fonts.main(size: 12))
                                        Text(cat.rawValue)
                                            .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(category == cat ? .white : DesignSystem.Colors.textMain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(category == cat ? cat.color : Color(hex: "f1f5f9"))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }

                    // Tags
                    fieldGroup(title: "Tags (comma separated)") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("e.g. Spring 2026, CSE 101, Final", text: $tagsText)
                                .textFieldStyle(.roundedBorder)
                            if !parsedTags.isEmpty {
                                FlowTagsView(tags: parsedTags, accentColor: accentPink)
                            }
                        }
                    }

                    // Color label
                    fieldGroup(title: "Color Label") {
                        HStack(spacing: 8) {
                            ForEach(VaultColorLabel.allCases) { label in
                                Button {
                                    colorLabel = label
                                } label: {
                                    ZStack {
                                        if label == .none {
                                            Circle()
                                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                                                .foregroundStyle(Color(hex: "94a3b8"))
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Circle()
                                                .fill(label.color)
                                                .frame(width: 24, height: 24)
                                        }
                                        if colorLabel == label {
                                            Image(systemName: "checkmark")
                                                .font(DesignSystem.Fonts.main(size: 9, weight: .bold))
                                                .foregroundStyle(label == .none ? DesignSystem.Colors.textLight : .white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .help(label.rawValue)
                            }
                            Spacer()
                        }
                    }

                    // Notes
                    fieldGroup(title: "Notes (optional)") {
                        TextEditor(text: $notes)
                            .font(DesignSystem.Fonts.main(size: 12))
                            .frame(height: 64)
                            .padding(DesignSystem.Spacing.sm)
                            .background(Color(hex: "f8fafc"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                            )
                    }
                }
                .padding(DesignSystem.Spacing.xl)
            }

            // Footer
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Spacer()
                Button("Add to Vault") {
                    let metadata = VaultUploadMetadata(
                        category: category,
                        customDisplayName: customName.trimmingCharacters(in: .whitespacesAndNewlines),
                        tags: parsedTags,
                        colorLabel: colorLabel,
                        notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onConfirm(metadata)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accentPink)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color(hex: "e2e8f0")), alignment: .top)
        }
        .frame(width: 480)
        .onAppear {
            category = Self.inferCategory(from: fileExtension)
            customName = ""
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textLight)
                .textCase(.uppercase)
                .tracking(0.3)
            content()
        }
    }

    private var fileIcon: String {
        switch fileExtension.lowercased() {
        case "pdf":         return "doc.text.fill"
        case "docx", "doc": return "doc.fill"
        case "jpg", "jpeg", "png": return "photo.fill"
        default:            return "doc.fill"
        }
    }

    private var fileIconColor: Color {
        switch fileExtension.lowercased() {
        case "pdf":         return DesignSystem.Colors.accent
        case "docx", "doc": return DesignSystem.Colors.primary
        case "jpg", "jpeg", "png": return DesignSystem.Colors.secondary
        default:            return DesignSystem.Colors.textLight
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func inferCategory(from ext: String) -> VaultDocumentCategory {
        switch ext.lowercased() {
        case "pdf", "docx", "doc": return .syllabi
        case "jpg", "jpeg", "png": return .other
        default:                   return .other
        }
    }
}

// MARK: - Flow tag layout

private struct FlowTagsView: View {
    let tags: [String]
    let accentColor: Color

    var body: some View {
        // Horizontal wrap using ViewThatFits-compatible approach
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
}
