// LogInteractionSheet.swift
// Feature: Career
// Purpose: Career module — LogInteractionSheet.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

enum InteractionType: String, CaseIterable {
    case coffeeChat = "Coffee Chat"
    case email = "Email"
    case linkedIn = "LinkedIn"
    case phoneCall = "Phone Call"
    case inPerson = "In Person"
    case referral = "Referral"

    var iconName: String {
        switch self {
        case .coffeeChat: return "cup.and.saucer.fill"
        case .email: return "envelope.fill"
        case .linkedIn: return "arrow.up.right.square.fill"
        case .phoneCall: return "phone.fill"
        case .inPerson: return "person.2.fill"
        case .referral: return "paperplane.fill"
        }
    }

    /// Stable `CareerEvent.kindRaw` token for timeline styling.
    var kindRaw: String {
        switch self {
        case .coffeeChat: return "coffee"
        case .email: return "email"
        case .linkedIn: return "linkedin"
        case .phoneCall: return "phone"
        case .inPerson: return "inperson"
        case .referral: return "referral"
        }
    }
}

/// Modal sheet to log a networking touchpoint for a recruiter contact.
struct LogInteractionSheet: View {
    @Environment(AppContainer.self) private var container
    @Bindable var contact: RecruiterContact

    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: InteractionType = .email
    @State private var interactionDate: Date = .init()
    @State private var notesText: String = ""

    private var notesAreEmpty: Bool {
        notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let typeGridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    typeSection
                    dateSection
                    notesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()
                .opacity(0.35)

            footerBar
                .padding(DesignSystem.Spacing.lg)
        }
        .frame(width: 460)
        .background(sheetChromeBackground)
    }

    private var sheetChromeBackground: Color {
        DesignSystem.Colors.surface
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Log Interaction")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(DesignSystem.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Type grid

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: typeGridColumns, spacing: 12) {
                ForEach(InteractionType.allCases, id: \.self) { kind in
                    typeCell(kind)
                }
            }
        }
    }

    private func typeCell(_ kind: InteractionType) -> some View {
        let isSelected = selectedType == kind
        return Button {
            selectedType = kind
        } label: {
            VStack(spacing: 10) {
                Image(systemName: kind.iconName)
                    .font(DesignSystem.Fonts.main(size: 22, weight: .semibold))
                Text(kind.rawValue)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                DatePicker("", selection: $interactionDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "calendar")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes *")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ZStack(alignment: .topLeading) {
                if notesAreEmpty {
                    Text("What did you discuss?")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notesText)
                    .font(.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    persistAndDismiss()
                } label: {
                    Text("Log")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(notesAreEmpty ? Color.white.opacity(0.85) : .white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(logButtonFill)
                        )
                }
                .buttonStyle(.plain)
                .disabled(notesAreEmpty)
            }
        }
    }

    private var logButtonFill: Color {
        if notesAreEmpty {
            return Color.secondary.opacity(0.38)
        }
        return DesignSystem.Colors.primary
    }

    // MARK: - Persistence

    private func persistAndDismiss() {
        let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try persistence.careerRepository.logInteraction(
                for: contact,
                kindRaw: selectedType.kindRaw,
                date: interactionDate,
                notes: trimmed
            )
            contact.lastInteractionChannelRaw = selectedType.rawValue
            dismiss()
        } catch {
            #if DEBUG
            print("[LogInteractionSheet] save failed: \(error)")
            #endif
        }
    }
}
