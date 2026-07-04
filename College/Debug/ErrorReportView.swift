// ErrorReportView.swift
// Feature: Debug
// Purpose: Debug module — ErrorReportView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct ErrorReportView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.dismiss) var dismiss
    private var collegePersistence: CollegePersistence { container.persistence }
    let policyName: String
    let currentValue: String
    let schoolID: String
    let schoolName: String
    
    @State private var correctedValue: String = ""
    @State private var source: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccess: Bool = false
    @State private var localErrorMessage: String? = nil
    
    private let githubService = GitHubDataService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Report Policy Error", systemImage: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textMain)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 24))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(DesignSystem.Colors.surface)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                        // School Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("School")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            
                            HStack {
                                Image(systemName: "building.columns.fill")
                                    .foregroundStyle(DesignSystem.Colors.primary)
                                Text(schoolName)
                                    .font(DesignSystem.Fonts.main(size: 14))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "f8f9fa"))
                            .clipShape(.rect(cornerRadius: 8))
                        }
                        
                        // Policy Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Policy")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            
                            Text(policyName)
                                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textMain)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "f8f9fa"))
                                .clipShape(.rect(cornerRadius: 8))
                        }
                        
                        // Current Value
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Value (Incorrect)")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(DesignSystem.Colors.error)
                                Text(currentValue)
                                    .font(DesignSystem.Fonts.main(size: 14))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignSystem.Colors.error.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DesignSystem.Colors.error.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Corrected Value
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Correct Value *")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            
                            TextField("Enter correct value", text: $correctedValue)
                                .textFieldStyle(.plain)
                                .font(DesignSystem.Fonts.main(size: 14))
                                .padding()
                                .background(DesignSystem.Colors.surface)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                )
                        }
                        
                        // Source
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source (Optional)")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundStyle(DesignSystem.Colors.textLight)
                            
                            TextField("e.g., Advisor meeting, Course catalog page 42", text: $source)
                                .textFieldStyle(.plain)
                                .font(DesignSystem.Fonts.main(size: 14))
                                .padding()
                                .background(DesignSystem.Colors.surface)
                                .clipShape(.rect(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                )
                            
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .foregroundStyle(DesignSystem.Colors.info)
                                Text("Adding a source helps verify the correction faster")
                                    .font(DesignSystem.Fonts.main(size: 11))
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                            }
                        }
                        
                        // Info Box
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(DesignSystem.Colors.primary)
                                .font(DesignSystem.Fonts.main(size: 16))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Help the Community")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundStyle(DesignSystem.Colors.textMain)
                                
                                Text("Your correction will be reviewed and shared with other students at \(schoolName)")
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .foregroundStyle(DesignSystem.Colors.textLight)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding()
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .padding()
                }
                
                Divider()
                
                // Footer Actions
                HStack(spacing: 12) {
                    Button(action: fixLocalOnly) {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Fix Locally Only")
                        }
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textMain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "f1f5f9"))
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .disabled(correctedValue.isEmpty || isSubmitting)
                    
                    Button(action: submitToGitHub) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                            Text("Submit to Community")
                        }
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            correctedValue.isEmpty || isSubmitting
                            ? DesignSystem.Colors.primary.opacity(0.5)
                            : DesignSystem.Colors.primary
                        )
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .disabled(correctedValue.isEmpty || isSubmitting)
                }
                .padding()
                .background(DesignSystem.Colors.surface)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 700)
        .overlay {
            if showSuccess {
                SuccessOverlay(message: "Thank you! Your correction has been submitted.")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showSuccess = false
                            dismiss()
                        }
                    }
            }
        }
        .alert(
            "Couldn’t Apply Correction",
            isPresented: Binding(
                get: { localErrorMessage != nil },
                set: { if !$0 { localErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(localErrorMessage ?? "Unknown error")
            }
        )
    }
    
    // MARK: - Actions
    
    private func fixLocalOnly() {
        // This immediately fixes the issue for this user.
        do {
            try collegePersistence.applyPolicyCorrection(
                universityName: schoolName,
                policyName: policyName,
                correctedValue: correctedValue
            )
            print("✅ Fixed locally: \(policyName) = \(correctedValue)")
            dismiss()
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }
    
    private func submitToGitHub() {
        guard !correctedValue.isEmpty else { return }
        
        isSubmitting = true
        
        let correction = PolicyCorrection(
            schoolID: schoolID,
            policyName: policyName,
            currentValue: currentValue,
            correctedValue: correctedValue,
            source: source.isEmpty ? nil : source,
            submittedBy: "anonymous",
            submittedDate: Date()
        )
        
        // Open GitHub in browser with pre-filled issue
        githubService.submitCorrection(correction)
        
        // Also fix locally
        fixLocalOnly()
        
        // Show success message
        showSuccess = true
        isSubmitting = false
    }
}

struct SuccessOverlay: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(DesignSystem.Fonts.main(size: 60))
                .foregroundStyle(DesignSystem.Colors.success)
            
            Text(message)
                .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textMain)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.Spacing.section)
        .background(DesignSystem.Colors.surface)
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
}

// MARK: - Preview Provider

#Preview {
    ErrorReportView(
        policyName: "Transfer Credit Limit",
        currentValue: "6 credits maximum",
        schoolID: "rutgers_nb",
        schoolName: "Rutgers University - New Brunswick"
    )
    }
