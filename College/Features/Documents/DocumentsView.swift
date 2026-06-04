// DocumentsView.swift
// Feature: Documents
// Purpose: Documents module — DocumentsEntranceModifier.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import UniformTypeIdentifiers
import os
import AppKit
import QuickLookUI

// MARK: - Motion Infrastructure

private enum DocumentsMotion {
    static let cardStaggerStep: Double = 0.05
    static let revealDuration: Double = 0.28
    static let reducedRevealDuration: Double = 0.10
}

private struct DocumentsEntranceModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 10))
            .animation(
                reduceMotion
                    ? .easeOut(duration: DocumentsMotion.reducedRevealDuration)
                    : .spring(response: DocumentsMotion.revealDuration, dampingFraction: 0.88)
                        .delay(Double(index) * DocumentsMotion.cardStaggerStep),
                value: isVisible
            )
    }
}

private struct PressableCardStyle: ButtonStyle {
    var reduceMotion: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.spring(response: 0.10, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct DocumentsDeferredInspectorModifier<InspectorContent: View>: ViewModifier {
    let isReady: Bool
    let isPresented: Binding<Bool>
    let inspectorContent: () -> InspectorContent

    @ViewBuilder
    func body(content: Content) -> some View {
        if isReady {
            content
                .inspector(isPresented: isPresented) {
                    inspectorContent()
                }
                .inspectorColumnWidth(min: 250, ideal: 300, max: 360)
        } else {
            content
        }
    }
}

struct DocumentsView: View {
    private let perfLog = OSLog(subsystem: "Timothy.College", category: "DocumentsViewPerf")
    @Binding var searchText: String
    @Binding var isInspectorPresented: Bool
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @StateObject private var cloudIntegration = CloudIntegrationService.shared

    @SceneStorage("documents.view.hasAnimatedIn") private var hasAnimatedIn = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var prefReduceMotion = false
    private var motionReduced: Bool { systemReduceMotion || prefReduceMotion }

    @State private var showUploadPicker = false
    @State private var isUploading = false
    @State private var lastUploadError: String?
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var isCreateFolderPromptPresented: Bool = false
    @State private var newFolderName: String = ""
    @State private var isRenameFolderPromptPresented: Bool = false
    @State private var renameFolderName: String = ""
    @State private var renameFolderID: UUID?
    @State private var isDeleteFolderDialogPresented: Bool = false
    @State private var pendingDeleteFolderID: UUID?
    @State private var isDeleteFilesDialogPresented: Bool = false
    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var vaultRefreshToken = 0

    private struct FolderRowData: Identifiable {
        let id: String
        let item: VaultSidebarItem
        let depth: Int
    }

    private enum VaultSidebarItem: Hashable, Identifiable {
        case allFiles
        case recent
        case starred
        case needsReview
        case folder(UUID, String)
        case integration(String, String, Bool)
        case course(String)

        var id: String {
            switch self {
            case .allFiles: return "all"
            case .recent: return "recent"
            case .starred: return "starred"
            case .needsReview: return "needsReview"
            case .folder(let id, _): return "folder::\(id.uuidString.lowercased())"
            case .integration(let providerID, _, _): return "integration::\(providerID.lowercased())"
            case .course(let code): return "course::\(code.lowercased())"
            }
        }

        var title: String {
            switch self {
            case .allFiles: return "All Files"
            case .recent: return "Recent"
            case .starred: return "Starred"
            case .needsReview: return "Needs Review"
            case .folder(_, let name): return name
            case .integration(_, let name, _): return name
            case .course(let code): return code
            }
        }

        var systemImage: String {
            switch self {
            case .allFiles: return "tray.full"
            case .recent: return "clock"
            case .starred: return "star"
            case .needsReview: return "exclamationmark.bubble"
            case .folder: return "folder"
            case .integration: return "folder.badge.cloud"
            case .course: return "book.closed"
            }
        }

        var destinationLabel: String {
            switch self {
            case .allFiles: return "/All Files"
            case .recent: return "/Smart/Recent"
            case .starred: return "/Smart/Starred"
            case .needsReview: return "/Smart/Needs Review"
            case .folder(_, let name): return "/Folders/\(name)"
            case .integration(_, let name, _): return "/Integrations/\(name)"
            case .course(let code): return "/Courses/\(code)"
            }
        }

        var folderID: UUID? {
            if case .folder(let id, _) = self { return id }
            return nil
        }
    }

    @State private var selectedSidebarItem: VaultSidebarItem = .allFiles

    private enum VaultFileFilter: String, CaseIterable, Identifiable {
        case all
        case pdf
        case sheets
        case scripts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .pdf: return "PDF"
            case .sheets: return "Sheets"
            case .scripts: return "Scripts"
            }
        }
    }

    @State private var selectedFilter: VaultFileFilter = .all

    private enum VaultItemsLayout: String, CaseIterable, Identifiable, Hashable {
        case list
        case grid

        var id: String { rawValue }
    }

    @State private var vaultItemsLayout: VaultItemsLayout = .grid

    private struct VaultMetricsSnapshot: Equatable {
        var pdfCount: Int = 0
        var sheetCount: Int = 0
        var scriptCount: Int = 0
        var totalFiles: Int = 0
        var totalCategories: Int = 0
        var totalBytes: Int64 = 0
    }

    @State private var vaultMetrics: VaultMetricsSnapshot = VaultMetricsSnapshot()
    @State private var vaultMetricsDebounceTask: Task<Void, Never>?
    @State private var lastVaultMetricsRefresh: Date?
    @State private var canAttachInspector: Bool = false
    @State private var canRenderFinderTable: Bool = false

    private var deferredInspectorPresentation: Binding<Bool> {
        Binding(
            get: { canAttachInspector && isInspectorPresented },
            set: { presented in
                guard canAttachInspector else { return }
                isInspectorPresented = presented
            }
        )
    }

    private var sidebarFolderItems: [VaultSidebarItem] {
        _ = vaultRefreshToken
        return VaultReadBridge.rootFolders(collegePersistence: collegePersistence).map { folder in
            let name = folder.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return .folder(folder.id, name.isEmpty ? "Folder" : name)
        }
    }

    /// local store-first vault list (Phase 7f).
    private var vaultDocuments: [VaultDocument] {
        _ = vaultRefreshToken
        return VaultReadBridge.allVaultDocuments(collegePersistence: collegePersistence)
    }

