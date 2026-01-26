import SwiftUI
import CoreData
import UniformTypeIdentifiers
import AppKit
import QuickLook

struct ResourcesView: View {
    var body: some View {
        ResourcesMainContent()
    }
}

struct ResourcesMainContent: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var notifications: AppNotificationCenter

    @State private var showUploadPicker: Bool = false
    @State private var selectedFilter: DocumentVaultFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Success Dashboard")
                            .font(DesignSystem.Fonts.main(size: 24, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("Your central hub for academic support, resources, and planning.")
                            .font(DesignSystem.Fonts.main(size: 14))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: {}) {
                            Label("Full Calendar", systemImage: "calendar")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(DesignSystem.Colors.surface)
                                .foregroundColor(DesignSystem.Colors.textMain)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                                )
                        }
                        
                        Button(action: { showUploadPicker = true }) {
                            Label("Upload Document", systemImage: "doc.badge.plus")
                                .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(DesignSystem.Colors.warning)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: DesignSystem.Colors.warning.opacity(0.3), radius: 5, x: 0, y: 2)
                        }
                    }
                }
                .padding(.bottom, 10)
                
                HStack(alignment: .top, spacing: 24) {
                    // Left Column: Advisor & Deadlines
                    VStack(spacing: 24) {
                        AcademicAdvisorCard()
                        CampusDeadlinesCard()
                    }
                    .frame(width: 360)
                    
                    // Right Column: Document Vault
                    DocumentVaultCard(
                        selectedFilter: $selectedFilter,
                        showUploadPicker: $showUploadPicker
                    )
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(32)
        }
        .background(DesignSystem.Colors.bgMain)
        .fileImporter(
            isPresented: $showUploadPicker,
            allowedContentTypes: [
                .pdf,
                UTType(filenameExtension: "docx") ?? .data,
                .jpeg
            ],
            allowsMultipleSelection: false
        ) { result in
            handlePickedUpload(result)
        }
    }

    private func handlePickedUpload(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            notifications.post(
                kind: .error,
                title: "Upload Failed",
                message: error.localizedDescription,
                isDismissible: true,
                autoDismissAfter: 6
            )
        case .success(let urls):
            guard let url = urls.first else { return }
            handleUploadURL(url)
        }
    }

    private func handleUploadURL(_ url: URL) {
        let maxBytes: Int64 = 10 * 1024 * 1024
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let allowed = ["pdf", "docx", "jpg", "jpeg"].contains(ext)
        if !allowed {
            notifications.post(
                kind: .error,
                title: "Upload Failed",
                message: "Only PDF, DOCX, or JPG files are supported.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        if size > maxBytes {
            notifications.post(
                kind: .error,
                title: "Upload Failed",
                message: "File size exceeds the 10MB limit.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        let toastID = notifications.post(
            kind: .progress,
            title: "Uploading Document",
            message: "Saving \(fileName)…",
            progress: 0.3,
            isDismissible: true
        )

        do {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                try coreDataManager.addVaultDocument(fromSelectedURL: url, category: .other, source: "vault")
            } else {
                try coreDataManager.addVaultDocument(fromSelectedURL: url, category: .other, source: "vault")
            }

            notifications.complete(
                id: toastID,
                kind: .success,
                title: "Uploaded",
                message: "Added \(fileName) to Document Vault.",
                autoDismissAfter: 3
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
    }
}

// MARK: - Document Vault
enum DocumentVaultFilter: String {
    case all = "All Files"
    case syllabi = "Syllabi"
    case transcripts = "Transcripts"
    case calendar = "Calendar"
}

struct DocumentVaultCard: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var notifications: AppNotificationCenter

    @Binding var selectedFilter: DocumentVaultFilter
    @Binding var showUploadPicker: Bool

    @State private var quickLookURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(DesignSystem.Fonts.main(size: 20))
                        .foregroundColor(DesignSystem.Colors.primary)
                        .frame(width: 40, height: 40)
                        .background(DesignSystem.Colors.primary.opacity(0.1))
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading) {
                        Text("Document Vault")
                            .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                        Text("Secure storage for academic records")
                            .font(DesignSystem.Fonts.main(size: 12))
                            .foregroundColor(DesignSystem.Colors.textLight)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    FilterButton(title: "All Files", isSelected: selectedFilter == .all) {
                        selectedFilter = .all
                    }
                    FilterButton(title: "Syllabi", isSelected: selectedFilter == .syllabi) {
                        selectedFilter = .syllabi
                    }
                    FilterButton(title: "Transcripts", isSelected: selectedFilter == .transcripts) {
                        selectedFilter = .transcripts
                    }
                    FilterButton(title: "Calendar", isSelected: selectedFilter == .calendar) {
                        selectedFilter = .calendar
                    }
                }
                .padding(4)
                .background(DesignSystem.Colors.bgMain)
                .cornerRadius(12)
            }
            .padding(24)
            .background(DesignSystem.Colors.bgMain.opacity(0.5))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(hex: "f1f5f9")),
                alignment: .bottom
            )
            
            // Content
            VStack(spacing: 24) {
                // Upload Area
                VStack(spacing: 12) {
                    Image(systemName: "cloud.upload")
                        .font(.system(size: 24))
                        .foregroundColor(DesignSystem.Colors.warning)
                        .frame(width: 48, height: 48)
                        .background(DesignSystem.Colors.warning.opacity(0.1))
                        .clipShape(Circle())
                    
                    Text("Click to upload or drag and drop")
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    
                    Text("PDF, DOCX, or JPG (Max 10MB)")
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .foregroundColor(Color(hex: "e2e8f0"))
                )
                .background(Color.white)
                .contentShape(Rectangle())
                .onTapGesture {
                    showUploadPicker = true
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                    handleDrop(providers)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Documents")
                        .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                    
                    VStack(spacing: 12) {
                        ForEach(recentItems()) { item in
                            DocumentItem(
                                name: item.name,
                                date: item.subtitle,
                                icon: item.icon,
                                color: item.color,
                                onOpen: { preview(item: item) },
                                onExport: { export(item: item) },
                                onDelete: deleteAction(for: item)
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10)
        .quickLookPreview($quickLookURL)
    }

    private struct VaultListItem: Identifiable {
        enum Source {
            case vault(VaultDocumentEntity)
            case transcript(ProfileEntity)
            case syllabus(CourseOverrideEntity)
        }

        let id: UUID
        let name: String
        let subtitle: String
        let icon: String
        let color: Color
        let source: Source
        let filter: DocumentVaultFilter
    }

    private func recentItems() -> [VaultListItem] {
        var items: [VaultListItem] = []

        // 1) Uploaded Vault documents (persisted)
        for doc in coreDataManager.vaultDocuments {
            let category = (doc.category ?? "Other")
            let filter: DocumentVaultFilter
            if category == CoreDataManager.VaultDocumentCategory.syllabi.rawValue { filter = .syllabi }
            else if category == CoreDataManager.VaultDocumentCategory.transcripts.rawValue { filter = .transcripts }
            else if category == CoreDataManager.VaultDocumentCategory.calendar.rawValue { filter = .calendar }
            else { filter = .all }

            let (icon, color) = iconAndColor(forFileName: doc.fileName ?? "")
            let added = doc.addedAt ?? Date()
            let size = Int64(doc.fileSizeBytes)
            items.append(
                VaultListItem(
                    id: doc.id ?? UUID(),
                    name: doc.fileName ?? "(Untitled)",
                    subtitle: "Added \(formatDate(added)) • \(formatBytes(size))",
                    icon: icon,
                    color: color,
                    source: .vault(doc),
                    filter: filter
                )
            )
        }

        // 2) Transcript from Profile (stored in Core Data)
        if let profile = coreDataManager.profile,
           let data = profile.transcriptData,
           !data.isEmpty {
            let added = profile.transcriptUploadDate ?? Date()
            let name = (profile.transcriptFileName?.isEmpty == false) ? (profile.transcriptFileName ?? "Transcript.pdf") : "Transcript.pdf"
            let (icon, color) = ("doc.text.fill", DesignSystem.Colors.accent)
            items.append(
                VaultListItem(
                    id: profile.id ?? UUID(),
                    name: name,
                    subtitle: "Added \(formatDate(added)) • \(formatBytes(Int64(data.count)))",
                    icon: icon,
                    color: color,
                    source: .transcript(profile),
                    filter: .transcripts
                )
            )
        }

        // 3) Syllabi from Course Overrides (stored in Core Data)
        for ov in coreDataManager.fetchSyllabusOverridesWithFiles() {
            let fileName = (ov.syllabusFileName?.isEmpty == false) ? (ov.syllabusFileName ?? "Syllabus") : "Syllabus"
            let added = ov.syllabusUploadedAt ?? Date()
            let bytes = ov.syllabusFileSizeBytes
            let (icon, color) = ("doc.fill", DesignSystem.Colors.primary)
            items.append(
                VaultListItem(
                    id: ov.id ?? UUID(),
                    name: fileName,
                    subtitle: "Added \(formatDate(added)) • \(formatBytes(bytes))",
                    icon: icon,
                    color: color,
                    source: .syllabus(ov),
                    filter: .syllabi
                )
            )
        }

        // Sort newest first using the “Added …” date where possible
        // (Already mostly sorted by fetch order; keep stable but ensure transcript/syllabi interleave.)
        return items
            .filter { item in
                switch selectedFilter {
                case .all: return true
                case .syllabi: return item.filter == .syllabi
                case .transcripts: return item.filter == .transcripts
                case .calendar: return item.filter == .calendar
                }
            }
            .prefix(12)
            .map { $0 }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            DispatchQueue.main.async {
                // Reuse the same validation as the picker by toggling picker workflow
                // (call into CoreDataManager directly here)
                uploadDroppedURL(url)
            }
        }

        return true
    }

    private func uploadDroppedURL(_ url: URL) {
        let maxBytes: Int64 = 10 * 1024 * 1024
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let allowed = ["pdf", "docx", "jpg", "jpeg"].contains(ext)
        if !allowed {
            notifications.post(
                kind: .error,
                title: "Upload Failed",
                message: "Only PDF, DOCX, or JPG files are supported.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        if size > maxBytes {
            notifications.post(
                kind: .error,
                title: "Upload Failed",
                message: "File size exceeds the 10MB limit.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        let toastID = notifications.post(
            kind: .progress,
            title: "Uploading Document",
            message: "Saving \(fileName)…",
            progress: 0.3,
            isDismissible: true
        )

        do {
            try coreDataManager.addVaultDocument(fromSelectedURL: url, category: .other, source: "vault")
            notifications.complete(
                id: toastID,
                kind: .success,
                title: "Uploaded",
                message: "Added \(fileName) to Document Vault.",
                autoDismissAfter: 3
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
    }

    private func deleteAction(for item: VaultListItem) -> (() -> Void)? {
        switch item.source {
        case .vault(let doc):
            return {
                coreDataManager.deleteVaultDocument(doc)
                notifications.post(
                    kind: .success,
                    title: "Deleted",
                    message: "Removed \(item.name).",
                    isDismissible: true,
                    autoDismissAfter: 3
                )
            }
        case .transcript:
            return nil
        case .syllabus:
            return nil
        }
    }

    private func preview(item: VaultListItem) {
        guard let url = previewURL(for: item) else {
            notifications.post(
                kind: .error,
                title: "Preview Failed",
                message: "Could not locate the file for preview.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }
        quickLookURL = url
    }

    private func previewURL(for item: VaultListItem) -> URL? {
        switch item.source {
        case .vault(let doc):
            return coreDataManager.urlForVaultDocument(doc)

        case .transcript(let profile):
            guard let data = profile.transcriptData else { return nil }
            let name = (profile.transcriptFileName?.isEmpty == false) ? (profile.transcriptFileName ?? "transcript.pdf") : "transcript.pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try data.write(to: tempURL, options: [.atomic])
                return tempURL
            } catch {
                notifications.post(
                    kind: .error,
                    title: "Preview Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
                return nil
            }

        case .syllabus(let ov):
            guard let bookmark = ov.syllabusFileBookmarkData else { return nil }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else {
                return nil
            }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            // Copy to a temp file so Quick Look can access it without needing a security scope later.
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
                return tempURL
            } catch {
                notifications.post(
                    kind: .error,
                    title: "Preview Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
                return nil
            }
        }
    }

    private func export(item: VaultListItem) {
        switch item.source {
        case .vault(let doc):
            guard let url = coreDataManager.urlForVaultDocument(doc) else {
                notifications.post(
                    kind: .error,
                    title: "Export Failed",
                    message: "Could not locate the stored file.",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
                return
            }
            exportFile(at: url, suggestedName: item.name)

        case .transcript(let profile):
            guard let data = profile.transcriptData else { return }
            exportData(data, suggestedName: item.name)

        case .syllabus(let ov):
            guard let data = ov.syllabusFileBookmarkData else { return }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                exportFile(at: url, suggestedName: item.name)
            }
        }
    }

    private func exportFile(at url: URL, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
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

    private func exportData(_ data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                try data.write(to: dest, options: [.atomic])
            } catch {
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

    private func iconAndColor(forFileName fileName: String) -> (String, Color) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return ("doc.text.fill", DesignSystem.Colors.accent)
        case "docx": return ("doc.fill", DesignSystem.Colors.primary)
        case "jpg", "jpeg": return ("photo.fill", DesignSystem.Colors.secondary)
        default: return ("folder.fill", DesignSystem.Colors.secondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                .foregroundColor(isSelected ? DesignSystem.Colors.textMain : DesignSystem.Colors.textLight)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? DesignSystem.Colors.surface : Color.clear)
                .cornerRadius(8)
                .shadow(color: isSelected ? Color.black.opacity(0.05) : Color.clear, radius: 2)
        }
        .buttonStyle(.plain)
    }
}

struct DocumentItem: View {
    let name: String
    let date: String
    let icon: String
    let color: Color
    let onOpen: () -> Void
    let onExport: () -> Void
    let onDelete: (() -> Void)?
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .cornerRadius(8)
                
                VStack(alignment: .leading) {
                    Text(name)
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Text(date)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                }
            }
            Spacer()
            
            HStack(spacing: 8) {
                VaultIconButton(systemName: "square.and.arrow.down", help: "Download") {
                    onExport()
                }

                VaultIconMenu(help: "More") {
                    Button("Preview") { onOpen() }
                    Button("Download") { onExport() }

                    if let onDelete {
                        Divider()
                        Button("Delete") { onDelete() }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.clear, lineWidth: 1)
        )
    }
}

private struct VaultIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(width: 34, height: 34)
                .background(DesignSystem.Colors.bgMain)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct VaultIconMenu<MenuContent: View>: View {
    let help: String
    @ViewBuilder let content: () -> MenuContent

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textLight)
                .frame(width: 34, height: 34)
                .background(DesignSystem.Colors.bgMain)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "e2e8f0"), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .help(help)
    }
}

// MARK: - Campus Deadlines
struct CampusDeadlinesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(DesignSystem.Fonts.main(size: 20))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.accent.opacity(0.1))
                    .cornerRadius(12)
                
                Text("Campus Deadlines")
                    .font(DesignSystem.Fonts.main(size: 18, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textMain)
            }
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(hex: "f1f5f9"))
                    .frame(width: 2)
                    .padding(.leading, 19)
                    .padding(.vertical, 12)
                
                VStack(spacing: 16) {
                    DeadlineItem(month: "OCT", color: DesignSystem.Colors.accent, title: "Last day to drop (W)", dateBadge: "2 days", description: "Academic Penalty applies after this date.", isHighlighted: true)
                    DeadlineItem(month: "NOV", color: DesignSystem.Colors.primary, title: "Spring Registration", dateBadge: "Nov 14", description: "Seniors and Juniors priority access.", isHighlighted: false)
                    DeadlineItem(month: "DEC", color: DesignSystem.Colors.success, title: "Filing for Graduation", dateBadge: "Dec 01", description: nil, isHighlighted: false)
                }
            }
        }
        .padding(24)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10)
    }
}

