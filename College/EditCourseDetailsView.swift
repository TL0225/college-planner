import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Modal sheet for editing a single course's details.
///
/// Data is persisted in `CourseOverrideEntity` so user edits are not overwritten by re-scrapes.
struct EditCourseDetailsView: View {
	@EnvironmentObject private var coreDataManager: CoreDataManager
	@EnvironmentObject private var notifications: AppNotificationCenter

	let courseCode: String
	let defaultCourseName: String
	let defaultCreditsText: String
	let onClose: () -> Void

	@State private var didLoadInitialValues = false

	@State private var courseName: String = ""
	@State private var professor: String = ""
	@State private var semesterYear: String = ""
	@State private var status: String = "Planned"
	@State private var creditsText: String = ""
	@State private var gradingType: String = "Letter Grade"
	@State private var externalURL: String = ""

	@State private var syllabusFileName: String? = nil
	@State private var syllabusFileSizeBytes: Int64 = 0
	@State private var syllabusUploadedAt: Date? = nil
	@State private var isPickingSyllabus: Bool = false

	private var normalizedCourseCode: String {
		courseCode
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
	}

	private var existingOverride: CourseOverrideEntity? {
		coreDataManager.getCourseOverride(courseCode: normalizedCourseCode)
	}

	private var plannedCourse: CourseEntity? {
		let needle = normalizedCourseCode
		return coreDataManager.plans
			.flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
			.first(where: {
				($0.code ?? "")
					.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
					.trimmingCharacters(in: .whitespacesAndNewlines)
					.uppercased() == needle
			})
	}

	private var catalogCourse: CourseCatalogEntity? {
		coreDataManager.getCatalogCourse(code: normalizedCourseCode)
	}