    private var allFolderEntities: [VaultDocument] {
        vaultDocuments
            .filter { $0.isFolder }
            .sorted {
                let lhs = $0.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhs = $1.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    // MARK: - Finder Tree Model

    /// A node in the Finder-style outline tree (folder or file).
    private struct VaultTreeItem: Identifiable {
        let id: UUID
        let entity: VaultDocument
        var children: [VaultTreeItem]?   // nil = leaf (file), array = folder

        init(entity: VaultDocument, children: [VaultTreeItem]? = nil) {
            self.id = entity.id
            self.entity = entity
            self.children = children
        }

        var name: String {
            let custom = entity.customDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty { return custom }
            return entity.fileName.isEmpty ? "Untitled" : entity.fileName
        }
        var isFolder: Bool { entity.isFolder }

        var sfSymbol: String {
            if isFolder { return "folder.fill" }
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "pdf": return "doc.fill"
            case "xlsx", "xls", "csv", "numbers": return "tablecells.fill"
            case "docx", "doc": return "doc.text.fill"
            case "rtf", "txt": return "doc.plaintext.fill"
            case "pptx", "ppt": return "rectangle.on.rectangle.fill"
            case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
            case "mp4", "mov", "avi": return "film.fill"
            case "mp3", "m4a", "wav": return "waveform"
            case "zip", "tar", "gz", "rar": return "archivebox.fill"
            case "swift": return "swift"
            case "py", "js", "ts", "html", "css", "sh": return "chevron.left.forwardslash.chevron.right"
            default: return "doc"
            }
        }

        var iconColor: Color {
            if isFolder { return .yellow }
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "pdf": return .red
            case "xlsx", "xls", "csv", "numbers": return .green
            case "docx", "doc", "rtf", "txt": return .blue
            case "pptx", "ppt": return .orange
            case "png", "jpg", "jpeg", "gif", "heic", "webp": return .purple
            case "mp4", "mov", "avi": return .pink
            case "zip", "tar", "gz", "rar": return .brown
            case "swift": return .orange
            case "py", "js", "ts", "html", "css", "sh": return .purple
            default: return .secondary
            }
        }

        var dateModifiedString: String {
            let date = entity.lastOpenedAt ?? entity.addedAt
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: date)
        }

        var sizeString: String {
            if isFolder { return "—" }
            let f = ByteCountFormatter()
            f.countStyle = .file
            f.zeroPadsFractionDigits = false
            return f.string(fromByteCount: entity.fileSizeBytes)
        }

