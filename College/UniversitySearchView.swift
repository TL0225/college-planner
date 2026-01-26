import SwiftUI

struct UniversitySearchView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter
    @State private var searchText: String = ""
    @State private var availableSchools: [SchoolManifest] = []
    @State private var filteredSchools: [SchoolManifest] = []
    @State private var isLoading: Bool = false
    @State private var loadingMessage: String = ""
    @State private var downloadProgress: Double = 0.0
    @State private var selectedSchool: SchoolManifest?
    
    private let githubService = GitHubDataService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("University Setup", systemImage: "building.columns.fill")
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()
                
                Button(action: refreshSchoolsList) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.primary.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isLoading)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            
            Divider()
            
            // Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.textLight)
                
                TextField("Where do you study?", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 16))
                    .onChange(of: searchText) {
                        filterSchools()
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
            .cornerRadius(12)
            .padding()
            
            // Content
            if isLoading {
                LoadingView(message: loadingMessage, progress: downloadProgress)
            } else if filteredSchools.isEmpty && !searchText.isEmpty {
                EmptySearchView(searchText: searchText)
            } else if filteredSchools.isEmpty {
                WelcomeView(onRefresh: refreshSchoolsList)
            } else {
                SchoolListView(
                    schools: filteredSchools,
                    onSelect: downloadSchool
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "fafbfc"))
        .onAppear {
            loadSchoolsList()
        }
    }
    
    // MARK: - Actions
    
    private func loadSchoolsList() {
        // Try to load from cache first
        if let cached = githubService.loadCachedSchoolsList() {
            availableSchools = cached
            filteredSchools = cached
            return
        }
        
        // If no cache, user needs to manually refresh
        availableSchools = []
        filteredSchools = []
    }
    
    private func refreshSchoolsList() {
        isLoading = true
        loadingMessage = "Fetching university list..."
        
        Task {
            let toastID = await MainActor.run {
                notifications.post(
                    kind: .progress,
                    title: "Refreshing",
                    message: "Fetching university list…",
                    progress: 0.1,
                    isDismissible: true
                )
            }
            do {
                let schools = try await githubService.fetchSchoolsList()
                
                await MainActor.run {
                    availableSchools = schools
                    filteredSchools = schools
                    isLoading = false

                    notifications.complete(
                        id: toastID,
                        kind: .success,
                        title: "Universities Updated",
                        message: "Loaded \(schools.count) universities.",
                        autoDismissAfter: 3
                    )
                    
                    // Cache for next time
                    try? githubService.cacheSchoolsList(schools)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    notifications.dismiss(id: toastID)
                    notifications.post(
                        kind: .error,
                        title: "Refresh Failed",
                        message: error.localizedDescription,
                        isDismissible: true,
                        autoDismissAfter: 6
                    )
                }
            }
        }
    }
    
    private func downloadSchool(_ school: SchoolManifest) {
        selectedSchool = school
        isLoading = true
        loadingMessage = "Downloading \(school.name) catalog..."
        downloadProgress = 0.0
        
        Task {
            let toastID = await MainActor.run {
                notifications.post(
                    kind: .progress,
                    title: "Downloading Catalog",
                    message: "Starting \(school.name)…",
                    progress: 0.05,
                    isDismissible: true
                )
            }
            do {
                // Simulate progress updates
                await updateProgress(0.2, message: "Fetching course data...")
                await MainActor.run {
                    notifications.update(id: toastID, message: "Fetching course data…", progress: 0.2)
                }
                
                let profile = try await githubService.downloadSchoolProfile(schoolID: school.id)
                
                await updateProgress(0.6, message: "Processing \(profile.courses.count) courses...")
                await MainActor.run {
                    notifications.update(
                        id: toastID,
                        message: "Processing \(profile.courses.count) courses…",
                        progress: 0.6
                    )
                }
                
                // Save to Core Data
                try await saveProfile(profile)
                await MainActor.run {
                    notifications.update(id: toastID, message: "Saving to your library…", progress: 0.85)
                }
                
                await updateProgress(1.0, message: "Complete!")
                await MainActor.run {
                    notifications.complete(
                        id: toastID,
                        kind: .success,
                        title: "Catalog Ready",
                        message: "\(school.name) is ready to search.",
                        autoDismissAfter: 4
                    )
                }
                
                // Wait a moment to show completion
                try await Task.sleep(nanoseconds: 500_000_000)
                
                await MainActor.run {
                    isLoading = false
                    selectedSchool = nil
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    selectedSchool = nil

                    notifications.dismiss(id: toastID)
                    notifications.post(
                        kind: .error,
                        title: "Download Failed",
                        message: error.localizedDescription,
                        isDismissible: true,
                        autoDismissAfter: 6
                    )
                }
            }
        }
    }
    
    private func updateProgress(_ value: Double, message: String) async {
        await MainActor.run {
            downloadProgress = value
            loadingMessage = message
        }
    }
    
    private func saveProfile(_ profile: SchoolProfile) async throws {
        let context = coreDataManager.viewContext
        
        await MainActor.run {
            // Create or update university
            let request = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
            request.predicate = NSPredicate(format: "name == %@", profile.schoolName)

            let university: UniversityEntity
            if let existing = (try? context.fetch(request))?.first {
                university = existing
            } else {
                university = UniversityEntity(context: context)
                university.id = UUID()
                university.name = profile.schoolName
            }

            university.catalogURL = profile.catalogURL
            university.lastCatalogSync = Date()
            coreDataManager.setActiveUniversity(university)
            
            // Save courses
            for catalogCourse in profile.courses {
                let course = CourseCatalogEntity(context: context)
                course.id = catalogCourse.id
                course.courseCode = catalogCourse.courseCode
                course.title = catalogCourse.title
                course.descriptionText = catalogCourse.description
                course.credits = Int16(catalogCourse.credits)
                course.department = catalogCourse.department
                course.lastUpdated = Date()
                course.university = university
                
                // Store prerequisites as JSON
                if let prereqs = catalogCourse.prerequisites {
                    let encoder = JSONEncoder()
                    if let jsonData = try? encoder.encode(prereqs),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        course.prerequisiteRulesJSON = jsonString
                    }
                }
                
                if let coreqs = catalogCourse.corequisites {
                    course.corequisiteCodes = coreqs.joined(separator: ",")
                }
                
                if let offered = catalogCourse.typicallyOffered {
                    course.typicallyOffered = offered.joined(separator: ",")
                }
            }
            
            // Save degree requirements
            for degreeReq in profile.degreeRequirements {
                let requirement = DegreeRequirementEntity(context: context)
                requirement.id = degreeReq.id
                requirement.degreeType = degreeReq.degreeType
                requirement.major = degreeReq.major
                requirement.requirementCategory = degreeReq.category
                requirement.creditsRequired = Int16(degreeReq.creditsRequired)
                requirement.descriptionText = degreeReq.description
                requirement.lastUpdated = Date()
                requirement.university = university
                
                if let courses = degreeReq.requiredCourses {
                    requirement.requiredCourses = courses.joined(separator: ",")
                }
            }
            
            coreDataManager.save()
        }
    }
    
    private func filterSchools() {
        if searchText.isEmpty {
            filteredSchools = availableSchools
        } else {
            filteredSchools = availableSchools.filter { school in
                school.name.localizedCaseInsensitiveContains(searchText) ||
                (school.shortName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    
}

// MARK: - Subviews

struct LoadingView: View {
    let message: String
    let progress: Double
    
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(DesignSystem.Fonts.main(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
            
            if progress > 0 {
                ProgressView(value: progress)
                    .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeView: View {
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "building.columns.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(DesignSystem.Colors.primary)
            
            VStack(spacing: 12) {
                Text("Welcome to College Planner")
                    .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                
                Text("Let's get started by connecting to your university")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onRefresh) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Load University List")
                }
                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.primary)
                .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmptySearchView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textLight)
            
            Text("No universities found for \"\(searchText)\"")
                .font(DesignSystem.Fonts.main(size: 14))
                .foregroundColor(DesignSystem.Colors.textLight)
            
            Text("Try a different search or request it to be added")
                .font(DesignSystem.Fonts.main(size: 12))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SchoolListView: View {
    let schools: [SchoolManifest]
    let onSelect: (SchoolManifest) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(schools) { school in
                    SchoolCard(school: school, onSelect: { onSelect(school) })
                }
            }
            .padding()
        }
    }
}

struct SchoolCard: View {
    let school: SchoolManifest
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: school.verified ? "checkmark.seal.fill" : "building.columns.fill")
                    .font(.system(size: 32))
                    .foregroundColor(school.verified ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                    .frame(width: 48)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(school.name)
                            .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        
                        if school.verified {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.Colors.success)
                        }
                    }
                    
                    Text("\(school.coursesCount) courses • Updated \(school.lastUpdated, style: .relative) ago")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    
                    Text(school.catalogFormat.uppercased())
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 24))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .padding()
            .background(DesignSystem.Colors.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
