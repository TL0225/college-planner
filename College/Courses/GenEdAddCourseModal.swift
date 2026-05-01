import SwiftUI
import CoreData

/// Global sheet used to add courses from the active university catalog.
struct GenEdAddCourseModal: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @Environment(\.dismiss) private var dismiss

    let targetSemesterID: NSManagedObjectID?
    let tagAsGenEd: Bool

    @State private var searchText: String = ""
    @State private var results: [CourseCatalogEntity] = []
    @State private var creditFilter: CreditFilter = .all
    @State private var selectedDepartment: String = "All"
    @State private var preloadLimit: Int = 2_000
    @State private var isGroupSelectionEnabled: Bool = false
    
    // Keyboard focus management
    @FocusState private var isSearchFocused: Bool
    
    // Arrow key navigation support
    @State private var selectedCourseID: NSManagedObjectID? = nil
    @State private var selectedCourseIDs: Set<NSManagedObjectID> = []

    private enum CreditFilter: String, CaseIterable, Identifiable {
        case all = "All Credits"
        case oneToTwo = "1-2 Cr"
        case three = "3 Cr"
        case fourOrMore = "4+ Cr"
        case tba = "TBA"

        var id: String { rawValue }

        func matches(_ creditsText: String) -> Bool {
            switch self {
            case .all:
                return true
            case .oneToTwo:
                guard let value = Int(creditsText) else { return false }
                return (1...2).contains(value)
            case .three:
                return creditsText == "3"
            case .fourOrMore:
                guard let value = Int(creditsText) else { return false }
                return value >= 4
            case .tba:
                return creditsText == "TBA"
            }
        }
    }

    private var availableDepartments: [String] {
        let departments = Set(results.compactMap(departmentCode(for:)).filter { !$0.isEmpty })
        return departments.sorted()
    }

    private var filteredResults: [CourseCatalogEntity] {
        results.filter { course in
            let departmentMatches = selectedDepartment == "All" || departmentCode(for: course) == selectedDepartment
            let creditsMatches = creditFilter.matches(creditsText(for: course))
            return departmentMatches && creditsMatches
        }
    }

    private var selectedCount: Int {
        isGroupSelectionEnabled ? selectedCourseIDs.count : (selectedCourseID == nil ? 0 : 1)
    }


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filtersBar

                if isGroupSelectionEnabled {
                    List(selection: $selectedCourseIDs) {
                        catalogRows
                    }
                    .listStyle(.inset)
                    .searchable(text: $searchText, placement: .toolbar, prompt: "Search catalog courses")
                    .focused($isSearchFocused)
                    .overlay(alignment: .topLeading) {
                        Text("Group mode: Command-click to select multiple courses.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                } else {
                    List(selection: $selectedCourseID) {
                        catalogRows
                    }
                    .listStyle(.inset)
                    .searchable(text: $searchText, placement: .toolbar, prompt: "Search catalog courses")
                    .focused($isSearchFocused)
                }

                Divider()

                HStack {
                    Toggle("Group Select", isOn: $isGroupSelectionEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Spacer()

                    Button("Cancel") {
                        closeSheet()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(isGroupSelectionEnabled ? "Add \(selectedCount)" : "Add") {
                        if isGroupSelectionEnabled {
                            addSelectedCoursesAsGroup()
                        } else if let selectedID = selectedCourseID,
                                  let course = filteredResults.first(where: { $0.objectID == selectedID }) {
                            addCourse(course)
                        }
                    }
                    .disabled(selectedCount == 0)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .onAppear {
                isSearchFocused = true
                preloadLimit = max(coreDataManager.activeUniversityCatalogCourseCount(), 200)
                refreshResults(query: "")
            }
            .onChange(of: searchText) { _, _ in
                performSearchDebounced()
            }
            .onChange(of: isGroupSelectionEnabled) { _, enabled in
                if enabled {
                    if let selectedCourseID {
                        selectedCourseIDs = [selectedCourseID]
                    } else {
                        selectedCourseIDs = []
                    }
                    selectedCourseID = nil
                } else {
                    if let existing = selectedCourseID,
                       filteredResults.contains(where: { $0.objectID == existing }) {
                        // keep existing single selection
                    } else {
                        selectedCourseID = selectedCourseIDs.first ?? filteredResults.first?.objectID
                    }
                    selectedCourseIDs = []
                }
            }
            .onKeyPress(.return) {
                if isGroupSelectionEnabled {
                    addSelectedCoursesAsGroup()
                    return selectedCourseIDs.isEmpty ? .ignored : .handled
                } else {
                    if let selectedID = selectedCourseID, let course = filteredResults.first(where: { $0.objectID == selectedID }) {
                        addCourse(course)
                        return .handled
                    }
                    return .ignored
                }
            }
            .onKeyPress(.escape) {
                closeSheet()
                return .handled
            }
            .navigationTitle("Add Course")
        }
        .frame(minWidth: 560, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func addCourse(_ course: CourseCatalogEntity) {
        coreDataManager.addCatalogCourse(
            from: course,
            targetSemesterID: targetSemesterID,
            tagAsGenEd: tagAsGenEd
        )
        closeSheet()
    }

    private func addSelectedCoursesAsGroup() {
        guard !selectedCourseIDs.isEmpty else { return }
        let selected = filteredResults.filter { selectedCourseIDs.contains($0.objectID) }
        guard !selected.isEmpty else { return }

        for course in selected {
            coreDataManager.addCatalogCourse(
                from: course,
                targetSemesterID: targetSemesterID,
                tagAsGenEd: tagAsGenEd
            )
        }
        closeSheet()
    }
    
    private func closeSheet() {
        dismiss()
    }

    @State private var searchTimer: Timer?
    private func performSearchDebounced() {
        searchTimer?.invalidate()
        let q = searchText
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            Task { @MainActor in
                refreshResults(query: q)
            }
        }
    }

    private func refreshResults(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = coreDataManager.searchCatalogCourses(query: trimmed, limit: max(preloadLimit, 200))

        syncSelectionAfterDataChange()
    }

    private func syncSelectionAfterDataChange() {
        if isGroupSelectionEnabled {
            selectedCourseIDs = selectedCourseIDs.filter { id in
                filteredResults.contains(where: { $0.objectID == id })
            }
            return
        }

        if let selected = selectedCourseID,
           filteredResults.contains(where: { $0.objectID == selected }) {
            return
        }
        selectedCourseID = filteredResults.first?.objectID
    }

    private var catalogRows: some View {
        Group {
            ForEach(filteredResults, id: \.objectID) { course in
                GenEdCatalogRow(
                    course: course,
                    isSelected: isGroupSelectionEnabled ? selectedCourseIDs.contains(course.objectID) : (selectedCourseID == course.objectID),
                    searchQuery: searchText,
                    onAdd: {
                        if isGroupSelectionEnabled {
                            if selectedCourseIDs.contains(course.objectID) {
                                selectedCourseIDs.remove(course.objectID)
                            } else {
                                selectedCourseIDs.insert(course.objectID)
                            }
                        } else {
                            addCourse(course)
                        }
                    },
                    groupSelectionEnabled: isGroupSelectionEnabled
                )
                .tag(course.objectID)
            }

            if results.isEmpty || filteredResults.isEmpty {
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasAnyCatalogData = coreDataManager.activeUniversityHasCatalogCourses()
                let message: String = {
                    if !hasAnyCatalogData {
                        return "No data available. Please scrape data."
                    }
                    if !results.isEmpty && filteredResults.isEmpty {
                        return "No courses match the active filters."
                    }
                    return trimmed.isEmpty ? "Type to search courses." : "No courses found."
                }()

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func departmentCode(for course: CourseCatalogEntity) -> String? {
        let code = (course.courseCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }

        let firstToken = code.split(separator: " ").first.map(String.init) ?? ""
        let letters = firstToken.prefix { $0.isLetter }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    private func creditsText(for course: CourseCatalogEntity) -> String {
        let c = Int(course.credits)
        if c > 0 { return String(c) }

        guard let d = course.descriptionText?.lowercased() else { return "TBA" }
        for re in GenEdCatalogRow.creditRegexes {
            let nsRange = NSRange(d.startIndex..<d.endIndex, in: d)
            if let m = re.firstMatch(in: d, range: nsRange), m.numberOfRanges >= 2,
               let r1 = Range(m.range(at: 1), in: d),
               let value = Int(d[r1]), value > 0 {
                return String(value)
            }
        }
        return "TBA"
    }

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CreditFilter.allCases) { filter in
                    Button(filter.rawValue) {
                        creditFilter = filter
                        syncSelectionAfterDataChange()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(creditFilter == filter ? .accentColor : nil)
                }

                Menu {
                    Button("All Departments") {
                        selectedDepartment = "All"
                        syncSelectionAfterDataChange()
                    }

                    ForEach(availableDepartments, id: \.self) { department in
                        Button(department) {
                            selectedDepartment = department
                            syncSelectionAfterDataChange()
                        }
                    }
                } label: {
                    Label(selectedDepartment == "All" ? "All Departments" : selectedDepartment, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.button)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }
}

private struct GenEdCatalogRow: View {
    static let creditRegexes: [NSRegularExpression] = {
        let patterns = [
            "credits?\\s*[:\\-]?\\s*(\\d{1,2})",
            "(\\d{1,2})\\s*credits?",
            "credit\\s*hours?\\s*[:\\-]?\\s*(\\d{1,2})"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    let course: CourseCatalogEntity
    let isSelected: Bool
    let searchQuery: String
    let onAdd: () -> Void
    let groupSelectionEnabled: Bool
    @State private var isHovered: Bool = false

    private var displayCode: String {
        (course.courseCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayTitle: String {
        let t = (course.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t.caseInsensitiveCompare(displayCode) == .orderedSame { return "" }
        return t
    }

    private var displayCreditsText: String {
        let c = Int(course.credits)
        if c > 0 { return String(c) }

        if let d = course.descriptionText?.lowercased() {
            for re in Self.creditRegexes {
                let nsRange = NSRange(d.startIndex..<d.endIndex, in: d)
                if let m = re.firstMatch(in: d, range: nsRange), m.numberOfRanges >= 2,
                   let r1 = Range(m.range(at: 1), in: d),
                   let value = Int(d[r1]), value > 0 {
                    return String(value)
                }
            }
        }
        return "TBA"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    highlightedText(displayCode, query: searchQuery)
                        .font(.headline)
                        .lineLimit(1)

                    if !displayTitle.isEmpty {
                        highlightedText(displayTitle, query: searchQuery)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(displayCreditsText) Cr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                let description = (course.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty {
                    highlightedText(description, query: searchQuery)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)

            Spacer()
            
            // "Plus" Action: Button on hover
            if isHovered || isSelected {
                Button(action: onAdd) {
                    Image(systemName: groupSelectionEnabled ? (isSelected ? "checkmark.circle.fill" : "plus.circle.fill") : "plus.app.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(groupSelectionEnabled ? (isSelected ? "Remove from group" : "Add to group") : "Add course")
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .padding(.vertical, 4)
    }

    private func highlightedText(_ source: String, query: String) -> Text {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Text(source) }

        var attributed = AttributedString(source)
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let match = source.range(of: trimmed, options: [.caseInsensitive], range: cursor..<source.endIndex),
              let attributedRange = Range(match, in: attributed) {
            attributed[attributedRange].font = .system(size: 14, weight: .semibold)
            cursor = match.upperBound
        }
        return Text(attributed)
    }
}
