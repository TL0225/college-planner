// CourseSearchView.swift
// Feature: Courses
// Purpose: Courses module — CourseSearchView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct CourseSearchView: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @Binding var isPresented: Bool
    let semester: SemesterEntity
    
    @State private var searchText: String = ""
    @State private var searchResults: [CourseCatalogEntity] = []
    @State private var isSearching: Bool = false
    @State private var selectedCourse: CourseCatalogEntity?
    @State private var showPrerequisites: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var catalogCapabilities: CollegePersistence.CatalogCapability?
    @State private var catalogImportMessage: String?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Label("Add Course", systemImage: "plus.circle.fill")
                        .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                
                Divider()
                
                // Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.textLight)
                    
                    TextField("Search courses (e.g., CS 101, Introduction...)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Fonts.main(size: 14))
                        .onChange(of: searchText) {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(hex: "f8f9fa"))
                .cornerRadius(10)
                .padding()
                
                // Search Results
                if let catalogImportMessage, !(catalogCapabilities?.coursesReady ?? true) {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(catalogImportMessage)
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .multilineTextAlignment(.center)
                        Text("Watch the menu bar for live import progress.")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight.opacity(0.85))
                    }
                    .padding()
                    Spacer()
                } else if isSearching {
                    ProgressView()
                        .padding()
                    Spacer()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Text("No courses found for \"\(searchText)\"")
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    .padding()
                    Spacer()
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.Colors.textLight)
                        Text("Start typing to search courses")
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(searchResults, id: \.id) { course in
                                CourseResultCard(
                                    course: course,
                                    onSelect: { selectedCourse = course },
                                    onAdd: { addCourse(course) }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(width: 700, height: 600)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20)
            .task { await refreshCatalogCapabilities() }
            
            // Course Detail Modal
            if let course = selectedCourse {
                CourseDetailModal(
                    course: course,
                    isPresented: .init(
                        get: { selectedCourse != nil },
                        set: { if !$0 { selectedCourse = nil } }
                    ),
                    onAdd: { addCourse(course) }
                )
            }
        }
    }
    
    // MARK: - Actions

    private func refreshCatalogCapabilities() async {
        let university = collegePersistence.getActiveUniversity()?.name ?? ""
        guard !university.isEmpty else { return }
        let caps = await collegePersistence.catalogCapabilities(universityName: university)
        await MainActor.run {
            catalogCapabilities = caps
            catalogImportMessage = caps.courseSearchBlockedReason
        }
    }
    
    private func performSearch() {
        searchTask?.cancel()

        guard !searchText.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        if catalogCapabilities?.coursesReady == false {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true

        let query = searchText
        let manager = collegePersistence
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            let hits = await MainActor.run {
                CatalogCourseSearchBridge.search(
                    query: query,
                    limit: 50,
                    persistence: manager,
                    performBackfill: false
                )
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                searchResults = CatalogCourseSearchBridge.resolveToModels(
                    hits: hits,
                    persistence: manager
                )
                isSearching = false
            }
        }
    }
    
    private func addCourse(_ catalogCourse: CourseCatalogEntity) {
        // Create new course from catalog
        let course = collegePersistence.addCourse(
            to: semester,
            code: catalogCourse.courseCode,
            name: catalogCourse.title,
            credits: Int(catalogCourse.credits),
            status: "Planned",
            gradingType: "Letter Grade",
            professor: nil
        )

        course.catalogCourseID = catalogCourse.id
        collegePersistence.save()
        
        isPresented = false
    }
}

struct CourseResultCard: View {
    let course: CourseCatalogEntity
    let onSelect: () -> Void
    let onAdd: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // Course Code and Title
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(course.courseCode)
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text(course.title)
                        .font(DesignSystem.Fonts.main(size: 14))
                        .foregroundColor(DesignSystem.Colors.textMain)
                }
                
                // Description
                let description = (course.descriptionText ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                Text(description.isEmpty ? "No description available." : description)
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .lineLimit(2)
                
                // Metadata
                HStack(spacing: 12) {
                    let creditsText = course.creditsDisplayText
                    Label("\(creditsText.isEmpty ? "0" : creditsText) credits", systemImage: "book.fill")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    
                    if let dept = course.department {
                        Label(dept, systemImage: "building.2.fill")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    
                    if let prereqJSON = course.prerequisiteRulesJSON,
                       !prereqJSON.isEmpty {
                        Label("Has Prerequisites", systemImage: "arrow.triangle.branch")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.warning)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 8) {
                Button(action: onSelect) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
                
                Button(action: onAdd) {
                    Image(systemName: "plus.app.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.success)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(DesignSystem.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
        )
        .draggable(course.draggableCourseCode)
    }
}

struct CourseDetailModal: View {
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    private var collegePersistence: CollegePersistence { container.persistence }
    @State private var plannerRefreshToken = 0
    let course: CourseCatalogEntity
    @Binding var isPresented: Bool
    let onAdd: () -> Void
    
    @State private var prerequisiteStatus: PrerequisiteValidationResult?
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.courseCode)
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                        Text(course.title)
                            .font(DesignSystem.Fonts.main(size: 16))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(DesignSystem.Colors.surface)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Basic Info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                let creditsText = course.creditsDisplayText
                                Label("\(creditsText.isEmpty ? "0" : creditsText) Credits", systemImage: "book.fill")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                
                                if let dept = course.department {
                                    Label(dept, systemImage: "building.2.fill")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                }
                            }
                        }
                        
                        // Description
                        if let description = course.descriptionText {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                
                                Text(description)
                                    .font(DesignSystem.Fonts.main(size: 13))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                            }
                        }
                        
                        // Prerequisites
                        if let prereqJSON = course.prerequisiteRulesJSON,
                           let prereqData = prereqJSON.data(using: .utf8),
                           let prereqRule = try? JSONDecoder().decode(PrerequisiteRule.self, from: prereqData) {
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Prerequisites")
                                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                    
                                    if let status = prerequisiteStatus {
                                        Image(systemName: status.met ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(status.met ? DesignSystem.Colors.success : DesignSystem.Colors.error)
                                    }
                                }
                                
                                Text(prereqRule.toReadableString())
                                    .font(DesignSystem.Fonts.main(size: 13))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(hex: "f8f9fa"))
                                    .cornerRadius(8)
                            }
                        }
                        
                    }
                    .padding()
                }
                
                Divider()
                
                // Add Button
                Button(action: {
                    onAdd()
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "plus.app.fill")
                        Text("Add to \(course.courseCode)")
                    }
                    .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.primary)
                    .cornerRadius(10)
                }
                .padding()
            }
            .frame(width: 500, height: 600)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
        .onAppear {
            checkPrerequisites()
        }
        .onChange(of: collegePersistence.profileRevision) { _, _ in
            plannerRefreshToken &+= 1
            checkPrerequisites()
        }
        .background {
            ProfilePlannerQueryHost {
                plannerRefreshToken &+= 1
            }
        }
    }

    private var plans: [PlanEntity] {
        _ = plannerRefreshToken
        return ProfilePlannerReadBridge.plans(collegePersistence: collegePersistence)
    }

    private func checkPrerequisites() {
        guard let plan = collegePersistence.getActivePlan() ?? plans.first else { return }
        prerequisiteStatus = collegePersistence.checkPrerequisites(for: course, plan: plan)
    }
}
