// AddSemesterView.swift
// Feature: Courses
// Purpose: Courses module — AddSemesterView.
// Data: CollegePersistence / repositories when applicable.

// AddSemesterView.swift
// Custom modal that creates a semester (and optionally a few starter courses)
// in one shot. Visual language mirrors the Academics page: purple gradient
// banner header, dark navy CTA, and the AcademicsStatusPalette colors for
// the Planned / In Progress / Completed states. The view is rendered inside
// a window-level sheet (see ContentView.addSemesterSheetPresented), so this
// component is responsible only for the card itself.

import SwiftUI

struct AddSemesterView: View {
    @Binding var isPresented: Bool
    let plan: PlannerPlan
    @EnvironmentObject var collegePersistence: CollegePersistence
    @EnvironmentObject var notifications: AppNotificationCenter
    @Environment(ModalCoordinator.self) var modalCoordinator

    // MARK: - Local state

    @State private var selectedSeason: Season = .fall
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedStatus: SemesterStatus = .planned

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBanner
            bodyScroll
            footerBar
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 30, x: 0, y: 14)
    }

    // MARK: - Header banner

    private var headerBanner: some View {
        ZStack(alignment: .topLeading) {
            // Indigo → purple gradient matching the Figma header.
            LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.36, blue: 0.93),   // indigo-500ish
                    Color(red: 0.55, green: 0.42, blue: 0.96)    // purple-500ish
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Big translucent season-letters watermark on the right.
            HStack {
                Spacer()
                Text(selectedSeason.letters)
                    .font(.system(size: 110, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.10))
                    .padding(.trailing, 18)
                    .padding(.top, -8)
                    .accessibilityHidden(true)
            }

            // Foreground content.
            VStack(alignment: .leading, spacing: 12) {
                Text("\(selectedSeason.rawValue.uppercased()) SEMESTER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.85))

                Text(String(selectedYear))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                statusChip
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 20)

            // Close button.
            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
        }
        .frame(height: 160)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Image(systemName: selectedStatus.iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(selectedStatus.rawValue)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(Color.white)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Scrollable body

    private var bodyScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                seasonAndYearRow
                statusCardsRow
                Divider().opacity(0.6)
                coursesSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: 460)
    }

    // MARK: Season + year stepper

    private var seasonAndYearRow: some View {
        HStack(spacing: 10) {
            ForEach(Season.allCases) { season in
                SeasonPill(
                    title: season.rawValue,
                    isSelected: season == selectedSeason
                ) {
                    selectedSeason = season
                }
            }

            Spacer(minLength: 0)

            yearStepper
        }
    }

    private var yearStepper: some View {
        HStack(spacing: 8) {
            stepperButton(symbol: "minus") {
                selectedYear = max(2000, selectedYear - 1)
            }
            Text(String(selectedYear))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 50)
            stepperButton(symbol: "plus") {
                selectedYear = min(2099, selectedYear + 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func stepperButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Status cards

    private var statusCardsRow: some View {
        HStack(spacing: 10) {
            ForEach(SemesterStatus.allCases) { status in
                StatusCard(
                    status: status,
                    isSelected: status == selectedStatus
                ) {
                    selectedStatus = status
                }
            }
        }
    }

    // MARK: Courses section

    /// The "Add Course" button creates the semester immediately and routes to
    /// the existing app-wide Add Course modal via `ModalCoordinator`. That keeps
    /// the catalog-aware course picker as the single source of truth for course
    /// entry instead of duplicating an inline draft form here.
    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("COURSES")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                addCourseEntrypointButton
            }

            emptyCoursesState
        }
    }

    private var emptyCoursesState: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.secondary.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text("No courses yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Use Add Course to pick from the catalog after the semester is created.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var addCourseEntrypointButton: some View {
        Button {
            beginAddCourseFlow()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Add Course")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Color.primary)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Create the semester and open the Add Course picker")
    }

    // MARK: Footer

    private var footerBar: some View {
        HStack(spacing: 10) {
            footerSummary
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(.primary)
            .keyboardShortcut(.cancelAction)

            Button {
                commitSemester()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Semester")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(Color.white)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.88))
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    private var footerSummary: some View {
        Text("Creates an empty \(selectedSeason.rawValue) \(String(selectedYear)) semester.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Actions

    /// Eagerly persists the semester and hands control to the standard
    /// `addCatalogCourse` modal scoped to the new semester. Anything the user
    /// did NOT click "Add Course" for is just discarded by tapping Cancel —
    /// only confirmation creates a row.
    private func beginAddCourseFlow() {
        let semester = persistSemester(showToast: false)
        let semesterID = semester.id
        isPresented = false
        DispatchQueue.main.async {
            modalCoordinator.activeModal = .addCatalogCourse(semesterID: semesterID)
        }
    }

    private func commitSemester() {
        _ = persistSemester(showToast: true)
        isPresented = false
    }

    @discardableResult
    private func persistSemester(showToast: Bool) -> PlannerSemester {
        let semesterName = "\(selectedSeason.rawValue) \(String(selectedYear))"
        let semester = collegePersistence.addSemester(
            to: plan,
            name: semesterName,
            year: selectedYear,
            season: selectedSeason.rawValue
        )
        if showToast {
            notifications.post(
                kind: .success,
                title: "Semester Added",
                message: "Created \(semesterName).",
                isDismissible: true,
                autoDismissAfter: 3
            )
        }
        return semester
    }
}

// MARK: - Local types

extension AddSemesterView {
    enum Season: String, CaseIterable, Identifiable {
        case fall = "Fall"
        case spring = "Spring"
        case summer = "Summer"
        case winter = "Winter"
        var id: String { rawValue }
        var letters: String {
            switch self {
            case .fall: return "FA"
            case .spring: return "SP"
            case .summer: return "SU"
            case .winter: return "WI"
            }
        }
    }

    enum SemesterStatus: String, CaseIterable, Identifiable {
        case planned = "Planned"
        case inProgress = "In Progress"
        case completed = "Completed"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .planned:    return "calendar"
            case .inProgress: return "clock"
            case .completed:  return "checkmark.circle"
            }
        }

        var subtitle: String {
            switch self {
            case .planned:    return "Future semester"
            case .inProgress: return "Currently enrolled"
            case .completed:  return "Already finished"
            }
        }

        var paletteState: AcademicsStatusPalette.State {
            switch self {
            case .planned:    return .planned
            case .inProgress: return .inProgress
            case .completed:  return .completed
            }
        }
    }
}

// MARK: - Subviews

private struct SeasonPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected
                              ? Color(red: 0.06, green: 0.10, blue: 0.18)
                              : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? Color.clear : Color.secondary.opacity(0.22),
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct StatusCard: View {
    let status: AddSemesterView.SemesterStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: status.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accentColor.opacity(isSelected ? 0.18 : 0.10))
                    )
                Text(status.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? accentColor : Color.primary)
                Text(status.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var accentColor: Color {
        // The Figma uses a stronger lavender for the dots/icons inside this sheet
        // than `AcademicsStatusPalette.dot(for:)` returns, so we lean on the
        // pill-foreground hues which carry more saturation.
        switch status {
        case .planned:    return AcademicsStatusPalette.plannedPillFG
        case .inProgress: return AcademicsStatusPalette.inProgressPillFG
        case .completed:  return AcademicsStatusPalette.completedPillFG
        }
    }
}

