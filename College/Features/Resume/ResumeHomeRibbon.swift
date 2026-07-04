// ResumeHomeRibbon.swift
// Feature: Resume
// Purpose: Word-like Home ribbon for typography and layout presets.

import SwiftUI

struct ResumeHomeRibbon: View {
    @Bindable var viewModel: ResumeBuilderViewModel
    var collegePersistence: CollegePersistence?

    var body: some View {
        HStack(spacing: 20) {
            ribbonGroup("Font") {
                Picker("Font", selection: fontPresetBinding) {
                    ForEach(ResumeFontPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            ribbonGroup("Size") {
                Stepper(value: bodySizeBinding, in: 8...14, step: 0.5) {
                    Text("\(viewModel.document.style.bodySize, specifier: "%.1f") pt")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 52, alignment: .leading)
                }
            }

            ribbonGroup("Margins") {
                Picker("Margins", selection: marginPresetBinding) {
                    ForEach(ResumeMarginPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            ribbonGroup("Line spacing") {
                Stepper(value: lineLeadingBinding, in: 0.45...1.0, step: 0.05) {
                    Text("\(viewModel.document.style.lineLeading, specifier: "%.2f")")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 40, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            if collegePersistence != nil {
                platformVariantMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.surface.opacity(0.65))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Resume formatting ribbon")
    }

    private var fontPresetBinding: Binding<ResumeFontPreset> {
        Binding(
            get: { viewModel.document.style.fontPreset },
            set: { newValue in
                viewModel.updateStyle { $0.fontPreset = newValue }
            }
        )
    }

    private var bodySizeBinding: Binding<Double> {
        Binding(
            get: { viewModel.document.style.bodySize },
            set: { newValue in
                viewModel.updateStyle { $0.bodySize = newValue }
            }
        )
    }

    private var marginPresetBinding: Binding<ResumeMarginPreset> {
        Binding(
            get: { viewModel.document.style.marginPreset },
            set: { newValue in
                viewModel.updateStyle { $0.applyMarginPreset(newValue) }
            }
        )
    }

    private var lineLeadingBinding: Binding<Double> {
        Binding(
            get: { viewModel.document.style.lineLeading },
            set: { newValue in
                viewModel.updateStyle { $0.lineLeading = newValue }
            }
        )
    }

    @ViewBuilder
    private func ribbonGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private var platformVariantMenu: some View {
        Menu {
            ForEach([JobBoardPlatform.workday, .greenhouse, .lever, .icims, .oracle], id: \.self) { platform in
                Button("Save \(platform.displayName) variant") {
                    guard let collegePersistence else { return }
                    Task {
                        try? await viewModel.savePlatformVariant(
                            for: platform,
                            collegePersistence: collegePersistence
                        )
                    }
                }
            }
        } label: {
            Label("Platform variants", systemImage: "square.stack.3d.up")
                .font(.caption.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .disabled(viewModel.linkedVaultDocumentID == nil)
        .help("Save an ATS-adapted canonical profile for a job board platform")
        .accessibilityLabel("Platform variants")
        .accessibilityHint(
            viewModel.linkedVaultDocumentID == nil
                ? "Save resume to library before creating platform variants"
                : "Save an ATS-adapted profile for a job board"
        )
    }
}
