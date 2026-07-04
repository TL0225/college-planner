// ResumeTypstSourceEditor.swift
// Feature: Resume
// Purpose: Advanced Typst source panel for power users.

import SwiftUI

struct ResumeTypstSourceEditor: View {
    @Bindable var viewModel: ResumeBuilderViewModel
    @State private var draftSource = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Typst Source")
                    .font(.headline)
                Spacer()
                Picker("Mode", selection: modeBinding) {
                    Text("Generated").tag(TypstSourceMode.generated)
                    Text("Manual").tag(TypstSourceMode.manual)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                if viewModel.document.typstSourceMode == .manual {
                    Button("Reset from fields") {
                        viewModel.resetManualSourceToGenerated()
                        draftSource = viewModel.currentTypstSource()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text("Advanced editing changes the document source directly. Most people should use the form fields.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.document.typstSourceMode == .manual {
                TextEditor(text: $draftSource)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .onChange(of: draftSource) { _, newValue in
                        viewModel.updateManualTypstSource(newValue)
                    }
            } else {
                ScrollView {
                    Text(viewModel.currentTypstSource())
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .onAppear {
            draftSource = viewModel.currentTypstSource()
        }
        .onChange(of: viewModel.document.typstSourceMode) { _, _ in
            if viewModel.document.typstSourceMode == .generated {
                draftSource = viewModel.currentTypstSource()
            }
        }
        .onChange(of: viewModel.previewData) { _, _ in
            if viewModel.document.typstSourceMode == .generated {
                draftSource = viewModel.currentTypstSource()
            }
        }
    }

    private var modeBinding: Binding<TypstSourceMode> {
        Binding(
            get: { viewModel.document.typstSourceMode },
            set: { newValue in
                if newValue == .manual, draftSource.isEmpty {
                    draftSource = viewModel.currentTypstSource()
                    viewModel.updateManualTypstSource(draftSource)
                } else {
                    viewModel.setTypstSourceMode(newValue)
                }
            }
        )
    }
}