struct DeadlineItem: View {
    let month: String
    let color: Color
    let title: String
    let dateBadge: String
    let description: String?
    let isHighlighted: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.surface)
                    .frame(width: 40, height: 40)
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 40, height: 40)
                Text(month)
                    .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                    Spacer()
                    Text(dateBadge)
                        .font(DesignSystem.Fonts.main(size: 10, weight: .bold))
                        .foregroundColor(isHighlighted ? color : DesignSystem.Colors.textLight)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(isHighlighted ? DesignSystem.Colors.surface : Color(hex: "f1f5f9"))
                        .cornerRadius(6)
                        .shadow(color: isHighlighted ? Color.black.opacity(0.05) : Color.clear, radius: 2)
                }
                
                if let description = description {
                    Text(description)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(isHighlighted ? color.opacity(0.8) : DesignSystem.Colors.textLight)
                }
            }
            .padding(12)
            .background(isHighlighted ? color.opacity(0.05) : DesignSystem.Colors.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHighlighted ? color.opacity(0.2) : Color(hex: "f1f5f9"), lineWidth: 1)
            )
            .shadow(color: isHighlighted ? Color.clear : Color.black.opacity(0.05), radius: 2)
        }
    }
}

// MARK: - Academic Advisor
struct AcademicAdvisorCard: View {
    @AppStorage("resources_academic_advisor_name") private var advisorName: String = ""
    @AppStorage("resources_academic_advisor_email") private var advisorEmail: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color(hex: "FFF4E6")
                    .frame(height: 140)
                
