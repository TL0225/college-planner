import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct DegreeView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @State private var showAddSemester = false
    @State private var showMajorDetails = false
    @State private var showMinorDetails = false
        @State private var selectedMinorDisplay: String? = nil
    @State private var selectedPlan: PlanEntity?
    @State private var requestedMajorScrollTarget: String? = nil

    private var selectedMajors: [String] {
        let majors = [coreDataManager.profile?.major, coreDataManager.profile?.secondaryMajor]
            .compactMap { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        return majors.filter { seen.insert($0).inserted }
    }

    private func showDetails(_ kind: DetailKind) {
        showMajorDetails = false
        showMinorDetails = false

        switch kind {
        case .major:
            showMajorDetails = true
        case .minor:
            showMinorDetails = true
        }
    }

    private func hideAllDetails() {
        showMajorDetails = false
        showMinorDetails = false
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Inner Sidebar
                DegreeSidebar(selectedPlan: $selectedPlan)
                    .frame(width: 320)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(Color(hex: "f1f5f9")),
                        alignment: .trailing
                    )

                // Main Content
                if showMajorDetails {
                    MultiMajorDetailsMainContent(
                        majors: selectedMajors.isEmpty ? ["Select Major"] : selectedMajors,
                        requestedScrollTarget: $requestedMajorScrollTarget,
                        onBack: {
                            hideAllDetails()
                        }
                    )
                } else if showMinorDetails {
                    MajorMinorDetailsView(
                        majorDisplay: selectedMinorDisplay ?? (coreDataManager.profile?.minor ?? ""),
                        onBack: {
                            hideAllDetails()
                        },
                        programKind: .minor
                    )
                } else {
                    DegreeMainContent(
                        showAddSemester: $showAddSemester,
                        selectedPlan: $selectedPlan
                    )
                }
            }
            .blur(radius: showAddSemester ? 5 : 0)
            .onReceive(NotificationCenter.default.publisher(for: .showMajorDetails)) { notification in
                if let major = notification.object as? String {
                    requestedMajorScrollTarget = major
                }
                showDetails(.major)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCollegeDetails)) { _ in
                // Replace the General Education screen with the Semester Planner.
                hideAllDetails()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showMinorDetails)) { notification in
                if let minor = notification.object as? String {
                    selectedMinorDisplay = minor
                } else {
                    selectedMinorDisplay = coreDataManager.profile?.minor
                }
                showDetails(.minor)
            }
            .onAppear {
                ensureDefaultPlanSelectedIfNeeded()
            }
            .onChange(of: selectedPlan) { _, newValue in
                coreDataManager.setActivePlan(newValue)
            }
            .onChange(of: coreDataManager.plans.count) {
                // When plans change (new plan saved), select the newest plan if nothing is selected.
                if selectedPlan == nil {
                    selectedPlan = coreDataManager.plans.last
                }
            }
            
            if showAddSemester, let plan = selectedPlan {
                AddSemesterView(isPresented: $showAddSemester, plan: plan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
    }

    private func ensureDefaultPlanSelectedIfNeeded() {
        if let existing = coreDataManager.plans.first {
            selectedPlan = selectedPlan ?? existing
            coreDataManager.setActivePlan(selectedPlan)
            return
        }

        // If the user has no plans, create a basic default plan.
        let plan = coreDataManager.addPlan(
            name: "My Plan",
            type: "Bachelors",
            major: coreDataManager.profile?.major ?? "",
            minor: coreDataManager.profile?.minor ?? "",
            concentration: ""
        )
        coreDataManager.fetchPlans()
        selectedPlan = plan
        coreDataManager.setActivePlan(selectedPlan)
    }
}

private struct MultiMajorDetailsMainContent: View {
    let majors: [String]
    @Binding var requestedScrollTarget: String?
    let onBack: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    ForEach(Array(majors.enumerated()), id: \ .offset) { idx, majorDisplay in
                        MajorMinorDetailsView(
                            majorDisplay: majorDisplay,
                            onBack: onBack,
                            showsBackButton: idx == 0,
                            embedInParentScrollView: true
                        )
                        .id(majorDisplay)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(DesignSystem.Colors.bgMain)
            .onChange(of: requestedScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                requestedScrollTarget = nil
            }
        }
    }
}

