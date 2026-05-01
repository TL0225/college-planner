import SwiftUI

struct AddSemesterView: View {
    @Binding var isPresented: Bool
    @ObservedObject var plan: PlanEntity
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter

    @State private var selectedTerm: String = "Fall"
    @State private var selectedAcademicYear: String = ""
    @State private var targetCredits: String = "15"
    @State private var prepopulateFromAudit: Bool = false

    let terms = ["Fall", "Spring", "Summer", "Winter"]

    var academicYears: [String] {
        let current = Calendar.current.component(.year, from: Date())
        return (current - 1 ... current + 6).map { "\($0) – \($0 + 1)" }
    }

    var defaultAcademicYear: String {
        let current = Calendar.current.component(.year, from: Date())
        return "\(current) – \(current + 1)"
    }

    var body: some View {
        content
        .onAppear {
            if selectedAcademicYear.isEmpty {
                selectedAcademicYear = defaultAcademicYear
            }
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Semester")
                .font(.title3.weight(.semibold))

            Text("Create a new term in your planner. You can add courses now or later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Academic Year")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("Academic Year", selection: $selectedAcademicYear) {
                        ForEach(academicYears, id: \.self) { year in
                            Text(year).tag(year)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Term")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("Term", selection: $selectedTerm) {
                        ForEach(terms, id: \.self) { term in
                            Text(term).tag(term)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Credits")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("15", text: $targetCredits)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Pre-populate from Audit", isOn: $prepopulateFromAudit)
                    .help("Automatically add recommended courses")

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("Will create: \(selectedTerm) \(parsedYearLabel())")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Semester") {
                    addSemester()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func parsedYearLabel() -> String {
        let yearString = selectedAcademicYear
            .components(separatedBy: CharacterSet(charactersIn: "–-–"))
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return yearString.isEmpty ? String(Calendar.current.component(.year, from: Date())) : yearString
    }

    private func addSemester() {
        // Parse start year from the academic year string (e.g. "2025 – 2026" → 2025)
        let yearString = selectedAcademicYear
            .components(separatedBy: CharacterSet(charactersIn: "–-–"))
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let year = Int(yearString) else {
            notifications.post(
                kind: .warning,
                title: "Invalid Year",
                message: "Please select a valid academic year.",
                isDismissible: true,
                autoDismissAfter: 4
            )
            return
        }
        let semesterName = "\(selectedTerm) \(year)"
        _ = coreDataManager.addSemester(to: plan, name: semesterName, year: year, season: selectedTerm)
        notifications.post(
            kind: .success,
            title: "Semester Added",
            message: "Created \(semesterName).",
            isDismissible: true,
            autoDismissAfter: 3
        )
        isPresented = false
    }
}
