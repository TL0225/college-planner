import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ProfileView: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ProfileSidebar()
                    .frame(width: 320)
                    .background(DesignSystem.Colors.surface)
                    .overlay(
                        Rectangle()
                            .frame(width: 1)
                            .foregroundColor(Color(hex: "f1f5f9")),
                        alignment: .trailing
                    )
                
                if let profile = coreDataManager.profile {
                    ProfileMainContent(profile: profile)
                        .environment(\.managedObjectContext, coreDataManager.viewContext)
                } else {
                    VStack {
                        ProgressView()
                        Text("Loading Profile...")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if coreDataManager.profile == nil {
                coreDataManager.fetchProfile()
            }
        }
    }
}

struct ProfileSidebar: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var notifications: AppNotificationCenter
    @State private var isEditingName = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false

    private func exportCatalogModifications() {
        guard let profile = coreDataManager.profile,
              let collegeName = profile.collegeName,
              !collegeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              coreDataManager.hasUniversityCatalog(name: collegeName) else {
            notifications.post(
                kind: .warning,
                title: "Export Unavailable",
                message: "Download a catalog first to export modifications.",
                isDismissible: true,
                autoDismissAfter: 4
            )
            return
        }

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

                NSWorkspace.shared.activateFileViewerSelecting([url])

                notifications.complete(
                    id: toastID,
                    kind: .success,
                    title: "Export Complete",
                    message: "Exported: \(url.lastPathComponent)",
                    autoDismissAfter: 4
                )
            } catch {
                notifications.dismiss(id: toastID)
                notifications.post(
                    kind: .error,
                    title: "Export Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
        }
    }
    
    // Helper function to extract year from expected graduation string
    func extractYear(from text: String) -> String {
        let pattern = #"\b(20\d{2}|19\d{2})\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return ""
    }
    
    // Helper function for class standing colors
    func classStandingColor(for standing: String?) -> Color {
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Avatar & Info
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.bgMain)
                            .frame(width: 96, height: 96)
                            .overlay(
                                Circle()
                                    .stroke(DesignSystem.Colors.primary.opacity(0.1), lineWidth: 4)
                            )

                        if let profile = coreDataManager.profile,
                           let data = profile.profilePhotoData,
                           let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .font(DesignSystem.Fonts.main(size: 40))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                    }

                    Button(action: {
                        showPhotoPicker = true
                    }) {
                        Text("Choose Photo")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.bgMain)
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if let profile = coreDataManager.profile, profile.profilePhotoData != nil {
                        Button(action: {
                            profile.profilePhotoData = nil
                            coreDataManager.save()
                        }) {
                            Text("Remove Photo")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(DesignSystem.Colors.bgMain)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if let profile = coreDataManager.profile {
                        VStack(spacing: 4) {
                            // Editable Name Field
                            TextField("Name", text: Binding(
                                get: { profile.name ?? "Name" },
                                set: { profile.name = $0; coreDataManager.save() }
                            ))
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(PlainTextFieldStyle())
                            
                            // Majors (each on its own centered line)
                            VStack(spacing: 2) {
                                if let major = profile.major, !major.isEmpty {
                                    Text("\(major) Major")
                                        .font(DesignSystem.Fonts.main(size: 14))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                        .multilineTextAlignment(.center)
                                }

                                if let secondaryMajor = profile.secondaryMajor, !secondaryMajor.isEmpty {
                                    Text("\(secondaryMajor) Major")
                                        .font(DesignSystem.Fonts.main(size: 14))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                        .multilineTextAlignment(.center)
                                }
                            }

                            // Minors (each on its own centered line)
                            VStack(spacing: 2) {
                                if let minor = profile.minor, !minor.isEmpty, minor != "None" {
                                    Text("\(minor) Minor")
                                        .font(DesignSystem.Fonts.main(size: 14))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        
                        HStack(spacing: 8) {
                            // Class Standing with color coding
                            Text(profile.classStanding ?? "Standing")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundColor(classStandingColor(for: profile.classStanding))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(classStandingColor(for: profile.classStanding).opacity(0.1))
                                .cornerRadius(12)
                            
                            // Class of Year badge
                            if let expectedGrad = profile.expectedGraduation, !expectedGrad.isEmpty {
                                let year = extractYear(from: expectedGrad)
                                if !year.isEmpty {
                                    Text("Class of \(year)")
                                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.info)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(DesignSystem.Colors.info.opacity(0.1))
                                        .cornerRadius(12)
                                }
                            }
                            
                            Text("GPA \(String(format: "%.1f", profile.gpa))")
                                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.warning)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(DesignSystem.Colors.warning.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.top, 16)
                
                Divider()
                
                // Quick Actions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Actions")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .textCase(.uppercase)
                    
                    if let profile = coreDataManager.profile {
                        TranscriptActionButton(profile: profile, showFilePicker: $showFilePicker)
                    }
                    QuickActionButton(icon: "calendar", title: "Appointments", subtitle: "Advising schedule", color: DesignSystem.Colors.info)
                }
                
                // Notifications
                VStack(alignment: .leading, spacing: 16) {
                    Text("Notifications")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .textCase(.uppercase)
                    
                    NotificationToggle(icon: "star.fill", title: "Grades", color: DesignSystem.Colors.primary)
                    NotificationToggle(icon: "book.closed.fill", title: "Courses", color: DesignSystem.Colors.info)
                    NotificationToggle(icon: "exclamationmark.triangle.fill", title: "Alerts", color: DesignSystem.Colors.warning)
                    NotificationToggle(icon: "calendar.badge.clock", title: "Deadlines", color: DesignSystem.Colors.accent)

                    if let profile = coreDataManager.profile,
                       let collegeName = profile.collegeName,
                       !collegeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       coreDataManager.hasUniversityCatalog(name: collegeName) {
                        Button {
                            exportCatalogModifications()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(DesignSystem.Fonts.main(size: 18))
                                    .foregroundColor(DesignSystem.Colors.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(DesignSystem.Colors.secondary.opacity(0.1))
                                    .cornerRadius(10)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Export Catalog Modifications")
                                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.textMain)
                                    Text("Share your corrections")
                                        .font(DesignSystem.Fonts.main(size: 12))
                                        .foregroundColor(DesignSystem.Colors.textLight)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Export your local corrections to share with the community")
                    }
                }
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .fileImporter(
            isPresented: $showPhotoPicker,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            handlePhotoSelection(result)
        }
    }
    
    func handleFileSelection(_ result: Result<[URL], Error>) {
        guard let profile = coreDataManager.profile else { return }

        let maxTranscriptBytes = 5 * 1024 * 1024
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let toastID = notifications.post(
                kind: .progress,
                title: "Uploading Transcript",
                message: "Reading \(url.lastPathComponent)…",
                progress: 0.1,
                isDismissible: true
            )
            
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    let data = try Data(contentsOf: url)

                    if data.count > maxTranscriptBytes {
                        notifications.dismiss(id: toastID)
                        notifications.post(
                            kind: .error,
                            title: "Upload Failed",
                            message: "Transcript file size exceeds the 5MB limit.",
                            isDismissible: true,
                            autoDismissAfter: 6
                        )
                        return
                    }

                    profile.transcriptData = data
                    profile.transcriptFileName = url.lastPathComponent
                    profile.transcriptUploadDate = Date()
                    coreDataManager.save()

                    notifications.complete(
                        id: toastID,
                        kind: .success,
                        title: "Transcript Added",
                        message: "\(url.lastPathComponent) added to your profile.",
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
                }
            } else {
                notifications.dismiss(id: toastID)
                notifications.post(
                    kind: .error,
                    title: "Upload Failed",
                    message: "Could not access the selected file.",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
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

    func handlePhotoSelection(_ result: Result<[URL], Error>) {
        guard let profile = coreDataManager.profile else { return }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let toastID = notifications.post(
                kind: .progress,
                title: "Updating Photo",
                message: "Reading \(url.lastPathComponent)…",
                progress: 0.15,
                isDismissible: true
            )

            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    profile.profilePhotoData = data
                    coreDataManager.save()

                    notifications.complete(
                        id: toastID,
                        kind: .success,
                        title: "Photo Updated",
                        message: "Your profile photo was updated.",
                        autoDismissAfter: 3
                    )
                } catch {
                    notifications.dismiss(id: toastID)
                    notifications.post(
                        kind: .error,
                        title: "Update Failed",
                        message: error.localizedDescription,
                        isDismissible: true,
                        autoDismissAfter: 6
                    )
                }
            } else {
                notifications.dismiss(id: toastID)
                notifications.post(
                    kind: .error,
                    title: "Update Failed",
                    message: "Could not access the selected image.",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
        case .failure(let error):
            notifications.post(
                kind: .error,
                title: "Update Failed",
                message: error.localizedDescription,
                isDismissible: true,
                autoDismissAfter: 6
            )
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(DesignSystem.Fonts.main(size: 18))
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Text(subtitle)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                Spacer()
            }
            .padding()
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NotificationToggle: View {
    let icon: String
    let title: String
    let color: Color
    @State private var isOn = true
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(DesignSystem.Fonts.main(size: 14))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            
            Text(title)
                .font(DesignSystem.Fonts.main(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: color))
        }
    }
}

struct ProfileMainContent: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var modalCoordinator: ModalCoordinator
    
    @FetchRequest private var experiences: FetchedResults<ExperienceEntity>
    @FetchRequest private var achievements: FetchedResults<AchievementEntity>

    init(profile: ProfileEntity) {
        let experiencePredicate = NSPredicate(format: "profile == %@", profile)
        _experiences = FetchRequest<ExperienceEntity>(
            entity: ExperienceEntity.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \ExperienceEntity.startDate, ascending: false)],
            predicate: experiencePredicate,
            animation: .default
        )

        let achievementPredicate = NSPredicate(format: "profile == %@", profile)
        _achievements = FetchRequest<AchievementEntity>(
            entity: AchievementEntity.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \AchievementEntity.dateReceived, ascending: false)],
            predicate: achievementPredicate,
            animation: .default
        )
    }
    
    var profile: ProfileEntity? {
        coreDataManager.profile
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Settings")
                        .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Text("Manage your academic identity and preferences.")
                        .font(DesignSystem.Fonts.main(size: 14))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }

                HStack(alignment: .top, spacing: 24) {
                    // Left Column
                    VStack(spacing: 24) {
                        if let p = profile {
                            AcademicIdentityView(profile: p)
                        }

                        // Experience section (inlined)
                        VStack(alignment: .leading, spacing: 24) {
                            HStack {
                                Label("Experience", systemImage: "briefcase.fill")
                                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.textMain)
                                Spacer()
                                Button(action: { modalCoordinator.activeModal = .addExperience }) {
                                    Label("Add", systemImage: "plus")
                                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                        .foregroundColor(DesignSystem.Colors.primary)
                                }
                                .buttonStyle(.plain)
                            }

                            if experiences.isEmpty {
                                Text("No experience added yet.")
                                    .font(DesignSystem.Fonts.main(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textLight)
                                    .padding()
                            } else {
                                ForEach(experiences) { experience in
                                    ExperienceCard(experience: experience)
                                }
                            }
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(24)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column
                    VStack(spacing: 24) {
                        DegreeSettingsView()
                        if let p = profile {
                            AchievementsViewContainer(profile: p, achievements: achievements)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(32)
        }
        .background(DesignSystem.Colors.bgMain)
    }
}

/// ProfileView uses @FetchRequest for reliability; this wrapper keeps the existing AchievementsView styling
/// while supplying a fetched list that updates automatically after inserts.
struct AchievementsViewContainer: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @EnvironmentObject var modalCoordinator: ModalCoordinator
    @ObservedObject var profile: ProfileEntity
    let achievements: FetchedResults<AchievementEntity>

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("Awards & Scholarships", systemImage: "trophy.fill")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Spacer()

                Button {
                    modalCoordinator.activeModal = .addAchievement
                } label: {
                    HStack(spacing: 6) {
                        Text("+")
                        Image(systemName: "plus")
                            .opacity(0)
                        Text("Add")
                    }
                    .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
            }

            if achievements.isEmpty {
                Text("No awards or scholarships added yet.")
                    .font(DesignSystem.Fonts.main(size: 14))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .padding()
            } else {
                ForEach(achievements) { achievement in
                    AchievementCard(achievement: achievement)
                }
            }
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Transcript Action Button
struct TranscriptActionButton: View {
    @EnvironmentObject var coreDataManager: CoreDataManager
    @ObservedObject var profile: ProfileEntity
    @Binding var showFilePicker: Bool
    
    var hasTranscript: Bool {
        profile.transcriptData != nil
    }
    
    var formattedUploadDate: String {
        guard let date = profile.transcriptUploadDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Main action button
            Button(action: {
                if hasTranscript {
                    // Open/view transcript
                    guard let data = profile.transcriptData else { return }
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(profile.transcriptFileName ?? "transcript.pdf")
                    try? data.write(to: tempURL)
                    NSWorkspace.shared.open(tempURL)
                } else {
                    // Show file picker
                    showFilePicker = true
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: hasTranscript ? "doc.text.fill" : "doc.text")
                        .font(DesignSystem.Fonts.main(size: 18))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(width: 40, height: 40)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasTranscript ? "View Transcript" : "Upload Transcript")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text(hasTranscript ? "Last Uploaded: \(formattedUploadDate)" : "No academic record found")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Re-upload button (only show if transcript exists)
            if hasTranscript {
                Button(action: {
                    showFilePicker = true
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignSystem.Fonts.main(size: 16))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(width: 40, height: 40)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Re-upload transcript")
            }
        }
    }
}
