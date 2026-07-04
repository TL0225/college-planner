// CareerApplyFieldReviewSheet.swift
// Feature: Career / Apply
// Purpose: Pre-apply review — user approves every field before web view opens.

import SwiftUI

struct CareerApplyFieldReviewSheet: View {
    let payload: CareerApplicationAutofillPayload
    let onApprove: (CareerApplicationAutofillPayload) -> Void
    let onCancel: () -> Void

    @State private var draft: CareerApplicationAutofillPayload

    init(
        payload: CareerApplicationAutofillPayload,
        onApprove: @escaping (CareerApplicationAutofillPayload) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.payload = payload
        self.onApprove = onApprove
        self.onCancel = onCancel
        _draft = State(initialValue: payload)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    LabeledContent("Name", value: draft.personal.fullName)
                    TextField("Email", text: emailBinding)
                    TextField("Phone", text: phoneBinding)
                }
                Section("Screening (this session)") {
                    toggleRow("US authorized to work", keyPath: \.usAuthorized)
                    toggleRow("Requires sponsorship now", keyPath: \.requiresSponsorshipNow)
                }
                Section("Resume") {
                    LabeledContent("Document", value: draft.documents.resumeFileName)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Review apply fields")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start apply") {
                        draft.approvedAt = Date()
                        onApprove(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func toggleRow(_ title: String, keyPath: WritableKeyPath<ApplyWorkAuthorization, Bool?>) -> some View {
        Picker(title, selection: boolBinding(keyPath)) {
            Text("Not set").tag(Optional<Bool>.none)
            Text("Yes").tag(Optional(true))
            Text("No").tag(Optional(false))
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ApplyWorkAuthorization, Bool?>) -> Binding<Bool?> {
        Binding(
            get: { draft.applicationProfile.workAuthorization[keyPath: keyPath] },
            set: { draft.applicationProfile.workAuthorization[keyPath: keyPath] = $0 }
        )
    }

    private var emailBinding: Binding<String> {
        Binding(
            get: { draft.personal.email ?? "" },
            set: { draft.personal.email = $0.isEmpty ? nil : $0 }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { draft.personal.phone ?? "" },
            set: { draft.personal.phone = $0.isEmpty ? nil : $0 }
        )
    }
}