struct DegreeSidebar: View {
    @Binding var selectedPlan: PlanEntity?
    @EnvironmentObject var coreDataManager: CoreDataManager

    private var collegeSubtitle: String {
        guard let profile = coreDataManager.profile else { return "Select University" }
        let university = (profile.collegeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dept = (profile.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !university.isEmpty, !dept.isEmpty,
           let school = coreDataManager.schoolForDepartment(universityName: university, departmentName: dept) {
            return school
        }

        if !university.isEmpty { return university }
        return "Select University"
    }

    private var selectedMajors: [String] {
        let majors = [coreDataManager.profile?.major, coreDataManager.profile?.secondaryMajor]
            .compactMap { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        return majors.filter { seen.insert($0).inserted }
    }

    private var minorSubtitle: String {
        let minor = (coreDataManager.profile?.minor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if minor.isEmpty || minor.lowercased() == "none" { return "None" }
        return minor
    }

    private func majorReqProgress(for majorDisplay: String) -> CoreDataManager.CourseProgressSummary {
        coreDataManager.majorRequirementsCourseProgress(forMajorDisplay: majorDisplay)
    }

    private func minorReqProgress(for minorDisplay: String) -> CoreDataManager.CourseProgressSummary {
        coreDataManager.minorRequirementsCourseProgress(forMinorDisplay: minorDisplay)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Plan Selector
                HStack {
                    Menu {
                        ForEach(coreDataManager.plans) { plan in
                            Button(action: { selectedPlan = plan }) {
                                Text(plan.name ?? "Unknown Plan")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(DesignSystem.Colors.primary)
                            Text(selectedPlan?.name ?? "Select Plan")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                        .padding()
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Requirements
                let gen = coreDataManager.genEdCourseProgress(for: selectedPlan)
                let genStatusText: String = {
                    if gen.assigned <= 0 { return "0 Assigned" }
                    return "\(gen.completed)/\(gen.assigned) Courses"
                }()

                RequirementCard(
                    title: "College Req.",
                    done: gen.completed,
                    total: gen.assigned,
                    color: DesignSystem.Colors.primary,
                    subTitle: collegeSubtitle,
                    progress: gen.fraction,
                    statusText: genStatusText,
                    onViewDetails: {
                        NotificationCenter.default.post(name: .showCollegeDetails, object: nil)
                    }
                )

                ForEach(selectedMajors.isEmpty ? ["Select Major"] : selectedMajors, id: \.self) { majorDisplay in
                    let p = majorReqProgress(for: majorDisplay)
                    RequirementCard(
                        title: "Major Req.",
                        done: p.done,
                        total: p.total,
                        color: DesignSystem.Colors.info,
                        subTitle: majorDisplay,
                        progress: p.fraction,
                        onViewDetails: {
                            // Switch the right panel to the Major Details page.
                            NotificationCenter.default.post(name: .showMajorDetails, object: majorDisplay)
                        }
                    )
                }

                let mp = minorReqProgress(for: minorSubtitle)
                RequirementCard(
                    title: "Minor Req.",
                    done: mp.done,
                    total: mp.total,
                    color: DesignSystem.Colors.accent,
                    subTitle: minorSubtitle,
                    progress: mp.fraction,
                    onViewDetails: {
                        NotificationCenter.default.post(name: .showMinorDetails, object: minorSubtitle)
                    }
                )
            }
            .padding()
        }
    }
}

private extension Notification.Name {
    static let showMajorDetails = Notification.Name("showMajorDetails")
    static let showCollegeDetails = Notification.Name("showCollegeDetails")
    static let showMinorDetails = Notification.Name("showMinorDetails")
}

private enum DetailKind {
    case major
    case minor
}

private struct RequirementsPlaceholderDetailsView: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                            .font(DesignSystem.Fonts.main(size: 13, weight: .bold))
                    }
                    .foregroundColor(DesignSystem.Colors.textMain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(DesignSystem.Colors.bgMain)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignSystem.Colors.textLight.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)

                Spacer()
            }
            .padding(20)
            .background(DesignSystem.Colors.surface)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(DesignSystem.Colors.textLight.opacity(0.12)),
                alignment: .bottom
            )

            Spacer()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.bgMain)
        }
        .background(DesignSystem.Colors.bgMain)
    }
}

