// CareerApplicationProfileView.swift
// Feature: Career / ApplicationProfile
// Purpose: Career workspace Apply Profile tab (not Settings).

import SwiftUI

struct CareerApplicationProfileView: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var prefs: CareerApplicationPreferences?
    @State private var saveError: String?

    var body: some View {
        Form {
            if prefs != nil {
                Section("Work authorization") {
                    boolPicker("US citizen", value: bind(\.usCitizen))
                    boolPicker("Authorized to work in US", value: bind(\.usAuthorized))
                    boolPicker("Requires sponsorship now", value: bind(\.requiresSponsorshipNow))
                    boolPicker("Requires sponsorship in future", value: bind(\.requiresSponsorshipFuture))
                    TextField("Country of citizenship", text: stringBind(\.countryOfCitizenship))
                }
                Section("Application defaults") {
                    TextField("Willing to relocate", text: stringBind(\.willingToRelocate))
                    TextField("Remote preference", text: stringBind(\.remotePreference))
                    TextField("Salary expectation", text: stringBind(\.salaryExpectation))
                    TextField("Earliest start date", text: stringBind(\.earliestStartDate))
                }
                Section("EEO") {
                    Toggle("Allow EEO autofill (V2 — off in V1 writes)", isOn: bindBool(\.allowEEOAutofill))
                        .disabled(true)
                    Text("EEO autofill is manual-only in V1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Loading Apply Profile…")
            }
            if let saveError {
                Text(saveError).foregroundStyle(.red).font(.caption)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { save() }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let repo = CareerRepository(context: appContainer.persistence.profileContext)
        prefs = (try? repo.ensureApplicationPreferences())
    }

    private func save() {
        guard let prefs else { return }
        let repo = CareerRepository(context: appContainer.persistence.profileContext)
        do {
            try repo.saveApplicationPreferences(prefs)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<CareerApplicationPreferences, Bool?>) -> Binding<Bool?> {
        Binding(
            get: { prefs?[keyPath: keyPath] },
            set: { prefs?[keyPath: keyPath] = $0 }
        )
    }

    private func bindBool(_ keyPath: ReferenceWritableKeyPath<CareerApplicationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs?[keyPath: keyPath] ?? false },
            set: { prefs?[keyPath: keyPath] = $0 }
        )
    }

    private func stringBind(_ keyPath: ReferenceWritableKeyPath<CareerApplicationPreferences, String?>) -> Binding<String> {
        Binding(
            get: { prefs?[keyPath: keyPath] ?? "" },
            set: { prefs?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    @ViewBuilder
    private func boolPicker(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(title, selection: value) {
            Text("Not set").tag(Optional<Bool>.none)
            Text("Yes").tag(Optional(true))
            Text("No").tag(Optional(false))
        }
    }
}
