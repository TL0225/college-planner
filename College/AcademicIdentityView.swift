import SwiftUI

nonisolated private func extractCourseCodes(from requirements: [DegreeRequirement]) -> Set<String> {
    var codes = Set<String>()
    for requirement in requirements {
        if let required = requirement.requiredCourses {
            for course in required { codes.insert(course) }
        }
        if let selectable = requirement.selectFrom {
            for course in selectable { codes.insert(course) }
        }
    }
    return codes
}

struct AcademicIdentityView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter
    @ObservedObject var profile: ProfileEntity

    private let githubService = GitHubDataService()
    private let scraperService = WebScraperService()

    @State private var showCatalogStatus: Bool = false
    @State private var isDownloadingCatalog: Bool = false
    @State private var catalogDownloadMessage: String = ""

    @State private var collegeNameDraft: String = ""
    @State private var showCollegeSuggestions: Bool = false
    @State private var isLoadingSchools: Bool = false
    @State private var availableSchools: [SchoolManifest] = []
    @State private var schoolsLoadError: String? = nil
    
    // Dynamic class standings based on degree level
    private var classStandings: [String] {
        let currentLevel = profile.degreeLevel ?? "Undergraduate"
        return DegreeConfiguration.classStandings(for: currentLevel)
    }
    
    // Available degree types from catalog (or fallback to hardcoded)
    private var availableDegreeTypes: [String] {
        guard let collegeName = profile.collegeName, !collegeName.isEmpty else {
            // Fallback to hardcoded types if no college selected
            let currentLevel = profile.degreeLevel ?? "Undergraduate"
            return DegreeConfiguration.types(for: currentLevel)
        }

        let currentLevel = profile.degreeLevel ?? "Undergraduate"

        if coreDataManager.hasUniversityCatalog(name: collegeName) {
            let types = coreDataManager.fetchDegreeTypes(for: collegeName, degreeLevel: currentLevel)
            if !types.isEmpty {
                return types
            }
        }

        return DegreeConfiguration.types(for: currentLevel)
    }

    private var availableDepartmentGroups: [(group: String, departments: [String])] {
        guard let collegeName = profile.collegeName, !collegeName.isEmpty else { return [] }
        let degreeLevel = profile.degreeLevel ?? "Undergraduate"
        let groups = coreDataManager.fetchDepartmentGroups(for: collegeName, degreeLevel: degreeLevel)
        
        // Clean and deduplicate department names within each group
        return groups.compactMap { group in
            var cleanedSet = Set<String>()
            
            for dept in group.departments {
                let cleaned = cleanDepartmentName(dept)
                if !cleaned.isEmpty {
                    cleanedSet.insert(cleaned)
                }
            }
            
            let uniqueDepts = Array(cleanedSet).sorted()
            
            // Only return groups that have at least one department
            // Also skip groups with suspicious artifact names in the header
            let cleanGroupName = group.group.lowercased()
            if uniqueDepts.isEmpty || 
               cleanGroupName.contains("department page") || 
               cleanGroupName.contains("learn more") {
                return nil
            }
            return (group: group.group, departments: uniqueDepts)
        }
    }

    private var availableDepartments: [String] {
        availableDepartmentGroups.flatMap { $0.departments }
    }
    
    // Helper to map cleaned department name back to original for Core Data queries
    private func getOriginalDepartmentName(_ cleanedName: String, collegeName: String) -> String? {
        let groups = coreDataManager.fetchDepartmentGroups(for: collegeName)
        for group in groups {
            for originalDept in group.departments {
                if cleanDepartmentName(originalDept) == cleanedName {
                    return originalDept
                }
            }
        }
        return nil
    }
    
    private var availableMajors: [String] {
        guard let collegeName = profile.collegeName, !collegeName.isEmpty else { return [] }

        // If we have a downloaded catalog, show ONLY scraped majors.
        if coreDataManager.hasUniversityCatalog(name: collegeName) {
            let degreeLevel = profile.degreeLevel ?? "Undergraduate"

            // If the user has selected a department/college, prefer showing *only* majors under it.
            if let selectedDept = profile.department, !selectedDept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // When a department is selected, show *all* majors within that department.
                // Filtering by degree type (BA vs BS) tends to hide valid majors and combined degrees.
                let degreeTypeForDept: String? = nil

                // Try multiple department name variations
                let originalDept = getOriginalDepartmentName(selectedDept, collegeName: collegeName) ?? selectedDept
                
                // Try with original name first
                var majorsForDept = coreDataManager.fetchMajors(
                    for: collegeName,
                    degreeLevel: degreeLevel,
                    department: originalDept,
                    degreeType: degreeTypeForDept,
                    includeMinors: false
                )

                // If empty, try with cleaned name
                if majorsForDept.isEmpty && originalDept != selectedDept {
                    majorsForDept = coreDataManager.fetchMajors(
                        for: collegeName,
                        degreeLevel: degreeLevel,
                        department: selectedDept,
                        degreeType: degreeTypeForDept,
                        includeMinors: false
                    )
                }
                
                // If still empty, try with " department" suffix added back
                if majorsForDept.isEmpty {
                    majorsForDept = coreDataManager.fetchMajors(
                        for: collegeName,
                        degreeLevel: degreeLevel,
                        department: "\(selectedDept) department",
                        degreeType: degreeTypeForDept,
                        includeMinors: false
                    )
                }

                return majorsForDept
            }

            // Enforce hierarchy: don't show majors until a department/program is selected.
            return []
        }

        // No downloaded catalog available.
        return []
    }
    
    private var availableMinors: [String] {
        guard let collegeName = profile.collegeName, !collegeName.isEmpty else { return [] }

        // If we have a downloaded catalog, show ONLY scraped minors.
        if coreDataManager.hasUniversityCatalog(name: collegeName) {
            let minorsFromCatalog = coreDataManager.fetchMinors(
                for: collegeName,
                // Minors are always Undergraduate (independent of selected major/degree level).
                degreeLevel: "Undergraduate"
            )
            // Avoid showing "None" twice if it ends up in the catalog list.
            let cleaned = minorsFromCatalog.filter { $0.lowercased() != "none" }
            return ["None"] + cleaned
        }

        // No downloaded catalog available.
        return []
    }

    private var availableCertificates: [String] {
        guard let collegeName = profile.collegeName, !collegeName.isEmpty else { return [] }

        // Certificates are treated as graduate/professional artifacts.
        // Keep this list independent of the selected degree level so the user can still
        // browse certificates while on Graduate vs Doctorate.
        if coreDataManager.hasUniversityCatalog(name: collegeName) {
            let certsFromCatalog = coreDataManager.fetchCertificates(for: collegeName)
            let cleaned = certsFromCatalog.filter { $0.lowercased() != "none" }
            return ["None"] + cleaned
        }

        return []
    }

    private func majorsForDepartmentSelection(_ cleanedDept: String) -> [String] {
        guard let collegeName = profile.collegeName, !collegeName.isEmpty else { return [] }
        let degreeLevel = profile.degreeLevel ?? "Undergraduate"

        let degreeTypeForDept: String? = nil
        let originalDept = getOriginalDepartmentName(cleanedDept, collegeName: collegeName) ?? cleanedDept

        var majorsForDept = coreDataManager.fetchMajors(
            for: collegeName,
            degreeLevel: degreeLevel,
            department: originalDept,
            degreeType: degreeTypeForDept,
            includeMinors: false
        )

        if majorsForDept.isEmpty && originalDept != cleanedDept {
            majorsForDept = coreDataManager.fetchMajors(
                for: collegeName,
                degreeLevel: degreeLevel,
                department: cleanedDept,
                degreeType: degreeTypeForDept,
                includeMinors: false
            )
        }

        if majorsForDept.isEmpty {
            majorsForDept = coreDataManager.fetchMajors(
                for: collegeName,
                degreeLevel: degreeLevel,
                department: "\(cleanedDept) department",
                degreeType: degreeTypeForDept,
                includeMinors: false
            )
        }

        return majorsForDept
    }

    private func deriveDegreeLevelForProgram(isMinor: Bool, programType: String, degreeType: String?, programName: String) -> String {
        if isMinor { return "Undergraduate" }

        func norm(_ s: String) -> String {
            s
                .uppercased()
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func isUndergradToken(_ t: String) -> Bool {
            let u = norm(t)
            return u.hasPrefix("B") || u == "AA" || u == "AS" || u == "AAS"
        }

        func isGradToken(_ t: String) -> Bool {
            let u = norm(t)
            if u.hasPrefix("M") { return true }
            if u.contains("PHD") || u == "JD" || u == "MD" || u == "DMD" || u == "DDS" || u == "DPT" || u == "PHARMD" { return true }
            return false
        }

        // If the degreeType or programName explicitly encodes multiple degrees (e.g. "BS/MS"), treat as Combined.
        let combinedHint = (degreeType ?? "") + " " + programName
        if combinedHint.contains("/") {
            // Try to be a bit conservative: only call it Combined when both undergrad+grad appear.
            let tokens = combinedHint
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "+", with: " ")
                .replacingOccurrences(of: ";", with: " ")
                .components(separatedBy: CharacterSet(charactersIn: "/ "))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let hasUndergrad = tokens.contains(where: isUndergradToken)
            let hasGrad = tokens.contains(where: isGradToken)
            if hasUndergrad && hasGrad {
                return "Combined"
            }
        }

        // Prefer explicit degreeType (usually acronyms like BS/BA/MS/PhD).
        let rawType = (degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedType = rawType
            .uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")

        if !normalizedType.isEmpty {
            if normalizedType.contains("PHD") { return "PhD" }
            if normalizedType.contains("JD") { return "Graduate" }
            if normalizedType.contains("MD") { return "Graduate" }
            if normalizedType.contains("DDS") || normalizedType.contains("DMD") { return "Graduate" }
            if normalizedType.contains("DO") && normalizedType.count <= 4 { return "Graduate" }
            if normalizedType.contains("DPT") { return "Graduate" }
            if normalizedType.contains("PHARMD") { return "Graduate" }
            if normalizedType.hasPrefix("M") { return "Graduate" }
            if normalizedType.hasPrefix("B") { return "Undergraduate" }
        }

        // Fallback: infer from the program name/type text.
        let lowerName = programName.lowercased()
        let lowerProgramType = programType.lowercased()

        if lowerName.contains("ph.d") || lowerName.contains("phd") || lowerProgramType.contains("doctor") {
            return "PhD"
        }
        if lowerName.contains("juris doctor") || lowerName.contains("j.d") || lowerProgramType.contains("law") {
            return "Graduate"
        }
        if lowerName.contains("doctor of medicine") || lowerName.contains("m.d") || lowerProgramType.contains("medical") {
            return "Graduate"
        }
        if lowerName.contains("doctor of dental") || lowerName.contains("d.d.s") || lowerName.contains("d.m.d") || lowerProgramType.contains("dental") {
            return "Graduate"
        }
        if lowerName.contains("master") || lowerName.contains("m.s") || lowerName.contains("m.a") || lowerName.contains("mba") || lowerProgramType.contains("master") {
            return "Graduate"
        }
        // Default: treat as Undergraduate if we can't tell.
        return "Undergraduate"
    }

    private var cardBorderColor: Color {
        DesignSystem.Colors.textLight.opacity(0.25)
    }

    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
    }

    private func pillContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.bgMain)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
            .foregroundColor(DesignSystem.Colors.textLight)
            .textCase(.uppercase)
    }

    private func menuValueLabel(value: String?, placeholder: String) -> some View {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? placeholder : trimmed
        let displayColor = trimmed.isEmpty ? DesignSystem.Colors.textLight : DesignSystem.Colors.textMain

        return HStack(spacing: 10) {
            Text(displayValue)
                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                .foregroundColor(displayColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.primary.opacity(0.14))
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .frame(width: 36, height: 36)

                Text("Academic Identity")
                    .font(DesignSystem.Fonts.main(size: 22, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                Spacer()
            }

            HStack(spacing: 12) {
                cardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel("Expected Grad")

                        pillContainer {
                            TextField("May 2025", text: Binding(
                                get: { profile.expectedGraduation ?? "" },
                                set: { profile.expectedGraduation = $0; coreDataManager.save() }
                            ))
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        }
                    }
                }

                cardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        fieldLabel("Class Standing")

                        Picker("", selection: Binding(
                            get: { profile.classStanding ?? "" },
                            set: { profile.classStanding = $0.isEmpty ? nil : $0; coreDataManager.save() }
                        )) {
                            Text("Select class standing…")
                                .foregroundColor(.gray)
                                .tag("")
                                .disabled(true)
                            ForEach(classStandings, id: \.self) { standing in
                                Text(standing).tag(standing)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(classStandingColor(for: profile.classStanding ?? "").opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            HStack(spacing: 10) {
                                Text(profile.classStanding?.isEmpty == false ? profile.classStanding! : "Select class standing…")
                                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                    .foregroundColor(profile.classStanding?.isEmpty == false ? classStandingColor(for: profile.classStanding!) : .gray)

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(profile.classStanding?.isEmpty == false ? classStandingColor(for: profile.classStanding!) : .gray)
                            }
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                        )
                    }
                }
            }

            cardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("School")

                    VStack(alignment: .leading, spacing: 8) {
                        pillContainer {
                            TextField("College name", text: $collegeNameDraft)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(DesignSystem.Fonts.main(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .onChange(of: collegeNameDraft) {
                                    showCollegeSuggestions = !collegeNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                }
                                .onSubmit {
                                    showCollegeSuggestions = false
                                    commitSchoolName(collegeNameDraft)
                                }
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task { await refreshSchoolsList() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text(isLoadingSchools ? "Loading…" : "Load schools")
                                }
                                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(DesignSystem.Colors.primary)
                            .disabled(isLoadingSchools)
                            
                            // Re-scrape button if school is already selected
                            if let currentSchool = profile.collegeName, !currentSchool.isEmpty {
                                Button {
                                    Task {
                                        if let school = availableSchools.first(where: { $0.name == currentSchool }) {
                                            await scrapeAndImportCatalog(school: school, forceRescrape: true)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("Force Re-scrape")
                                    }
                                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(DesignSystem.Colors.warning)
                            }

                            if let err = schoolsLoadError {
                                Text(err)
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .foregroundColor(DesignSystem.Colors.error)
                                    .lineLimit(1)
                            } else if !availableSchools.isEmpty {
                                Text("\(availableSchools.count) schools")
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }

                            Spacer()
                        }

                        if showCollegeSuggestions {
                            let matches = filteredSchoolMatches(for: collegeNameDraft)

                            if matches.isEmpty {
                                Text(isLoadingSchools ? "Loading schools…" : "No matches. Tap ‘Load schools’. ")
                                    .font(DesignSystem.Fonts.main(size: 12))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .padding(.horizontal, 8)
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(matches.prefix(6)), id: \.id) { school in
                                        Button {
                                            selectSchool(school)
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(school.name)
                                                        .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                                                        .foregroundColor(DesignSystem.Colors.textMain)
                                                    if let short = school.shortName, !short.isEmpty {
                                                        Text(short)
                                                            .font(DesignSystem.Fonts.main(size: 12))
                                                            .foregroundColor(DesignSystem.Colors.textLight)
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: "arrow.down.left")
                                                    .foregroundColor(DesignSystem.Colors.textLight)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)

                                        Divider()
                                    }
                                }
                                .background(DesignSystem.Colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(cardBorderColor, lineWidth: 1)
                                )
                            }
                        }
                    }

                    Divider().opacity(0.7)

                    fieldLabel("Department/Program")
                    Menu {
                        Button("Select Department/Program") {
                            profile.department = nil
                            profile.major = nil
                            profile.secondaryMajor = nil
                            coreDataManager.save()
                        }

                        if availableDepartments.isEmpty {
                            Button("No departments available") { }
                                .disabled(true)
                        } else {
                            ForEach(Array(availableDepartmentGroups.enumerated()), id: \ .offset) { _, group in
                                Menu(group.group) {
                                    if group.departments.isEmpty {
                                        Button("No departments") { }
                                            .disabled(true)
                                    } else {
                                        ForEach(group.departments, id: \ .self) { dept in
                                            let majors = majorsForDepartmentSelection(dept)

                                            // Department selector (keeps existing behavior)
                                            Button(dept) {
                                                profile.department = dept
                                                profile.major = nil
                                                profile.secondaryMajor = nil
                                                coreDataManager.save()
                                            }

                                            // Program list under the department
                                            if !majors.isEmpty {
                                                ForEach(majors, id: \ .self) { major in
                                                    Button("•  \(major)") {
                                                        profile.department = dept
                                                        profile.major = major
                                                        profile.secondaryMajor = nil

                                                        if let collegeName = profile.collegeName {
                                                            let degreeType = coreDataManager.fetchDegreeType(for: major, universityName: collegeName)
                                                            profile.degreeType = degreeType
                                                        }

                                                        coreDataManager.save()
                                                    }
                                                }
                                            }

                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        pillContainer {
                            if let dept = profile.department, !dept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                menuValueLabel(value: profile.department, placeholder: "Select department/program…")
                            } else {
                                menuValueLabel(value: profile.major, placeholder: "Select department/program…")
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().opacity(0.25)

                    fieldLabel("Program")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Degree Level")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        Menu {
                            ForEach(DegreeConfiguration.allLevels, id: \.self) { level in
                                Button(level) {
                                    let newLevel = level
                                    profile.degreeLevel = newLevel

                                    let types = DegreeConfiguration.types(for: newLevel)
                                    if !types.isEmpty {
                                        profile.degreeType = types[0]
                                    }

                                    let standings = DegreeConfiguration.classStandings(for: newLevel)
                                    if let current = profile.classStanding, !standings.contains(current) {
                                        profile.classStanding = standings.first
                                    }

                                    profile.major = nil
                                    profile.secondaryMajor = nil
                                    profile.minor = nil

                                    // Department/school list is degree-level scoped.
                                    profile.department = nil

                                    coreDataManager.save()
                                }
                            }
                        } label: {
                            pillContainer {
                                menuValueLabel(value: profile.degreeLevel, placeholder: "Select degree level…")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                
                // Degree Type is now automatically set based on the selected major
                // No manual selection needed
                /*
                // Degree Type - Second dropdown (BS, BA, MS, PhD, etc.)
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEGREE TYPE")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    
                    Picker("", selection: Binding(
                        get: { 
                            // If no degree type is set yet, use the first available one
                            if let currentType = profile.degreeType, !availableDegreeTypes.isEmpty {
                                return availableDegreeTypes.contains(currentType) ? currentType : availableDegreeTypes[0]
                            }
                            return availableDegreeTypes.first ?? "BS"
                        },
                        set: { newType in
                            profile.degreeType = newType
                            
                            // Reset majors when degree type changes (different programs available)
                            profile.major = nil
                            profile.secondaryMajor = nil
                            profile.minor = nil
                            
                            coreDataManager.save()
                        }
                    )) {
                        ForEach(availableDegreeTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.bgMain)
                    .cornerRadius(12)
                    .overlay(
                        HStack {
                            // Display the degree type (short form if available, or the value itself)
                            let currentType = profile.degreeType ?? availableDegreeTypes.first ?? "BS"
                            let displayText = currentType.count <= 5 ? currentType : DegreeConfiguration.shortForm(from: currentType)
                            Text(displayText)
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)
                    )
                }
                */
                
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Primary Major")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)

                        Menu {
                            if availableMajors.isEmpty {
                                Button("No majors available") { }
                                    .disabled(true)
                            } else {
                                ForEach(availableMajors, id: \.self) { major in
                                    Button(major) {
                                        profile.major = major

                                        if let collegeName = profile.collegeName {
                                            let degreeType = coreDataManager.fetchDegreeType(for: major, universityName: collegeName)
                                            profile.degreeType = degreeType
                                        }

                                        coreDataManager.save()
                                    }
                                }
                            }
                        } label: {
                            pillContainer {
                                menuValueLabel(value: profile.major, placeholder: "Select major…")
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Secondary Major")
                                .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)

                            Menu {
                                Button("None") {
                                    profile.secondaryMajor = nil
                                    coreDataManager.save()
                                }
                                if availableMajors.isEmpty {
                                    Button("No majors available") { }
                                        .disabled(true)
                                } else {
                                    ForEach(availableMajors, id: \.self) { major in
                                        Button(major) {
                                            profile.secondaryMajor = major
                                            coreDataManager.save()
                                        }
                                    }
                                }
                            } label: {
                                pillContainer {
                                    menuValueLabel(value: profile.secondaryMajor, placeholder: "Select major…")
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if DegreeConfiguration.isUndergraduate(profile.degreeLevel ?? "Undergraduate") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Minor")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)

                                Menu {
                                    Button("None") {
                                        profile.minor = nil
                                        coreDataManager.save()
                                    }
                                    ForEach(availableMinors, id: \.self) { minor in
                                        Button(minor) {
                                            profile.minor = minor
                                            coreDataManager.save()
                                        }
                                    }
                                } label: {
                                    pillContainer {
                                        menuValueLabel(value: profile.minor, placeholder: "Select minor…")
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Certificate")
                                    .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)

                                Menu {
                                    Button("None") {
                                        profile.minor = nil
                                        coreDataManager.save()
                                    }
                                    if availableCertificates.isEmpty {
                                        Button("No certificates available") { }
                                            .disabled(true)
                                    } else {
                                        ForEach(availableCertificates, id: \.self) { cert in
                                            Button(cert) {
                                                profile.minor = (cert == "None") ? nil : cert
                                                coreDataManager.save()
                                            }
                                        }
                                    }
                                } label: {
                                    pillContainer {
                                        menuValueLabel(value: profile.minor, placeholder: "Select certificate…")
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .onAppear {
                    if collegeNameDraft.isEmpty {
                        collegeNameDraft = profile.collegeName ?? ""
                    }
                    if availableSchools.isEmpty {
                        availableSchools = githubService.loadCachedSchoolsList() ?? []
                    }
                }
            }
        }
        .padding(24)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    // MARK: - Autocomplete helpers

    private func filteredSchoolMatches(for query: String) -> [SchoolManifest] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        // If we don't have schools loaded yet, show nothing (and prompt user to load)
        guard !availableSchools.isEmpty else { return [] }

        // Prioritize prefix matches, then contains
        let lowerQ = q.lowercased()
        let prefix = availableSchools.filter {
            $0.name.lowercased().hasPrefix(lowerQ) || ($0.shortName?.lowercased().hasPrefix(lowerQ) ?? false)
        }
        let contains = availableSchools.filter {
            $0.name.lowercased().contains(lowerQ) || ($0.shortName?.lowercased().contains(lowerQ) ?? false)
        }

        // Preserve order while de-duping
        var seen = Set<String>()
        var result: [SchoolManifest] = []
        for s in (prefix + contains) {
            if seen.insert(s.id).inserted {
                result.append(s)
            }
        }
        return result
    }

    private func normalizeSchoolNameForMatch(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitSchoolName(_ name: String) {
        let previous = normalizeSchoolNameForMatch(profile.collegeName ?? "")
        let next = normalizeSchoolNameForMatch(name)

        profile.collegeName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only clear / restore selections when the school truly changed.
        if !next.isEmpty, previous != next {
            coreDataManager.setActiveUniversity(named: profile.collegeName ?? "")
        } else {
            coreDataManager.save()
        }
    }

    @MainActor
    private func refreshSchoolsList() async {
        let logger = DebugLogger.shared
        logger.logSection("REFRESHING SCHOOLS LIST")

        schoolsLoadError = nil
        isLoadingSchools = true
        defer { isLoadingSchools = false }

        do {
            logger.log("📡 Fetching schools from GitHub...")
            let schools = try await githubService.fetchSchoolsList()
            availableSchools = schools
            
            logger.log("✅ Loaded \(schools.count) schools:")
            for school in schools {
                logger.log("   • \(school.name)")
                logger.log("     ID: \(school.id)")
                logger.log("     Catalog URL: \(school.catalogURL ?? "nil")")
                logger.log("     Format: \(school.catalogFormat)")
            }
            try? githubService.cacheSchoolsList(schools)
        } catch {
            // Surface the actual error so issues like 404/403/400 show the real cause + URL.
            schoolsLoadError = error.localizedDescription
        }
    }

    private func selectSchool(_ school: SchoolManifest) {
        // Fill field
        collegeNameDraft = school.name
        commitSchoolName(school.name)

        showCollegeSuggestions = false
        
        // Automatically scrape catalog from school's website
        Task {
            await scrapeAndImportCatalog(school: school)
        }
    }
    
    /// Clean up department names by removing common artifacts
    private func cleanDepartmentName(_ name: String) -> String {
        // Normalize whitespace first (ModernCampus often uses NBSP \u00A0)
        var cleaned = name.normalizedCatalogText()

        let lower = cleaned.lowercased()
        
        // Filter out noise entries
        if lower.isEmpty || 
           lower == "learn more about the" || 
           lower == "program office" || 
           lower == "program office:" ||
           lower.count < 3 {
            return ""
        }
        
        // Remove common artifacts
        cleaned = cleaned.replacingOccurrences(of: " department page", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: " page", with: "", options: .caseInsensitive)
        
        // Remove " department" suffix UNLESS it's "Department of X"
        if !lower.hasPrefix("department of") && lower.hasSuffix(" department") {
            cleaned = cleaned.replacingOccurrences(of: " department", with: "", options: [.caseInsensitive, .anchored, .backwards])
        }
        
        // Trim again after replacements
        cleaned = cleaned.normalizedCatalogText()
        
        return cleaned
    }

    private func extractCatoid(fromAcalogURL urlString: String) -> String? {
        guard let components = URLComponents(string: urlString) else { return nil }
        let catoid = components.queryItems?.first(where: { $0.name.lowercased() == "catoid" })?.value
        let trimmed = (catoid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func inferDegreeLevel(fromCatalogTitle title: String) -> String? {
        let t = title.normalizedCatalogText().lowercased()
        if t.isEmpty { return nil }

        // Prefer explicit doctoral/PhD cues.
        if t.contains("phd") || t.contains("ph.d") || t.contains("doctoral") || t.contains("doctor of") {
            return "PhD"
        }
        
        // Check "undergraduate" BEFORE "graduate" to avoid false substring matches!
        if t.contains("undergraduate") {
            return "Undergraduate"
        }

        // Catalog-wide titles that imply post-baccalaureate / professional programs.
        // UB splits these into separate catalogs (graduate/law/medical/dental).
        if t.contains("graduate") || t.contains("law") || t.contains("medical") || t.contains("medicine") || t.contains("dental") {
            return "Graduate"
        }

        return nil
    }
    
    /// Scrape course catalog from school's website and import into Core Data
    /// - Parameter forceRescrape: If true, ignores existing data and re-scrapes everything
    private func scrapeAndImportCatalog(school: SchoolManifest, forceRescrape: Bool = false) async {
        let logger = DebugLogger.shared

        func setCatalogStatus(message: String? = nil, isDownloading: Bool? = nil, showStatus: Bool? = nil) async {
            await MainActor.run {
                if let isDownloading { isDownloadingCatalog = isDownloading }
                if let message { catalogDownloadMessage = message }
                if let showStatus { showCatalogStatus = showStatus }
            }
        }

        let toastID = await MainActor.run {
            isDownloadingCatalog = true
            catalogDownloadMessage = "Connecting to \(school.name) catalog..."
            showCatalogStatus = true
            return notifications.post(
                kind: .progress,
                title: "Scraping Catalog",
                message: "Connecting to \(school.name)…",
                progress: 0.05,
                isDismissible: true
            )
        }
        
        logger.logSection("SCRAPING ATTEMPT")
        logger.log("🔍 Starting scrape for: \(school.name)")
        logger.log("School ID: \(school.id)")
        logger.log("Catalog URL: \(school.catalogURL ?? "nil")")
        logger.log("Catalog Format: \(school.catalogFormat)")
        
        do {
            // Get catalog URL from school manifest
            guard let catalogURL = school.catalogURL, !catalogURL.isEmpty else {
                logger.log("❌ catalogURL is nil or empty")
                await setCatalogStatus(message: "Error: No catalog URL configured for \(school.name)")
                throw ScraperError.invalidURL
            }

            await MainActor.run {
                notifications.update(id: toastID, message: "Scraping course list…", progress: 0.15)
            }

            logger.log("✓ Validated catalog URL: \(catalogURL)")
            await setCatalogStatus(message: "Scraping courses from \(catalogURL)...")

            // 1) Scrape courses and programs.
            // For UB (ModernCampus gateway), scrape *all* active catalogs (undergrad/grad/law/medical/dental)
            // and then import once. This avoids per-catalog ghost-archiving.
            var courses: [CatalogCourse] = []
            var programs: [ScrapedProgram] = []
            var coursesWereSkippedByIncremental = false
            var courseScrapeStatesToUpsert: [(catoid: String, title: String, count: Int)] = []

            logger.log("📋 Starting course extraction...")
            logger.log("Format: \(school.catalogFormat.lowercased())")

            let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
            guard let baseURL = URL(string: normalizedCatalogURL) else {
                logger.log("❌ Invalid normalized catalog URL: \(normalizedCatalogURL)")
                await setCatalogStatus(message: "Error: Invalid catalog URL for \(school.name)")
                throw ScraperError.invalidURL
            }

            // Determine which catalogs to scrape.
            let catalogsToScrape: [ModernCampusCatalogDescriptor]
            if school.catalogFormat.lowercased() == "acalog" {
                // Try multi-catalog discovery where supported (UB).
                let discovered = (try? await ModernCampusEngine.discoverActiveCatalogs(baseURL: normalizedCatalogURL)) ?? []
                if !discovered.isEmpty {
                    catalogsToScrape = discovered
                } else {
                    let catalogID = try await (catoidHint != nil ? catoidHint! : ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL))
                    catalogsToScrape = [ModernCampusCatalogDescriptor(catoid: catalogID, title: "Catalog")]
                }
            } else {
                catalogsToScrape = []
            }

            // When multi-catalog discovery is available (e.g., UB), we always scrape *all* discovered catalogs
            // in a single run. Degree-level selection in the UI should only affect filtering, not ingestion.
            let catalogTitleByCatoid: [String: String] = Dictionary(
                uniqueKeysWithValues: catalogsToScrape.map { ($0.catoid, $0.title) }
            )

            if school.catalogFormat.lowercased() == "acalog", !catalogsToScrape.isEmpty {
                logger.log("📚 Multi-catalog scrape: \(catalogsToScrape.count) catalog(s)")

                // Incremental scrape: avoid re-scraping catalogs that are already stored in Core Data.
                // We key programs/requirements by catoid present in their program URLs.
                let catoids = catalogsToScrape.map { $0.catoid }
                let coverage = await coreDataManager.scrapeCoverage(universityName: school.name, catoids: catoids)
                logger.log("🧪 CoreData coverage: courses=\(coverage.totalCourses)")
                for cat in catalogsToScrape {
                    let cCount = coverage.coursesByCatoid[cat.catoid] ?? 0
                    let pCount = coverage.programsByCatoid[cat.catoid] ?? 0
                    let rCount = coverage.requirementsByCatoid[cat.catoid] ?? 0
                    logger.log("🧪 CoreData coverage [\(cat.catoid)]: courses=\(cCount) programs=\(pCount) requirements=\(rCount) title='\(cat.title)'")
                }

                struct CatalogScrapeResult {
                    let catalog: ModernCampusCatalogDescriptor
                    let courses: [CatalogCourse]
                    let programs: [ScrapedProgram]
                    let courseError: Error?
                    let programError: Error?
                    let skippedCourses: Bool
                    let skippedPrograms: Bool
                }

                // Bound concurrency across catalogs so we don't effectively multiply per-catalog crawl concurrency.
                actor CatalogLimiter {
                    private var available: Int
                    private var waiters: [CheckedContinuation<Void, Never>] = []

                    init(value: Int) { self.available = max(1, value) }

                    func acquire() async {
                        if available > 0 {
                            available -= 1
                            return
                        }
                        await withCheckedContinuation { cont in
                            waiters.append(cont)
                        }
                    }

                    nonisolated func release() {
                        Task { await self._release() }
                    }

                    private func _release() {
                        if !waiters.isEmpty {
                            let cont = waiters.removeFirst()
                            cont.resume()
                            return
                        }
                        available += 1
                    }
                }

                // Program scraping can be request-heavy (especially if requirements are fetched).
                // Keep catalog-level concurrency modest to reduce WAF/timeout failures.
                let maxConcurrentCatalogs = min(3, max(1, catalogsToScrape.count))
                let limiter = CatalogLimiter(value: maxConcurrentCatalogs)

                var byCode: [String: CatalogCourse] = [:]
                byCode.reserveCapacity(20000)
                var programSet = Set<ScrapedProgram>()

                var skippedAllCourses = true

                let startedAt = Date()
                var completedCatalogs = 0

                await withTaskGroup(of: CatalogScrapeResult.self) { group in
                    for cat in catalogsToScrape {
                        group.addTask {
                            if Task.isCancelled {
                                return CatalogScrapeResult(catalog: cat, courses: [], programs: [], courseError: nil, programError: nil, skippedCourses: false, skippedPrograms: false)
                            }
                            await limiter.acquire()
                            defer { limiter.release() }

                            var fetchedCourses: [CatalogCourse] = []
                            var scrapedPrograms: [ScrapedProgram] = []
                            var courseError: Error? = nil
                            var programError: Error? = nil

                            // Decide what we should scrape for this catalog.
                            // - If we already have programs for this catoid, skip program scraping (unless force re-scrape).
                            // - Courses: use the per-catoid course scrape marker for exact incremental behavior.
                            let existingPrograms = coverage.programsByCatoid[cat.catoid] ?? 0
                            let existingRequirements = coverage.requirementsByCatoid[cat.catoid] ?? 0
                            // Export is requirement-driven; if requirements are missing for a catoid,
                            // we must scrape programs again even if program shells exist.
                            let shouldScrapePrograms = forceRescrape || (existingPrograms == 0) || (existingRequirements == 0)

                            logger.log("📊 [\(cat.catoid)] Incremental decision: forceRescrape=\(forceRescrape), existingPrograms=\(existingPrograms), existingRequirements=\(existingRequirements), shouldScrapePrograms=\(shouldScrapePrograms)")

                            let existingCoursesForCatoid = coverage.coursesByCatoid[cat.catoid] ?? 0
                            var shouldScrapeCourses = forceRescrape || existingCoursesForCatoid == 0

                        // Targeted cross-catalog backfill: if requirements reference LAW courses but
                        // catalog course rows are missing/incomplete, force a Law catalog course crawl.
                        if !shouldScrapeCourses {
                            let titleLower = cat.title.lowercased()
                            if titleLower.contains("law") {
                                let needsLawBackfill = await coreDataManager.shouldForceCourseRescrapeForSubject(
                                    universityName: school.name,
                                    subjectPrefix: "LAW"
                                )
                                if needsLawBackfill {
                                    logger.log("🧩 [\(cat.catoid)] Forcing course rescrape for Law catalog (requirements reference LAW; courses missing/incomplete)")
                                    shouldScrapeCourses = true
                                }
                            }
                        }

                            let skippedCourses = !shouldScrapeCourses
                            let skippedPrograms = !shouldScrapePrograms

                            do {
                                if shouldScrapeCourses {
                                    fetchedCourses = try await ModernCampusEngine.fetchAllCourses(baseURL: normalizedCatalogURL, catoid: cat.catoid)
                                }
                            } catch {
                                courseError = error
                            }

                            do {
                                if shouldScrapePrograms {
                                    logger.log("🔍 [\(cat.catoid)] SCRAPING PROGRAMS (catalog title: '\(cat.title)')")
                                    let universalScraper = UniversalCatalogScraper()
                                    let catIDInt = Int(cat.catoid) ?? 0
                                    scrapedPrograms = try await universalScraper.scrapeAllPrograms(baseURL: baseURL, catalogID: catIDInt)
                                    logger.log("🔍 [\(cat.catoid)] SCRAPE RETURNED \(scrapedPrograms.count) programs")
                                } else {
                                    logger.log("⏭️ [\(cat.catoid)] SKIPPING PROGRAMS (existingPrograms=\(existingPrograms), existingRequirements=\(existingRequirements))")
                                }
                            } catch {
                                programError = error
                                logger.log("❌ [\(cat.catoid)] PROGRAM SCRAPE ERROR: \(error)")
                            }

                            return CatalogScrapeResult(
                                catalog: cat,
                                courses: fetchedCourses,
                                programs: scrapedPrograms,
                                courseError: courseError,
                                programError: programError,
                                skippedCourses: skippedCourses,
                                skippedPrograms: skippedPrograms
                            )
                        }
                    }

                    for await result in group {
                        completedCatalogs += 1
                        let label = result.catalog.title.isEmpty ? "Catalog" : result.catalog.title

                        if !result.skippedCourses { skippedAllCourses = false }

                        if let err = result.courseError {
                            logger.log("⚠️ [\(result.catalog.catoid)] Course scrape failed: \(err)")
                        } else if result.skippedCourses {
                            logger.log("⏭️ [\(result.catalog.catoid)] Skipped courses (already present)")
                        } else {
                            logger.log("✅ [\(result.catalog.catoid)] Courses: \(result.courses.count)")

                            // Defer updating scrape-state until *after* the course import succeeds.
                            if !result.courses.isEmpty {
                                courseScrapeStatesToUpsert.append(
                                    (catoid: result.catalog.catoid, title: result.catalog.title, count: result.courses.count)
                                )
                            }
                        }

                        if let err = result.programError {
                            logger.log("⚠️ [\(result.catalog.catoid)] Program scrape failed: \(err)")
                        } else if result.skippedPrograms {
                            logger.log("⏭️ [\(result.catalog.catoid)] Skipped programs (already present)")
                        } else {
                            logger.log("✅ [\(result.catalog.catoid)] Programs: \(result.programs.count)")
                        }

                        for c in result.courses {
                        func normalizeCourseKey(_ raw: String) -> String {
                            let cleaned = raw
                                .replacingOccurrences(of: "\u{00A0}", with: " ")
                                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .uppercased()
                            if let re = try? NSRegularExpression(pattern: "\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4})\\b") {
                                let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                                if let m = re.firstMatch(in: cleaned, range: nsRange), m.numberOfRanges >= 3,
                                   let r1 = Range(m.range(at: 1), in: cleaned),
                                   let r2 = Range(m.range(at: 2), in: cleaned) {
                                    return "\(cleaned[r1]) \(cleaned[r2])"
                                }
                            }
                            return cleaned
                        }

                        func normalizedText(_ s: String?) -> String {
                            (s ?? "")
                                .replacingOccurrences(of: "\u{00A0}", with: " ")
                                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        func isLowQualityTitle(_ title: String, code: String) -> Bool {
                            let t = normalizedText(title)
                            let c = normalizedText(code)
                            return t.isEmpty || (!c.isEmpty && t.caseInsensitiveCompare(c) == .orderedSame)
                        }

                        func mergeCourses(existing: CatalogCourse, incoming: CatalogCourse, normalizedCode: String) -> CatalogCourse {
                            let existingDesc = normalizedText(existing.description)
                            let incomingDesc = normalizedText(incoming.description)
                            let existingTitle = normalizedText(existing.title)
                            let incomingTitle = normalizedText(incoming.title)
                            let existingDept = normalizedText(existing.department)
                            let incomingDept = normalizedText(incoming.department)

                            let bestTitle: String = {
                                if isLowQualityTitle(existingTitle, code: normalizedCode), !isLowQualityTitle(incomingTitle, code: normalizedCode) {
                                    return incomingTitle
                                }
                                if incomingTitle.count > existingTitle.count, !isLowQualityTitle(incomingTitle, code: normalizedCode) {
                                    return incomingTitle
                                }
                                return existingTitle.isEmpty ? normalizedCode : existingTitle
                            }()

                            let bestDesc: String? = {
                                if existingDesc.isEmpty, !incomingDesc.isEmpty { return incomingDesc }
                                return existingDesc.isEmpty ? (incomingDesc.isEmpty ? nil : incomingDesc) : existingDesc
                            }()

                            let bestCredits: Int = {
                                if existing.credits <= 0, incoming.credits > 0 { return incoming.credits }
                                return existing.credits
                            }()

                            let bestDept: String? = {
                                if existingDept.isEmpty, !incomingDept.isEmpty { return incomingDept }
                                return existingDept.isEmpty ? nil : existingDept
                            }()

                            return CatalogCourse(
                                id: existing.id,
                                courseCode: normalizedCode,
                                title: bestTitle,
                                description: bestDesc,
                                credits: bestCredits,
                                department: bestDept,
                                prerequisites: existing.prerequisites ?? incoming.prerequisites,
                                prerequisiteText: existing.prerequisiteText ?? incoming.prerequisiteText,
                                corequisites: existing.corequisites ?? incoming.corequisites,
                                typicallyOffered: existing.typicallyOffered ?? incoming.typicallyOffered
                            )
                        }

                        let normalizedCode = normalizeCourseKey(c.courseCode)
                        let incomingNormalized = CatalogCourse(
                            id: c.id,
                            courseCode: normalizedCode,
                            title: c.title,
                            description: c.description,
                            credits: c.credits,
                            department: c.department,
                            prerequisites: c.prerequisites,
                            prerequisiteText: c.prerequisiteText,
                            corequisites: c.corequisites,
                            typicallyOffered: c.typicallyOffered
                        )

                        if let existing = byCode[normalizedCode] {
                            byCode[normalizedCode] = mergeCourses(existing: existing, incoming: incomingNormalized, normalizedCode: normalizedCode)
                        } else {
                            byCode[normalizedCode] = incomingNormalized
                        }
                        }

                        for p in result.programs { programSet.insert(p) }

                        await MainActor.run {
                            let progressWithinScrape = Double(completedCatalogs) / Double(max(1, catalogsToScrape.count))
                            let progress = 0.15 + (0.18 * progressWithinScrape)
                            notifications.update(id: toastID, message: "Scraping \(label)… (\(completedCatalogs)/\(catalogsToScrape.count))", progress: progress)
                        }
                    }
                }

                let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
                logger.log(String(format: "📚 Multi-catalog scrape finished: catalogs=%d elapsed=%.2fs", catalogsToScrape.count, elapsed))

                courses = Array(byCode.values).sorted { $0.courseCode < $1.courseCode }
                programs = Array(programSet).sorted { $0.name < $1.name }

                // If incremental behavior skipped course scraping for every catalog, we must NOT import
                // an empty course list (that could archive existing data). Keep courses empty and
                // remember that this was a deliberate skip.
                if skippedAllCourses {
                    coursesWereSkippedByIncremental = true
                }
            } else {
                // Legacy single-catalog behavior (Banner/custom or non-multi-catalog Acalog).
                switch school.catalogFormat.lowercased() {
                case "acalog":
                    logger.log("Using Acalog scraper")
                    await setCatalogStatus(message: "Detected Acalog system, scraping...")
                    courses = try await scraperService.scrapeAcalog(url: catalogURL)

                    // If the entry URL doesn't contain a global course list (common on ModernCampus),
                    // try the robots-compliant Course Descriptions content page.
                    if courses.isEmpty {
                        logger.log("⚠️ Entry scrape returned 0 courses; attempting Course Descriptions crawl...")
                        let catalogID = try await (catoidHint != nil ? catoidHint! : ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL))
                        let crawled = try await ModernCampusEngine.fetchAllCourses(baseURL: normalizedCatalogURL, catoid: catalogID)
                        if !crawled.isEmpty {
                            courses = crawled
                            logger.log("✅ Course Descriptions crawl found \(courses.count) courses")
                        } else {
                            logger.log("⚠️ Course Descriptions crawl returned 0 courses")
                        }
                    }
                case "banner":
                    logger.log("Using Banner scraper")
                    await setCatalogStatus(message: "Detected Banner system, scraping...")
                    courses = try await scraperService.scrapeBanner(url: catalogURL)
                default:
                    logger.log("Using default (Acalog) scraper")
                    await setCatalogStatus(message: "Attempting to scrape catalog...")
                    courses = try await scraperService.scrapeAcalog(url: catalogURL)
                }
            }

            await MainActor.run {
                notifications.update(id: toastID, message: "Importing \(courses.count) courses…", progress: 0.35)
            }
            
            logger.log("✅ Found \(courses.count) courses")
            await setCatalogStatus(message: "Found \(courses.count) courses, importing...")
            
            // 2. Create SchoolProfile structure with scraped data
            let schoolProfile = SchoolProfile(
                schoolID: school.id,
                schoolName: school.name,
                catalogURL: normalizedCatalogURL,
                version: (school.catalogFormat.lowercased() == "acalog" && !catalogsToScrape.isEmpty)
                    ? "1.0.0-scraped-multi-catalog"
                    : "1.0.0-scraped",
                lastUpdated: Date(),
                courses: courses,
                degreeRequirements: [], // Will be populated manually or scraped separately
                policies: SchoolPolicies(
                    transferCreditLimit: nil,
                    minorTransferLimit: nil,
                    maxCreditsPerSemester: nil,
                    minCreditsForFullTime: nil,
                    gradeForCredit: nil,
                    repeatCoursePolicy: nil
                )
            )
            
            // 3. Import courses into Core Data
            if coursesWereSkippedByIncremental {
                logger.log("⏭️ Skipping course import (incremental: courses already present)")
            } else if courses.isEmpty {
                logger.log("⚠️ Skipping course import (0 courses scraped)")
            } else {
                logger.log("💾 Importing courses to Core Data...")
                try await coreDataManager.importSchoolCatalog(schoolProfile)
                logger.log("✅ Imported \(courses.count) courses")

                // Now that import succeeded, persist per-catalog completion markers.
                for state in courseScrapeStatesToUpsert {
                    await coreDataManager.upsertCourseScrapeState(
                        universityName: school.name,
                        catoid: state.catoid,
                        catalogTitle: state.title,
                        courseCount: state.count
                    )
                }
            }

            await MainActor.run {
                notifications.update(id: toastID, message: "Discovering catalog version…", progress: 0.5)
            }
            
            // 4. Use UniversalCatalogScraper for hierarchy (departments, colleges, majors)
            await setCatalogStatus(message: "Scraping academic programs...")
            logger.log("🧭 Starting UniversalCatalogScraper...")

            await MainActor.run {
                notifications.update(id: toastID, message: "Scraping programs…", progress: 0.65)
            }

			let universalScraper = UniversalCatalogScraper()

            // If we didn't already scrape programs during multi-catalog pass, do the legacy single-catalog scrape.
            if programs.isEmpty, school.catalogFormat.lowercased() == "acalog" {
                logger.log("🔎 Discovering current catalog ID...")
                let catalogID = try await (catoidHint != nil ? catoidHint! : ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL))
                logger.log("✅ Using catalog ID: \(catalogID)")
                let catalogIDInt = Int(catalogID) ?? 0
                programs = try await universalScraper.scrapeAllPrograms(baseURL: baseURL, catalogID: catalogIDInt)
            }

            logger.log("✅ Universal scraper found \(programs.count) programs")

            await MainActor.run {
                notifications.update(id: toastID, message: "Saving programs and departments…", progress: 0.85)
            }

            // 4b. If we failed to extract a global course list, derive courses by crawling major/minor
            // program requirements pages and aggregating unique course codes.
            if courses.isEmpty, !coursesWereSkippedByIncremental {
                logger.log("⚠️ No global courses found on catalog entry URL; deriving courses from Major/Minor program pages...")
                await setCatalogStatus(message: "No global course list found; scanning majors/minors for courses...")

                let targetPrograms = programs.filter { p in
                    let t = p.type.lowercased()
                    return t == "major" || t == "minor"
                }

                var codeSet = Set<String>()
                codeSet.reserveCapacity(4096)

                // Crawl program pages concurrently (bounded) to speed up large catalogs.
                let maxConcurrent = 8
                var nextIndex = 0
                var completed = 0

                await withTaskGroup(of: Set<String>.self) { group in
                    func enqueue(_ program: ScrapedProgram) {
                        group.addTask {
                            if Task.isCancelled { return Set<String>() }
                            do {
                                let reqs = try await universalScraper.scrapeProgramRequirements(programURL: program.url)
                                return extractCourseCodes(from: reqs)
                            } catch {
                                // Avoid spamming logs; individual failures are expected.
                                return Set<String>()
                            }
                        }
                    }

                    let initial = min(maxConcurrent, targetPrograms.count)
                    if initial > 0 {
                        logger.log("📚 Scanning programs for courses: 0/\(targetPrograms.count) (concurrency=\(maxConcurrent))")
                    }

                    for _ in 0..<initial {
                        enqueue(targetPrograms[nextIndex])
                        nextIndex += 1
                    }

                    for await codes in group {
                        completed += 1
                        if !codes.isEmpty {
                            codeSet.formUnion(codes)
                        }

                        if completed % 20 == 0 || completed == targetPrograms.count {
                            logger.log("📚 Scanning programs for courses: \(completed)/\(targetPrograms.count)")
                        }

                        if nextIndex < targetPrograms.count {
                            enqueue(targetPrograms[nextIndex])
                            nextIndex += 1
                        }
                    }
                }

                let derivedCodes = codeSet.sorted()
                let derivedCourses: [CatalogCourse] = derivedCodes.map { code in
                    let dept = code.split(separator: " ").first.map(String.init)
                    return CatalogCourse(
                        id: UUID(),
                        courseCode: code,
                        title: code,
                        description: nil,
                        credits: 0,
                        department: dept,
                        prerequisites: nil,
                        corequisites: nil,
                        typicallyOffered: nil
                    )
                }

                courses = derivedCourses
                logger.log("✅ Derived \(courses.count) unique course codes from \(targetPrograms.count) programs")
                await setCatalogStatus(message: "Derived \(courses.count) courses from majors/minors, importing...")

                // Re-import just to populate CourseCatalogEntity rows.
                let fallbackProfile = SchoolProfile(
                    schoolID: school.id,
                    schoolName: school.name,
                    catalogURL: catalogURL,
                    version: "1.0.0-derived-from-programs",
                    lastUpdated: Date(),
                    courses: courses,
                    degreeRequirements: [],
                    policies: SchoolPolicies(
                        transferCreditLimit: nil,
                        minorTransferLimit: nil,
                        maxCreditsPerSemester: nil,
                        minCreditsForFullTime: nil,
                        gradeForCredit: nil,
                        repeatCoursePolicy: nil
                    )
                )

                logger.log("💾 Importing derived courses to Core Data...")
                try await coreDataManager.importSchoolCatalog(fallbackProfile)
                logger.log("✅ Imported \(courses.count) derived courses")
            }
            
            // Extract unique departments from scraped programs
            var departmentSet = Set<String>()
            var collegeSet = Set<String>()
            for program in programs {
                if let dept = program.department {
                    // Clean up department name before adding to set
                    let cleanedDept = cleanDepartmentName(dept)
                    if !cleanedDept.isEmpty {
                        departmentSet.insert(cleanedDept)
                    }
                }
                if let college = program.college {
                    let cleanedCollege = college.normalizedCatalogText()
                    if !cleanedCollege.isEmpty {
                        collegeSet.insert(cleanedCollege)
                    }
                }
            }
            
            logger.log("✅ Extracted \(departmentSet.count) departments and \(collegeSet.count) colleges")
            
            // Save departments with college associations
            await setCatalogStatus(message: "Saving departments and colleges...")
            let departmentsWithSchools = departmentSet.sorted().map { cleanedDept in
                // Find which college this department belongs to by looking at programs.
                // IMPORTANT: don't take the first match, because many UB program pages have college=nil.
                // Instead, pick the *best available* college among all programs that share the dept.
                let matchingPrograms = programs.filter { program in
                    guard let originalDept = program.department else { return false }
                    return cleanDepartmentName(originalDept) == cleanedDept
                }

                // Prefer a non-empty college from any matching program.
                let college = matchingPrograms
                    .compactMap { $0.college?.normalizedCatalogText() }
                    .first(where: { !$0.isEmpty })

                return (name: cleanedDept, code: nil as String?, school: college)
            }
            
            try coreDataManager.saveDepartments(departmentsWithSchools, for: school.name)
            logger.log("💾 Saved \(departmentsWithSchools.count) departments to Core Data")
            
            // Save majors with hierarchy information
            await setCatalogStatus(message: "Saving \(programs.count) programs...")
            
            // Convert ScrapedProgram to the tuple format expected by saveMajors
            var debugProgramCount = 0
            let majorsForSaving = programs.map { program -> (
                name: String,
                degreeLevel: String,
                degreeType: String?,
                isMinor: Bool,
                department: String?,
                url: String?,
                resolvedDepartment: String?,
                resolvedCollege: String?,
                mappingConfidence: Double?,
                mappingSource: String?,
                requirements: [DegreeRequirement]?
            ) in
                let isMinor = program.type.lowercased().contains("minor")

                func normalizeDegreeLevelToken(_ raw: String) -> String {
                    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { return "" }
                    let lower = t.lowercased()
                    
                    // Keep known canonical values as-is (check first to avoid false matches).
                    if t == "Undergraduate" || t == "Graduate" || t == "PhD" || t == "Combined" { return t }
                    
                    if lower.contains("combined") { return "Combined" }
                    
                    // Check "undergraduate" BEFORE "graduate" to avoid false matches!
                    if lower.contains("undergraduate") { return "Undergraduate" }
                    
                    // Only treat explicitly PhD/Doctor of Philosophy as "PhD".
                    // Professional doctorates (JD/MD/DDS/etc.) should appear under "Graduate" for UX.
                    if lower.contains("phd") || lower.contains("ph.d") || lower.contains("doctor of philosophy") {
                        return "PhD"
                    }
                    
                    // Map heuristic values to canonical values
                    if lower.contains("doctorate") || lower.contains("professional") {
                        return "Graduate"
                    }
                    if lower.contains("master") || lower.contains("graduate") {
                        return "Graduate"
                    }
                    if lower.contains("juris doctor") || lower.contains("jd") { return "Graduate" }
                    if lower.contains("doctor of medicine") || lower.contains("md") { return "Graduate" }
                    if lower.contains("dds") || lower.contains("dmd") || lower.contains("dental") { return "Graduate" }
                    if lower.contains("dpt") || lower.contains("pharmd") { return "Graduate" }
                    
                    // Any unrecognized value defaults to Graduate if it looks professional
                    if lower.contains("law") || lower.contains("medical") || lower.contains("medicine") { return "Graduate" }
                    return t
                }

                // Prefer catalog-level truth (via catoid) over name/degree heuristics.
                let catoid = extractCatoid(fromAcalogURL: program.url)
                let titleHint = catoid.flatMap { catalogTitleByCatoid[$0] }
                let heuristicLevel = deriveDegreeLevelForProgram(
                    isMinor: isMinor,
                    programType: program.type,
                    degreeType: program.degreeType,
                    programName: program.name
                )

                // If we can detect a PhD/doctoral program from the program itself, keep that signal.
                // (Doctoral programs are often published inside catalogs titled "Graduate".)
                let catalogLevel = titleHint.flatMap(inferDegreeLevel(fromCatalogTitle:)).map(normalizeDegreeLevelToken)
                let heuristicNormalized = normalizeDegreeLevelToken(heuristicLevel)
                
                // DEBUG: Log degree level determination for first few programs
                let shouldLogDebug = debugProgramCount < 5
                if shouldLogDebug {
                    logger.log("🔍 [DegreeLevel Debug] program=\(program.name)")
                    logger.log("🔍   catoid=\(catoid ?? "nil"), titleHint=\(titleHint ?? "nil")")
                    logger.log("🔍   catalogLevel=\(catalogLevel ?? "nil"), heuristicNormalized=\(heuristicNormalized)")
                }
                debugProgramCount += 1
                
                // Determine the final degree level, preferring catalog info
                var degreeLevel: String
                if heuristicNormalized == "PhD" {
                    degreeLevel = "PhD"
                } else if let catLevel = catalogLevel {
                    degreeLevel = catLevel
                } else if !heuristicNormalized.isEmpty {
                    degreeLevel = heuristicNormalized
                } else {
                    degreeLevel = "Undergraduate"
                }
                
                // Map internal values to UI values for consistency with DegreeConfiguration
                // The UI uses: "Undergraduate", "Graduate (Masters)", "Doctorate / Professional"
                // But the scraper logic uses: "Undergraduate", "Graduate", "PhD"
                switch degreeLevel {
                case "Graduate":
                    degreeLevel = "Graduate (Masters)"
                case "PhD":
                    degreeLevel = "Doctorate / Professional"
                case "Combined":
                    // Combined degrees should probably be categorized based on the highest level
                    degreeLevel = "Graduate (Masters)"
                default:
                    // Keep "Undergraduate" and any other values as-is
                    break
                }
                
                // DEBUG: Log final degree level
                if shouldLogDebug {
                    logger.log("🔍   Final degreeLevel=\(degreeLevel)")
                }
                
                // Debug logging for degree level assignment issues
                if catalogLevel == nil && catoid != nil {
                    logger.log("⚠️ Program degree level fallback: catoid=\(catoid ?? "nil"), titleHint=\(titleHint ?? "nil"), catalogLevel=nil, using heuristic=\(degreeLevel) for program=\(program.name)")
                }
                if catoid == nil {
                    logger.log("⚠️ No catoid found in URL for program: \(program.name) url=\(program.url)")
                }
                
                return (
                    name: program.name,
                    degreeLevel: degreeLevel,
                    degreeType: program.degreeType, // Use the extracted degree type (BS, BA, etc.)
                    isMinor: isMinor,
                    department: program.department,
                    url: program.url,
                    resolvedDepartment: program.department,
                    resolvedCollege: program.college,
                    mappingConfidence: 1.0, // High confidence from direct scraping
                    mappingSource: "UniversalCatalogScraper",
                    requirements: program.requirements
                )
            }
            
            try coreDataManager.saveMajors(majorsForSaving, for: school.name)
            logger.log("💾 Saved \(programs.count) programs to Core Data")

#if DEBUG
            if let url = coreDataManager.debugExportProgramsTSV(for: school.name) {
                logger.log("🧾 Exported programs TSV: \(url.path)")
            }

            let otherSources = coreDataManager.debugOtherDepartmentSources(for: school.name)
            if !otherSources.isEmpty {
                logger.logSection("(OTHER) DEPARTMENT SOURCES")
                for (dept, programs) in otherSources.sorted(by: { $0.key < $1.key }) {
                    logger.log("• \(dept)  [\(programs.count) program(s)]")
                    for p in programs.prefix(10) {
                        logger.log("    - \(p)")
                    }
                    if programs.count > 10 {
                        logger.log("    ... and \(programs.count - 10) more")
                    }
                }
            }
#endif
            
            // 5. Show success
            logger.log("🎉 SUCCESS! Complete catalog import:")
            logger.log("   • \(courses.count) courses")
            logger.log("   • \(departmentsWithSchools.count) departments")
            logger.log("   • \(programs.count) programs")
            
            await setCatalogStatus(message: "✓ Successfully imported \(courses.count) courses, \(departmentsWithSchools.count) departments, and \(programs.count) programs from \(school.name)")

            await MainActor.run {
                notifications.complete(
                    id: toastID,
                    kind: .success,
                    title: "Catalog Imported",
                    message: "\(school.name): \(courses.count) courses, \(programs.count) programs.",
                    autoDismissAfter: 4
                )
                
                // After successful import, set a default degreeLevel if none is selected
                // so that departments/majors/minors become visible in dropdowns.
                if profile.degreeLevel == nil || profile.degreeLevel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    // Check what degree levels are available for this university
                    let availableLevels = DegreeConfiguration.allLevels.filter { level in
                        let depts = coreDataManager.fetchDepartments(for: school.name, degreeLevel: level)
                        return !depts.isEmpty
                    }
                    
                    // Prefer Undergraduate, then Graduate, then PhD, then Combined, then first available
                    if availableLevels.contains("Undergraduate") {
                        profile.degreeLevel = "Undergraduate"
                    } else if availableLevels.contains("Graduate") {
                        profile.degreeLevel = "Graduate"
                    } else if availableLevels.contains("PhD") {
                        profile.degreeLevel = "PhD"
                    } else if availableLevels.contains("Combined") {
                        profile.degreeLevel = "Combined"
                    } else if let first = availableLevels.first {
                        profile.degreeLevel = first
                    } else {
                        // Fallback if no programs found (shouldn't happen after successful import)
                        profile.degreeLevel = "Undergraduate"
                    }
                    
                    // Set a matching degree type
                    if let level = profile.degreeLevel {
                        let types = DegreeConfiguration.types(for: level)
                        if !types.isEmpty {
                            profile.degreeType = types[0]
                        }
                    }
                    
                    coreDataManager.save()
                    logger.log("📋 Auto-selected degreeLevel: \(profile.degreeLevel ?? "nil") for better UX")
                }
            }
            
            // Hide success message after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                showCatalogStatus = false
            }
            
        } catch {
            logger.logError(error)
            
            if let scraperError = error as? ScraperError {
                logger.log("Scraper-specific error: \(scraperError)")
            }
            
            await setCatalogStatus(message: "Failed to scrape catalog: \(error.localizedDescription)")

            await MainActor.run {
                notifications.dismiss(id: toastID)
                notifications.post(
                    kind: .error,
                    title: "Scrape Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
            
            // Hide error message after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                showCatalogStatus = false
            }
        }
        
        await setCatalogStatus(isDownloading: false)
    }
    
    private func exportCatalog() {
        guard let collegeName = profile.collegeName else { return }

        isDownloadingCatalog = true
        catalogDownloadMessage = "Exporting stored program requirements…"
        showCatalogStatus = true

        let toastID = notifications.post(
            kind: .progress,
            title: "Exporting",
            message: "Preparing export…",
            progress: 0.2,
            isDismissible: true
        )

        Task { @MainActor in
            do {
                notifications.update(id: toastID, message: "Writing CSV…", progress: 0.6)
                let url = try await coreDataManager.exportScrapedCatalogCSVFromExistingCoreData(for: collegeName)
                let urls = [url]

                NSWorkspace.shared.activateFileViewerSelecting(urls)

                let names = urls.map { $0.lastPathComponent }.joined(separator: ", ")
                catalogDownloadMessage = "✓ Exported: \(names)"
                showCatalogStatus = true

                notifications.complete(
                    id: toastID,
                    kind: .success,
                    title: "Export Complete",
                    message: "Exported: \(names)",
                    autoDismissAfter: 4
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    showCatalogStatus = false
                }
            } catch {
                catalogDownloadMessage = "Failed to export: \(error.localizedDescription)"
                showCatalogStatus = true

                notifications.dismiss(id: toastID)
                notifications.post(
                    kind: .error,
                    title: "Export Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    showCatalogStatus = false
                }
            }

            isDownloadingCatalog = false
        }
    }
    
    // Helper function for class standing colors
    func classStandingColor(for standing: String) -> Color {
        switch standing {
        case "Freshman":
            return Color(hex: "10b981") // Green
        case "Sophomore":
            return Color(hex: "3b82f6") // Blue
        case "Junior":
            return Color(hex: "f59e0b") // Amber/Orange
        case "Senior":
            return Color(hex: "ef4444") // Red
        default:
            return DesignSystem.Colors.primary
        }
    }
}