                HStack(alignment: .bottom, spacing: 16) {
                    LinearGradient(
                        colors: [Color(hex: "E8E8A6"), Color(hex: "999966")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white, lineWidth: 4)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Advisor Name", text: $advisorName)
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .textFieldStyle(.plain)
                            .disableAutocorrection(true)
                        Text("ACADEMIC ADVISOR")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "D97706"))
                            .tracking(0.5)
                        TextField("advisor@school.edu", text: $advisorEmail)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .textFieldStyle(.plain)
                            .disableAutocorrection(true)
                    }
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 24)
            }
            .frame(height: 140)
            .zIndex(1)
            
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "FEF3C7"))
                                .frame(width: 40, height: 40)
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(Color(hex: "D97706"))
                                .font(.system(size: 18))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Office Hours")
                                .font(DesignSystem.Fonts.main(size: 16, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textMain)
                            Text("Drop-ins welcome")
                                .font(DesignSystem.Fonts.main(size: 14))
                                .foregroundColor(DesignSystem.Colors.textLight)
                        }
                    }
                    
                    VStack(spacing: 6) {
                        Text("TOMORROW")
                            .font(DesignSystem.Fonts.main(size: 11, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textLight)
                            .textCase(.uppercase)
                        Text("10:00 AM - 12:00 PM")
                            .font(DesignSystem.Fonts.main(size: 20, weight: .bold))
                            .foregroundColor(DesignSystem.Colors.textMain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
                    )
                }
                .padding(20)
                .background(Color(hex: "F8FAFC"))
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(hex: "F1F5F9"), lineWidth: 1)
                )
                
                HStack(spacing: 16) {
                    Button(action: {
                        let trimmed = advisorEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let url = URL(string: "mailto:\(trimmed)") else { return }
                        NSWorkspace.shared.open(url)
                    }) {
                        Label(advisorEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Email" : advisorEmail, systemImage: "envelope")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundColor(DesignSystem.Colors.textMain)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
                            )
                    }
                    .disabled(advisorEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button(action: {}) {
                        Label("Book", systemImage: "calendar.badge.plus")
                            .font(DesignSystem.Fonts.main(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "ECA83B"))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: Color(hex: "ECA83B").opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
            }
            .padding(24)
            .background(Color.white)
        }
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10)
    }
}
