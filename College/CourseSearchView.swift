import SwiftUI

struct CourseSearchView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @Binding var isPresented: Bool
    let semester: SemesterEntity
    
    @State private var searchText: String = ""
    @State private var searchResults: [CourseCatalogEntity] = []
    @State private var isSearching: Bool = false
    @State private var selectedCourse: CourseCatalogEntity?
    @State private var showPrerequisites: Bool = false
    
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
                if isSearching {
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
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // Debounce search
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            searchResults = coreDataManager.searchCatalogCourses(query: searchText)
            isSearching = false
        }
    }
    
    private func addCourse(_ catalogCourse: CourseCatalogEntity) {
        // Create new course from catalog
        let course = coreDataManager.addCourse(
            to: semester,
            code: catalogCourse.courseCode ?? "",
            name: catalogCourse.title ?? "",
            credits: Int(catalogCourse.credits),
            status: "Planned",
            gradingType: "Letter Grade",
            professor: nil
        )
        
        // Link to catalog
        course.catalogCourse = catalogCourse
        coreDataManager.save()
        
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
                    Text(course.courseCode ?? "")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                    
                    Text(course.title ?? "")
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
                    Image(systemName: "plus.circle.fill")
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
    }
}

struct CourseDetailModal: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
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
                        Text(course.courseCode ?? "")
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.primary)
                        Text(course.title ?? "")
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
                        
                        // Typically Offered
                        if let offered = course.typicallyOffered, !offered.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Typically Offered")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                
                                Text(offered)
                                    .font(DesignSystem.Fonts.main(size: 13))
                                    .foregroundColor(DesignSystem.Colors.textMain)
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
                        Image(systemName: "plus.circle.fill")
                        Text("Add to \(course.courseCode ?? "Course")")
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
    }
    
    private func checkPrerequisites() {
        guard let plan = coreDataManager.plans.first else { return }
        prerequisiteStatus = coreDataManager.checkPrerequisites(for: course, plan: plan)
    }
}
