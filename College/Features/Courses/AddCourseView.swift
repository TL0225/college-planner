// AddCourseView.swift
// Feature: Courses
// Purpose: Courses module — AddCourseView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import UniformTypeIdentifiers

struct AddCourseView: View {
    @Binding var isPresented: Bool
    let semester: PlannerSemester
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject var notifications: AppNotificationCenter
    var courseToEdit: CourseEntity?
    
    @State private var courseID: String = ""
    @State private var credits: String = ""
    @State private var status: String = ""
    @State private var gradingType: String = ""
    @State private var courseName: String = ""
    @State private var professor: String = ""
    @State private var showFileImporter = false
    @State private var selectedFileName: String?
    
    @State private var showStatusDropdown = false
    @State private var showGradingDropdown = false
    
    let statuses = ["Planned", "In Progress", "Completed"]
    let gradingTypes = ["Letter Grade", "Pass/Fail", "Audit"]
    
    var body: some View {
        ZStack {
            // Backdrop
            Color(hex: "0f172a").opacity(0.4)
                .ignoresSafeArea()
            
            // Modal Content
            VStack(spacing: 0) {
                // Header
                HStack {
                    if courseToEdit != nil {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(DesignSystem.Colors.info.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "doc.text")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.info)
                        }

                        Text("Edit Course Details")
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    } else {
                        Text("Add Course")
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .padding(8)
                            .background(Color.clear)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                
                Text(courseToEdit != nil ? "Update the course details below." : "Fill in the details below to add a course to your plan.")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                
                VStack(spacing: 16) {
                    // Semester / Year
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SEMESTER / YEAR")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(DesignSystem.Colors.textLight)
                            Text(semester.name)
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Spacer()
                            Text("AUTO-SELECTED")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.success)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DesignSystem.Colors.success.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .padding(12)
                        .background(DesignSystem.Colors.bgMain)
                        .cornerRadius(12)
                    }
                    
                    // Row 1: Course ID & Credits
                    HStack(alignment: .top, spacing: 16) {
                        // Course ID
                        VStack(alignment: .leading, spacing: 6) {
                            Text("COURSE ID *")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            TextField("e.g. CS 1110", text: $courseID)
                                .font(DesignSystem.Fonts.main(size: 14))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                )
                        }
                        
                        // Credits
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CREDITS")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            TextField("e.g. 3", text: $credits)
                                .font(DesignSystem.Fonts.main(size: 14))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                )
                        }
                    }
                    
                    // Row 2: Status & Grading Type
                    HStack(alignment: .top, spacing: 16) {
                        // Status
                        VStack(alignment: .leading, spacing: 6) {
                            Text("STATUS")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            ZStack(alignment: .top) {
                                Button(action: {
                                    showStatusDropdown.toggle()
                                    showGradingDropdown = false
                                }) {
                                    HStack {
                                        Text(status.isEmpty ? "Planned" : status)
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                            .foregroundColor(status.isEmpty ? DesignSystem.Colors.textLight : DesignSystem.Colors.textMain)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                            .rotationEffect(.degrees(showStatusDropdown ? 180 : 0))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "cbd5e1"), lineWidth: 1)
                                    )
                                }
                                
                                if showStatusDropdown {
                                    VStack(spacing: 0) {
                                        ForEach(statuses, id: \.self) { s in
                                            Button(action: {
                                                status = s
                                                showStatusDropdown = false
                                            }) {
                                                Text(s)
                                                    .font(DesignSystem.Fonts.main(size: 14))
                                                    .foregroundColor(DesignSystem.Colors.textMain)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(12)
                                            }
                                            if s != statuses.last {
                                                Divider()
                                                    .background(Color(hex: "cbd5e1"))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "cbd5e1"), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                    .padding(.top, 48)
                                    .transition(.opacity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .zIndex(showStatusDropdown ? 10 : 1)
                        
                        // Grading Type
                        VStack(alignment: .leading, spacing: 6) {
                            Text("GRADING TYPE")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            
                            ZStack(alignment: .top) {
                                Button(action: {
                                    showGradingDropdown.toggle()
                                    showStatusDropdown = false
                                }) {
                                    HStack {
                                        Text(gradingType.isEmpty ? "Letter Grade" : gradingType)
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                            .foregroundColor(gradingType.isEmpty ? DesignSystem.Colors.textLight : DesignSystem.Colors.textMain)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                            .rotationEffect(.degrees(showGradingDropdown ? 180 : 0))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "cbd5e1"), lineWidth: 1)
                                    )
                                }
                                
                                if showGradingDropdown {
                                    VStack(spacing: 0) {
                                        ForEach(gradingTypes, id: \.self) { type in
                                            Button(action: {
                                                gradingType = type
                                                showGradingDropdown = false
                                            }) {
                                                Text(type)
                                                    .font(DesignSystem.Fonts.main(size: 14))
                                                    .foregroundColor(DesignSystem.Colors.textMain)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(12)
                                            }
                                            if type != gradingTypes.last {
                                                Divider()
                                                    .background(Color(hex: "cbd5e1"))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "cbd5e1"), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                    .padding(.top, 48)
                                    .transition(.opacity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .zIndex(showGradingDropdown ? 10 : 1)
                    }
                    .zIndex(100)
                    
                    // Course Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COURSE NAME *")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        
                        TextField("e.g. Introduction to Computing", text: $courseName)
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "cbd5e1"), lineWidth: 1)
                            )
                    }
                    
                    // Professor
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PROFESSOR")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(DesignSystem.Colors.textLight)
                            TextField("e.g. Walker White", text: $professor)
                                .font(DesignSystem.Fonts.main(size: 14))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .textFieldStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "cbd5e1"), lineWidth: 1)
                        )
                    }
                    
                    // Syllabus Upload
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYLLABUS UPLOAD")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        
                        Button(action: { showFileImporter = true }) {
                            VStack(spacing: 12) {
                                Image(systemName: "cloud.upload.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                
                                if let fileName = selectedFileName {
                                    Text(fileName)
                                        .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.primary)
                                } else {
                                    VStack(spacing: 4) {
                                        Text("Upload a file or drag and drop")
                                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                            .foregroundColor(DesignSystem.Colors.primary)
                                        Text("PDF, DOCX up to 10MB")
                                            .font(DesignSystem.Fonts.main(size: 10))
                                            .foregroundColor(DesignSystem.Colors.textLight)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.5))
                            )
                        }
                        .fileImporter(
                            isPresented: $showFileImporter,
                            allowedContentTypes: [UTType.pdf, UTType.plainText, UTType.image],
                            allowsMultipleSelection: false
                        ) { result in
                            switch result {
                            case .success(let urls):
                                guard let url = urls.first else { return }
                                let fileName = url.lastPathComponent

                                let maxBytes = 10 * 1024 * 1024
                                let sizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                                if sizeBytes > maxBytes {
                                    notifications.post(
                                        kind: .error,
                                        title: "Upload Failed",
                                        message: "Syllabus file size exceeds the 10MB limit.",
                                        isDismissible: true,
                                        autoDismissAfter: 6
                                    )
                                    return
                                }

                                selectedFileName = fileName
                                notifications.post(
                                    kind: .success,
                                    title: "Syllabus Attached",
                                    message: fileName,
                                    isDismissible: true,
                                    autoDismissAfter: 3
                                )
                            case .failure(let error):
                                notifications.post(
                                    kind: .error,
                                    title: "Upload Failed",
                                    message: error.localizedDescription,
                                    isDismissible: true,
                                    autoDismissAfter: 6
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                
                // Footer (Save Button)
                Button(action: {
                    // Save action
                    let trimmedID = courseID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !trimmedID.isEmpty, !trimmedName.isEmpty else {
                        notifications.post(
                            kind: .warning,
                            title: "Missing Fields",
                            message: "Please enter a course ID and name.",
                            isDismissible: true,
                            autoDismissAfter: 4
                        )
                        return
                    }

                    guard let creditsInt = Int(credits) else {
                        notifications.post(
                            kind: .warning,
                            title: "Invalid Credits",
                            message: "Credits must be a whole number.",
                            isDismissible: true,
                            autoDismissAfter: 4
                        )
                        return
                    }
                    
                    let finalStatus = status.isEmpty ? "Planned" : status
                    let finalGradingType = gradingType.isEmpty ? "Letter Grade" : gradingType
                    
                    if let course = courseToEdit {
                        // Update existing course
                        course.code = trimmedID
                        course.name = trimmedName
                        course.credits = Int16(creditsInt)
                        course.status = finalStatus
                        course.gradingType = finalGradingType
                        course.professor = professor.isEmpty ? nil : professor
                        course.isCompleted = (finalStatus == "Completed")
                        collegePersistence.save()

                        notifications.post(
                            kind: .success,
                            title: "Course Updated",
                            message: "Saved changes for \(trimmedID).",
                            isDismissible: true,
                            autoDismissAfter: 3
                        )
                    } else {
                        // Add new course
                        _ = collegePersistence.addCourse(
                            to: semester,
                            code: trimmedID,
                            name: trimmedName,
                            credits: creditsInt,
                            status: finalStatus,
                            gradingType: finalGradingType,
                            professor: professor.isEmpty ? nil : professor
                        )

                        notifications.post(
                            kind: .success,
                            title: "Course Added",
                            message: "Added \(trimmedID) to \(semester.name).",
                            isDismissible: true,
                            autoDismissAfter: 3
                        )
                    }
                    
                    isPresented = false
                }) {
                    Text(courseToEdit != nil ? "Save Changes" : "Add Course")
                        .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DesignSystem.Colors.primary)
                        .cornerRadius(16)
                }
                .padding(24)
            }
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.2), radius: 20)
            .frame(maxWidth: 500, maxHeight: 700)
            .padding(24)
        }
        .transition(.opacity)
        .zIndex(100)
        .onAppear {
            if let course = courseToEdit {
                courseID = course.code
                credits = String(course.credits)
                status = course.status
                gradingType = course.gradingType
                courseName = course.name
                professor = course.professor ?? ""
            }
        }
    }
}
