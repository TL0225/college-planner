// CareerApplicationFormSheet.swift
// Feature: Career / Applications
// Purpose: Add/edit job application form sheet.

import SwiftUI
import CollegeCareer

struct CareerApplicationFormSheet: View {
    @Environment(AppContainer.self) private var appContainer
        private var collegePersistence: CollegePersistence { appContainer.persistence }
    @Environment(\.dismiss) private var dismiss
    let existingApplicationID: UUID?

    @State private var title = ""
    @State private var company = ""
    @State private var postingURL = ""
    @State private var descriptionText = ""
    @State private var deadline = Date()
    @State private var status: CareerApplicationStatus = .interested
    @State private var interviewStatus = ""
    /// Maps to local store `baseSalaryText` (AI ingest · offer inspector share this field).
    @State private var baseSalaryText = ""
    /// Maps to local store `locationText` — job location string, unrelated to bonuses.
    @State private var locationText = ""
    @State private var offerBonusText = ""
    @State private var offerSigningText = ""
    @State private var offerEquityText = ""
    @State private var isExtracting = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case title, company, url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Job Title", text: $title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .company }
                    TextField("Company", text: $company)
                        .focused($focusedField, equals: .company)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                    TextField("Interview Status", text: $interviewStatus)
                    Picker("Pipeline", selection: $status) {
                        ForEach(CareerApplicationStatus.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                }
                Section("Details") {
                    DatePicker("Application Deadline", selection: $deadline, displayedComponents: .date)
                    TextField("Posting URL", text: $postingURL)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.done)
                        .onSubmit { saveAndDismiss() }
                    TextField("Location", text: $locationText, prompt: Text("City / region (from posting)"))
                    TextField("Base compensation (optional)", text: $baseSalaryText, prompt: Text("e.g. 175000 or $175k /yr"))
                    if isExtracting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 120)
                }

                if status == .offer {
                    Section("Offer breakdown") {
                        TextField("Annual bonus target (optional)", text: $offerBonusText)
                        TextField("Signing bonus (optional)", text: $offerSigningText)
                        TextField("Equity notes (optional)", text: $offerEquityText, axis: .vertical)
                            .lineLimit(3...10)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Application")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
        .onAppear {
            focusedField = .title
            hydrateExistingIfNeeded()
        }
        .task(id: postingURL) {
            let trimmed = postingURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URL(string: trimmed) != nil, !trimmed.isEmpty else {
                isExtracting = false
                return
            }
            isExtracting = true
            do {
                try await Task.sleep(for: .milliseconds(500))
                if company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    company = inferCompany(from: trimmed)
                }
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = inferTitle(from: trimmed)
                }
            } catch { }
            isExtracting = false
        }
    }

    private func saveAndDismiss() {
        do {
            if let existingApplicationID,
               let app = collegePersistence.jobApplication(id: existingApplicationID) {
                let baseTrim = baseSalaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                let locationTrim = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
                app.title = title
                app.company = company
                app.postingURLString = postingURL
                app.jobDescriptionText = descriptionText
                app.interviewStatus = interviewStatus
                app.applicationDeadline = deadline
                app.statusRaw = status.rawValue
                app.updatedAt = Date()
                app.baseSalaryText = baseTrim.isEmpty ? nil : baseTrim
                app.locationText = locationTrim.isEmpty ? nil : locationTrim
                persistOfferTexts(to: app)
                collegePersistence.save()
            } else {
                let row = try collegePersistence.addCareerApplication(
                    title: title,
                    company: company,
                    postingURLString: postingURL,
                    jobDescriptionText: descriptionText,
                    interviewStatus: interviewStatus,
                    applicationDeadline: deadline,
                    status: status
                )
                let baseTrim = baseSalaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                let locationTrim = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
                row.baseSalaryText = baseTrim.isEmpty ? nil : baseTrim
                row.locationText = locationTrim.isEmpty ? nil : locationTrim
                persistOfferTexts(to: row)
                row.updatedAt = Date()
                collegePersistence.save()
            }
            dismiss()
        } catch {
            AppLogger.shared.error("CareerApplicationFormSheet save failed: \(error)")
        }
    }

    private func hydrateExistingIfNeeded() {
        guard let existingApplicationID,
              let app = collegePersistence.jobApplication(id: existingApplicationID)
        else { return }
        title = app.title ?? ""
        company = app.company ?? ""
        postingURL = app.postingURLString ?? ""
        descriptionText = app.jobDescriptionText ?? ""
        interviewStatus = app.interviewStatus ?? ""
        deadline = app.applicationDeadline ?? Date()
        status = CareerApplicationStatus(rawValue: app.statusRaw) ?? .interested
        baseSalaryText = app.baseSalaryText ?? ""
        locationText = app.locationText ?? ""
        let offerPkg = collegePersistence.careerOfferCompensationPackage(for: app)
        offerBonusText = offerPkg.bonusText
        offerSigningText = offerPkg.signingText
        offerEquityText = offerPkg.equityText
    }

    private func persistOfferTexts(to app: JobApplication) {
        let pkg = CareerOfferCompensationPackage(
            bonusText: offerBonusText.trimmingCharacters(in: .whitespacesAndNewlines),
            signingText: offerSigningText.trimmingCharacters(in: .whitespacesAndNewlines),
            equityText: offerEquityText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        collegePersistence.setCareerOfferCompensationPackage(pkg, for: app)
    }

    private func inferCompany(from urlString: String) -> String {
        guard let host = URL(string: urlString)?.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first?.capitalized ?? ""
    }

    private func inferTitle(from urlString: String) -> String {
        guard let path = URL(string: urlString)?.pathComponents.last else { return "New Role" }
        return path.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