        var kind: String {
            if isFolder { return "Folder" }
            let ext = (name as NSString).pathExtension.uppercased()
            switch ext {
            case "PDF": return "PDF Document"
            case "XLSX", "XLS": return "Excel Spreadsheet"
            case "CSV": return "CSV"
            case "NUMBERS": return "Numbers Spreadsheet"
            case "DOCX", "DOC": return "Word Document"
            case "RTF": return "Rich Text Document"
            case "TXT": return "Plain Text"
            case "PPTX", "PPT": return "Presentation"
            case "PNG": return "PNG Image"
            case "JPG", "JPEG": return "JPEG Image"
            case "GIF": return "GIF Image"
            case "HEIC": return "HEIC Image"
            case "WEBP": return "WebP Image"
            case "MP4": return "MPEG-4 Movie"
            case "MOV": return "QuickTime Movie"
            case "MP3": return "MP3 Audio"
            case "M4A": return "MPEG-4 Audio"
            case "ZIP": return "ZIP Archive"
            case "TAR", "GZ", "RAR": return "Archive"
            case "SWIFT": return "Swift Source"
            case "PY": return "Python Script"
            case "JS": return "JavaScript"
            case "TS": return "TypeScript"
            case "HTML": return "HTML Document"
            case "CSS": return "CSS Document"
            case "SH": return "Shell Script"
            default: return ext.isEmpty ? "Document" : "\(ext) File"
            }
        }
    }

    /// Recursively builds tree nodes rooted at `parentID`.
    private func buildFinderTreeItems(parentID: UUID?) -> [VaultTreeItem] {
        let all = vaultDocuments
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var children = all.filter { $0.parentFolderID == parentID }

        // Apply file-type filter (folders pass through always)
        if selectedFilter != .all {
            children = children.filter { doc in
                guard !doc.isFolder else { return true }
                let p = VaultDocumentPresentation(doc: doc)
                switch selectedFilter {
                case .all: return true
                case .pdf: return p.iconKind == "pdf"
                case .sheets: return p.iconKind == "sheet"
                case .scripts: return p.iconKind == "script"
                }
            }
        }

        // Apply search query (folders pass through so subtrees are reachable)
        if !query.isEmpty {
            children = children.filter { doc in
                guard !doc.isFolder else { return true }
                let name = doc.fileName
                let cat  = doc.category
                let link = doc.courseCodeLinked ?? ""
                return name.localizedCaseInsensitiveContains(query)
                    || cat.localizedCaseInsensitiveContains(query)
                    || link.localizedCaseInsensitiveContains(query)
            }
        }

        let sorted = children.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }

        return sorted.map { doc in
            if doc.isFolder {
                return VaultTreeItem(entity: doc, children: buildFinderTreeItems(parentID: doc.id))
            } else {
                return VaultTreeItem(entity: doc, children: nil)
            }
        }
    }

    /// Root nodes for the Finder-style outline, driven by the current sidebar selection.
    private var finderRootItems: [VaultTreeItem] {
        switch selectedSidebarItem {
        case .allFiles:
            return buildFinderTreeItems(parentID: nil)
        case .folder(let folderID, _):
            return buildFinderTreeItems(parentID: folderID)
        default:
            // Smart filters: flat list without hierarchy
            return visibleVaultDocuments.map { VaultTreeItem(entity: $0, children: nil) }
        }
    }

    private func childFolders(of parentID: UUID?) -> [VaultDocument] {
        allFolderEntities.filter { $0.parentFolderID == parentID }
    }

    private func folderHasChildren(_ folderID: UUID) -> Bool {
        allFolderEntities.contains(where: { $0.parentFolderID == folderID })
    }

    private func collapseAllFolders() {
        collapsedFolderIDs = Set(
            allFolderEntities
                .compactMap(\.id)
                .filter(folderHasChildren)
        )
    }

    private func expandAllFolders() {
        collapsedFolderIDs = []
    }

    private var flattenedFolderRows: [FolderRowData] {
        var rows: [FolderRowData] = []

        func collect(parentID: UUID?, depth: Int) {
            for folder in childFolders(of: parentID) {
                let id = folder.id
                let name = folder.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                let item: VaultSidebarItem = .folder(id, name.isEmpty ? "Folder" : name)
                rows.append(.init(id: item.id, item: item, depth: depth))
                if !collapsedFolderIDs.contains(id) {
                    collect(parentID: id, depth: depth + 1)
                }
            }
        }

        collect(parentID: nil, depth: 0)
        return rows
    }

    private var sidebarCourseItems: [VaultSidebarItem] {
        let codes = Set(
            vaultDocuments
                .compactMap { $0.courseCodeLinked?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return codes.sorted().map { .course($0) }
    }

    private var sidebarIntegrationItems: [VaultSidebarItem] {
        cloudIntegration.providers
            .filter { $0.isDetected || $0.isAuthorized || $0.needsRegrant }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { .integration($0.id, $0.displayName, $0.isAuthorized) }
    }

    private var selectedDocument: VaultDocument? {
        guard let selectedID = selectedDocumentIDs.first else { return nil }
        return vaultDocuments.first(where: { $0.id == selectedID })
    }

    private var selectedDocuments: [VaultDocument] {
        vaultDocuments.filter { doc in
            !doc.isFolder && selectedDocumentIDs.contains(doc.id)
        }
    }

    private var hasSelection: Bool {
        !selectedDocuments.isEmpty
    }

    private var moveDestinationFolders: [(id: UUID, name: String)] {
        allFolderEntities.compactMap { folder in
            let id = folder.id
            let name = folder.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (id, name.isEmpty ? "Folder" : name)
        }
    }

    private var visibleVaultDocuments: [VaultDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return vaultDocuments.filter { doc in
            let matchesSidebar: Bool = {
                switch selectedSidebarItem {
                case .allFiles:
                    return !doc.isFolder
                case .recent:
                    return !doc.isFolder && doc.lastOpenedAt != nil
                case .starred:
                    return !doc.isFolder && doc.isFavorite
                case .needsReview:
                    return !doc.isFolder && doc.needsReview
                case .folder(let folderID, _):
                    return !doc.isFolder && doc.parentFolderID == folderID
                case .integration(let providerID, _, _):
                    let source = (doc.source ?? "")
                    return !doc.isFolder && source.hasPrefix("integration::\(providerID)")
                case .course(let code):
                    let linked = (doc.courseCodeLinked ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return !doc.isFolder && linked.caseInsensitiveCompare(code) == .orderedSame
                }
            }()
            guard matchesSidebar else { return false }

            let p = VaultDocumentPresentation(doc: doc)

            let passesFilter: Bool = {
                switch selectedFilter {
                case .all: return true
                case .pdf: return p.iconKind == "pdf"
                case .sheets: return p.iconKind == "sheet"
                case .scripts: return p.iconKind == "script"
                }
            }()
            guard passesFilter else { return false }

            guard !query.isEmpty else { return true }
            let fileName = doc.fileName
            let category = doc.category
            let linkedCourse = doc.courseCodeLinked ?? ""
            return fileName.localizedCaseInsensitiveContains(query)
                || category.localizedCaseInsensitiveContains(query)
                || linkedCourse.localizedCaseInsensitiveContains(query)
        }
        .sorted {
            ($0.addedAt) > ($1.addedAt)
        }
    }

    private var emptyStateTitle: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return String(localized: "documents.empty.filtered_title", defaultValue: "No matching files")
        }

        switch selectedFilter {
        case .all:
            return String(localized: "documents.empty.title")
        case .pdf:
            return "No PDF files"
        case .sheets:
            return "No Sheets files"
        case .scripts:
            return "No Scripts files"
        }
    }

    private var emptyStateMessage: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return String(localized: "documents.empty.filtered_message", defaultValue: "Try a different search term.")
        }

        if selectedFilter != .all {
            return "Try another file type or switch back to All."
        }

        return String(localized: "documents.empty.message")
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding = proxy.size.width < 980 ? 16.0 : 24.0

            VStack(alignment: .leading, spacing: 16) {
                fileTypeCountsRow
                    .modifier(DocumentsEntranceModifier(index: 0, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                breadcrumbSection
                    .modifier(DocumentsEntranceModifier(index: 1, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                vaultToolbarRow
                    .modifier(DocumentsEntranceModifier(index: 2, isVisible: hasAnimatedIn, reduceMotion: motionReduced))

                filesListSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(DocumentsEntranceModifier(index: 3, isVisible: hasAnimatedIn, reduceMotion: motionReduced))
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(.windowBackground)
        .onAppear {
            guard !hasAnimatedIn else { return }
            withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.28, dampingFraction: 0.88)) {
                hasAnimatedIn = true
            }
        }

        .modifier(DocumentsDeferredInspectorModifier(
            isReady: canAttachInspector,
            isPresented: deferredInspectorPresentation,
            inspectorContent: { documentsInspectorPanel }
        ))
        .fileImporter(
            isPresented: $showUploadPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { @MainActor in
                await handlePickedUpload(result)
            }
        }
        .onAppear {
            scheduleRecomputeVaultMetrics()
            cloudIntegration.refreshDetectedProviders()

            // Only defer table mount automatically; inspector attachment is now
            // explicit-on-demand to avoid first-entry split-view constraint churn.
            guard !canRenderFinderTable else { return }
            if !canRenderFinderTable {
                DispatchQueue.main.async {
                    canRenderFinderTable = true
                }
            }
        }
        .onChange(of: isInspectorPresented) { _, presented in
            guard presented, !canAttachInspector else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                canAttachInspector = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            scheduleRecomputeVaultMetrics()
            cloudIntegration.refreshDetectedProviders()
        }
        .background {
            DocumentsVaultQueryHost(refreshToken: $vaultRefreshToken)
        }
        .onReceive(collegePersistence.$vaultDidChangeToken) { _ in
            vaultRefreshToken &+= 1
            refreshVaultSelectionState()
        }
        .alert("Create Folder", isPresented: $isCreateFolderPromptPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                createFolderFromPrompt()
            }
        } message: {
            Text("Create a new folder in the current location.")
        }
        .alert("Rename Folder", isPresented: $isRenameFolderPromptPresented) {
            TextField("Folder name", text: $renameFolderName)
            Button("Cancel", role: .cancel) {
                renameFolderID = nil
                renameFolderName = ""
            }
            Button("Rename") {
                renameFolderFromPrompt()
            }
        } message: {
            Text("Choose a new folder name.")
        }
        .confirmationDialog(
            "Delete Folder",
            isPresented: $isDeleteFolderDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Folder Only") {
                deletePendingFolder(includeContents: false)
            }
            Button("Delete Folder and Contents", role: .destructive) {
                deletePendingFolder(includeContents: true)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteFolderID = nil
            }
        } message: {
            if let pendingDeleteFolderID,
               let folder = folderEntity(withID: pendingDeleteFolderID) {
                Text("Choose how to delete \(folder.fileName.isEmpty ? "this folder" : folder.fileName).")
            } else {
                Text("Choose how to delete this folder.")
            }
        }
        .confirmationDialog(
            "Delete Selected Files",
            isPresented: $isDeleteFilesDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedDocuments.count) Files", role: .destructive) {
                deleteSelectedDocumentsConfirmed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func scheduleRecomputeVaultMetrics() {
        vaultMetricsDebounceTask?.cancel()
        vaultMetricsDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            recomputeVaultMetrics()
        }
    }

    private func refreshVaultSelectionState() {
        scheduleRecomputeVaultMetrics()
        selectedDocumentIDs = selectedDocumentIDs.filter { id in
            visibleVaultDocuments.contains(where: { $0.id == id })
        }
    }

    private func recomputeVaultMetrics() {
        let signpostID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "recomputeVaultMetrics", signpostID: signpostID)
        defer { os_signpost(.end, log: perfLog, name: "recomputeVaultMetrics", signpostID: signpostID) }

        var snapshot = VaultMetricsSnapshot()
        var categories = Set<String>()
        let docs = vaultDocuments.filter { !$0.isFolder }
        snapshot.totalFiles = docs.count
        for doc in docs {
            snapshot.totalBytes += doc.fileSizeBytes
            if !doc.category.isEmpty { categories.insert(doc.category) }
            let name = (doc.fileName).lowercased()
            if name.hasSuffix(".pdf") {
                snapshot.pdfCount += 1
            }
            if name.hasSuffix(".xlsx") || name.hasSuffix(".xls") || name.hasSuffix(".csv") || name.hasSuffix(".numbers") {
                snapshot.sheetCount += 1
            }
            if name.hasSuffix(".js") || name.hasSuffix(".py") || name.hasSuffix(".swift") || name.hasSuffix(".sh") || name.hasSuffix(".html") {
                snapshot.scriptCount += 1
            }
        }
        snapshot.totalCategories = categories.count
        vaultMetrics = snapshot
        lastVaultMetricsRefresh = Date()
    }
    
    @MainActor
    private func handlePickedUpload(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            _ = await importURLs(urls)
        case .failure(let error):
            lastUploadError = error.localizedDescription
        }
    }

    @MainActor
    private func importURLs(
        _ urls: [URL],
        sourceOverride: String? = nil,
        providerRoots: [CloudIntegrationService.AuthorizedRoot] = []
    ) async -> Bool {
        guard !urls.isEmpty else { return false }
        isUploading = true
        defer { isUploading = false }

        let destinationFolderID = selectedSidebarItem.folderID
        var importedCount = 0

        var firstError: String?
        for url in urls {
            do {
                let source = resolvedSourceForImport(
                    url,
                    sourceOverride: sourceOverride,
                    providerRoots: providerRoots
                )
                try await collegePersistence.addVaultDocument(
                    fromSelectedURL: url,
                    source: source,
                    parentFolderID: destinationFolderID
                )
                importedCount += 1
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
        }
        lastUploadError = firstError
        return importedCount > 0
    }

    private func resolvedSourceForImport(
        _ url: URL,
        sourceOverride: String?,
        providerRoots: [CloudIntegrationService.AuthorizedRoot]
    ) -> String {
        if let sourceOverride {
            return sourceOverride
        }

        if !providerRoots.isEmpty {
            let canonical = (url.path as NSString).standardizingPath
            if let root = providerRoots.first(where: { root in
                canonical == root.path || canonical.hasPrefix(root.path + "/")
            }) {
                return "integration::\(root.providerID)"
            }
        }

        return "vault"
    }

    private func pickFilesFromIntegration(provider: CloudIntegrationService.Provider?) {
        let roots = cloudIntegration.authorizedRoots().filter { root in
            guard let provider else { return true }
            return root.providerID == provider.id
        }
        guard !roots.isEmpty else {
            if let provider {
                lastUploadError = "\(provider.displayName) has no authorized folders yet. Grant access in Settings > Documents first."
            } else {
                lastUploadError = "No authorized integrations yet. Grant access in Settings > Documents first."
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = roots.first?.url
        panel.prompt = "Import"
        if let provider {
            panel.message = "Choose files from authorized \(provider.displayName) folders."
        } else {
            panel.message = "Choose files from authorized cloud integration folders."
        }

        panel.begin { response in
            guard response == .OK else { return }
            let picked = panel.urls

            let allowedRoots = roots.map { ($0.path as NSString).standardizingPath }
            let allowedURLs = picked.filter { url in
                let canonical = (url.path as NSString).standardizingPath
                return allowedRoots.contains(where: { root in
                    canonical == root || canonical.hasPrefix(root + "/")
                })
            }

            Task { @MainActor in
                if allowedURLs.isEmpty {
                    lastUploadError = "No selected files were inside authorized integration folders."
                    return
                }

                if allowedURLs.count < picked.count {
                    lastUploadError = "Some selected files were ignored because they were outside authorized integration folders."
                }

                let sourceOverride: String?
                if let provider {
                    sourceOverride = "integration::\(provider.id)"
                } else {
                    sourceOverride = nil
                }

                let imported = await importURLs(
                    allowedURLs,
                    sourceOverride: sourceOverride,
                    providerRoots: roots
                )
                guard imported else { return }

                let touchedProviderIDs = Set(allowedURLs.compactMap { fileURL -> String? in
                    let canonical = (fileURL.path as NSString).standardizingPath
                    guard let root = roots.first(where: { root in
                        canonical == root.path || canonical.hasPrefix(root.path + "/")
                    }) else {
                        return nil
                    }
                    return root.providerID
                })

                for providerID in touchedProviderIDs {
                    cloudIntegration.recordImport(providerID: providerID)
                }
            }
        }
    }

    @MainActor
    private func openVaultDocument(_ doc: VaultDocument) {
        Task {
            guard let url = await VaultDocumentAccess.decryptedTempURL(for: doc.id, collegePersistence: collegePersistence) else { return }
            VaultDocumentAccess.markOpened(id: doc.id, collegePersistence: collegePersistence)
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func revealVaultDocumentInFinder(_ doc: VaultDocument) {
        guard let vaultURL = VaultDocumentAccess.urlForDocument(id: doc.id, collegePersistence: collegePersistence) else { return }
        NSWorkspace.shared.selectFile(vaultURL.path, inFileViewerRootedAtPath: "")
    }

    private var availableCourseCodes: [String] {
        let codes = collegePersistence.semesters
            .flatMap { $0.coursesArray }
            .compactMap { $0.code }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        return Array(Set(codes)).sorted()
    }

    @MainActor
    private func quickLookVaultDocument(_ doc: VaultDocument) {
        Task {
            guard let url = await VaultDocumentAccess.decryptedTempURL(for: doc.id, collegePersistence: collegePersistence) else { return }
            VaultQuickLookPresenter.shared.present(url: url)
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder private var vaultActionsMenu: some View {
        Menu {
            Button("Select Visible", systemImage: "checklist") {
                selectAllVisibleDocuments()
            }

            Menu {
                Button("All Files (Root)", systemImage: "tray.full") {
                    moveSelectedDocuments(to: nil)
                }
                .disabled(!canMoveSelectedDocuments(to: nil))

                Divider()

                ForEach(moveDestinationFolders, id: \.id) { destination in
                    Button(destination.name, systemImage: "folder") {
                        moveSelectedDocuments(to: destination.id)
                    }
                    .disabled(!canMoveSelectedDocuments(to: destination.id))
                }
            } label: {
                Label("Move Selected", systemImage: "folder")
            }
            .disabled(!hasSelection)

            Button("Delete Selected", systemImage: "trash", role: .destructive) {
                isDeleteFilesDialogPresented = true
            }
            .disabled(!hasSelection)

            Button("Clear Selection", systemImage: "xmark.circle") {
                selectedDocumentIDs = []
            }
            .disabled(!hasSelection)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .help("Actions")
    }

    @ViewBuilder private var vaultImportMenu: some View {
        Menu {
            Button("Import from Mac…") {
                showUploadPicker = true
            }
            Button("Import from Integration…") {
                pickFilesFromIntegration(provider: nil)
            }

            let authorizedProviders = cloudIntegration.providers.filter { $0.isAuthorized }
            if !authorizedProviders.isEmpty {
                Divider()
                ForEach(authorizedProviders) { provider in
                    Button("Import from \(provider.displayName)…") {
                        pickFilesFromIntegration(provider: provider)
                    }
                }
            }
        } label: {
            ZStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isUploading ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isUploading)
                    .opacity(isUploading ? 0.0 : 1.0)
                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(isUploading)
        .help(isUploading ? String(localized: "documents.add.uploading") : "Import files")
    }

    private var documentsInspectorPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SMART")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    sidebarRow(for: .allFiles)
                    sidebarRow(for: .recent)
                    sidebarRow(for: .starred)
                    sidebarRow(for: .needsReview)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("FOLDERS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.8)

                        Spacer()

                        Menu {
                            Button("Expand All", systemImage: "arrow.down.right.and.arrow.up.left") {
                                expandAllFolders()
                            }
                            Button("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right") {
                                collapseAllFolders()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                        .help("Folder tree actions")
                    }

                    if flattenedFolderRows.isEmpty {
                        Text("No folders yet")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(flattenedFolderRows) { row in
                            sidebarRow(for: row.item, depth: row.depth)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("INTEGRATIONS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    if sidebarIntegrationItems.isEmpty {
                        Text("No integrations")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(sidebarIntegrationItems) { item in
                            sidebarRow(for: item)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("COURSES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)

                    if sidebarCourseItems.isEmpty {
                        Text("No linked courses")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(sidebarCourseItems) { item in
                            sidebarRow(for: item)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                inspectorSection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicatorsFlash(trigger: selectedSidebarItem)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.windowBackground)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func sidebarRow(for item: VaultSidebarItem, depth: Int = 0) -> some View {
        let isSelected = selectedSidebarItem == item
        let count = countForSidebarItem(item)
        let folderID = item.folderID
        let isFolderWithChildren = folderID.map(folderHasChildren) ?? false
        let isCollapsed = folderID.map { collapsedFolderIDs.contains($0) } ?? false

        return HStack(spacing: 6) {
            if let folderID, isFolderWithChildren {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        if collapsedFolderIDs.contains(folderID) {
                            collapsedFolderIDs.remove(folderID)
                        } else {
                            collapsedFolderIDs.insert(folderID)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .animation(.easeInOut(duration: 0.20), value: isCollapsed)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand folder" : "Collapse folder")
            } else if folderID != nil {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            SidebarRowButtonLabel(
                systemImage: item.systemImage,
                title: item.title,
                isSelected: isSelected,
                count: count,
                motionReduced: motionReduced,
                onSelect: {
                    withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedSidebarItem = item
                    }
                }
            )
        }
        .padding(.leading, CGFloat(10 + depth * 14))
        .contextMenu {
            if case .folder(let id, _) = item {
                Button("New Subfolder") {
                    selectedSidebarItem = item
                    newFolderName = ""
                    isCreateFolderPromptPresented = true
                }
                Divider()
                Button("Rename") {
                    beginRenameFolder(folderID: id)
                }
                Button("Delete...") {
                    pendingDeleteFolderID = id
                    isDeleteFolderDialogPresented = true
                }
                if isFolderWithChildren {
                    Divider()
                    Button(isCollapsed ? "Expand" : "Collapse") {
                        if collapsedFolderIDs.contains(id) {
                            collapsedFolderIDs.remove(id)
                        } else {
                            collapsedFolderIDs.insert(id)
                        }
                    }
                }
            }

            if case .integration(let providerID, let name, _) = item,
               let provider = providerForSidebarIntegration(providerID: providerID) {
                Divider()
                Button("Import from \(name)…") {
                    pickFilesFromIntegration(provider: provider)
                }
            }
        }
        .dropDestination(for: String.self, isEnabled: true) { droppedPayloads, _ in
            switch item {
            case .allFiles:
                moveDraggedDocuments(droppedPayloads, to: nil)
            case .folder(let folderID, _):
                moveDraggedDocuments(droppedPayloads, to: folderID)
            default:
                break
            }
        }
    }

    private var breadcrumbSection: some View {
        HStack(spacing: 10) {
            Button {
                selectedSidebarItem = .allFiles
            } label: {
                Label("Documents", systemImage: "folder")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if case .folder(let folderID, _) = selectedSidebarItem {
                let breadcrumbItems = folderBreadcrumbItems(for: folderID)
                ForEach(breadcrumbItems) { crumb in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)

                    Button {
                        selectedSidebarItem = crumb
                    } label: {
                        Text(crumb.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(crumb == selectedSidebarItem ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)

                Text(selectedSidebarItem.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            if hasSelection {
                Text("\(selectedDocuments.count) selected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var inspectorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Inspector")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)

            if let document = selectedDocument {
                Group {
                    inspectorRow(label: "Name", value: document.fileName)
                    inspectorRow(label: "Category", value: document.category)
                    inspectorRow(label: "Course", value: (document.courseCodeLinked ?? "Not linked"))
                    inspectorRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: document.fileSizeBytes, countStyle: .file))
                    inspectorRow(label: "Added", value: formattedDate(document.addedAt))
                    inspectorRow(label: "Tags", value: (document.tags ?? "None"))
                }

                if let notes = document.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Text(notes)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("Select a document to view metadata.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    private func inspectorRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func countForSidebarItem(_ item: VaultSidebarItem) -> Int {
        vaultDocuments.filter { doc in
            switch item {
            case .allFiles:
                return !doc.isFolder
            case .recent:
                return !doc.isFolder && doc.lastOpenedAt != nil
            case .starred:
                return !doc.isFolder && doc.isFavorite
            case .needsReview:
                return !doc.isFolder && doc.needsReview
            case .folder(let id, _):
                return !doc.isFolder && doc.parentFolderID == id
            case .integration(let providerID, _, _):
                let source = (doc.source ?? "")
                return !doc.isFolder && source.hasPrefix("integration::\(providerID)")
            case .course(let code):
                let linked = (doc.courseCodeLinked ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !doc.isFolder && linked.caseInsensitiveCompare(code) == .orderedSame
            }
        }.count
    }

    @MainActor
    private func createFolderFromPrompt() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let created = collegePersistence.createVaultFolderDocument(name: trimmed, parentFolderID: selectedSidebarItem.folderID)
        if let created {
            selectedSidebarItem = .folder(created.id, trimmed)
        }
        newFolderName = ""
    }

    private func folderEntity(withID id: UUID) -> VaultDocument? {
        vaultDocuments.first(where: { $0.isFolder && $0.id == id })
    }

    private func folderBreadcrumbItems(for folderID: UUID) -> [VaultSidebarItem] {
        var result: [VaultSidebarItem] = []
        var currentID: UUID? = folderID
        var guardCount = 0

        while let id = currentID, guardCount < 64 {
            guard let folder = folderEntity(withID: id) else { break }
            let name = folder.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(.folder(id, name.isEmpty ? "Folder" : name))
            currentID = folder.parentFolderID
            guardCount += 1
        }

        return result.reversed()
    }

    private func providerForSidebarIntegration(providerID: String) -> CloudIntegrationService.Provider? {
        cloudIntegration.providers.first(where: { $0.id == providerID })
    }

    private func beginRenameFolder(folderID: UUID) {
        guard let folder = folderEntity(withID: folderID) else { return }
        renameFolderID = folderID
        renameFolderName = folder.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenameFolderPromptPresented = true
    }

    private func renameFolderFromPrompt() {
        guard let renameFolderID,
              let folder = folderEntity(withID: renameFolderID) else {
            return
        }
        let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        collegePersistence.renameVaultFolder(folder, newName: trimmed)

        if case .folder(let selectedID, _) = selectedSidebarItem, selectedID == renameFolderID {
            selectedSidebarItem = .folder(renameFolderID, trimmed)
        }

        self.renameFolderID = nil
        self.renameFolderName = ""
    }

    private func deletePendingFolder(includeContents: Bool) {
        guard let pendingDeleteFolderID,
              let folder = folderEntity(withID: pendingDeleteFolderID) else {
            self.pendingDeleteFolderID = nil
            return
        }

        collegePersistence.deleteVaultFolder(folder, includeContents: includeContents)

        if case .folder(let selectedID, _) = selectedSidebarItem, selectedID == pendingDeleteFolderID {
            selectedSidebarItem = .allFiles
        }

        self.pendingDeleteFolderID = nil
    }

    private func dragPayload(for doc: VaultDocument) -> String {
        let ids: [UUID]
        if selectedDocumentIDs.contains(doc.id), !selectedDocumentIDs.isEmpty {
            ids = Array(selectedDocumentIDs)
        } else {
            ids = [doc.id]
        }
        return ids.map(\.uuidString).joined(separator: "|")
    }

    private func moveDraggedDocuments(_ droppedPayloads: [String], to folderID: UUID?) {
        let tokens: [String] = droppedPayloads
            .flatMap { payload in
                payload.split(separator: "|").map(String.init)
            }

        let documentIDs: [UUID] = tokens.compactMap { UUID(uuidString: $0) }
        guard !documentIDs.isEmpty else { return }

        for documentID in documentIDs {
            guard let doc = vaultDocuments.first(where: { $0.id == documentID }) else { continue }
            guard !doc.isFolder, doc.parentFolderID != folderID else { continue }
            collegePersistence.moveVaultDocument(doc, toFolderID: folderID)
        }
    }

    private func selectAllVisibleDocuments() {
        selectedDocumentIDs = Set(visibleVaultDocuments.map(\.id))
    }

    private func moveSelectedDocuments(to folderID: UUID?) {
        for doc in selectedDocuments {
            guard doc.parentFolderID != folderID else { continue }
            collegePersistence.moveVaultDocument(doc, toFolderID: folderID)
        }
        selectedDocumentIDs = Set(selectedDocuments.map(\.id))
    }

    private func canMoveSelectedDocuments(to folderID: UUID?) -> Bool {
        selectedDocuments.contains(where: { $0.parentFolderID != folderID })
    }

    private func deleteSelectedDocumentsConfirmed() {
        let docs = selectedDocuments
        guard !docs.isEmpty else { return }
        collegePersistence.bulkDeleteVaultDocuments(docs)
        selectedDocumentIDs = []
    }
    
    private var vaultFooterStatusLine: String {
        let n = visibleVaultDocuments.count
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            if n == 1 {
                return String(
                    localized: "documents.footer.filtered_one",
                    defaultValue: "Showing 1 filtered file"
                )
            }
            return String(
                format: String(
                    localized: "documents.footer.filtered_many",
                    defaultValue: "Showing %d filtered files"
                ),
                n
            )
        }
        if n == 1 {
            return String(localized: "documents.footer.showing_one")
        }
        return String(format: String(localized: "documents.footer.showing_many"), n)
    }

    @ViewBuilder
    private func vaultDocumentContextMenu(for doc: VaultDocument) -> some View {
        Button("Open") {
            openVaultDocument(doc)
        }
        Button("Quick Look") {
            quickLookVaultDocument(doc)
        }
        Divider()
        Button("Reveal in Finder") {
            revealVaultDocumentInFinder(doc)
        }
        Menu("Move to Folder") {
            Button("All Files (Root)") {
                collegePersistence.moveVaultDocument(doc, toFolderID: nil)
            }
            .disabled(doc.parentFolderID == nil)

            Divider()

            ForEach(moveDestinationFolders, id: \.id) { destination in
                Button(destination.name) {
                    collegePersistence.moveVaultDocument(doc, toFolderID: destination.id)
                }
                .disabled(doc.parentFolderID == destination.id)
            }
        }
        Menu("Link to Course") {
            if let linked = doc.courseCodeLinked?.trimmingCharacters(in: .whitespacesAndNewlines),
               !linked.isEmpty {
                Button("Remove Link (\(linked))") {
                    collegePersistence.setVaultDocumentCourseLink(doc, courseCode: nil)
                }
            }
            ForEach(Array(availableCourseCodes.prefix(30)), id: \.self) { code in
                Button(code) {
                    collegePersistence.setVaultDocumentCourseLink(doc, courseCode: code)
                }
            }
        }
        Divider()
        Button("Delete File", role: .destructive) {
            VaultDocumentAccess.delete(id: doc.id, collegePersistence: collegePersistence)
        }
    }

    private var vaultDocumentsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148, maximum: 188), spacing: 12)],
                spacing: 12
            ) {
                ForEach(visibleVaultDocuments, id: \.id) { doc in
                    VaultDocumentGridCell(doc: doc, isSelected: selectedDocumentIDs.contains(doc.id))
                        .scrollTransition(.animated(.spring(response: 0.34, dampingFraction: 0.88))) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0)
                                .scaleEffect(phase.isIdentity ? 1 : 0.90)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDocumentIDs = [doc.id]
                        }
                        .contextMenu {
                            vaultDocumentContextMenu(for: doc)
                        }
                        .draggable(dragPayload(for: doc))
                        .onTapGesture(count: 2) {
                            openVaultDocument(doc)
                        }
                }
            }
            .padding(16)
            .sensoryFeedback(.selection, trigger: selectedDocumentIDs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicatorsFlash(trigger: selectedSidebarItem)
    }

    // MARK: – Grouped "All Files" view

    /// Renders documents grouped by folder using collapsible List Sections.
    /// Shown instead of the flat Table/Grid when All Files has 2+ groups (at least one folder).
    // MARK: - Finder-style outline table

    /// Native macOS outline table — folders expand with disclosure triangles, Finder columns.
    private var finderStyleTable: some View {
        Table(of: VaultTreeItem.self, selection: $selectedDocumentIDs) {
            TableColumn("Name") { item in
                finderNameCell(item: item)
                    .contentShape(Rectangle())
                    .contextMenu { vaultDocumentContextMenu(for: item.entity) }
                    .draggable(dragPayload(for: item.entity))
                    .onTapGesture(count: 2) {
                        if item.isFolder {
                            let name = item.entity.fileName
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            selectedSidebarItem = .folder(item.entity.id, name.isEmpty ? "Folder" : name)
                        } else {
                            openVaultDocument(item.entity)
                        }
                    }
            }
            .width(min: 200, ideal: 360)

            TableColumn("Date Modified") { item in
                Text(item.dateModifiedString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 110, ideal: 160, max: 210)

            TableColumn("Size") { item in
                Text(item.sizeString)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80, max: 110)

            TableColumn("Kind") { item in
                Text(item.kind)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 150, max: 230)
        } rows: {
            OutlineGroup(finderRootItems, id: \.id, children: \.children) { item in
                TableRow(item)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first,
               let doc = vaultDocuments.first(where: { $0.id == id }) {
                vaultDocumentContextMenu(for: doc)
            }
        }
    }

    private func finderNameCell(item: VaultTreeItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.sfSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(item.iconColor)
                .frame(width: 20, alignment: .center)
                .symbolRenderingMode(.hierarchical)

            Text(item.name)
                .font(.system(size: 13, weight: item.isFolder ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let linked = item.entity.courseCodeLinked?.trimmingCharacters(in: .whitespacesAndNewlines),
               !linked.isEmpty, !item.isFolder {
                Text(linked)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.vertical, 1)
    }

    private var filesListSection: some View {
        VStack(spacing: 0) {
            if let err = lastUploadError {
                DashboardErrorHint(
                    title: String(localized: "documents.upload.error_title"),
                    message: err,
                    onDismiss: { lastUploadError = nil }
                )
                .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ZStack {
                    if finderRootItems.isEmpty {
                        documentsEmptyStateSection
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.98))
                            ))
                    } else {
                        Group {
                            if vaultItemsLayout == .list {
                                if canRenderFinderTable {
                                    finderStyleTable
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                }
                            } else {
                                vaultDocumentsGrid
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        ))
                        .focusable()
                        .onKeyPress(.space) {
                            guard let selectedDocumentID = selectedDocumentIDs.first,
                                  let doc = vaultDocuments.first(where: { $0.id == selectedDocumentID }) else {
                                return .ignored
                            }
                            quickLookVaultDocument(doc)
                            return .handled
                        }
                        .onKeyPress(.delete) {
                            guard !selectedDocuments.isEmpty else { return .ignored }
                            isDeleteFilesDialogPresented = true
                            return .handled
                        }
                        .dropDestination(for: URL.self, isEnabled: true) { droppedURLs, _ in
                            Task { @MainActor in
                                await importURLs(droppedURLs)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .animation(motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.30, dampingFraction: 0.88), value: visibleVaultDocuments.isEmpty)
                .animation(motionReduced ? .easeOut(duration: 0.12) : .spring(response: 0.30, dampingFraction: 0.88), value: vaultItemsLayout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack(spacing: 0) {
                    Text(vaultFooterStatusLine)
                        .contentTransition(motionReduced ? .opacity : .numericText(value: Double(visibleVaultDocuments.count)))
                        .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: visibleVaultDocuments.count)
                        .foregroundStyle(.secondary)
                    if let last = lastVaultMetricsRefresh {
                        Text(" · Updated \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date()))")
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(documentsListChromeFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var documentsListChromeFill: Color {
        Color(nsColor: .textBackgroundColor).opacity(0.65)
    }

    private var documentsEmptyStateSection: some View {
        DashboardEmptyHint(
            title: emptyStateTitle,
            message: emptyStateMessage,
            systemImage: "doc.badge.plus"
        )
        .frame(maxWidth: 520)
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Button("Import from Mac…") {
                    showUploadPicker = true
                }
                .disabled(isUploading)

                Button("Import from Integration…") {
                    pickFilesFromIntegration(provider: nil)
                }
                .disabled(isUploading)
            }
            .buttonStyle(.borderless)
            .offset(y: 28)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var fileTypeCountsRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                Text("\(vaultMetrics.pdfCount)")
                    .contentTransition(motionReduced ? .opacity : .numericText(value: Double(vaultMetrics.pdfCount)))
                    .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: vaultMetrics.pdfCount)
                Text("PDFs")
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "tablecells.fill")
                Text("\(vaultMetrics.sheetCount)")
                    .contentTransition(motionReduced ? .opacity : .numericText(value: Double(vaultMetrics.sheetCount)))
                    .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: vaultMetrics.sheetCount)
                Text("Sheets")
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("\(vaultMetrics.scriptCount)")
                    .contentTransition(motionReduced ? .opacity : .numericText(value: Double(vaultMetrics.scriptCount)))
                    .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: vaultMetrics.scriptCount)
                Text("Scripts")
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    private var vaultToolbarRow: some View {
        ViewThatFits(in: .horizontal) {
            vaultToolbarWide
            vaultToolbarCompact
        }
    }

    private var vaultSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(String(localized: "documents.search.placeholder", defaultValue: "Search local vault"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var vaultFileTypePicker: some View {
        Picker("File Type", selection: $selectedFilter) {
            ForEach(VaultFileFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    private var vaultStorageLabel: some View {
        Text(ByteCountFormatter.string(fromByteCount: vaultMetrics.totalBytes, countStyle: .file))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var vaultLayoutModeControl: some View {
        HStack(spacing: 0) {
            ForEach(VaultItemsLayout.allCases) { mode in
                Button {
                    withAnimation(motionReduced ? .easeOut(duration: 0.10) : .spring(response: 0.26, dampingFraction: 0.82)) {
                        vaultItemsLayout = mode
                    }
                } label: {
                    Image(systemName: mode == .list ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(vaultItemsLayout == mode ? Color.accentColor : .secondary)
                        .frame(width: 30, height: 28)
                        .symbolEffect(.bounce, value: vaultItemsLayout)
                }
                .buttonStyle(.plain)
                .help(
                    mode == .list
                        ? String(localized: "documents.toolbar.list_help", defaultValue: "List view")
                        : String(localized: "documents.toolbar.grid_help", defaultValue: "Grid view")
                )
            }
        }
        .padding(.horizontal, 2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel(String(localized: "documents.toolbar.layout_a11y", defaultValue: "File layout"))
    }

    private var vaultFilterMenu: some View {
        Menu {
            Button {
                selectedFilter = .all
                searchText = ""
            } label: {
                Label(
                    String(localized: "documents.toolbar.reset_filters", defaultValue: "Reset filters"),
                    systemImage: "arrow.counterclockwise"
                )
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .help(String(localized: "documents.toolbar.filter_help", defaultValue: "Filter options"))
    }

    private var vaultToolbarWide: some View {
        HStack(alignment: .center, spacing: 10) {
            vaultSearchField
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)

            vaultFileTypePicker
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 320)

            Divider()
                .frame(height: 18)

            vaultActionsMenu
            vaultImportMenu

            Spacer(minLength: 4)

            vaultStorageLabel

            vaultLayoutModeControl

            vaultFilterMenu
        }
    }

    private var vaultToolbarCompact: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                vaultSearchField
                vaultActionsMenu
                vaultImportMenu
                vaultLayoutModeControl
                vaultFilterMenu
            }
            HStack(spacing: 10) {
                vaultFileTypePicker
                    .frame(maxWidth: .infinity)
                vaultStorageLabel
            }
        }
    }
}

// MARK: - Components

struct MetricCard: View {
    let title: String
    let count: String
    let icon: String
    let iconColor: Color
    let iconBg: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBg)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.5)
                Text(count)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(24)
        .frame(width: 140, alignment: .leading)
        .background(metricCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    private var metricCardFill: Color {
        DesignSystem.Colors.glassCardBase
    }
}

struct StorageHealthCard: View {
    let totalBytes: Int64
    let fileCount: Int

    private var formattedUsed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    private var filesInVaultLine: String {
        if fileCount == 1 {
            return String(localized: "documents.storage.files_one")
        }
        return String(format: String(localized: "documents.storage.files_many"), fileCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "documents.storage.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(formattedUsed)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text(filesInVaultLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 280, alignment: .leading)
        .background(storageCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }

    private var storageCardFill: Color {
        DesignSystem.Colors.glassCardBase
    }
}

// MARK: - Vault table helpers

private struct VaultDocumentPresentation {
    let doc: VaultDocument

    var fileName: String {
        let custom = doc.customDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        if doc.fileName.isEmpty {
            return String(localized: "documents.unknown_file")
        }
        return doc.fileName
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    var iconKind: String {
        switch fileExtension {
        case "pdf": return "pdf"
        case "xlsx", "xls", "csv", "numbers": return "sheet"
        case "js", "py", "swift", "sh", "html": return "script"
        default: return "other"
        }
    }

    var iconBg: Color {
        switch iconKind {
        case "pdf": return Color.red.opacity(0.10)
        case "sheet": return Color.green.opacity(0.10)
        case "script": return Color.purple.opacity(0.10)
        default: return Color.primary.opacity(0.08)
        }
    }

    var iconImgColor: Color {
        switch iconKind {
        case "pdf": return .red
        case "sheet": return .green
        case "script": return .purple
        default: return .secondary
        }
    }

    var categoryText: String {
        doc.category.isEmpty ? "UNCATEGORIZED" : doc.category.uppercased()
    }

    var catText: Color {
        switch iconKind {
        case "pdf": return .accentColor
        case "sheet": return .green
        case "script": return .purple
        default: return .secondary
        }
    }

    var catBg: Color {
        switch iconKind {
        case "pdf": return Color.accentColor.opacity(0.10)
        case "sheet": return Color.green.opacity(0.10)
        case "script": return Color.purple.opacity(0.10)
        default: return Color.primary.opacity(0.08)
        }
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: doc.addedAt)
    }

    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: doc.fileSizeBytes)
    }
}

private struct VaultDocumentGridCell: View {
    let doc: VaultDocument
    let isSelected: Bool

    @State private var isHovered = false
    @GestureState private var isPressed = false

    private var cellBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if isHovered { return Color.primary.opacity(0.07) }
        return Color.primary.opacity(0.04)
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor.opacity(0.42) }
        if isHovered { return Color.primary.opacity(0.14) }
        return Color.primary.opacity(0.06)
    }

    private var cellScale: CGFloat {
        if isPressed { return 0.97 }
        if isHovered { return 1.025 }
        return 1.0
    }

    var body: some View {
        let p = VaultDocumentPresentation(doc: doc)
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(p.iconBg)
                    .frame(width: 44, height: 44)
                if p.iconKind == "pdf" {
                    Text("PDF")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(p.iconImgColor)
                } else if p.iconKind == "sheet" {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 20))
                        .foregroundStyle(p.iconImgColor)
                } else if p.iconKind == "script" {
                    Text(String(p.fileExtension.uppercased().prefix(2)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(p.iconImgColor)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 20))
                        .foregroundStyle(p.iconImgColor)
                }
            }

            Text(p.fileName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(p.sizeString)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .top)
        .background(cellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .scaleEffect(cellScale)
        .shadow(color: isHovered && !isPressed ? Color.black.opacity(0.10) : .clear, radius: 6, y: 3)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.10, dampingFraction: 0.72), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct VaultDocumentFileTableCell: View {
    let doc: VaultDocument

    var body: some View {
        let p = VaultDocumentPresentation(doc: doc)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(p.iconBg)
                    .frame(width: 36, height: 36)
                if p.iconKind == "pdf" {
                    Text("PDF")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(p.iconImgColor)
                } else if p.iconKind == "sheet" {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 16))
                        .foregroundStyle(p.iconImgColor)
                } else if p.iconKind == "script" {
                    Text(String(p.fileExtension.uppercased().prefix(2)))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(p.iconImgColor)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 16))
                        .foregroundStyle(p.iconImgColor)
                }
            }
            Text(p.fileName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let linked = doc.courseCodeLinked?.trimmingCharacters(in: .whitespacesAndNewlines),
               !linked.isEmpty {
                Text(linked)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SidebarRowButtonLabel: View {
    let systemImage: String
    let title: String
    let isSelected: Bool
    let count: Int
    let motionReduced: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(motionReduced ? .opacity : .numericText(value: Double(count)))
                    .animation(motionReduced ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.22), value: count)
            }
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : isHovered ? Color.primary.opacity(0.055) : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(motionReduced ? .easeOut(duration: 0.08) : .easeOut(duration: 0.14), value: isSelected)
            .animation(motionReduced ? nil : .easeOut(duration: 0.10), value: isHovered)
        }
        .buttonStyle(PressableCardStyle(reduceMotion: motionReduced))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct VaultDocumentCategoryTableCell: View {
    let doc: VaultDocument

    var body: some View {
        let p = VaultDocumentPresentation(doc: doc)
        Text(p.categoryText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(p.catText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(p.catBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

@MainActor
final class VaultQuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    static let shared = VaultQuickLookPresenter()

    private var previewURLs: [URL] = []

    func present(url: URL) {
        previewURLs = [url]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> (any QLPreviewItem)? {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}

enum DocumentsFeaturePreloadRegistration {
    @MainActor
    static func register() {
        LaunchPreloadCoordinator.registerFeaturePreload(
            .init(
                id: "documents",
                title: "Document vault",
                criticality: .requiredBeforeReady,
                timeoutSeconds: 1.2,
                retryLimit: 1,
                run: { context, onProgress, _ in
                    LaunchBootstrapCache.fetchVaultDocumentsIfNeeded()
                    onProgress(1)
                }
            )
        )
    }
}
