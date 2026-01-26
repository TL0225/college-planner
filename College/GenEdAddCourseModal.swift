import SwiftUI
import CoreData

/// Global modal used to add courses from the active university catalog into General Education.
///
/// Presented via `ModalCoordinator` to ensure it is centered in the viewport even when
/// the requirements UI is embedded inside a parent `ScrollView`.
struct GenEdAddCourseModal: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager

    @Binding var isPresented: Bool

    let targetSemesterID: NSManagedObjectID?
    let tagAsGenEd: Bool

    @State private var searchText: String = ""
    @State private var results: [CourseCatalogEntity] = []
    @State private var isSearching: Bool = false
    @State private var isDraggingOut: Bool = false

    init(
        isPresented: Binding<Bool>,
        targetSemesterID: NSManagedObjectID? = nil,
        tagAsGenEd: Bool = true
    ) {
        _isPresented = isPresented
        self.targetSemesterID = targetSemesterID
        self.tagAsGenEd = tagAsGenEd
    }

    var body: some View {
        ZStack {
            // Gray backdrop (visual only; keeps underlying drop targets usable).
            DesignSystem.Colors.textLight
                .opacity(0.22)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if !isDraggingOut {
                VStack(spacing: 0) {
                    header

                    Divider().opacity(0.35)

                    VStack(alignment: .leading, spacing: 12) {
                        searchBar

                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(results, id: \.objectID) { course in
                                    GenEdCatalogRow(course: course, onPick: {
                                        coreDataManager.addCatalogCourse(
                                            from: course,
                                            targetSemesterID: targetSemesterID,
                                            tagAsGenEd: tagAsGenEd
                                        )
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                            isPresented = false
                                        }
                                    })
                                    .onDrag {
                                        withAnimation(.easeOut(duration: 0.12)) {
                                            isDraggingOut = true
                                        }
                                        return NSItemProvider(object: (course.courseCode ?? "") as NSString)
                                    }
                                }

                                if results.isEmpty {
                                    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let hasAnyCatalogData = coreDataManager.activeUniversityHasCatalogCourses()
                                    let message: String = {
                                        if !hasAnyCatalogData {
                                            return "No data available. Please scrape data."
                                        }
                                        if trimmed.isEmpty {
                                            return "No data available. Please scrape data."
                                        }
                                        return "No courses found."
                                    }()

                                    Text(message)
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 18)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 360)
                    }
                    .padding(20)
                }
                .frame(width: 640)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: DesignSystem.Colors.textLight.opacity(0.18), radius: 16, x: 0, y: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear { refreshResults(query: "") }
        .onReceive(NotificationCenter.default.publisher(for: .catalogCourseDropCompleted)) { _ in
            withAnimation(.easeOut(duration: 0.12)) {
                isDraggingOut = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.info.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "book.pages")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.info)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Add Course")
                    .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("Search the university catalog")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    isPresented = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding(8)
                    .background(DesignSystem.Colors.bgMain.opacity(0.6))
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(20)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textLight)

            TextField("Search catalog courses", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textMain)
                .onChange(of: searchText) { _, _ in
                    performSearchDebounced()
                }

            Spacer()

            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignSystem.Colors.bgMain)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
        )
    }

    private func performSearchDebounced() {
        isSearching = true
        let q = searchText
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard q == searchText else { return }
            refreshResults(query: q)
            isSearching = false
        }
    }

    private func refreshResults(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = coreDataManager.searchCatalogCourses(query: trimmed, limit: 200)
    }
}

private struct GenEdCatalogRow: View {
    let course: CourseCatalogEntity
    let onPick: () -> Void

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

        // Try to infer from description when credits are missing in the catalog.
        if let d = course.descriptionText?.lowercased() {
            let patterns = [
                "credits?\\s*[:\\-]?\\s*(\\d{1,2})",
                "(\\d{1,2})\\s*credits?",
                "credit\\s*hours?\\s*[:\\-]?\\s*(\\d{1,2})"
            ]
            for p in patterns {
                if let re = try? NSRegularExpression(pattern: p, options: []) {
                    let nsRange = NSRange(d.startIndex..<d.endIndex, in: d)
                    if let m = re.firstMatch(in: d, range: nsRange), m.numberOfRanges >= 2,
                       let r1 = Range(m.range(at: 1), in: d),
                       let value = Int(d[r1]), value > 0 {
                        return String(value)
                    }
                }
            }
        }

        return "TBA"
    }

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    let topLine: String = {
                        if displayTitle.isEmpty {
                            return displayCode
                        }
                        return "\(displayCode) - \(displayTitle)"
                    }()
                    Text(topLine)
                        .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)

                    let description = (course.descriptionText ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(description.isEmpty ? "No description available." : description)
                        .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(2)

                    Text("\(displayCreditsText) credits")
                        .font(DesignSystem.Fonts.main(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            .padding(12)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