private struct RequirementCard: View {
    let title: String
    let done: Int
    let total: Int
    let color: Color
    let subTitle: String
    let progress: Double
    var statusText: String? = nil
    var onViewDetails: (() -> Void)? = nil

    @State private var isHovering: Bool = false
    @State private var tapBump: Bool = false

    private var isInteractive: Bool { onViewDetails != nil }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var interactionScale: CGFloat {
        if tapBump { return 1.035 }
        if isHovering { return 1.02 }
        return 1.0
    }

    private var interactionOffsetY: CGFloat {
        if tapBump { return -6 }
        if isHovering { return -3 }
        return 0
    }

    private var cardBorderOpacity: Double {
        isHovering ? 0.30 : 0.20
    }

    private var cardBackgroundOpacity: Double {
        isHovering ? 0.08 : 0.05
    }

    private func triggerTapBump() {
        guard isInteractive else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.70)) {
            tapBump = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
                tapBump = false
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textMain)
            Spacer()
            Text(statusText ?? "\(done)/\(total) Done")
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private var bigBox: some View {
        VStack {
            Text(subTitle)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(color.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            HStack {
                Text("Progress")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Text("\(Int(clampedProgress * 100))%")
                    .font(DesignSystem.Fonts.main(size: 10, weight: .semibold))
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * clampedProgress, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(color.opacity(cardBackgroundOpacity))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(cardBorderOpacity), lineWidth: 1)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            headerRow

            if let onViewDetails {
                Button {
                    triggerTapBump()
                    onViewDetails()
                } label: {
                    bigBox
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) {
                        isHovering = hovering
                    }
                }
                .scaleEffect(interactionScale)
                .offset(y: interactionOffsetY)
                .animation(.spring(response: 0.25, dampingFraction: 0.80), value: isHovering)
                .animation(.spring(response: 0.30, dampingFraction: 0.75), value: tapBump)
            } else {
                bigBox
            }
        }
    }
}

struct DegreeMainContent: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @Binding var showAddSemester: Bool
    @Binding var selectedPlan: PlanEntity?

    private var totalEarnedCredits: Int {
        guard let plan = selectedPlan else { return 0 }
        // Use manager-backed fetch (always fresh) and compare by id to avoid context identity issues.
        let semestersForPlan = coreDataManager.semesters.filter { $0.plan?.id == plan.id }
        return semestersForPlan.reduce(0) { $0 + $1.totalCredits }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Your Journey")
                            .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("Track your academic progress semester by semester.")
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    Spacer()

                    HStack(spacing: 16) {
                        VStack(alignment: .trailing) {
                            Text("TOTAL EARNED")
                                .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(totalEarnedCredits)")
                                    .font(DesignSystem.Fonts.main(size: 30, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.primary)
                                Text("/ 120 Credits")
                                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                            }
                        }

                        Button(action: {
                            if selectedPlan == nil {
                                // If the user hasn't selected a plan yet, pick a sensible default.
                                if let first = coreDataManager.plans.first {
                                    selectedPlan = first
                                } else {
                                    let plan = coreDataManager.addPlan(
                                        name: "My Plan",
                                        type: "Bachelors",
                                        major: coreDataManager.profile?.major ?? "",
                                        minor: coreDataManager.profile?.minor ?? "",
                                        concentration: ""
                                    )
                                    coreDataManager.fetchPlans()
                                    selectedPlan = plan
                                }
                            }
                            showAddSemester = true
                        }) {
                            Label("New Semester", systemImage: "plus.circle")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.secondary], startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 5, x: 0, y: 2)
                        }
                    }
                }
                .padding(.bottom, 20)
                
                // Semesters Grid
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 24) {
                        if let plan = selectedPlan {
                            ForEach(plan.semestersArray) { semester in
                                SemesterCard(
                                    semester: semester
                                )
                            }
                        } else {
                            Text("No plan selected.")
                                .font(DesignSystem.Fonts.main(size: 16))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding()
                        }
                    }
                    .padding(.bottom, 40) // Space for shadow
                }
            }
            .padding(32)
        }
        .background(DesignSystem.Colors.bgMain)
    }
}

struct SemesterCard: View {
    @ObservedObject var semester: SemesterEntity
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @State private var draggingCourse: CourseEntity?
    