	private var resolvedCourseName: String {
		let fromCatalog = (catalogCourse?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		if !fromCatalog.isEmpty { return fromCatalog }
		let fromPlanned = (plannedCourse?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		if !fromPlanned.isEmpty { return fromPlanned }
		let fromDefault = defaultCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
		return fromDefault.isEmpty ? "Course" : fromDefault
	}

	private var resolvedCreditsText: String {
		if let catalogCourse {
			let txt = catalogCourse.creditsDisplayText
			return txt.isEmpty ? "-" : txt
		}
		let planned = Double(plannedCourse?.credits ?? 0)
		if planned > 0 {
			return String(format: "%.1f", planned)
		}
		let fromDefault = defaultCreditsText.trimmingCharacters(in: .whitespacesAndNewlines)
		return fromDefault.isEmpty ? "-" : fromDefault
	}

	private struct StatusOption: Identifiable {
		let id: String
		let title: String
		let color: Color
	}

	private var statusOptions: [StatusOption] {
		[
			.init(id: "Not Planned", title: "Not Planned", color: DesignSystem.Colors.textLight),
			.init(id: "Planned", title: "Planned", color: DesignSystem.Colors.info),
			.init(id: "In-Progress", title: "In-Progress", color: DesignSystem.Colors.warning),
			.init(id: "Completed", title: "Completed", color: DesignSystem.Colors.success),
			.init(id: "Dropped", title: "Dropped", color: DesignSystem.Colors.textLight)
		]
	}

	private func normalizedStatus(_ raw: String) -> String {
		let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if s == "In Progress" { return "In-Progress" }
		return s.isEmpty ? "Not Planned" : s
	}

	private func statusColor(for status: String) -> Color {
		let s = normalizedStatus(status)
		return statusOptions.first(where: { $0.id == s })?.color ?? DesignSystem.Colors.info
	}

	private var lastUpdatedDisplayText: String {
		guard let overrideEntity = existingOverride else { return "-" }
		guard let lastUpdated = overrideEntity.lastUpdated else { return "-" }
		return formatDate(lastUpdated)
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				header

				form
					.padding(.top, 16)

				footerButtons
					.padding(.top, 18)
			}
			.padding(24)
			.frame(maxWidth: 600)
			.background(
				RoundedRectangle(cornerRadius: 24)
					.fill(DesignSystem.Colors.surface)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 24)
					.stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
			)
		}
		.frame(maxWidth: 600, maxHeight: 700)
		.onAppear {
			loadInitialValuesIfNeeded()
		}
		.fileImporter(
			isPresented: $isPickingSyllabus,
			allowedContentTypes: [UTType.pdf],
			allowsMultipleSelection: false
		) { result in
			handlePickedSyllabus(result)
		}
	}

	private var header: some View {
		VStack(spacing: 0) {
			HStack(alignment: .top, spacing: 12) {
				ZStack {
					RoundedRectangle(cornerRadius: 14)
						.fill(DesignSystem.Colors.info.opacity(0.12))
						.frame(width: 56, height: 56)
					Image(systemName: "doc.text.fill")
						.font(.system(size: 20, weight: .bold))
						.foregroundColor(DesignSystem.Colors.info)
				}

				VStack(alignment: .leading, spacing: 6) {
					Text("Edit Course Details")
						.font(DesignSystem.Fonts.main(size: 18, weight: .bold))
						.foregroundColor(DesignSystem.Colors.textMain)

					HStack(spacing: 4) {
						Text("Update information for")
							.font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
							.foregroundColor(DesignSystem.Colors.textLight)
						Text(normalizedCourseCode)
							.font(DesignSystem.Fonts.main(size: 12, weight: .bold))
							.foregroundColor(DesignSystem.Colors.info)
					}

					HStack(spacing: 6) {
						Text("Last Updated:")
							.font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
							.foregroundColor(DesignSystem.Colors.textLight)
						Text(lastUpdatedDisplayText)
							.font(DesignSystem.Fonts.main(size: 12, weight: .bold))
							.foregroundColor(DesignSystem.Colors.textMain)
					}
				}

				Spacer()

				Button(action: { onClose() }) {
					Image(systemName: "xmark")
						.font(.system(size: 12, weight: .bold))
						.foregroundColor(DesignSystem.Colors.textLight)
						.frame(width: 34, height: 34)
						.background(DesignSystem.Colors.surface)
						.cornerRadius(999)
						.overlay(
							RoundedRectangle(cornerRadius: 999)
								.stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
						)
				}
				.buttonStyle(PlainButtonStyle())
			}
			.padding(.bottom, 16)

			Rectangle()
				.fill(DesignSystem.Colors.textLight.opacity(0.12))
				.frame(height: 1)
		}
	}

	private var form: some View {
		VStack(spacing: 16) {
			gridRow(
				left: labeledField(title: "Course Name") {
					styledTextField(text: .constant(resolvedCourseName), placeholder: "")
						.disabled(true)
						.opacity(0.95)
				},
				right: labeledField(title: "Course ID") {
					styledTextField(text: .constant(normalizedCourseCode), placeholder: "")
						.disabled(true)
						.opacity(0.9)
				}
			)

			gridRow(
				left: labeledField(title: "Professor") {
					iconTextField(systemImage: "person", text: $professor, placeholder: "")
				},
				right: labeledField(title: "Semester / Year") {
					iconTextField(systemImage: "calendar", text: $semesterYear, placeholder: "")
				}
			)

			gridRow(
				left: labeledField(title: "Status") {
					styledStatusPicker(selection: $status)
				},
				right: labeledField(title: "Credits") {
					styledTextField(text: .constant(resolvedCreditsText), placeholder: "")
						.disabled(true)
						.opacity(0.95)
				}
			)

			gridRow(
				left: labeledField(title: "Grading Type") {
					styledPicker(selection: $gradingType, options: ["Letter Grade", "Pass/Fail", "Audit"])
				},
				right: labeledField(title: "External URL") {
					iconTextField(systemImage: "link", text: $externalURL, placeholder: "https://")
				}
			)

			syllabusCard
		}
	}

	private var syllabusCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			if let syllabusFileName {
				HStack(spacing: 12) {
					ZStack {
						Circle()
							.fill(DesignSystem.Colors.surface)
							.frame(width: 40, height: 40)
							.overlay(
								Circle()
									.stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
							)
						Image(systemName: "doc.richtext")
							.font(.system(size: 16, weight: .bold))
							.foregroundColor(DesignSystem.Colors.error)
					}

					VStack(alignment: .leading, spacing: 2) {
						Text(syllabusFileName)
							.font(DesignSystem.Fonts.main(size: 12, weight: .bold))
							.foregroundColor(DesignSystem.Colors.textMain)

						if !syllabusSubtitle.isEmpty {
							Text(syllabusSubtitle)
								.font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
								.foregroundColor(DesignSystem.Colors.textLight)
						}
					}

					Spacer()

					HStack(spacing: 8) {
						Button(action: { openSyllabus() }) {
							Image(systemName: "eye")
								.font(.system(size: 14, weight: .bold))
								.foregroundColor(DesignSystem.Colors.textLight)
								.frame(width: 34, height: 34)
								.background(DesignSystem.Colors.surface)
								.cornerRadius(10)
								.overlay(
									RoundedRectangle(cornerRadius: 10)
										.stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
								)
						}
						.buttonStyle(PlainButtonStyle())

						Button(action: { deleteSyllabus() }) {
							Image(systemName: "trash")
								.font(.system(size: 14, weight: .bold))
								.foregroundColor(DesignSystem.Colors.textLight)
								.frame(width: 34, height: 34)
								.background(DesignSystem.Colors.surface)
								.cornerRadius(10)
								.overlay(
									RoundedRectangle(cornerRadius: 10)
										.stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
								)
						}
						.buttonStyle(PlainButtonStyle())
					}
				}

				Rectangle()
					.fill(DesignSystem.Colors.textLight.opacity(0.14))
					.frame(height: 1)

				Button(action: { isPickingSyllabus = true }) {
					HStack(spacing: 6) {
						Image(systemName: "square.and.arrow.up")
							.font(.system(size: 12, weight: .bold))
						Text("Upload New Version")
							.font(DesignSystem.Fonts.main(size: 11, weight: .bold))
					}
					.foregroundColor(DesignSystem.Colors.info)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 6)
				}
				.buttonStyle(PlainButtonStyle())
			} else {
				Button(action: { isPickingSyllabus = true }) {
					HStack(spacing: 12) {
						ZStack {
							Circle()
								.fill(DesignSystem.Colors.surface)
								.frame(width: 40, height: 40)
								.overlay(
									Circle()
										.stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
								)
							Image(systemName: "doc")
								.font(.system(size: 16, weight: .bold))
								.foregroundColor(DesignSystem.Colors.textLight)
						}

						VStack(alignment: .leading, spacing: 2) {
							Text("Upload Syllabus")
								.font(DesignSystem.Fonts.main(size: 12, weight: .bold))
								.foregroundColor(DesignSystem.Colors.textMain)
							Text("PDF")
								.font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
								.foregroundColor(DesignSystem.Colors.textLight)
						}

						Spacer()

						Image(systemName: "plus")
							.font(.system(size: 12, weight: .bold))
							.foregroundColor(DesignSystem.Colors.textLight)
					}
					.padding(14)
					.frame(maxWidth: .infinity)
					.background(DesignSystem.Colors.bgMain.opacity(0.45))
					.overlay(
						RoundedRectangle(cornerRadius: 14, style: .continuous)
							.stroke(
								DesignSystem.Colors.textLight.opacity(0.35),
								style: StrokeStyle(lineWidth: 1, dash: [6])
							)
					)
					.cornerRadius(14)
				}
				.buttonStyle(PlainButtonStyle())
			}
		}
		.padding(14)
		.background(DesignSystem.Colors.bgMain.opacity(0.35))
		.cornerRadius(14)
		.overlay(
			RoundedRectangle(cornerRadius: 14)
				.stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
		)
	}

	private var footerButtons: some View {
		HStack(spacing: 12) {
			Button(action: { onClose() }) {
				Text("Cancel")
					.font(DesignSystem.Fonts.main(size: 13, weight: .bold))
					.foregroundColor(DesignSystem.Colors.textMain)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
					.background(DesignSystem.Colors.textLight.opacity(0.12))
					.cornerRadius(14)
			}
			.buttonStyle(PlainButtonStyle())

			Button(action: { save() }) {
				Text("Save Changes")
					.font(DesignSystem.Fonts.main(size: 13, weight: .bold))
					.foregroundColor(.white)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 12)
					.background(DesignSystem.Colors.info)
					.cornerRadius(14)
			}
			.buttonStyle(PlainButtonStyle())
		}
	}

	// MARK: - Components

	private func gridRow<Left: View, Right: View>(left: Left, right: Right) -> some View {
		HStack(alignment: .top, spacing: 12) {
			left.frame(maxWidth: .infinity, alignment: .leading)
			right.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title.uppercased())
				.font(DesignSystem.Fonts.main(size: 10, weight: .bold))
				.foregroundColor(DesignSystem.Colors.textLight)

			content()
		}
	}

	private func styledTextField(text: Binding<String>, placeholder: String) -> some View {
		TextField(placeholder, text: text)
			.textFieldStyle(.plain)
			.font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
			.foregroundColor(DesignSystem.Colors.textMain)
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(DesignSystem.Colors.bgMain)
			.cornerRadius(12)
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.stroke(DesignSystem.Colors.textLight.opacity(0.22), lineWidth: 1)
			)
	}

	private func iconTextField(systemImage: String, text: Binding<String>, placeholder: String) -> some View {
		HStack(spacing: 10) {
			Image(systemName: systemImage)
				.font(.system(size: 14, weight: .bold))
				.foregroundColor(DesignSystem.Colors.textLight)

			TextField(placeholder, text: text)
				.textFieldStyle(.plain)
				.font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
				.foregroundColor(DesignSystem.Colors.textMain)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(DesignSystem.Colors.bgMain)
		.cornerRadius(12)
		.overlay(
			RoundedRectangle(cornerRadius: 12)
				.stroke(DesignSystem.Colors.textLight.opacity(0.22), lineWidth: 1)
		)
	}

	private func styledPicker(selection: Binding<String>, options: [String]) -> some View {
		return Menu {
			ForEach(options, id: \ .self) { option in
				Button(option) { selection.wrappedValue = option }
			}
		} label: {
			HStack {
				Text(selection.wrappedValue)
					.font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
					.foregroundColor(DesignSystem.Colors.textMain)
				Spacer()
				Image(systemName: "chevron.down")
					.font(.system(size: 12, weight: .bold))
					.foregroundColor(DesignSystem.Colors.textLight)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(DesignSystem.Colors.bgMain)
			.cornerRadius(12)
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.stroke(DesignSystem.Colors.textLight.opacity(0.22), lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func styledStatusPicker(selection: Binding<String>) -> some View {
		let current = normalizedStatus(selection.wrappedValue)
		return Menu {
			ForEach(statusOptions) { option in
				Button {
					selection.wrappedValue = option.id
				} label: {
					HStack(spacing: 10) {
						Circle()
							.fill(option.color)
							.frame(width: 10, height: 10)
						Text(option.title)
					}
				}
			}
		} label: {
			HStack(spacing: 10) {
				Circle()
					.fill(statusColor(for: current))
					.frame(width: 10, height: 10)
				Text(current)
					.font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
					.foregroundColor(DesignSystem.Colors.textMain)
				Spacer()
				Image(systemName: "chevron.down")
					.font(.system(size: 12, weight: .bold))
					.foregroundColor(DesignSystem.Colors.textLight)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.background(DesignSystem.Colors.bgMain)
			.cornerRadius(12)
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.stroke(DesignSystem.Colors.textLight.opacity(0.22), lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	// MARK: - Data

	private func loadInitialValuesIfNeeded() {
		guard !didLoadInitialValues else { return }
		didLoadInitialValues = true

		if let overrideEntity = existingOverride {
			courseName = resolvedCourseName
			professor = overrideEntity.professor ?? ""
			semesterYear = overrideEntity.semesterText ?? ""
			status = normalizedStatus(overrideEntity.status ?? "Not Planned")
			creditsText = resolvedCreditsText
			gradingType = overrideEntity.gradingType ?? "Letter Grade"
			externalURL = overrideEntity.externalURL ?? ""

			syllabusFileName = overrideEntity.syllabusFileName
			syllabusFileSizeBytes = overrideEntity.syllabusFileSizeBytes
			syllabusUploadedAt = overrideEntity.syllabusUploadedAt
			return
		}

		if let plannedCourse {
			courseName = resolvedCourseName
			professor = plannedCourse.professor ?? ""
			semesterYear = plannedSemesterText(from: plannedCourse)
			status = normalizedStatus(plannedCourse.status ?? "Planned")
			creditsText = resolvedCreditsText
			gradingType = plannedCourse.gradingType ?? "Letter Grade"
			externalURL = ""

			syllabusFileName = plannedCourse.syllabusFileName
			syllabusFileSizeBytes = 0
			syllabusUploadedAt = nil
			return
		}

		courseName = resolvedCourseName
		professor = ""
		semesterYear = ""
		status = "Not Planned"
		creditsText = resolvedCreditsText

		gradingType = "Letter Grade"
		externalURL = ""
	}

	private func plannedSemesterText(from course: CourseEntity) -> String {
		guard let semester = course.semester else { return "" }
		let season = (semester.season ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		let year = Int(semester.year)
		guard !season.isEmpty, year > 0 else { return "" }
		return "\(season) \(year)"
	}

	private func save() {
		let finalStatus: String = {
			let s = normalizedStatus(status)
			if !semesterYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s == "Not Planned" {
				return "Planned"
			}
			return s
		}()

		if !semesterYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			coreDataManager.ensureCourseScheduledInPlanner(
				courseCode: normalizedCourseCode,
				courseName: courseName,
				creditsText: creditsText,
				semesterText: semesterYear,
				status: finalStatus,
				gradingType: gradingType,
				professor: professor.isEmpty ? nil : professor
			)
		}

		let parsedCredits: Double? = {
			let t = creditsText.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !t.isEmpty, t != "-" else { return nil }
			return Double(t)
		}()

		coreDataManager.upsertCourseOverride(
			courseCode: normalizedCourseCode,
			courseName: courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : courseName,
			credits: parsedCredits,
			professor: professor.isEmpty ? nil : professor,
			semesterText: semesterYear.isEmpty ? nil : semesterYear,
			status: finalStatus,
			grade: existingOverride?.grade,
			gradingType: gradingType,
			externalURL: externalURL.isEmpty ? nil : externalURL
		)

		onClose()
	}

	private var syllabusSubtitle: String {
		var parts: [String] = []

		if syllabusFileSizeBytes > 0 {
			parts.append(formatBytes(syllabusFileSizeBytes))
		}

		if let syllabusUploadedAt {
			parts.append("Uploaded \(formatDate(syllabusUploadedAt))")
		}

		return parts.isEmpty ? "" : parts.joined(separator: " • ")
	}

	private func formatDate(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		return formatter.string(from: date)
	}

	private func formatBytes(_ bytes: Int64) -> String {
		let formatter = ByteCountFormatter()
		formatter.allowedUnits = [.useMB, .useKB]
		formatter.countStyle = .file
		return formatter.string(fromByteCount: bytes)
	}

	private func handlePickedSyllabus(_ result: Result<[URL], Error>) {
		let maxBytes: Int64 = 10 * 1024 * 1024

		switch result {
		case .failure(let error):
			notifications.post(
				kind: .error,
				title: "Upload Failed",
				message: error.localizedDescription,
				isDismissible: true,
				autoDismissAfter: 6
			)
			return
		case .success(let urls):
			guard let url = urls.first else { return }

			let fileName = url.lastPathComponent
			let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0

			if size > maxBytes {
				notifications.post(
					kind: .error,
					title: "Upload Failed",
					message: "Syllabus file size exceeds the 10MB limit.",
					isDismissible: true,
					autoDismissAfter: 6
				)
				return
			}

			let toastID = notifications.post(
				kind: .progress,
				title: "Uploading Syllabus",
				message: "Saving \(fileName)…",
				progress: 0.3,
				isDismissible: true
			)

			do {
				let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
				coreDataManager.updateCourseOverrideSyllabus(
					courseCode: normalizedCourseCode,
					fileName: fileName,
					bookmarkData: bookmark,
					fileSizeBytes: size,
					uploadedAt: Date()
				)

				syllabusFileName = fileName
				syllabusFileSizeBytes = size
				syllabusUploadedAt = Date()

				notifications.complete(
					id: toastID,
					kind: .success,
					title: "Syllabus Uploaded",
					message: "\(fileName) saved for \(normalizedCourseCode).",
					autoDismissAfter: 4
				)
			} catch {
				notifications.dismiss(id: toastID)
				notifications.post(
					kind: .error,
					title: "Upload Failed",
					message: error.localizedDescription,
					isDismissible: true,
					autoDismissAfter: 6
				)
				return
			}
		}
	}

	private func openSyllabus() {
		guard let overrideEntity = existingOverride else { return }
		guard let data = overrideEntity.syllabusFileBookmarkData else { return }

		var stale = false
		if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
			_ = url.startAccessingSecurityScopedResource()
			NSWorkspace.shared.open(url)
			url.stopAccessingSecurityScopedResource()
		} else {
			notifications.post(
				kind: .error,
				title: "Open Failed",
				message: "Could not open the saved syllabus file.",
				isDismissible: true,
				autoDismissAfter: 6
			)
		}
	}

	private func deleteSyllabus() {
		coreDataManager.updateCourseOverrideSyllabus(
			courseCode: normalizedCourseCode,
			fileName: nil,
			bookmarkData: nil,
			fileSizeBytes: nil,
			uploadedAt: nil
		)

		syllabusFileName = nil
		syllabusFileSizeBytes = 0
		syllabusUploadedAt = nil

		notifications.post(
			kind: .success,
			title: "Syllabus Removed",
			message: "Removed saved syllabus for \(normalizedCourseCode).",
			isDismissible: true,
			autoDismissAfter: 3
		)
	}
}