    var gradientColors: [Color] {
        switch semester.season {
        case "Fall": return [DesignSystem.Colors.warning, Color(hex: "f97316")] // Amber to Orange
        case "Spring": return [DesignSystem.Colors.secondary, DesignSystem.Colors.primary] // Purple to Indigo
        default: return [DesignSystem.Colors.info, Color(hex: "0ea5e9")] // Cyan to Sky
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color Bar
            Rectangle()
                .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(semester.name ?? "Unknown Semester")
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("\(semester.totalCredits) Credits \(semester.isPlanned ? "Planned" : "Completed")")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .textCase(.uppercase)
                    }
                    Spacer()
                    
                    // Progress Circle (Simplified)
                    ZStack {
                        Circle()
                            .stroke(Color(hex: "e2e8f0"), lineWidth: 3)
                        if !semester.isPlanned {
                            Circle()
                                .stroke(gradientColors[1], lineWidth: 3)
                        }
                        Text(semester.isPlanned ? "0%" : "100%")
                            .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                            .foregroundColor(semester.isPlanned ? DesignSystem.Colors.textLight : gradientColors[1])
                    }
                    .frame(width: 40, height: 40)
                }
                
                // Courses
                ForEach(semester.coursesArray) { course in
                    CourseCard(
                        course: course,
                        accentColor: gradientColors[1],
                        draggingCourse: $draggingCourse
                    )
                }
                
                // Add Course Button
                Button(action: {
                    modalCoordinator.activeModal = .addCatalogCourse(semesterObjectID: semester.objectID)
                }) {
                    Label("Add Course", systemImage: "plus")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(999)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999)
                                .stroke(DesignSystem.Colors.textLight.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        .frame(width: 360)
    }
}

struct CourseCard: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @ObservedObject var course: CourseEntity
    let accentColor: Color
    @Binding var draggingCourse: CourseEntity?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(course.code ?? "N/A")
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                
                Text(course.name ?? "Unknown Course")
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                
                Text("\(course.creditsInt) credits • \(course.status ?? "Unknown")")
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            
            Spacer()
            
            // Drag Handle (6 dots)
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.Colors.textLight.opacity(0.5))
                .padding(4)
        }
        .padding()
        .background(DesignSystem.Colors.bgMain.opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHovering ? accentColor : Color(hex: "f1f5f9"), lineWidth: isHovering ? 2 : 1)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            let code = (course.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return }

            let name = (course.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultName = name.isEmpty ? "Course" : name
            let creditsText = String(format: "%.1f", Double(course.credits))

            modalCoordinator.activeModal = .editCourse(
                ModalCoordinator.CourseEditSelection(
                    courseCode: code,
                    defaultCourseName: defaultName,
                    defaultCreditsText: creditsText
                )
            )
        }
        .onDrag {
            draggingCourse = course
            return NSItemProvider(object: (course.id?.uuidString ?? "") as NSString)
        }
        // Ensure the drop type matches what we're providing.
        .onDrop(of: [UTType.text], delegate: CourseDropDelegate(destinationCourse: course, semester: course.semester!, draggingCourse: $draggingCourse, coreDataManager: coreDataManager))
    }
}

struct CourseDropDelegate: DropDelegate {
    let destinationCourse: CourseEntity
    let semester: SemesterEntity
    @Binding var draggingCourse: CourseEntity?
    let coreDataManager: CoreDataManager

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        // Make it feel instant: update order in-memory as the cursor crosses items.
        // Do NOT save here (saving during drag is what makes it laggy and can break subsequent drags).
        guard let draggingCourse,
              draggingCourse != destinationCourse,
              draggingCourse.semester == semester
        else { return }

        var courses = semester.coursesArray
        guard let fromIndex = courses.firstIndex(of: draggingCourse),
              let toIndex = courses.firstIndex(of: destinationCourse)
        else { return }

        if fromIndex == toIndex { return }

        courses.remove(at: fromIndex)
        courses.insert(draggingCourse, at: toIndex)

        for (idx, c) in courses.enumerated() {
            c.sortOrder = Int32(idx)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        // Persist exactly once at the end.
        coreDataManager.save()
        draggingCourse = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // No-op but keeps the delegate predictable.
    }
}
