import Foundation
import CoreData
import Combine
import CryptoKit
import os

class CoreDataManager: ObservableObject {
    /// Shared app instance (kept for compatibility with existing call sites).
    ///
    /// Modernized stack configuration lives in `PersistenceController`.
    @MainActor static let shared = CoreDataManager(persistence: .shared)

    private struct RegexKey: Hashable {
        let pattern: String
        let options: NSRegularExpression.Options.RawValue
    }

    nonisolated(unsafe) private static var regexCache: [RegexKey: NSRegularExpression] = [:]
    private static let regexCacheLock = NSLock()

    /// Session-level cache for the `bestByCode` map built from DegreeRequirementEntity rows.
    /// Keyed by university NSManagedObjectID; invalidated when the catalog is reimported.
    /// Access must occur on the viewContext queue (main thread).
    private var requirementBackfillCache: [NSManagedObjectID: [String: RequirementCourseInfo]] = [:]

    private static func cachedRegex(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        let key = RegexKey(pattern: pattern, options: options.rawValue)
        regexCacheLock.lock()
        if let cached = regexCache[key] {
            regexCacheLock.unlock()
            return cached
        }
        regexCacheLock.unlock()

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        regexCacheLock.lock()
        regexCache[key] = regex
        regexCacheLock.unlock()
        return regex
    }
    
    let container: NSPersistentContainer
    /// Mirrors `PersistenceController.isStoreLoaded`; `true` once the SQLite store is open.
    @Published private(set) var isStoreLoaded: Bool = false
    private var cancellables = Set<AnyCancellable>()

    @Published var semesters: [SemesterEntity] = []
    @Published var plans: [PlanEntity] = []
    @Published var profile: ProfileEntity?

    /// Tracks the plan currently selected in the UI (Semester Planner).
    /// Used by global flows like Edit Course Details to know which plan to modify.
    @Published var activePlanObjectID: NSManagedObjectID? = nil

    // MARK: - Document Vault
    @Published var vaultDocuments: [VaultDocumentEntity] = []
    
    // MARK: - Calendar (Tasks + One-off Events)
    @Published var calendarSelectedSemesterID: UUID? = nil
    
    /// Calendar-scoped change token so Calendar UI can refresh without reacting to unrelated Core Data changes.
    @Published private(set) var calendarDidChangeToken: Int = 0
    /// Incremented whenever a course's completion status changes so the audit panel can reload.
    @Published private(set) var plannerChangeToken: Int = 0

    #if DEBUG
    /// Lightweight in-app debug status that we can surface in the UI when the Xcode console isn't visible.
    @Published var debugStatus: String = ""

    /// Debug counters that query Core Data directly (not via possibly-faulted relationships).
    @Published var debugProfileCount: Int = 0
    @Published var debugExperienceCount: Int = 0
    @Published var debugAchievementCount: Int = 0
    @Published var debugActiveProfileID: String = ""

    func setDebugStatus(_ message: String) {
        debugStatus = message
        print("[DebugStatus] \(message)")
    }

    private func refreshDebugCounts() {
        let context = viewContext

        do {
            let profileRequest = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
            debugProfileCount = try context.count(for: profileRequest)
        } catch {
            debugProfileCount = -1
        }

        do {
            let experienceRequest = NSFetchRequest<ExperienceEntity>(entityName: "ExperienceEntity")
            debugExperienceCount = try context.count(for: experienceRequest)
        } catch {
            debugExperienceCount = -1
        }

        do {
            let achievementRequest = NSFetchRequest<AchievementEntity>(entityName: "AchievementEntity")
            debugAchievementCount = try context.count(for: achievementRequest)
        } catch {
            debugAchievementCount = -1
        }

        if let id = profile?.id {
            debugActiveProfileID = id.uuidString
        } else {
            debugActiveProfileID = "nil"
        }
    }
    #endif

    // MARK: - Option C: Multi-department display helpers

    /// Returns the `DepartmentEntity.school` value for a given university + department name.
    ///
    /// This is used to keep UI subtitles (e.g., "College Req.") dynamic without hardcoding.
    /// The lookup is resilient to common catalog naming differences like:
    /// - "Department of X" vs "X"
    /// - punctuation and "&" vs "and"
    func schoolForDepartment(universityName: String, departmentName: String) -> String? {
        let u = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = departmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !d.isEmpty else { return nil }

        func normalize(_ value: String) -> String {
            var s = value.normalizedCatalogText().lowercased()

            if s.hasPrefix("department of ") {
                s = String(s.dropFirst("department of ".count))
            }
            let removeList = [" department page", " department", " program", " office", " page"]
            for term in removeList {
                if s.hasSuffix(term) { s = String(s.dropLast(term.count)) }
            }

            s = s.replacingOccurrences(of: "&", with: "and")
            // Use static regex for non-alphanumeric stripping
            if let re = Self.nonAlphanumericRegex {
                s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
            }
            return s.normalizedCatalogText()
        }

        let normalizedInput = normalize(d)
        let request = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        request.predicate = NSPredicate(format: "university.name == %@", u)
        let all = (try? viewContext.fetch(request)) ?? []

        // Prefer exact/close matches with a non-empty school value.
        let matches = all.filter { dept in
            guard let name = dept.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return false }
            let normalizedName = normalize(name)
            return normalizedName == normalizedInput ||
                normalizedName.contains(normalizedInput) ||
                normalizedInput.contains(normalizedName)
        }

        let best = matches.first { dept in
            let school = (dept.school ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !school.isEmpty
        } ?? matches.first

        let school = (best?.school ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return school.isEmpty ? nil : school
    }

    /// Deterministic list of linked department names for a major.
    /// Sorted case-insensitively for stable UI output and predictable "primary" selection.
    func majorDepartmentNames(_ major: MajorEntity) -> [String] {
        let set = (major.departments as? Set<DepartmentEntity>) ?? []
        return set
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Returns a compact, user-facing department display string for a major/program.
    ///
    /// Option C behavior:
    /// - No linked departments → fall back to `resolvedDepartment` (if present) else nil
    /// - One linked department → that department name
    /// - Multiple linked departments → "<primary> (+N)" where primary is alphabetically-first
    func majorDepartmentDisplayText(_ major: MajorEntity) -> String? {
        let names = majorDepartmentNames(major)
        if names.isEmpty {
            let fallback = major.resolvedDepartment?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (fallback?.isEmpty == false) ? fallback : nil
        }
        if names.count == 1 {
            return names[0]
        }
        let primary = names[0]
        let extra = names.count - 1
        return "\(primary) (+\(extra))"
    }
    
    private init(persistence: PersistenceController) {
        container = persistence.container

        // The store loads asynchronously; defer all fetches until it is ready.
        // `CurrentValueSubject` emits its current value immediately on subscription, so this fires
        // at once if the store is already open (e.g., the in-memory preview path).
        persistence.storeLoadPublisher
            .filter { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                #if DEBUG
                if let store = self.container.persistentStoreCoordinator.persistentStores.first,
                   let url = store.url {
                    print("[CoreData] Persistent store: \(url.path)")
                } else {
                    print("[CoreData] Persistent store: <unknown>")
                }
                #endif
                self.fetchSemesters()
                self.fetchPlans()
                self.fetchProfile()
                self.fetchVaultDocuments()
                self.isStoreLoaded = true
            }
            .store(in: &cancellables)
    }

    /// Test-only initializer that allows an in-memory (or otherwise injected) container.
    ///
    /// By default, this skips app bootstrap fetches/creation (like default Profile) to avoid
    /// side-effects and crashes in unit tests.
    internal init(testContainer: NSPersistentContainer, skipBootstrapFetches: Bool = true) {
        container = testContainer
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil

        if !skipBootstrapFetches {
            fetchSemesters()
            fetchPlans()
            fetchProfile()
            fetchVaultDocuments()
        }
    }

    // MARK: - Bootstrap

    /// Loads the initial set of @Published data from Core Data.
    /// Called from `CollegeApp.onAppear` after the persistent store is ready,
    /// and also internally from the store-loaded Combine subscription in `init`.
    func loadInitialData() async {
        fetchSemesters()
        fetchPlans()
        fetchProfile()
        fetchVaultDocuments()
    }

    // MARK: - Document Vault
    enum VaultDocumentCategory: String {
        case syllabi = "Syllabi"
        case transcripts = "Transcripts"
        case calendar = "Calendar"
        case other = "Other"
    }

    func fetchVaultDocuments() {
        let request = NSFetchRequest<VaultDocumentEntity>(entityName: "VaultDocumentEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: false)]
        request.fetchBatchSize = 200
        request.returnsObjectsAsFaults = true

        do {
            vaultDocuments = try viewContext.fetch(request)
        } catch {
            vaultDocuments = []

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Load Failed",
                    message: "Could not load Document Vault items.",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
        }
    }

    private func documentVaultDirectoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("College/DocumentVault", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func decryptedVaultTempDirectoryURL() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("College-DecryptedVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // The metadata-aware overload below (addVaultDocument(fromSelectedURL:category:source:metadata:))
    // handles all vault uploads. Keep both sync and async entry points for compatibility
    // with restored call sites that are not yet async.
    @MainActor
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault"
    ) throws {
        try addVaultDocumentSync(fromSelectedURL: url, category: category, source: source, metadata: nil, parentFolderID: nil)
    }

    @MainActor
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault"
    ) async throws {
        try addVaultDocumentSync(fromSelectedURL: url, category: category, source: source, metadata: nil, parentFolderID: nil)
    }

    func urlForVaultDocument(_ doc: VaultDocumentEntity) -> URL? {
        guard let rel = doc.localRelativePath, !rel.isEmpty else { return nil }
        do {
            let dir = try documentVaultDirectoryURL()
            return dir.appendingPathComponent(rel)
        } catch {
            return nil
        }
    }

    /// Returns a temporary decrypted file URL suitable for Quick Look / export.
    /// The caller should delete the returned file when done.
    @MainActor
    func decryptedTempURLForVaultDocument(_ doc: VaultDocumentEntity) -> URL? {
        decryptedTempURLForVaultDocumentSync(doc)
    }

    @MainActor
    private func decryptedTempURLForVaultDocumentSync(_ doc: VaultDocumentEntity) -> URL? {
        guard let storedURL = urlForVaultDocument(doc) else { return nil }
        let stored: Data
        do {
            stored = try Data(contentsOf: storedURL)
        } catch {
            return nil
        }

        // If it isn't encrypted (older data), return the stored URL directly.
        guard BlobCrypto.isEncryptedBlob(stored) else { return storedURL }

        guard let plaintext = SecurityManager.shared.decryptBlobFromStorage(stored) else { return nil }
        let tempDir = decryptedVaultTempDirectoryURL()
        let name = (doc.fileName?.isEmpty == false) ? (doc.fileName ?? "Document") : "Document"
        let tempURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            try plaintext.write(to: tempURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
            return tempURL
        } catch {
            return nil
        }
    }

    /// Async compatibility wrapper for newer call sites.
    @MainActor
    func decryptedTempURLForVaultDocument(_ doc: VaultDocumentEntity) async -> URL? {
        decryptedTempURLForVaultDocumentSync(doc)
    }

    func deleteVaultDocument(_ doc: VaultDocumentEntity) {
        if let url = urlForVaultDocument(doc) {
            try? FileManager.default.removeItem(at: url)
        }

        viewContext.delete(doc)
        save()
        fetchVaultDocuments()
    }

    // MARK: - Vault: Rename / Custom display name

    func renameVaultDocument(_ doc: VaultDocumentEntity, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        doc.customDisplayName = trimmed
        save()
        fetchVaultDocuments()
    }

    // MARK: - Vault: Tags  (stored as comma-separated string)

    func updateVaultDocumentTags(_ doc: VaultDocumentEntity, tags: [String]) {
        doc.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        save()
        fetchVaultDocuments()
    }

    func vaultDocumentTags(_ doc: VaultDocumentEntity) -> [String] {
        guard let raw = doc.tags, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    // MARK: - Vault: Color label

    func updateVaultDocumentColorLabel(_ doc: VaultDocumentEntity, label: String) {
        doc.colorLabel = label
        save()
        fetchVaultDocuments()
    }

    // MARK: - Vault: Favorites

    func toggleVaultDocumentFavorite(_ doc: VaultDocumentEntity) {
        doc.isFavorite = !doc.isFavorite
        save()
        fetchVaultDocuments()
    }

    func setVaultDocumentFavorite(_ doc: VaultDocumentEntity, isFavorite: Bool) {
        doc.isFavorite = isFavorite
        save()
        fetchVaultDocuments()
    }

    // MARK: - Vault: Notes

    func updateVaultDocumentNotes(_ doc: VaultDocumentEntity, notes: String) {
        doc.userNotes = notes
        save()
    }

    // MARK: - Vault: Track open

    func markVaultDocumentOpened(_ doc: VaultDocumentEntity) {
        doc.lastOpenedAt = Date()
        save()
    }

    // MARK: - Vault: Save annotated PDF data back to vault

    @MainActor
    func saveAnnotatedVaultDocument(_ doc: VaultDocumentEntity, data: Data) {
        guard let url = urlForVaultDocument(doc) else { return }
        let stored = SecurityManager.shared.encryptBlobForStorage(data) ?? data
        do {
            try stored.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            doc.fileSizeBytes = Int64(data.count)
            save()
        } catch {
            // Annotation save failed silently; existing file is unchanged.
        }
    }

    // MARK: - Vault: Upload with full metadata

    @MainActor
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault",
        metadata: VaultUploadMetadata? = nil,
        parentFolderID: UUID? = nil
    ) throws {
        try addVaultDocumentSync(
            fromSelectedURL: url,
            category: category,
            source: source,
            metadata: metadata,
            parentFolderID: parentFolderID
        )
    }

    @MainActor
    private func addVaultDocumentSync(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory,
        source: String,
        metadata: VaultUploadMetadata?,
        parentFolderID: UUID?
    ) throws {
        let fileName = url.lastPathComponent
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        let vaultDir = try documentVaultDirectoryURL()
        let id = UUID()
        let storedFileName = "\(id.uuidString)-\(fileName).colenc"
        let destination = vaultDir.appendingPathComponent(storedFileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let plaintext = try Data(contentsOf: url)
        let stored = SecurityManager.shared.encryptBlobForStorage(plaintext) ?? plaintext
        try stored.write(to: destination, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        let entity = VaultDocumentEntity(context: viewContext)
        entity.id                = id
        entity.fileName          = fileName
        entity.fileSizeBytes     = fileSize
        entity.addedAt           = Date()
        entity.localRelativePath = storedFileName
        entity.source            = source
        entity.parentFolderID    = parentFolderID

        if let meta = metadata {
            let cat: VaultDocumentCategory
            switch meta.category {
            case .syllabi:     cat = .syllabi
            case .transcripts: cat = .transcripts
            case .calendar:    cat = .calendar
            case .other:       cat = .other
            }
            entity.category          = cat.rawValue
            entity.customDisplayName = meta.customDisplayName.isEmpty ? nil : meta.customDisplayName
            entity.tags              = meta.tags.isEmpty ? nil : meta.tags.joined(separator: ",")
            entity.colorLabel        = meta.colorLabel == .none ? nil : meta.colorLabel.rawValue
            entity.userNotes         = meta.notes.isEmpty ? nil : meta.notes
        } else {
            entity.category = category.rawValue
        }

        save()
        fetchVaultDocuments()
    }

    @MainActor
    func addVaultDocument(
        fromSelectedURL url: URL,
        category: VaultDocumentCategory = .other,
        source: String = "vault",
        metadata: VaultUploadMetadata? = nil,
        parentFolderID: UUID? = nil
    ) async throws {
        try addVaultDocumentSync(
            fromSelectedURL: url,
            category: category,
            source: source,
            metadata: metadata,
            parentFolderID: parentFolderID
        )
    }

    // MARK: - Vault folder compatibility helpers

    func fetchRootVaultFolders() -> [VaultDocumentEntity] {
        vaultDocuments
            .filter { $0.isFolder && $0.parentFolderID == nil }
            .sorted {
                let lhs = ($0.fileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rhs = ($1.fileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    @discardableResult
    func createVaultFolder(name: String, parentFolderID: UUID?) -> VaultDocumentEntity? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let folder = VaultDocumentEntity(context: viewContext)
        folder.id = UUID()
        folder.fileName = trimmed
        folder.category = VaultDocumentCategory.other.rawValue
        folder.addedAt = Date()
        folder.fileSizeBytes = 0
        folder.localRelativePath = ""
        folder.source = "vault"
        folder.isFolder = true
        folder.parentFolderID = parentFolderID

        save()
        fetchVaultDocuments()
        return folder
    }

    func renameVaultFolder(_ folder: VaultDocumentEntity, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.fileName = trimmed
        save()
        fetchVaultDocuments()
    }

    func deleteVaultFolder(_ folder: VaultDocumentEntity, includeContents: Bool) {
        guard folder.isFolder else { return }

        let folderID = folder.id
        if includeContents, let folderID {
            var queue: [UUID] = [folderID]
            while let current = queue.popLast() {
                let children = vaultDocuments.filter { $0.parentFolderID == current }
                for child in children {
                    if child.isFolder, let childID = child.id {
                        queue.append(childID)
                    }
                    if let url = urlForVaultDocument(child), !child.isFolder {
                        try? FileManager.default.removeItem(at: url)
                    }
                    viewContext.delete(child)
                }
            }
        } else if let folderID {
            let children = vaultDocuments.filter { $0.parentFolderID == folderID }
            for child in children {
                child.parentFolderID = folder.parentFolderID
            }
        }

        viewContext.delete(folder)
        save()
        fetchVaultDocuments()
    }

    func moveVaultDocument(_ doc: VaultDocumentEntity, toFolderID folderID: UUID?) {
        doc.parentFolderID = folderID
        save()
        fetchVaultDocuments()
    }

    func setVaultDocumentCourseLink(_ doc: VaultDocumentEntity, courseCode: String?) {
        let normalized = courseCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
        doc.courseCodeLinked = (normalized?.isEmpty == false) ? normalized : nil
        save()
        fetchVaultDocuments()
    }

    // MARK: - Vault: Bulk delete

    func bulkDeleteVaultDocuments(_ docs: [VaultDocumentEntity]) {
        for doc in docs {
            if let url = urlForVaultDocument(doc) {
                try? FileManager.default.removeItem(at: url)
            }
            viewContext.delete(doc)
        }
        save()
        fetchVaultDocuments()
    }

    // MARK: - Vault: Intelligence metadata

    func updateVaultDocumentSummary(_ doc: VaultDocumentEntity, summary: String) {
        doc.summaryText = summary
        if (doc.userNotes ?? "").isEmpty {
            doc.userNotes = "[AI Summary]\n\(summary)"
        } else if !(doc.userNotes ?? "").contains("[AI Summary]") {
            doc.userNotes = (doc.userNotes ?? "") + "\n\n[AI Summary]\n\(summary)"
        }
        save()
    }

    func linkVaultDocument(_ doc: VaultDocumentEntity, toTask taskID: UUID) {
        doc.linkedTaskID = taskID
        save()
    }

    func updateReadingProgress(_ doc: VaultDocumentEntity, page: Int, totalPages: Int) {
        doc.readingProgress = Int16(max(0, page))
        doc.readingTotalPages = Int16(max(0, totalPages))
        save()
    }

    func markVaultDocumentNeedsReview(_ doc: VaultDocumentEntity, courseCode: String?, confidence: Float) {
        doc.needsReview = true
        doc.courseCodeLinked = courseCode
        doc.classificationConfidence = confidence
        save()
    }

    func confirmVaultDocumentReview(_ doc: VaultDocumentEntity, courseCode: String?, category: VaultDocumentCategory) {
        doc.needsReview = false
        doc.courseCodeLinked = courseCode
        doc.category = category.rawValue
        doc.classificationConfidence = 1.0
        save()
    }

    // MARK: - Vault: WatchedFolder CRUD

    func fetchWatchedFolders() -> [WatchedFolderEntity] {
        let request = NSFetchRequest<WatchedFolderEntity>(entityName: "WatchedFolderEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "addedAt", ascending: true)]
        return (try? viewContext.fetch(request)) ?? []
    }

    @discardableResult
    func addWatchedFolder(path: String, bookmarkData: Data? = nil) -> WatchedFolderEntity {
        let entity = WatchedFolderEntity(context: viewContext)
        entity.id = UUID()
        entity.path = path
        entity.isEnabled = true
        entity.addedAt = Date()
        entity.bookmarkData = bookmarkData
        save()
        return entity
    }

    func removeWatchedFolder(id: UUID) {
        let request = NSFetchRequest<WatchedFolderEntity>(entityName: "WatchedFolderEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? viewContext.fetch(request).first {
            viewContext.delete(entity)
            save()
        }
    }

    func toggleWatchedFolder(_ entity: WatchedFolderEntity) {
        entity.isEnabled.toggle()
        save()
    }

    // MARK: - Calendar Course Linking Helpers

    /// All calendar events that have not yet been assigned to a CourseEntity.
    func fetchUnlinkedCalendarEvents() -> [CalendarEventEntity] {
        let req = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
        // Limit scope to events within the past 2 years to avoid full-table scan.
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        req.predicate = NSPredicate(format: "course == nil AND startDate >= %@", twoYearsAgo as NSDate)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \CalendarEventEntity.startDate, ascending: true)]
        req.fetchBatchSize = 200
        return (try? viewContext.fetch(req)) ?? []
    }

    /// Scans every semester for courses that share the same base code (e.g. "CSE191" and
    /// Removes all CourseEntity records whose code matches `code` (or shares a base prefix),
    /// unlinking any associated CalendarEventEntities first. Used when the user deletes a
    /// course calendar entry from the sidebar.
    func removeAutoLinkedCourse(code: String) {
        let upperCode = code.uppercased()
        let req = NSFetchRequest<CourseEntity>(entityName: "CourseEntity")
        let all = (try? viewContext.fetch(req)) ?? []
        let toDelete = all.filter { c in
            let c2 = (c.code ?? "").uppercased()
            return c2 == upperCode || c2.hasPrefix(upperCode) || upperCode.hasPrefix(c2)
        }
        for course in toDelete {
            if let events = course.calendarEvents?.allObjects as? [CalendarEventEntity] {
                for event in events { event.course = nil }
            }
            viewContext.delete(course)
        }
        if !toDelete.isEmpty { try? viewContext.save() }
    }

    /// "CSE191LR") and merges duplicates into the single authoritative entry.
    /// The "winner" is chosen by: has catalogCourse > has a non-code name > was not autoLinked.
    /// All CalendarEventEntity links and the `autoLinked` flag are re-pointed to the winner
    /// before the losers are deleted. Safe to call repeatedly (idempotent).
    func mergeCourseDuplicates() {
        let semReq = NSFetchRequest<SemesterEntity>(entityName: "SemesterEntity")
        let semesters = (try? viewContext.fetch(semReq)) ?? []

        var didChange = false

        for semester in semesters {
            guard let courses = semester.courses?.allObjects as? [CourseEntity] else { continue }

            // Group by base code: strip trailing non-digit characters then uppercase.
            var groups: [String: [CourseEntity]] = [:]
            for course in courses {
                let base = baseCode(for: course.code ?? "")
                groups[base, default: []].append(course)
            }

            for (_, group) in groups where group.count > 1 {
                // Pick the best course: prefer catalog link, then non-auto-linked, then longest name.
                let winner = group.sorted { a, b in
                    if (a.catalogCourse != nil) != (b.catalogCourse != nil) {
                        return a.catalogCourse != nil
                    }
                    if a.autoLinked != b.autoLinked { return !a.autoLinked }
                    return (a.name ?? "").count > (b.name ?? "").count
                }.first!

                for loser in group where loser.objectID != winner.objectID {
                    // Re-point all linked events to the winner.
                    if let events = loser.calendarEvents?.allObjects as? [CalendarEventEntity] {
                        for event in events { event.course = winner }
                    }
                    // Inherit autoLinked=false if any entry was manually added.
                    if !loser.autoLinked { winner.autoLinked = false }
                    viewContext.delete(loser)
                    didChange = true
                }
            }
        }

        if didChange {
            try? viewContext.save()
        }
    }

    /// Strips the alphabetic section suffix from a course code and returns an uppercase
    /// base code. E.g. "CSE191LR" → "CSE191", "CSE 191LEC" → "CSE191", "MGS405" → "MGS405".
    private func baseCode(for code: String) -> String {
        // Remove internal spaces, uppercase.
        let compact = code.replacingOccurrences(of: " ", with: "").uppercased()
        // Find where the trailing alpha suffix begins after the digits.
        var result = ""
        var seenDigit = false
        for ch in compact {
            if ch.isNumber { seenDigit = true; result.append(ch) }
            else if seenDigit { break }   // first alpha after digits → suffix, stop
            else { result.append(ch) }    // prefix letters
        }
        return result
    }

    /// Finds or creates a SemesterEntity for the given season/year.
    /// Links to the active plan if one exists; silently creates a default plan if needed.
    /// NOTE: does NOT save — caller is responsible for saving after all changes are made.
    @discardableResult
    func findOrCreateSemester(season: String, year: Int) -> SemesterEntity {
        let semesterName = "\(season) \(year)"
        let req = NSFetchRequest<SemesterEntity>(entityName: "SemesterEntity")
        req.predicate = NSPredicate(format: "name ==[c] %@", semesterName)
        req.fetchLimit = 1
        if let existing = (try? viewContext.fetch(req))?.first {
            return existing
        }
        // Need a plan to attach to
        let plan: PlanEntity = getActivePlan() ?? plans.first ?? {
            let p = PlanEntity(context: viewContext)
            p.id = UUID()
            p.name = "Academic Plan"
            p.type = "standard"
            return p
        }()
        // Create semester in-memory without saving; caller saves.
        let semester = SemesterEntity(context: viewContext)
        semester.id = UUID()
        semester.name = semesterName
        semester.year = Int16(year)
        semester.season = season
        semester.isPlanned = true
        semester.seasonOrder = seasonOrder(for: season)
        semester.plan = plan
        return semester
    }

    /// Finds or creates a CourseEntity for the given code in the given semester.
    /// Returns `(entity, isNew)`.
    /// NOTE: does NOT save — caller is responsible for saving after all changes are made.
    func findOrCreateCourse(code: String, in semester: SemesterEntity) -> (CourseEntity, Bool) {
        let upperCode = code.uppercased()
        if let courses = semester.courses?.allObjects as? [CourseEntity],
           let existing = courses.first(where: {
               // Match exact code OR allow one to be a prefix of the other so that
               // "CSE191" and "CSE191LR" (same course, section suffix) are not duplicated.
               let c = ($0.code ?? "").uppercased()
               return c == upperCode || c.hasPrefix(upperCode) || upperCode.hasPrefix(c)
           }) {
            return (existing, false)
        }
        // Look up catalog for name/credits
        let catalog = fetchCatalogCourseForCode(upperCode)
        let rawName = catalog?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let courseName = rawName.isEmpty ? upperCode : rawName
        let credits = catalog != nil ? Int(catalog!.credits) : 3

        // Create in-memory without saving; caller saves.
        let course = CourseEntity(context: viewContext)
        course.id = UUID()
        course.code = upperCode
        course.name = courseName
        course.credits = Int16(credits)
        course.status = "In Progress"
        course.gradingType = "Letter Grade"
        course.isCompleted = false
        course.autoLinked = true
        course.semester = semester
        let currentCount = semester.courses?.count ?? 0
        course.sortOrder = Int32(currentCount)
        if let catalog { course.catalogCourse = catalog }
        return (course, true)
    }

    /// Looks up the active university's catalog for a matching course code.
    func fetchCatalogCourseForCode(_ code: String) -> CourseCatalogEntity? {
        guard let uni = getActiveUniversity() else { return nil }
        let req = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        req.predicate = NSPredicate(format: "courseCode ==[cd] %@ AND university == %@", code, uni)
        req.fetchLimit = 1
        return (try? viewContext.fetch(req))?.first
    }

    /// Multi-strategy catalog lookup used by the Academic History title scour.
    /// Tries four strategies in order, stopping at the first hit:
    ///  1. Exact code + active university
    ///  2. Exact code, any university (catches un-linked or multi-university catalogs)
    ///  3. Code with spaces removed/added ("MGS 405" ↔ "MGS405"), active university
    ///  4. Code with spaces variant, any university
    func fetchCatalogCourseForCodeBroadSearch(_ rawCode: String) -> CourseCatalogEntity? {
        let code = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }

        func fetch(predicate: NSPredicate) -> CourseCatalogEntity? {
            let req = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
            req.predicate = predicate
            req.fetchLimit = 1
            return (try? viewContext.fetch(req))?.first
        }

        let uni = getActiveUniversity()

        // 1. Exact + university
        if let uni,
           let hit = fetch(predicate: NSPredicate(format: "courseCode ==[cd] %@ AND university == %@", code, uni)) {
            return hit
        }
        // 2. Exact, any university
        if let hit = fetch(predicate: NSPredicate(format: "courseCode ==[cd] %@", code)) {
            return hit
        }
        // Build a spaced variant: "MGS405" → "MGS 405", and vice-versa
        let spacedVariant: String = {
            // If code has a space, strip it; if not, insert space before trailing digits
            if code.contains(" ") { return code.replacingOccurrences(of: " ", with: "") }
            // Insert space before the digit run: "MGS405" → "MGS 405"
            if let range = code.range(of: #"(?<=[A-Za-z])(?=\d)"#, options: .regularExpression) {
                var s = code; s.insert(" ", at: range.lowerBound); return s
            }
            return ""
        }()

        if !spacedVariant.isEmpty {
            // 3. Spaced variant + university
            if let uni,
               let hit = fetch(predicate: NSPredicate(format: "courseCode ==[cd] %@ AND university == %@", spacedVariant, uni)) {
                return hit
            }
            // 4. Spaced variant, any university
            if let hit = fetch(predicate: NSPredicate(format: "courseCode ==[cd] %@", spacedVariant)) {
                return hit
            }
        }

        // 5. Space-normalized comparison: strip spaces from both the query and
        //    catalog codes, then compare. Handles "PSC103" ↔ "PSC 103" and any
        //    other spacing mismatch reliably.
        //    Fetch candidates whose courseCode starts with the letter prefix, then
        //    filter in Swift after stripping spaces on both sides.
        let noSpaceCode = code.replacingOccurrences(of: " ", with: "")
        let letterPrefix = String(noSpaceCode.prefix(while: { $0.isLetter }))
        if !letterPrefix.isEmpty {
            let candidateReq = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
            candidateReq.predicate = NSPredicate(format: "courseCode BEGINSWITH[cd] %@", letterPrefix)
            candidateReq.fetchLimit = 40
            if let candidates = try? viewContext.fetch(candidateReq) {
                if let hit = candidates.first(where: {
                    ($0.courseCode ?? "").replacingOccurrences(of: " ", with: "").uppercased() == noSpaceCode
                }) {
                    return hit
                }
            }
        }

        return nil
    }

    /// Batch-deletes CalendarEventEntity rows by their stable UUID.
    /// Uses NSBatchDeleteRequest for efficiency — safe to call with large lists.
    func bulkDeleteCalendarEvents(withUUIDs uuids: [UUID]) {
        guard !uuids.isEmpty else { return }
        let req = NSFetchRequest<NSFetchRequestResult>(entityName: "CalendarEventEntity")
        req.predicate = NSPredicate(format: "id IN %@", uuids as CVarArg)
        let batchDelete = NSBatchDeleteRequest(fetchRequest: req)
        batchDelete.resultType = .resultTypeObjectIDs
        do {
            let result = try viewContext.execute(batchDelete) as? NSBatchDeleteResult
            let ids = result?.result as? [NSManagedObjectID] ?? []
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                into: [viewContext]
            )
            calendarDidChangeToken &+= 1
        } catch {
            print("[CoreData] bulkDeleteCalendarEvents failed: \(error)")
        }
    }

    /// Sets the course + semester relationships on a batch of events and saves.
    func bulkLinkCalendarEvents(_ events: [CalendarEventEntity],
                                to course: CourseEntity,
                                semester: SemesterEntity) {
        guard !events.isEmpty else { return }
        let now = Date()
        for event in events {
            event.course = course
            event.semester = semester
            // Heal any required fields that may not have been set yet by the sync pipeline.
            if event.id == nil        { event.id = UUID() }
            if event.createdAt == nil { event.createdAt = now }
            if event.lastUpdated == nil { event.lastUpdated = now }
        }
        // Use a quiet save that does NOT post a user-visible notification on failure,
        // preventing spurious "Save Failed - createdAt is a required value" toasts.
        viewContext.performAndWait {
            guard viewContext.hasChanges else { return }
            do {
                try viewContext.save()
                calendarDidChangeToken &+= 1
            } catch {
                print("[CalendarCourseLinker] bulkLink save failed (will retry on next sync): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Vault: Delete transcript from profile

    func deleteTranscript(from profile: ProfileEntity) {
        profile.transcriptData       = nil
        profile.transcriptFileName   = nil
        profile.transcriptUploadDate = nil
        save()
    }

    // MARK: - Vault: Delete syllabus from course override

    func deleteSyllabus(from override: CourseOverrideEntity) {
        override.syllabusFileBookmarkData = nil
        override.syllabusFileName          = nil
        override.syllabusFileSizeBytes     = 0
        override.syllabusUploadedAt        = nil
        save()
    }

    /// Best-effort university resolution for CourseOverride operations.
    /// Prefers the active university, else falls back deterministically to the first university by name.
    private func resolvedUniversityForOverrides() -> UniversityEntity? {
        if let active = getActiveUniversity() { return active }

        let request: NSFetchRequest<UniversityEntity> = UniversityEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }

    func fetchSyllabusOverridesWithFiles() -> [CourseOverrideEntity] {
        guard let university = resolvedUniversityForOverrides() else { return [] }
        let request = NSFetchRequest<CourseOverrideEntity>(entityName: "CourseOverrideEntity")
        request.predicate = NSPredicate(
            format: "university == %@ AND syllabusFileName != nil AND syllabusFileBookmarkData != nil",
            university
        )
        request.sortDescriptors = [NSSortDescriptor(key: "syllabusUploadedAt", ascending: false)]
        return (try? viewContext.fetch(request)) ?? []
    }

    func getCourseOverride(courseCode: String) -> CourseOverrideEntity? {
        guard let university = resolvedUniversityForOverrides() else { return nil }
        let needle = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        let request = NSFetchRequest<CourseOverrideEntity>(entityName: "CourseOverrideEntity")
        request.predicate = NSPredicate(
            format: "courseCode == %@ AND university == %@",
            needle, university
        )
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    // MARK: - Context
    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }
    
    // MARK: - Save
    func save() {
        let context = viewContext

        // Do not block the caller; save on the context queue instead.
        context.perform {
            guard context.hasChanges else { return }

            do {
                try context.save()
                #if DEBUG
                DispatchQueue.main.async {
                    CoreDataManager.shared.refreshDebugCounts()
                    CoreDataManager.shared.setDebugStatus("Saved changes")
                }
                #endif
            } catch {
                print("Failed to save context: \(error.localizedDescription)")
                print("Error details: \(error)")

                // Extract sub-errors from NSValidationMultipleErrorsError so user can diagnose
                let nsError = error as NSError
                var detail = error.localizedDescription
                if let subErrors = nsError.userInfo[NSDetailedErrorsKey] as? [NSError], !subErrors.isEmpty {
                    let descriptions = subErrors.prefix(3).map { "• \($0.localizedDescription)" }.joined(separator: "\n")
                    detail = descriptions
                } else if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    detail = underlying.localizedDescription
                }

                Task { @MainActor in
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Save Failed",
                        message: detail,
                        isDismissible: true,
                        autoDismissAfter: 8
                    )
                }

                #if DEBUG
                DispatchQueue.main.async {
                    CoreDataManager.shared.refreshDebugCounts()
                    CoreDataManager.shared.setDebugStatus("Save FAILED: \(error.localizedDescription)")
                }
                #endif
            }
        }
    }

    /// Non-blocking save for UI-sensitive paths.
    ///
    /// This schedules the save on the context queue and returns immediately,
    /// preventing long I/O or SQLite work from freezing SwiftUI rendering.
    func saveAsync() {
        let context = viewContext

        context.perform {
            guard context.hasChanges else { return }

            do {
                try context.save()
                #if DEBUG
                DispatchQueue.main.async {
                    CoreDataManager.shared.refreshDebugCounts()
                    CoreDataManager.shared.setDebugStatus("Saved changes (async)")
                }
                #endif
            } catch {
                print("Failed to save context (async): \(error.localizedDescription)")
                print("Error details: \(error)")

                Task { @MainActor in
                    AppNotificationCenter.shared.post(
                        kind: .error,
                        title: "Save Failed",
                        message: error.localizedDescription,
                        isDismissible: true,
                        autoDismissAfter: 6
                    )
                }

                #if DEBUG
                DispatchQueue.main.async {
                    CoreDataManager.shared.refreshDebugCounts()
                    CoreDataManager.shared.setDebugStatus("Save FAILED (async): \(error.localizedDescription)")
                }
                #endif
            }
        }
    }

    /// Lightweight save for calendar/task interactions.
    ///
    /// Calendar UX can be high frequency (drag-to-reschedule). Keep a dedicated path
    /// that bumps `calendarDidChangeToken` without triggering broader app state refresh.
    func saveCalendarChanges() {
        let context = container.viewContext

        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                CoreDataManager.shared.saveCalendarChanges()
            }
            return
        }

        guard context.hasChanges else { return }

        do {
            try context.save()
            // calendarDidChangeToken is @Published — incrementing it automatically fires
            // objectWillChange, so a redundant explicit send() is removed.
            calendarDidChangeToken &+= 1

            #if DEBUG
            refreshDebugCounts()
            setDebugStatus("Saved calendar changes")
            #endif
        } catch {
            print("[CoreData][Calendar] Failed to save context: \(error.localizedDescription)")
            print("[CoreData][Calendar] Error details: \(error)")

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Save Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }

            #if DEBUG
            refreshDebugCounts()
            setDebugStatus("Calendar save FAILED: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Profile Operations
    func fetchProfile() {
        let request = NSFetchRequest<ProfileEntity>(entityName: "ProfileEntity")
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false
        
        do {
            let profiles = try viewContext.fetch(request)
            if let existingProfile = profiles.first {
                self.profile = existingProfile

                let priorGPA = existingProfile.gpa
                let priorCreditsEarned = existingProfile.creditsEarned
                recomputeProfileAcademics()
                if existingProfile.gpa != priorGPA || existingProfile.creditsEarned != priorCreditsEarned {
                    save()
                }
            } else {
                // Create default profile
                let newProfile = ProfileEntity(context: viewContext)
                newProfile.id = UUID()
                newProfile.name = "Alex Student"
                newProfile.major = ""
                newProfile.classStanding = "Junior"
                newProfile.gpa = 0
                newProfile.expectedGraduation = "Spring 2026"
                // Don't preselect a school/department; it makes the dropdown appear "pre-populated"
                // even after the persistent store is cleared.
                newProfile.collegeName = ""
                newProfile.department = ""
                save()
                self.profile = newProfile
            }

            #if DEBUG
            refreshDebugCounts()
            #endif
        } catch {
            print("Failed to fetch profile: \(error.localizedDescription)")

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Profile Load Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
        }
    }
    
    func updateProfile(name: String, major: String, minor: String, gpa: Double, classStanding: String, expectedGraduation: String, collegeName: String, department: String) {
        guard let profile = profile else { return }
        profile.name = name
        profile.major = major
        profile.minor = minor
        profile.gpa = gpa
        profile.classStanding = classStanding
        profile.expectedGraduation = expectedGraduation
        profile.collegeName = collegeName
        profile.department = department
        save()
        objectWillChange.send()
    }
    
    // MARK: - Experience Operations
    func addExperience(title: String, company: String, location: String, startDate: Date, endDate: Date?, isCurrent: Bool, description: String) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                CoreDataManager.shared.addExperience(title: title, company: company, location: location, startDate: startDate, endDate: endDate, isCurrent: isCurrent, description: description)
            }
            return
        }
        
        guard let profile = profile else {
            print("[CoreData] addExperience failed: profile is nil")

            #if DEBUG
            setDebugStatus("Add Experience FAILED: profile is nil")
            #endif
            return
        }
        print("[CoreData] addExperience(title=\(title), company=\(company), isCurrent=\(isCurrent))")

        #if DEBUG
        setDebugStatus("Adding experience: \(title) @ \(company)")
        #endif
        
        let experience = ExperienceEntity(context: viewContext)
        experience.id = UUID()
        experience.title = title
        experience.company = company
        experience.location = location
        experience.startDate = startDate
        experience.endDate = endDate
        experience.isCurrent = isCurrent
        experience.descriptionText = description
        experience.profile = profile

        #if DEBUG
        refreshDebugCounts()
        #endif
        save()
    }
    
    func deleteExperience(_ experience: ExperienceEntity) {
        viewContext.delete(experience)
        save()
        objectWillChange.send()
    }
    
    // MARK: - Achievement Operations
    func addAchievement(name: String, organization: String, dateReceived: Date, amount: String, description: String, url: String) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                CoreDataManager.shared.addAchievement(name: name, organization: organization, dateReceived: dateReceived, amount: amount, description: description, url: url)
            }
            return
        }
        
        guard let profile = profile else {
            print("[CoreData] addAchievement failed: profile is nil")

            #if DEBUG
            setDebugStatus("Add Award FAILED: profile is nil")
            #endif
            return
        }
        print("[CoreData] addAchievement(name=\(name), organization=\(organization))")

        #if DEBUG
        setDebugStatus("Adding award: \(name) @ \(organization)")
        #endif
        
        let achievement = AchievementEntity(context: viewContext)
        achievement.id = UUID()
        achievement.name = name
        achievement.organization = organization
        achievement.dateReceived = dateReceived
        achievement.amount = amount
        achievement.descriptionText = description
        achievement.url = url
        achievement.profile = profile

        #if DEBUG
        refreshDebugCounts()
        #endif
        save()
    }
    
    func deleteAchievement(_ achievement: AchievementEntity) {
        viewContext.delete(achievement)
        save()
        objectWillChange.send()
    }
    
    // MARK: - Plan Operations
    func fetchPlans() {
        let request = NSFetchRequest<PlanEntity>(entityName: "PlanEntity")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PlanEntity.createdAt, ascending: true)]
        request.fetchBatchSize = 100
        request.returnsObjectsAsFaults = true
        
        do {
            plans = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch plans: \(error.localizedDescription)")

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Plans Load Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
        }
    }
    
    func addPlan(name: String, type: String, major: String, minor: String, concentration: String) -> PlanEntity {
        let plan = PlanEntity(context: viewContext)
        plan.id = UUID()
        plan.name = name
        plan.type = type
        plan.major = major
        plan.minor = minor
        plan.concentration = concentration
        plan.createdAt = Date()
        saveAsync()
        return plan
    }
    
    // MARK: - Semester Operations
    func fetchSemesters() {
        let request = NSFetchRequest<SemesterEntity>(entityName: "SemesterEntity")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \SemesterEntity.year, ascending: true),
            NSSortDescriptor(keyPath: \SemesterEntity.seasonOrder, ascending: true)
        ]
        request.fetchBatchSize = 120
        request.returnsObjectsAsFaults = true
        
        do {
            semesters = try viewContext.fetch(request)
        } catch {
            print("Failed to fetch semesters: \(error.localizedDescription)")

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Semesters Load Failed",
                    message: error.localizedDescription,
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
        }
    }

    /// Fetch a specific semester by its stable UUID.
    ///
    /// Prefer this over scanning in-memory arrays; it stays correct even as we migrate views to `@FetchRequest`.
    func semester(with id: UUID) -> SemesterEntity? {
        let request = NSFetchRequest<SemesterEntity>(entityName: "SemesterEntity")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? viewContext.fetch(request))?.first
    }
    
    func addSemester(to plan: PlanEntity, name: String, year: Int, season: String) -> SemesterEntity {
        let semester = SemesterEntity(context: viewContext)
        semester.id = UUID()
        semester.name = name
        semester.year = Int16(year)
        semester.season = season
        semester.isPlanned = true
        semester.seasonOrder = seasonOrder(for: season)
        semester.plan = plan
        save()
        return semester
    }
    
    func deleteSemester(_ semester: SemesterEntity) {
        viewContext.delete(semester)
        save()
    }
    
    func updateSemester(_ semester: SemesterEntity) {
        save()
    }
    
    // MARK: - Course Operations
    func addCourse(
        to semester: SemesterEntity,
        code: String,
        name: String,
        credits: Int,
        status: String,
        gradingType: String,
        professor: String?
    ) -> CourseEntity {
        let course = CourseEntity(context: viewContext)
        course.id = UUID()
        course.code = code
        course.name = name
        course.credits = Int16(credits)
        course.status = status
        course.gradingType = gradingType
        course.professor = professor
        course.isCompleted = (status == "Completed")
        course.semester = semester
        
        // Set sort order
        let currentCount = semester.courses?.count ?? 0
        course.sortOrder = Int32(currentCount)

        recomputeProfileAcademics()   // mutates profile in-memory BEFORE saving
        save()                        // one atomic write: course + profile together
        return course
    }
    
    func deleteCourse(_ course: CourseEntity) {
        viewContext.delete(course)
        save()
    }

    func deleteCourseOverride(_ overrideEntity: CourseOverrideEntity) {
        viewContext.delete(overrideEntity)
        save()
    }
    
    func updateCourse(_ course: CourseEntity) {
        course.isCompleted = (course.status == "Completed")
        recomputeProfileAcademics()   // mutates profile in-memory BEFORE saving
        save()                        // one atomic write: course + profile together
        plannerChangeToken += 1
        AcademicNotificationScheduler.shared.reschedule(using: self)
    }

    /// Recomputes `profile.gpa` and `profile.creditsEarned` from current CourseEntity data.
    /// Called automatically after every course status/grade change so stat cards stay live.
    private func recomputeProfileAcademics() {
        guard let profile = self.profile else { return }

        let allCourses = semesters.flatMap { $0.coursesArray }

        // --- Credits earned: sum of credits for all isCompleted courses ---
        let earnedCredits = allCourses
            .filter { $0.isCompleted }
            .reduce(0) { $0 + Int($1.credits) }
        profile.creditsEarned = Int32(earnedCredits)

        // --- Profile GPA: weighted across selected majors/minors ---
        // GPA = Total Grade Points / Total Credits
        // Total Grade Points = grade points * credits for each counted course.
        let selectedMajors = [profile.major, profile.secondaryMajor]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let selectedMinor = profile.minor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasProgramSelections = !selectedMajors.isEmpty || (!selectedMinor.isEmpty && selectedMinor.lowercased() != "none")

        var totalGradePoints: Double = 0
        var totalCredits: Double = 0

        for major in selectedMajors {
            let reqs = getDegreeRequirementsForMajorDisplay(major)
            if let summary = majorGPASummary(requirements: reqs), summary.creditsCounted > 0 {
                totalGradePoints += summary.gpa * summary.creditsCounted
                totalCredits += summary.creditsCounted
            }
        }

        if let minorSummary = minorGPASummary(minorName: selectedMinor), minorSummary.creditsCounted > 0 {
            totalGradePoints += minorSummary.gpa * minorSummary.creditsCounted
            totalCredits += minorSummary.creditsCounted
        }

        if totalCredits > 0 {
            let computed = (totalGradePoints / totalCredits * 100).rounded() / 100
            profile.gpa = computed
            return
        }

        // If the user selected programs but none produced a GPA sample yet, keep profile GPA empty.
        if hasProgramSelections {
            profile.gpa = 0
            return
        }

        // Fallback when no major/minor is selected yet: compute from all completed letter-graded courses.
        var qualityPoints = 0.0
        var creditsCounted = 0.0
        struct CourseKey: Hashable { let code: String }
        var latestByCode: [CourseKey: (course: CourseEntity, semesterSort: Int)] = [:]
        for sem in semesters {
            let semSort = Int(sem.year) * 10 + Int(sem.seasonOrder)
            for course in sem.coursesArray where course.isCompleted {
                guard let grade = course.grade, !grade.isEmpty else { continue }
                guard isLetterGraded(course.gradingType) else { continue }
                guard gradePoints(for: grade) != nil else { continue }
                let codeStr = (course.code ?? course.name ?? UUID().uuidString)
                    .uppercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let key = CourseKey(code: codeStr)
                if let existing = latestByCode[key] {
                    if semSort > existing.semesterSort { latestByCode[key] = (course, semSort) }
                } else {
                    latestByCode[key] = (course, semSort)
                }
            }
        }

        for entry in latestByCode.values {
            let course = entry.course
            guard let grade = course.grade, !grade.isEmpty,
                  isLetterGraded(course.gradingType),
                  let pts = gradePoints(for: grade) else { continue }
            let cr = Double(course.credits)
            qualityPoints += pts * cr
            creditsCounted += cr
        }

        if creditsCounted > 0 {
            let computed = (qualityPoints / creditsCounted * 100).rounded() / 100
            profile.gpa = computed
        } else {
            profile.gpa = 0
        }
        // NOTE: Do NOT save here — the calling site's save() will commit both
        // the triggering entity change AND the profile update in one atomic write.
    }

    /// Returns (attempted, completed, rate) for SAP financial aid tracking.
    /// Attempted = Completed + Dropped + Failed. Completed = isCompleted only.
    func sapStats() -> (attempted: Int, completed: Int, rate: Double) {
        let all = semesters.flatMap { $0.coursesArray }
        let completedCredits = all.filter { $0.isCompleted }
            .reduce(0) { $0 + Int($1.credits) }
        let attemptedStatuses: Set<String> = ["Completed", "Dropped", "Failed", "Transfer"]
        let attemptedCredits = all.filter { c in
            let s = (c.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return attemptedStatuses.contains(s) || c.isCompleted
        }.reduce(0) { $0 + Int($1.credits) }
        let rate = attemptedCredits > 0 ? Double(completedCredits) / Double(attemptedCredits) : 1.0
        return (attemptedCredits, completedCredits, rate)
    }
    
    // MARK: - Calendar: Events
    nonisolated(unsafe) private var _notifyDebounceWork: DispatchWorkItem? = nil

    /// Coalesces rapid-fire calls (e.g. 50 events imported in one Google sync) into a
    /// single token increment after a 100 ms idle window.
    func notifyCalendarDidChange() {
        DispatchQueue.main.async {
            CoreDataManager.shared._notifyDebounceWork?.cancel()
            let work = DispatchWorkItem {
                CoreDataManager.shared.calendarDidChangeToken &+= 1
            }
            CoreDataManager.shared._notifyDebounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }
    }

    func addCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semester: SemesterEntity?,
        course: CourseEntity?,
        notes: String? = nil,
        location: String? = nil
    ) -> CalendarEventEntity {
        let event = CalendarEventEntity(context: viewContext)
        event.id = UUID()
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.allDay = allDay
        event.notes = notes
        event.location = location
        event.createdAt = Date()
        event.lastUpdated = Date()
        event.semester = semester
        event.course = course
        saveCalendarChanges()
        return event
    }
    
    func deleteCalendarEvent(_ event: CalendarEventEntity) {
        viewContext.delete(event)
        saveCalendarChanges()
    }
    
    func deleteCalendarEvent(objectID: NSManagedObjectID) {
        do {
            if let event = try viewContext.existingObject(with: objectID) as? CalendarEventEntity {
                deleteCalendarEvent(event)
            }
        } catch {
            print("[CoreData][Calendar] Failed to delete event by objectID: \(error)")
        }
    }
    
    func fetchCalendarEvents(
        semester: SemesterEntity?,
        start: Date,
        end: Date
    ) -> [CalendarEventEntity] {
        let request = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
        request.fetchBatchSize = 200
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "startDate <= %@ AND endDate >= %@", end as NSDate, start as NSDate)
        ]
        
        if let semester = semester {
            // Include events for the selected semester AND events with no semester
            // (Google calendar events, Apple System events, etc. are stored with semester == nil)
            let semesterPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "semester == %@", semester),
                NSPredicate(format: "semester == nil")
            ])
            predicates.append(semesterPredicate)
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CalendarEventEntity.startDate, ascending: true),
            NSSortDescriptor(keyPath: \CalendarEventEntity.title, ascending: true)
        ]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("[CoreData][Calendar] Failed to fetch events: \(error)")
            return []
        }
    }

    func searchCalendarEvents(
        semester: SemesterEntity?,
        query: String
    ) -> [CalendarEventEntity] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let request = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
        request.fetchBatchSize = 50

        let textPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "title CONTAINS[cd] %@", q),
            NSPredicate(format: "notes CONTAINS[cd] %@", q),
            NSPredicate(format: "location CONTAINS[cd] %@", q),
            NSPredicate(format: "course.code CONTAINS[cd] %@", q),
            NSPredicate(format: "course.name CONTAINS[cd] %@", q)
        ])

        var predicates: [NSPredicate] = [textPredicate]
        if let semester {
            let semesterPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "semester == %@", semester),
                NSPredicate(format: "semester == nil")
            ])
            predicates.append(semesterPredicate)
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CalendarEventEntity.startDate, ascending: true),
            NSSortDescriptor(keyPath: \CalendarEventEntity.title, ascending: true)
        ]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("[CoreData][Calendar] Failed to search events: \(error)")
            return []
        }
    }

    func updateCalendarEventTimes(
        objectID: NSManagedObjectID,
        startDate: Date,
        endDate: Date
    ) {
        do {
            guard let event = try viewContext.existingObject(with: objectID) as? CalendarEventEntity else {
                return
            }

            event.startDate = startDate
            event.endDate = endDate
            event.lastUpdated = Date()
            saveCalendarChanges()
        } catch {
            print("[CoreData][Calendar] Failed to update event times: \(error)")
        }
    }

    func updateCalendarEvent(
        objectID: NSManagedObjectID,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semester: SemesterEntity?,
        course: CourseEntity?,
        notes: String? = nil,
        location: String? = nil
    ) {
        do {
            guard let event = try viewContext.existingObject(with: objectID) as? CalendarEventEntity else {
                return
            }

            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.allDay = allDay
            event.semester = semester
            event.course = course
            event.notes = notes
            event.location = location
            event.lastUpdated = Date()
            saveCalendarChanges()
        } catch {
            print("[CoreData][Calendar] Failed to update event: \(error)")
        }
    }
    
    // MARK: - Calendar: Tasks
    func addTask(
        title: String,
        dueDate: Date?,
        semester: SemesterEntity?,
        course: CourseEntity?,
        notes: String? = nil,
        priority: Int16 = 0,
        categoryName: String? = nil,
        gradingCategory: CourseGradingCategoryEntity? = nil,
        categoryWeightPercent: Double? = nil,
        weightPercent: Double? = nil,
        estimatedEffortMinutes: Int32? = nil
    ) -> TaskEntity {
        let task = TaskEntity(context: viewContext)
        task.id = UUID()
        task.title = title
        task.dueDate = dueDate
        task.isCompleted = false
        task.completedAt = nil
        task.notes = notes
        task.priority = priority
        task.categoryName = categoryName
        task.gradingCategory = gradingCategory
        task.setValue(categoryWeightPercent, forKey: "categoryWeightPercent")
        task.setValue(weightPercent, forKey: "weightPercent")
        task.setValue(estimatedEffortMinutes, forKey: "estimatedEffortMinutes")
        task.createdAt = Date()
        task.lastUpdated = Date()
        task.semester = semester
        task.course = course
        saveCalendarChanges()
        return task
    }
    
    func setTaskCompleted(_ task: TaskEntity, completed: Bool) {
        task.isCompleted = completed
        task.completedAt = completed ? Date() : nil
        task.lastUpdated = Date()
        saveCalendarChanges()
    }
    
    func deleteTask(_ task: TaskEntity) {
        viewContext.delete(task)
        saveCalendarChanges()
    }
    
    func deleteTask(objectID: NSManagedObjectID) {
        do {
            if let task = try viewContext.existingObject(with: objectID) as? TaskEntity {
                deleteTask(task)
            }
        } catch {
            print("[CoreData][Calendar] Failed to delete task by objectID: \(error)")
        }
    }

    // MARK: - Brightspace deduplication

    /// Returns true if a TaskEntity with the given brightspaceItemId already exists.
    func taskExists(brightspaceItemId: String) -> Bool {
        guard !brightspaceItemId.isEmpty else { return false }
        let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
        request.predicate = NSPredicate(format: "brightspaceItemId == %@", brightspaceItemId)
        request.fetchLimit = 1
        return (try? viewContext.count(for: request)) ?? 0 > 0
    }

    /// Returns true if a CalendarEventEntity with the given brightspaceAnnouncementId already exists.
    func announcementExists(brightspaceAnnouncementId: String) -> Bool {
        guard !brightspaceAnnouncementId.isEmpty else { return false }
        let request = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
        request.predicate = NSPredicate(format: "brightspaceAnnouncementId == %@", brightspaceAnnouncementId)
        request.fetchLimit = 1
        return (try? viewContext.count(for: request)) ?? 0 > 0
    }


    func fetchTasks(
        semester: SemesterEntity?,
        dueStart: Date,
        dueEnd: Date,
        includeCompleted: Bool = false
    ) -> [TaskEntity] {
        let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "dueDate >= %@ AND dueDate <= %@", dueStart as NSDate, dueEnd as NSDate)
        ]
        
        if let semester = semester {
            predicates.append(NSPredicate(format: "semester == %@", semester))
        }
        
        if !includeCompleted {
            predicates.append(NSPredicate(format: "isCompleted == NO"))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \TaskEntity.dueDate, ascending: true),
            NSSortDescriptor(keyPath: \TaskEntity.priority, ascending: false),
            NSSortDescriptor(keyPath: \TaskEntity.title, ascending: true)
        ]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("[CoreData][Calendar] Failed to fetch tasks: \(error)")
            return []
        }
    }

    func searchTasks(
        semester: SemesterEntity?,
        query: String,
        includeCompleted: Bool = false
    ) -> [TaskEntity] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let request = NSFetchRequest<TaskEntity>(entityName: "TaskEntity")

        let textPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "title CONTAINS[cd] %@", q),
            NSPredicate(format: "notes CONTAINS[cd] %@", q),
            NSPredicate(format: "course.code CONTAINS[cd] %@", q),
            NSPredicate(format: "course.name CONTAINS[cd] %@", q)
        ])

        var predicates: [NSPredicate] = [textPredicate]
        if let semester {
            predicates.append(NSPredicate(format: "semester == %@", semester))
        }
        if !includeCompleted {
            predicates.append(NSPredicate(format: "isCompleted == NO"))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \TaskEntity.dueDate, ascending: true),
            NSSortDescriptor(keyPath: \TaskEntity.priority, ascending: false),
            NSSortDescriptor(keyPath: \TaskEntity.title, ascending: true)
        ]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("[CoreData][Calendar] Failed to search tasks: \(error)")
            return []
        }
    }

    func updateTask(
        objectID: NSManagedObjectID,
        title: String,
        dueDate: Date?,
        semester: SemesterEntity?,
        course: CourseEntity?,
        notes: String? = nil,
        priority: Int16 = 0,
        categoryName: String? = nil,
        gradingCategory: CourseGradingCategoryEntity? = nil,
        categoryWeightPercent: Double? = nil,
        weightPercent: Double? = nil,
        estimatedEffortMinutes: Int32? = nil
    ) {
        do {
            guard let task = try viewContext.existingObject(with: objectID) as? TaskEntity else {
                return
            }

            task.title = title
            task.dueDate = dueDate
            task.semester = semester
            task.course = course
            task.notes = notes
            task.priority = priority
            task.categoryName = categoryName
            task.gradingCategory = gradingCategory
            task.setValue(categoryWeightPercent, forKey: "categoryWeightPercent")
            task.setValue(weightPercent, forKey: "weightPercent")
            task.setValue(estimatedEffortMinutes, forKey: "estimatedEffortMinutes")
            task.lastUpdated = Date()
            save()
        } catch {
            print("[CoreData][Calendar] Failed to update task: \(error)")
        }
    }

    // MARK: - Course: Grading Categories (Syllabus AI)

    private static let nonAlphanumericRegex = try? NSRegularExpression(pattern: "[^a-z0-9]+")

    /// Stable normalization key so we can upsert categories despite casing/punctuation differences.
    private func normalizeGradingCategoryKey(_ raw: String) -> String {
        var s = raw.normalizedCatalogText().lowercased().replacingOccurrences(of: "&", with: "and")
        if let re = Self.nonAlphanumericRegex {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }
        return s.normalizedCatalogText()
    }

    func gradingCategories(for course: CourseEntity) -> [CourseGradingCategoryEntity] {
        let set = (course.gradingCategories as? Set<CourseGradingCategoryEntity>) ?? []
        return set.sorted { a, b in
            let aw = (a.value(forKey: "weightPercent") as? Double) ?? (a.value(forKey: "weightPercent") as? NSNumber)?.doubleValue ?? -1
            let bw = (b.value(forKey: "weightPercent") as? Double) ?? (b.value(forKey: "weightPercent") as? NSNumber)?.doubleValue ?? -1
            if aw != bw { return aw > bw }
            return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
        }
    }

    /// Upserts grading categories/weights for a specific planned course.
    ///
    /// Behavior:
    /// - Update existing categories that match by normalized name.
    /// - Create missing categories.
    /// - Delete categories that are no longer present in the incoming set.
    ///
    /// Tasks linked to deleted categories are automatically nullified.
    @discardableResult
    func upsertGradingCategories(
        for course: CourseEntity,
        items: [SyllabusGradingItem],
        source: String = "syllabus_ai"
    ) -> [CourseGradingCategoryEntity] {
        let trimmedItems: [(name: String, weight: Double?, notes: String?)] = items
            .map { item in
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (name: name, weight: item.weightPercent, notes: (notes?.isEmpty == false ? notes : nil))
            }
            .filter { !$0.name.isEmpty }

        let request = NSFetchRequest<CourseGradingCategoryEntity>(entityName: "CourseGradingCategoryEntity")
        request.predicate = NSPredicate(format: "course == %@", course)
        let existing = (try? viewContext.fetch(request)) ?? []

        var existingByKey: [String: CourseGradingCategoryEntity] = [:]
        for cat in existing {
            let key = normalizeGradingCategoryKey(cat.name ?? "")
            if !key.isEmpty {
                existingByKey[key] = cat
            }
        }

        var seen = Set<String>()
        var upserted: [CourseGradingCategoryEntity] = []

        for item in trimmedItems {
            let key = normalizeGradingCategoryKey(item.name)
            guard !key.isEmpty else { continue }
            seen.insert(key)

            let entity: CourseGradingCategoryEntity
            if let e = existingByKey[key] {
                entity = e
            } else {
                entity = CourseGradingCategoryEntity(context: viewContext)
                entity.id = UUID()
                entity.createdAt = Date()
                entity.course = course
            }

            entity.name = item.name
            entity.setValue(item.weight, forKey: "weightPercent")
            entity.notes = item.notes
            entity.source = source
            entity.lastUpdated = Date()

            upserted.append(entity)
        }

        // Remove old categories that are no longer present.
        for old in existing {
            let key = normalizeGradingCategoryKey(old.name ?? "")
            if key.isEmpty || !seen.contains(key) {
                viewContext.delete(old)
            }
        }

        save()
        return upserted
    }
    
    // MARK: - Helpers
    private func seasonOrder(for season: String) -> Int16 {
        switch season {
        case "Fall": return 0
        case "Winter": return 1
        case "Spring": return 2
        case "Summer": return 3
        default: return 4
        }
    }
}

// MARK: - Active University + Profile Selections Persistence
private struct ProfileSelectionsSnapshot: Codable {
    var degreeLevel: String?
    var degreeType: String?
    var major: String?
    var secondaryMajor: String?
    var minor: String?
    var department: String?
    var classStanding: String?
    var expectedGraduation: String?
}

extension CoreDataManager {
    private func loadSavedSelectionsMap(from profile: ProfileEntity) -> [String: ProfileSelectionsSnapshot] {
        guard let json = profile.savedSelectionsJSON,
              let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: ProfileSelectionsSnapshot].self, from: data)) ?? [:]
    }

    private func storeSavedSelectionsMap(_ map: [String: ProfileSelectionsSnapshot], to profile: ProfileEntity) {
        if let data = try? JSONEncoder().encode(map),
           let json = String(data: data, encoding: .utf8) {
            profile.savedSelectionsJSON = json
        }
    }

    private func snapshotSelections(from profile: ProfileEntity) -> ProfileSelectionsSnapshot {
        ProfileSelectionsSnapshot(
            degreeLevel: profile.degreeLevel,
            degreeType: profile.degreeType,
            major: profile.major,
            secondaryMajor: profile.secondaryMajor,
            minor: profile.minor,
            department: profile.department,
            classStanding: profile.classStanding,
            expectedGraduation: profile.expectedGraduation
        )
    }

    private func applySelections(_ snapshot: ProfileSelectionsSnapshot, to profile: ProfileEntity) {
        profile.degreeLevel = snapshot.degreeLevel
        profile.degreeType = snapshot.degreeType
        profile.major = snapshot.major
        profile.secondaryMajor = snapshot.secondaryMajor
        profile.minor = snapshot.minor
        profile.department = snapshot.department
        profile.classStanding = snapshot.classStanding
        profile.expectedGraduation = snapshot.expectedGraduation
    }

    private func clearSelections(on profile: ProfileEntity) {
        profile.degreeLevel = nil
        profile.degreeType = nil
        profile.major = nil
        profile.secondaryMajor = nil
        profile.minor = nil
        profile.department = nil
        profile.classStanding = nil
        profile.expectedGraduation = nil
    }

    /// Enforces that at most one UniversityEntity is active at a time.
    /// Also clears current profile selections and restores any saved selections for the activated university name.
    func setActiveUniversity(_ university: UniversityEntity?) {
        let context = viewContext

        // Save current selections under the currently-active university name (if any).
        if let profile,
           let currentActiveName = getActiveUniversity()?.name,
           !currentActiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var map = loadSavedSelectionsMap(from: profile)
            map[currentActiveName] = snapshotSelections(from: profile)
            storeSavedSelectionsMap(map, to: profile)
        }

        // Enforce single active university.
        let fetch: NSFetchRequest<UniversityEntity> = UniversityEntity.fetchRequest()
        let universities = (try? context.fetch(fetch)) ?? []
        for u in universities {
            u.isActive = (university != nil && u.objectID == university?.objectID)
        }

        // Clear profile selections, then restore saved selections for new university (if any).
        if let profile {
            clearSelections(on: profile)
            if let newName = university?.name {
                profile.collegeName = newName
                let map = loadSavedSelectionsMap(from: profile)
                if let saved = map[newName] {
                    applySelections(saved, to: profile)
                }
            }
        }

        save()
    }

    @discardableResult
    func setActiveUniversity(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setActiveUniversity(nil)
            return false
        }
        let request: NSFetchRequest<UniversityEntity> = UniversityEntity.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", trimmed)
        if let found = (try? viewContext.fetch(request))?.first {
            setActiveUniversity(found)
            return true
        }

        setActiveUniversity(nil)
        return false
    }

    /// Deterministic active university lookup. If multiple are active, this will pick one consistently.
    func getActiveUniversity() -> UniversityEntity? {
        let fetchRequest: NSFetchRequest<UniversityEntity> = UniversityEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isActive == YES")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        guard let results = try? viewContext.fetch(fetchRequest), !results.isEmpty else { return nil }
        return results.first
    }
}

// MARK: - Manual GenEd Progress
extension CoreDataManager {
    struct GenEdCourseProgress {
        let completed: Int
        let assigned: Int
        var fraction: Double {
            guard assigned > 0 else { return 0.0 }
            return Double(completed) / Double(assigned)
        }
    }

    struct CreditsProgressSummary: Equatable {
        let completed: Double
        let required: Double
        let fraction: Double

        var completedRoundedInt: Int { Int(completed.rounded()) }
        var requiredRoundedInt: Int { Int(required.rounded()) }
    }

    func genEdCourseProgress(for plan: PlanEntity?) -> GenEdCourseProgress {
        guard let plan else { return GenEdCourseProgress(completed: 0, assigned: 0) }
        let courses = plan.semestersArray.flatMap { $0.coursesArray }
        let assignedCourses = courses.filter { $0.countsTowardGenEd }
        let completedCount = assignedCourses.filter { $0.isCompleted }.count
        return GenEdCourseProgress(completed: completedCount, assigned: assignedCourses.count)
    }

    func genEdCreditsProgress(for plan: PlanEntity?) -> CreditsProgressSummary {
        guard let plan else {
            return CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
        }
        let courses = plan.semestersArray.flatMap { $0.coursesArray }.filter { $0.countsTowardGenEd }
        let required = courses.reduce(0.0) { $0 + Double($1.credits) }
        let completed = courses.filter { $0.isCompleted }.reduce(0.0) { $0 + Double($1.credits) }
        let fraction = required > 0 ? min(max(completed / required, 0), 1) : 0
        return CreditsProgressSummary(completed: completed, required: required, fraction: fraction)
    }
}

// MARK: - Credits-based Requirements Progress (Major/Minor)
extension CoreDataManager {
    struct RequirementCreditBuckets {
        let requiredCore: Double
        let requiredElective: Double

        var totalRequired: Double {
            requiredCore + requiredElective
        }
    }

    private func parseCreditsRequirementFromTitle(_ title: String) -> (min: Double, max: Double?)? {
        let pattern = #"\((\d+(?:\.\d+)?)\s*(?:[-–]\s*(\d+(?:\.\d+)?))?\s*credits?\)"#
        guard let re = Self.cachedRegex(pattern, options: [.caseInsensitive]) else { return nil }
        let ns = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let m = re.firstMatch(in: title, options: [], range: ns) else { return nil }

        func capture(_ idx: Int) -> String? {
            guard m.numberOfRanges > idx else { return nil }
            let r = m.range(at: idx)
            guard r.location != NSNotFound, let rr = Range(r, in: title) else { return nil }
            return String(title[rr])
        }

        guard let a = capture(1), let min = Double(a) else { return nil }
        let max = capture(2).flatMap(Double.init)
        return (min: min, max: max)
    }

    private func creditsRequiredMinMaxForCategoryTitle(_ title: String, requirements: [DegreeRequirementEntity]) -> (min: Double, max: Double?) {
        if let parsed = parseCreditsRequirementFromTitle(title) {
            return (parsed.min, parsed.max)
        }

        let fallback: Double = {
            if let firstNonZero = requirements.first(where: { $0.creditsRequired > 0 }) {
                return Double(firstNonZero.creditsRequired)
            }
            return 0
        }()
        return (fallback, nil)
    }

    private func normalizeCourseCodeForProgress(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            // Strip trailing section-type suffix after a digit (e.g., "CSE191LEC" → "CSE191"),
            // mirroring the audit panel's normaliseCode so catalog and plan codes always match.
            .replacingOccurrences(of: #"(?<=\d)[A-Za-z]+$"#, with: "", options: .regularExpression)
            // Remove all internal spaces so "CSE 191" and "CSE191" compare equal.
            .replacingOccurrences(of: " ", with: "")
    }

    private func isElectiveRequirementCategory(_ title: String) -> Bool {
        let normalized = title
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty { return false }

        let electiveSignals = [
            "elective",
            "electives",
            "optional",
            "option",
            "options",
            "choose",
            "select",
            "approved",
            "free"
        ]

        return electiveSignals.contains(where: { normalized.contains($0) })
    }

    private func requirementCreditBuckets(requirements: [DegreeRequirementEntity]) -> RequirementCreditBuckets {
        func normalizeCategoryKey(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        var byKey: [String: [DegreeRequirementEntity]] = [:]
        var orderedKeys: [String] = []
        for r in requirements {
            let display = (r.requirementCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeCategoryKey(display)
            guard !key.isEmpty else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                orderedKeys.append(key)
            }
            byKey[key, default: []].append(r)
        }

        let sections: [(title: String, requirements: [DegreeRequirementEntity])] = orderedKeys.compactMap { key in
            guard var reqs = byKey[key], !reqs.isEmpty else { return nil }
            reqs.sort { $0.sectionOrder < $1.sectionOrder }
            let title = (reqs.first?.requirementCategory ?? "Requirements").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title: title.isEmpty ? "Requirements" : title, requirements: reqs)
        }

        var core: Double = 0
        var elective: Double = 0

        for section in sections {
            let required = creditsRequiredMinMaxForCategoryTitle(section.title, requirements: section.requirements).min
            guard required > 0 else { continue }
            if isElectiveRequirementCategory(section.title) {
                elective += required
            } else {
                core += required
            }
        }

        if core + elective == 0 {
            let required = creditsProgressSummary(requirements: requirements).required
            return RequirementCreditBuckets(requiredCore: required, requiredElective: 0)
        }

        return RequirementCreditBuckets(requiredCore: core, requiredElective: elective)
    }

    func majorRequirementCreditBuckets(forMajorDisplay majorDisplay: String) -> RequirementCreditBuckets {
        var reqs = getDegreeRequirementsForMajorDisplay(majorDisplay)
        if reqs.isEmpty {
            let degreeType = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let profileMajor = (profile?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedRequest = cleanedProgramNameFromDisplay(majorDisplay)
            let cleanedProfile = cleanedProgramNameFromDisplay(profileMajor)
            let matchesPrimary = !profileMajor.isEmpty &&
                (majorDisplay == profileMajor || cleanedRequest == cleanedProfile)

            let resolvedURL: String?
            if matchesPrimary {
                resolvedURL = resolveSelectedMajorProgramURL()
            } else {
                resolvedURL = resolveNonMinorMajorProgramURL(display: majorDisplay)
            }

            if let programURL = resolvedURL {
                reqs = getDegreeRequirements(programURL: programURL, degreeType: degreeType)
            }
        }

        return requirementCreditBuckets(requirements: reqs)
    }

    func minorRequirementCreditBuckets(forMinorDisplay minorDisplay: String) -> RequirementCreditBuckets {
        let trimmed = minorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else {
            return RequirementCreditBuckets(requiredCore: 0, requiredElective: 0)
        }
        guard let programURL = resolveProgramProgramURL(programDisplay: trimmed, isMinor: true) else {
            return RequirementCreditBuckets(requiredCore: 0, requiredElective: 0)
        }
        let reqs = getDegreeRequirements(programURL: programURL, degreeType: "Minor")
        return requirementCreditBuckets(requirements: reqs)
    }

    /// Credits-based progress for a set of degree requirements.
    ///
    /// This intentionally mirrors the behavior used by Major/Minor Details:
    /// - Required credits: sum per requirement category section (parse from title like "(12 credits)" or fall back to entity creditsRequired)
    /// - Completed credits: sum completed credits for any courses explicitly listed by the requirements
    /// - If any requirement category has no listed courses (open-ended), also count completed unclaimed courses (excluding GenEd)
    private func creditsProgressSummary(requirements: [DegreeRequirementEntity]) -> CreditsProgressSummary {
        // Group requirements by category (section), preserving deterministic ordering.
        func normalizeCategoryKey(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        var byKey: [String: [DegreeRequirementEntity]] = [:]
        var orderedKeys: [String] = []
        for r in requirements {
            let display = (r.requirementCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeCategoryKey(display)
            guard !key.isEmpty else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                orderedKeys.append(key)
            }
            byKey[key, default: []].append(r)
        }

        let sections: [(title: String, requirements: [DegreeRequirementEntity])] = orderedKeys.compactMap { key in
            guard var reqs = byKey[key], !reqs.isEmpty else { return nil }
            reqs.sort { $0.sectionOrder < $1.sectionOrder }
            let title = (reqs.first?.requirementCategory ?? "Requirements").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title: title.isEmpty ? "Requirements" : title, requirements: reqs)
        }

        // Required credits.
        var requiredMin: Double = 0
        for section in sections {
            let req = creditsRequiredMinMaxForCategoryTitle(section.title, requirements: section.requirements)
            requiredMin += req.min
        }

        // Claimed course codes.
        var claimed: Set<String> = []
        for req in requirements {
            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailed = decodeDetailedCourseList(detailedJSON) {
                for d in detailed {
                    let code = normalizeCourseCodeForProgress(d.code)
                    if !code.isEmpty { claimed.insert(code) }
                }
            }

            let requiredCodes: [String] = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { normalizeCourseCodeForProgress(String($0)) }
                .filter { !$0.isEmpty }
            for c in requiredCodes { claimed.insert(c) }

            if let selectDetailedJSON = req.selectFromDetailedJSON,
               let selectDetailed = decodeDetailedCourseList(selectDetailedJSON) {
                for d in selectDetailed {
                    let code = normalizeCourseCodeForProgress(d.code)
                    if !code.isEmpty { claimed.insert(code) }
                }
            }

            let selectCodes = decodeJSONCourseList(req.selectFromJSON)
                .map(normalizeCourseCodeForProgress)
                .filter { !$0.isEmpty }
            for c in selectCodes { claimed.insert(c) }
        }

        // Course completion snapshot (planned courses + completed overrides).
        struct CompletionInfo {
            let isCompleted: Bool
            let credits: Double
            let countsTowardGenEd: Bool
        }

        var completionByCode: [String: CompletionInfo] = [:]

        // Planned courses — a course is treated as completed when its stored flag is
        // true OR when its semester has already passed, matching displayStatus logic.
        let today = Date()
        func semesterHasEnded(_ c: CourseEntity) -> Bool {
            guard let sem = c.semester else { return false }
            let yr = Int(sem.year)
            let month: Int
            switch (sem.season ?? "").lowercased() {
            case "winter": month = 1
            case "spring": month = 5
            case "summer": month = 8
            default:       month = 12
            }
            let end = Calendar.current.date(from: DateComponents(year: yr, month: month, day: 28)) ?? .distantPast
            return end < today
        }

        let plannedCourses = plans.flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
        for c in plannedCourses {
            let code = normalizeCourseCodeForProgress(c.code ?? "")
            guard !code.isEmpty else { continue }
            let credits = Double(c.credits)
            let effectivelyCompleted = c.isCompleted || semesterHasEnded(c)
            completionByCode[code] = CompletionInfo(isCompleted: effectivelyCompleted, credits: credits, countsTowardGenEd: c.countsTowardGenEd)
        }

        // Completed overrides should count even if not in the plan.
        if let university = getActiveUniversity() {
            let oreq = NSFetchRequest<CourseOverrideEntity>(entityName: "CourseOverrideEntity")
            oreq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university == %@", university),
                NSPredicate(format: "status == %@", "Completed"),
                NSPredicate(format: "courseCode != nil")
            ])
            if let overrides = try? viewContext.fetch(oreq) {
                for ov in overrides {
                    let code = normalizeCourseCodeForProgress(ov.courseCode ?? "")
                    guard !code.isEmpty else { continue }
                    let existing = completionByCode[code]
                    let overrideCredits = ov.credits
                    let credits = overrideCredits > 0 ? overrideCredits : (existing?.credits ?? 0)
                    completionByCode[code] = CompletionInfo(isCompleted: true, credits: credits, countsTowardGenEd: existing?.countsTowardGenEd ?? false)
                }
            }
        }

        func completedCredits(for codes: Set<String>) -> Double {
            codes.reduce(0.0) { partial, code in
                guard let info = completionByCode[code], info.isCompleted else { return partial }
                return partial + info.credits
            }
        }

        let completedFromClaimed = completedCredits(for: claimed)

        // If no explicit credit total could be derived from section titles or entity creditsRequired
        // (common for catalogs that omit per-section credit counts), estimate by summing catalog
        // credit hours for every explicitly listed required course.
        if requiredMin == 0, !claimed.isEmpty {
            // Helper: look up catalog credits tolerant of space-stripping in normalizeCourseCodeForProgress.
            // Catalog courseCode is stored as "CSE 191"; our normalized claimed codes are "CSE191".
            // Try the normalized form first, then insert a space before the first digit group as fallback.
            func catalogCreditsForNormalizedCode(_ code: String) -> Double {
                if let cat = getCatalogCourse(code: code), Double(cat.credits) > 0 {
                    return Double(cat.credits)
                }
                // Re-space: "CSE191" → "CSE 191" (inserts space before leading digit run)
                let spaced = code.replacingOccurrences(of: "([A-Za-z]+)(\\d+)",
                                                       with: "$1 $2",
                                                       options: .regularExpression)
                if spaced != code, let cat = getCatalogCourse(code: spaced), Double(cat.credits) > 0 {
                    return Double(cat.credits)
                }
                return 0
            }
            var estimate = 0.0
            for code in claimed {
                if let info = completionByCode[code], info.credits > 0 {
                    estimate += info.credits
                } else {
                    let c = catalogCreditsForNormalizedCode(code)
                    if c > 0 { estimate += c }
                }
            }
            if estimate > 0 { requiredMin = estimate }
        }

        // Open-ended detection: any section with no listed courses.
        _ = sections.contains { section in
            let reqs = section.requirements
            for req in reqs {
                let selectCount = Int(req.selectCount)
                if selectCount > 0 { return false }
                if let detailedJSON = req.requiredCoursesDetailedJSON,
                   let detailed = decodeDetailedCourseList(detailedJSON),
                   detailed.contains(where: { !normalizeCourseCodeForProgress($0.code).isEmpty }) {
                    return false
                }
                let requiredCodes: [String] = (req.requiredCourses ?? "")
                    .split(separator: ",")
                    .map { normalizeCourseCodeForProgress(String($0)) }
                    .filter { !$0.isEmpty }
                if !requiredCodes.isEmpty { return false }
                if let selectDetailedJSON = req.selectFromDetailedJSON,
                   let selectDetailed = decodeDetailedCourseList(selectDetailedJSON),
                   selectDetailed.contains(where: { !normalizeCourseCodeForProgress($0.code).isEmpty }) {
                    return false
                }
                let selectCodes = decodeJSONCourseList(req.selectFromJSON)
                    .map(normalizeCourseCodeForProgress)
                    .filter { !$0.isEmpty }
                if !selectCodes.isEmpty { return false }
            }
            return true
        }

        // Only courses explicitly listed in the degree requirements count toward
        // progress. Open-ended / elective sections that have no enumerated course
        // codes are intentionally excluded — a random CSE course that isn't in the
        // requirements list should not inflate the completion bar.
        let completed = completedFromClaimed
        let fraction = requiredMin > 0 ? min(max(completed / requiredMin, 0), 1) : 0
        return CreditsProgressSummary(completed: completed, required: requiredMin, fraction: fraction)
    }

    func majorRequirementsCreditsProgress(forMajorDisplay majorDisplay: String) -> CreditsProgressSummary {
        var reqs = getDegreeRequirementsForMajorDisplay(majorDisplay)
        // If name-based lookup returned nothing, fall back to URL-based resolution.
        // This handles complex concentration names like "Business Administration BS - MIS Concentration, BS"
        // where the stored major key may not match the display string exactly.
        if reqs.isEmpty {
            let degreeType = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // Prefer the robust multi-pass resolver (resolveSelectedMajorProgramURL) when the
            // requested display name matches the profile's primary major, because that resolver
            // uses the same fuzzy-name logic as the audit panel and is guaranteed to find the
            // same MajorEntity (and thus the same programURL) that the audit checklist uses.
            let profileMajor  = (profile?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedRequest = cleanedProgramNameFromDisplay(majorDisplay)
            let cleanedProfile = cleanedProgramNameFromDisplay(profileMajor)
            let matchesPrimary = !profileMajor.isEmpty &&
                (majorDisplay == profileMajor || cleanedRequest == cleanedProfile)

            let resolvedURL: String?
            if matchesPrimary {
                // Primary major: use the pre-existing robust resolver (preserves existing behaviour).
                resolvedURL = resolveSelectedMajorProgramURL()
            } else {
                // Secondary / other major: use the generalized robust resolver which has the same
                // fuzzy normalized-name fallback so concentration names resolve correctly.
                resolvedURL = resolveNonMinorMajorProgramURL(display: majorDisplay)
            }

            if let programURL = resolvedURL {
                reqs = getDegreeRequirements(programURL: programURL, degreeType: degreeType)
            }
        }
        return creditsProgressSummary(requirements: reqs)
    }

    func aggregateDeclaredProgramsRequirementCredits() -> Double {
        let major = (profile?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var total = 0.0
        if !major.isEmpty {
            total += majorRequirementsCreditsProgress(forMajorDisplay: major).required
        }
        let minor = (profile?.minor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !minor.isEmpty, minor.lowercased() != "none" {
            total += minorRequirementsCreditsProgress(forMinorDisplay: minor).required
        }
        return total
    }

    func getActiveUniversityName() -> String? {
        getActiveUniversity()?.name
    }

    private static let schoolPolicyMetadataDefaultsKey = "coreData.university.schoolPolicyMetadata.v1"

    func activeSchoolPolicyMetadata() -> SchoolPolicyMetadata? {
        guard let university = getActiveUniversity() else { return nil }
        return schoolPolicyMetadata(for: university)
    }

    func schoolPolicyMetadata(for university: UniversityEntity) -> SchoolPolicyMetadata? {
        let keys = [
            university.id?.uuidString,
            university.name
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let dataByKey = UserDefaults.standard.dictionary(forKey: Self.schoolPolicyMetadataDefaultsKey) as? [String: Data] ?? [:]
        for key in keys {
            if let data = dataByKey[key],
               let decoded = try? JSONDecoder().decode(SchoolPolicyMetadata.self, from: data) {
                return decoded
            }
        }
        guard let name = university.name else { return nil }
        return SchoolPolicyMetadataEnricher.metadata(profile: SchoolProfile(
            schoolID: university.id?.uuidString ?? name,
            schoolName: name,
            catalogURL: university.catalogURL ?? "",
            version: "active-university-fallback",
            lastUpdated: Date(),
            courses: [],
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        ))
    }

    func storeSchoolPolicyMetadata(_ metadata: SchoolPolicyMetadata, for university: UniversityEntity? = nil) {
        guard let encoded = try? JSONEncoder().encode(metadata) else { return }
        var dataByKey = UserDefaults.standard.dictionary(forKey: Self.schoolPolicyMetadataDefaultsKey) as? [String: Data] ?? [:]
        let keys = [
            metadata.schoolID,
            metadata.schoolName,
            university?.id?.uuidString,
            university?.name
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for key in Set(keys) where !key.isEmpty {
            dataByKey[key] = encoded
        }
        UserDefaults.standard.set(dataByKey, forKey: Self.schoolPolicyMetadataDefaultsKey)
    }

    func resolvedMajorNames() -> [String] {
        let majors = (profile?.major ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return majors
    }

    func resolvedMinorNames() -> [String] {
        let minors = (profile?.minor ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "none" }
        return minors
    }

    static func isUnusableCatalogDescription(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        return lower == "n/a" || lower == "na" || lower == "none" || lower == "tbd"
    }

    func archiveCourse(_ course: CourseEntity) {
        course.setValue(true, forKey: "isArchived")
        save()
    }

    func activeUniversityCatalogCourseCount() -> Int {
        guard let university = getActiveUniversity() else { return 0 }
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(format: "university == %@", university)
        return (try? viewContext.count(for: request)) ?? 0
    }

    func minorRequirementsCreditsProgress(forMinorDisplay minorDisplay: String) -> CreditsProgressSummary {
        let trimmed = minorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else {
            return CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
        }
        guard let programURL = resolveProgramProgramURL(programDisplay: trimmed, isMinor: true) else {
            return CreditsProgressSummary(completed: 0, required: 0, fraction: 0)
        }
        let reqs = getDegreeRequirements(programURL: programURL, degreeType: "Minor")
        return creditsProgressSummary(requirements: reqs)
    }

    /// Background computation for multiple majors to keep the Degree sidebar responsive.
    func computeMajorRequirementsCreditsProgressSummariesAsync(
        majorDisplays: [String],
        degreeTypeRaw: String
    ) async -> [String: CreditsProgressSummary] {
        let trimmedDegreeType = degreeTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputDisplays = majorDisplays
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !inputDisplays.isEmpty else { return [:] }

        let container = self.container

        let sendableDecodeDetailed: @Sendable (String?) -> [CourseDetail]? = { json in
            guard let json, !json.isEmpty else { return nil }
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([CourseDetail].self, from: data)
        }
        let sendableDecodeJSON: @Sendable (String?) -> [String] = { json in
            guard let json, !json.isEmpty else { return [] }
            guard let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        let sendableDegreeTypeCandidates: @Sendable (String) -> [String] = { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            var candidates: [String] = [trimmed]
            let splitParts = trimmed
                .replacingOccurrences(of: " ", with: "")
                .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            if splitParts.count >= 2 { candidates.append(contentsOf: splitParts) }
            if let open = trimmed.firstIndex(of: "("),
               let close = trimmed.firstIndex(of: ")"),
               open < close {
                let inner = String(trimmed[trimmed.index(after: open)..<close])
                let innerParts = inner
                    .replacingOccurrences(of: " ", with: "")
                    .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
                    .map { String($0) }
                    .filter { !$0.isEmpty }
                if !innerParts.isEmpty { candidates.append(contentsOf: innerParts) }
            }
            var seen: Set<String> = []
            var unique: [String] = []
            for c in candidates where !c.isEmpty {
                if seen.insert(c.lowercased()).inserted { unique.append(c) }
            }
            return unique
        }
        let sendableCleanedProgramName: @Sendable (String) -> String = { display in
            let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return trimmed }
            if let comma = trimmed.lastIndex(of: ",") {
                let suffix = trimmed[trimmed.index(after: comma)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if suffix.count <= 8,
                   suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                    return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return trimmed
            }
            let candidates = sendableDegreeTypeCandidates(trimmedDegreeType)
            guard !candidates.isEmpty else { return trimmed }
            let normalizedDisplay = trimmed.replacingOccurrences(of: ".", with: "")
            for token in candidates.sorted(by: { $0.count > $1.count }) {
                let normalizedToken = token.replacingOccurrences(of: ".", with: "")
                if normalizedToken.isEmpty { continue }
                let pattern = "\\s+" + NSRegularExpression.escapedPattern(for: normalizedToken) + "$"
                if normalizedDisplay.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    if let lastSpace = trimmed.lastIndex(of: " ") {
                        return String(trimmed[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return trimmed
        }

        return await withCheckedContinuation { continuation in
            let ctx = container.newBackgroundContext()
            ctx.name = "coreData.computeMajorReqCreditsProgress"
            ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

            ctx.perform {
                // Resolve active university deterministically.
                let ureq = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
                ureq.predicate = NSPredicate(format: "isActive == YES")
                ureq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                let university = (try? ctx.fetch(ureq))?.first
                guard let university else {
                    continuation.resume(returning: [:])
                    return
                }

                func normalizeCode(_ raw: String) -> String {
                    raw
                        .replacingOccurrences(of: "\u{00A0}", with: " ")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                }

                // Completion snapshot.
                struct CompletionInfo {
                    let isCompleted: Bool
                    let credits: Double
                    let countsTowardGenEd: Bool
                }
                var completionByCode: [String: CompletionInfo] = [:]

                let today = Date()
                func semesterHasEnded(_ c: CourseEntity) -> Bool {
                    guard let sem = c.semester else { return false }
                    let yr = Int(sem.year)
                    let month: Int
                    switch (sem.season ?? "").lowercased() {
                    case "winter": month = 1
                    case "spring": month = 5
                    case "summer": month = 8
                    default:       month = 12
                    }
                    let end = Calendar.current.date(from: DateComponents(year: yr, month: month, day: 28)) ?? .distantPast
                    return end < today
                }

                let creq = NSFetchRequest<CourseEntity>(entityName: "CourseEntity")
                creq.predicate = NSPredicate(format: "code != nil")
                if let courses = try? ctx.fetch(creq) {
                    for c in courses {
                        let code = normalizeCode(c.code ?? "")
                        guard !code.isEmpty else { continue }
                        let effectivelyCompleted = c.isCompleted || semesterHasEnded(c)
                        completionByCode[code] = CompletionInfo(
                            isCompleted: effectivelyCompleted,
                            credits: Double(c.credits),
                            countsTowardGenEd: c.countsTowardGenEd
                        )
                    }
                }

                let oreq = NSFetchRequest<CourseOverrideEntity>(entityName: "CourseOverrideEntity")
                oreq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "university == %@", university),
                    NSPredicate(format: "status == %@", "Completed"),
                    NSPredicate(format: "courseCode != nil")
                ])
                if let overrides = try? ctx.fetch(oreq) {
                    for ov in overrides {
                        let code = normalizeCode(ov.courseCode ?? "")
                        guard !code.isEmpty else { continue }
                        let existing = completionByCode[code]
                        let overrideCredits = ov.credits
                        let credits = overrideCredits > 0 ? overrideCredits : (existing?.credits ?? 0)
                        completionByCode[code] = CompletionInfo(
                            isCompleted: true,
                            credits: credits,
                            countsTowardGenEd: existing?.countsTowardGenEd ?? false
                        )
                    }
                }

                // Parse credits requirements from category titles.
                func parseCreditsRequirementFromTitle(_ title: String) -> (min: Double, max: Double?)? {
                    let pattern = #"\((\d+(?:\.\d+)?)\s*(?:[-–]\s*(\d+(?:\.\d+)?))?\s*credits?\)"#
                    guard let re = Self.cachedRegex(pattern, options: [.caseInsensitive]) else { return nil }
                    let ns = NSRange(title.startIndex..<title.endIndex, in: title)
                    guard let m = re.firstMatch(in: title, options: [], range: ns) else { return nil }
                    func capture(_ idx: Int) -> String? {
                        guard m.numberOfRanges > idx else { return nil }
                        let r = m.range(at: idx)
                        guard r.location != NSNotFound, let rr = Range(r, in: title) else { return nil }
                        return String(title[rr])
                    }
                    guard let a = capture(1), let min = Double(a) else { return nil }
                    let max = capture(2).flatMap(Double.init)
                    return (min: min, max: max)
                }

                func normalizeCategoryKey(_ raw: String) -> String {
                    raw
                        .replacingOccurrences(of: "\u{00A0}", with: " ")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                }

                func creditsRequiredMinForCategoryTitle(_ title: String, requirements: [DegreeRequirementEntity]) -> Double {
                    if let parsed = parseCreditsRequirementFromTitle(title) {
                        return parsed.min
                    }
                    if let firstNonZero = requirements.first(where: { $0.creditsRequired > 0 }) {
                        return Double(firstNonZero.creditsRequired)
                    }
                    return 0
                }

                func claimedCourseCodes(in requirements: [DegreeRequirementEntity]) -> Set<String> {
                    var out: Set<String> = []
                    for req in requirements {
                        if let detailed = sendableDecodeDetailed(req.requiredCoursesDetailedJSON) {
                            for d in detailed {
                                let code = normalizeCode(d.code)
                                if !code.isEmpty { out.insert(code) }
                            }
                        }
                        let requiredCodes: [String] = (req.requiredCourses ?? "")
                            .split(separator: ",")
                            .map { normalizeCode(String($0)) }
                            .filter { !$0.isEmpty }
                        for c in requiredCodes { out.insert(c) }
                        if let detailed = sendableDecodeDetailed(req.selectFromDetailedJSON) {
                            for d in detailed {
                                let code = normalizeCode(d.code)
                                if !code.isEmpty { out.insert(code) }
                            }
                        }
                        let selectCodes = sendableDecodeJSON(req.selectFromJSON)
                            .map(normalizeCode)
                            .filter { !$0.isEmpty }
                        for c in selectCodes { out.insert(c) }
                    }
                    return out
                }

                func openEndedExists(sections: [(title: String, requirements: [DegreeRequirementEntity])]) -> Bool {
                    for section in sections {
                        let reqs = section.requirements
                        var hasAnyCourseCode = false
                        for req in reqs {
                            if Int(req.selectCount) > 0 { hasAnyCourseCode = true; break }
                            if let detailed = sendableDecodeDetailed(req.requiredCoursesDetailedJSON),
                               detailed.contains(where: { !normalizeCode($0.code).isEmpty }) { hasAnyCourseCode = true; break }
                            let requiredCodes: [String] = (req.requiredCourses ?? "")
                                .split(separator: ",")
                                .map { normalizeCode(String($0)) }
                                .filter { !$0.isEmpty }
                            if !requiredCodes.isEmpty { hasAnyCourseCode = true; break }
                            if let detailed = sendableDecodeDetailed(req.selectFromDetailedJSON),
                               detailed.contains(where: { !normalizeCode($0.code).isEmpty }) { hasAnyCourseCode = true; break }
                            let selectCodes = sendableDecodeJSON(req.selectFromJSON)
                                .map(normalizeCode)
                                .filter { !$0.isEmpty }
                            if !selectCodes.isEmpty { hasAnyCourseCode = true; break }
                        }
                        if !hasAnyCourseCode { return true }
                    }
                    return false
                }

                func creditsProgressSummary(requirements: [DegreeRequirementEntity]) -> CreditsProgressSummary {
                    var byKey: [String: [DegreeRequirementEntity]] = [:]
                    var orderedKeys: [String] = []
                    for r in requirements {
                        let display = (r.requirementCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let key = normalizeCategoryKey(display)
                        guard !key.isEmpty else { continue }
                        if byKey[key] == nil { byKey[key] = []; orderedKeys.append(key) }
                        byKey[key, default: []].append(r)
                    }

                    let sections: [(title: String, requirements: [DegreeRequirementEntity])] = orderedKeys.compactMap { key in
                        guard var reqs = byKey[key], !reqs.isEmpty else { return nil }
                        reqs.sort { $0.sectionOrder < $1.sectionOrder }
                        let title = (reqs.first?.requirementCategory ?? "Requirements").trimmingCharacters(in: .whitespacesAndNewlines)
                        return (title: title.isEmpty ? "Requirements" : title, requirements: reqs)
                    }

                    var requiredMin: Double = 0
                    for section in sections {
                        requiredMin += creditsRequiredMinForCategoryTitle(section.title, requirements: section.requirements)
                    }

                    let claimed = claimedCourseCodes(in: requirements)

                    let completedFromClaimed: Double = claimed.reduce(0.0) { partial, code in
                        guard let info = completionByCode[code], info.isCompleted else { return partial }
                        return partial + info.credits
                    }

                    // Only count credits for courses explicitly listed in the requirements.
                    // Unclaimed courses (open-ended elective slots) are excluded so that
                    // arbitrary department courses never inflate the completion bar.
                    let completed = completedFromClaimed
                    let fraction = requiredMin > 0 ? min(max(completed / requiredMin, 0), 1) : 0
                    return CreditsProgressSummary(completed: completed, required: requiredMin, fraction: fraction)
                }

                var candidates = sendableDegreeTypeCandidates(trimmedDegreeType)
                if !trimmedDegreeType.isEmpty, !candidates.contains(trimmedDegreeType) {
                    candidates.insert(trimmedDegreeType, at: 0)
                }

                func fetchRequirements(for majorDisplay: String) -> [DegreeRequirementEntity] {
                    let cleaned = sendableCleanedProgramName(majorDisplay)
                    let majorKey = cleaned.isEmpty ? majorDisplay : cleaned
                    if majorKey.isEmpty { return [] }

                    func fetch(matchingDegreeTypes: [String]?) -> [DegreeRequirementEntity] {
                        let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
                        var preds: [NSPredicate] = [
                            NSPredicate(format: "university == %@", university),
                            NSPredicate(format: "major == %@", majorKey)
                        ]
                        if let matchingDegreeTypes, !matchingDegreeTypes.isEmpty {
                            let degreePreds = matchingDegreeTypes.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                            preds.append(NSCompoundPredicate(orPredicateWithSubpredicates: degreePreds))
                        }
                        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
                        request.sortDescriptors = [
                            NSSortDescriptor(key: "sectionOrder", ascending: true),
                            NSSortDescriptor(key: "requirementCategory", ascending: true)
                        ]
                        return (try? ctx.fetch(request)) ?? []
                    }

                    if !candidates.isEmpty {
                        let exactish = fetch(matchingDegreeTypes: candidates)
                        if !exactish.isEmpty { return exactish }
                    }
                    return fetch(matchingDegreeTypes: nil)
                }

                var out: [String: CreditsProgressSummary] = [:]
                for display in inputDisplays {
                    let reqs = fetchRequirements(for: display)
                    out[display] = creditsProgressSummary(requirements: reqs)
                }
                continuation.resume(returning: out)
            }
        }
    }
}

// MARK: - Extensions for convenience
extension SemesterEntity {
    var coursesArray: [CourseEntity] {
        let set = courses as? Set<CourseEntity> ?? []
        return set.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return ($0.code ?? "") < ($1.code ?? "")
        }
    }
    
    var totalCredits: Int {
        coursesArray
            .filter { c in
                let s = (c.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return s != "Dropped" && s != "Not Planned" && s != "Failed"
            }
            .reduce(0) { $0 + Int($1.credits) }
    }
    
    var progress: Double {
        let total = totalCredits
        guard total > 0 else { return 0.0 }
        let completed = coursesArray
            .filter { $0.isCompleted }
            .reduce(0) { $0 + Int($1.credits) }
        return Double(completed) / Double(total)
    }
}

extension PlanEntity {
    var semestersArray: [SemesterEntity] {
        let set = semesters as? Set<SemesterEntity> ?? []
        return set.sorted {
            if $0.year != $1.year {
                return $0.year < $1.year
            }
            return $0.seasonOrder < $1.seasonOrder
        }
    }
}

extension CourseEntity {
    var creditsInt: Int {
        return Int(credits)
    }
}

extension ProfileEntity {
    var experiencesArray: [ExperienceEntity] {
        let set = experiences as? Set<ExperienceEntity> ?? []
        return set.sorted { ($0.startDate ?? Date()) > ($1.startDate ?? Date()) }
    }
    
    var achievementsArray: [AchievementEntity] {
        let set = achievements as? Set<AchievementEntity> ?? []
        return set.sorted { ($0.dateReceived ?? Date()) > ($1.dateReceived ?? Date()) }
    }
}

// MARK: - School Catalog Import (GitHub → Core Data)
extension CoreDataManager {
    func setActivePlan(_ plan: PlanEntity?) {
        activePlanObjectID = plan?.objectID
    }

    func getActivePlan() -> PlanEntity? {
        if let id = activePlanObjectID,
           let plan = try? viewContext.existingObject(with: id) as? PlanEntity {
            return plan
        }
        return plans.last
    }

    private func ensureDefaultPlanExists() -> PlanEntity {
        if let existing = getActivePlan() { return existing }
        if let any = plans.last { return any }

        let plan = addPlan(
            name: "My Plan",
            type: "Bachelors",
            major: profile?.major ?? "",
            minor: profile?.minor ?? "",
            concentration: ""
        )
        fetchPlans()
        setActivePlan(plan)
        return plan
    }

    private func parseSemesterText(_ text: String) -> (season: String, year: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let seasons = ["fall", "spring", "summer", "winter"]
        guard let seasonToken = seasons.first(where: { lower.contains($0) }) else { return nil }

        let year: Int? = {
            // Prefer 4-digit year.
                if let re = Self.cachedRegex("\\b(\\d{4})\\b"),
               let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)),
               let r = Range(m.range(at: 1), in: lower) {
                return Int(lower[r])
            }
            // Fallback to 2-digit year.
                if let re = Self.cachedRegex("\\b(\\d{2})\\b"),
               let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)),
               let r = Range(m.range(at: 1), in: lower),
               let yy = Int(lower[r]) {
                return 2000 + yy
            }
            return nil
        }()

        guard let year, year > 0 else { return nil }

        let season = seasonToken.prefix(1).uppercased() + seasonToken.dropFirst()
        return (season, year)
    }

    func ensureCourseScheduledInPlanner(
        courseCode: String,
        courseName: String,
        creditsText: String,
        semesterText: String,
        status: String,
        gradingType: String,
        professor: String?
    ) {
        let normalizedCode = normalizeCourseCode(courseCode)
        guard !normalizedCode.isEmpty else { return }
        guard let parsed = parseSemesterText(semesterText) else { return }

        let plan = ensureDefaultPlanExists()

        let semester: SemesterEntity = {
            if let existing = plan.semestersArray.first(where: {
                Int($0.year) == parsed.year && ($0.season ?? "").caseInsensitiveCompare(parsed.season) == .orderedSame
            }) {
                existing.isPlanned = true
                return existing
            }
            return addSemester(to: plan, name: "\(parsed.season) \(parsed.year)", year: parsed.year, season: parsed.season)
        }()

        let finalStatus: String = {
            let s = status.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? "Not Planned" : s
        }()

        if let existing = plannedCourse(for: normalizedCode) {
            existing.semester = semester
            existing.status = finalStatus
            existing.gradingType = gradingType
            existing.professor = professor

            if (existing.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if Int(existing.credits) <= 0 {
                let parsedCredits = Int((Double(creditsText) ?? 0).rounded())
                if parsedCredits > 0 {
                    existing.credits = Int16(parsedCredits)
                } else if let catalog = getCatalogCourse(code: normalizedCode), Int(catalog.credits) > 0 {
                    existing.credits = catalog.credits
                }
            }

            if existing.catalogCourse == nil {
                existing.catalogCourse = getCatalogCourse(code: normalizedCode)
            }

            updateCourse(existing)
            return
        }

        let parsedCredits = Int((Double(creditsText) ?? 0).rounded())
        let catalog = getCatalogCourse(code: normalizedCode)
        let credits = parsedCredits > 0 ? parsedCredits : Int(catalog?.credits ?? 0)
        let name = {
            let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }
            return (catalog?.title ?? normalizedCode).trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let newCourse = addCourse(
            to: semester,
            code: normalizedCode,
            name: name,
            credits: max(0, credits),
            status: finalStatus,
            gradingType: gradingType,
            professor: professor
        )
        newCourse.catalogCourse = catalog
        save()
    }

    /// Import full school catalog from SchoolProfile JSON into Core Data
    /// This makes the local database the source of truth
    func importSchoolCatalog(_ schoolProfile: SchoolProfile) async throws {
        let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "College", category: "CoreDataImport")
        let spid = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ImportSchoolCatalog", signpostID: spid, "school=%{public}@ courses=%{public}d", schoolProfile.schoolName, schoolProfile.courses.count)
        defer { os_signpost(.end, log: log, name: "ImportSchoolCatalog", signpostID: spid) }
        storeSchoolPolicyMetadata(SchoolPolicyMetadataEnricher.metadata(profile: schoolProfile))

        // Run import work on a private queue context to avoid blocking UI and to satisfy Core Data confinement.
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        let (coursesNeedingLLM, batchInsertedCourseObjectIDs) = try await context.perform { () throws -> ([(courseObjectID: NSManagedObjectID, text: String, courseCode: String)], [NSManagedObjectID]) in
            // Initialize services within the context-perform closure to avoid Sendable captures.
            let intelligenceService = IntelligenceService()
            let catalogValidator = CatalogPrerequisiteValidator(context: context)

            // Track courses that need LLM processing.
            var coursesNeedingLLM: [(courseObjectID: NSManagedObjectID, text: String, courseCode: String)] = []

            // Track objectIDs inserted via NSBatchInsertRequest so we can merge them into viewContext.
            var batchInsertedCourseObjectIDs: [NSManagedObjectID] = []

            func normalize(_ value: String?) -> String {
                (value ?? "")
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            func normalizeCourseCode(_ raw: String) -> String {
                let cleaned = raw
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()

                if let re = Self.cachedRegex("\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4})\\b") {
                    let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                    if let m = re.firstMatch(in: cleaned, range: nsRange), m.numberOfRanges >= 3,
                       let r1 = Range(m.range(at: 1), in: cleaned),
                       let r2 = Range(m.range(at: 2), in: cleaned) {
                        return "\(cleaned[r1]) \(cleaned[r2])"
                    }
                }

                return cleaned
            }

            struct BatchCourseInsert {
                let courseCode: String
                let title: String
                let descriptionText: String?
                let credits: Int16
                let creditsValue: Double?
                let department: String?
                let departmentEntity: DepartmentEntity?
                let prerequisiteCodes: String?
                let prerequisiteRulesJSON: String?
                let prerequisiteParsingStatus: String?
                let prerequisiteValidationStatus: String?
                let prerequisiteConfidence: String?
                let invalidPrerequisiteCodes: String?
                let corequisiteCodes: String?
                let typicallyOffered: String?
                let lastUpdated: Date
            }

            func isInvalidCatalogDescription(_ value: String) -> Bool {
                let lower = value
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if lower.isEmpty { return true }
                if lower.contains("resource not found") && (lower.contains("unable to locate the resource") || lower.contains("we were unable to locate")) {
                    return true
                }
                if lower.contains("home page") && lower.contains("search page") && lower.contains("unable to locate") {
                    return true
                }
                if lower.contains("print-friendly page") && (lower.contains("undergraduate catalog") || lower.contains("graduate catalog")) {
                    return true
                }
                return false
            }

            func sanitizeCatalogDescription(_ value: String, courseCode: String, title: String) -> String {
                func collapse(_ s: String) -> String {
                    s
                        .replacingOccurrences(of: "\u{00A0}", with: " ")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                func stripLeadingPunctuation(_ s: Substring) -> String {
                    var out = String(s)
                    out = out.replacingOccurrences(of: "^[\u{00A0}\t –—:;.,-]+", with: "", options: .regularExpression)
                    out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    return out.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                var cleaned = collapse(value)
                guard !cleaned.isEmpty else { return "" }

                let normalizedTitle = collapse(title)
                let normalizedCode = collapse(courseCode)

                // 1) Strip a leading "CODE - TITLE" header when present.
                if !normalizedCode.isEmpty {
                    if let codeRange = cleaned.range(of: normalizedCode, options: [.caseInsensitive, .anchored]) {
                        let afterCode = cleaned[codeRange.upperBound...]
                        if !normalizedTitle.isEmpty,
                           let titleRange = afterCode.range(of: normalizedTitle, options: [.caseInsensitive]) {
                            let afterTitle = afterCode[titleRange.upperBound...]
                            let stripped = stripLeadingPunctuation(afterTitle)
                            if !stripped.isEmpty { cleaned = stripped }
                        } else {
                            // Common form: "CODE. Description" or "CODE - Description"
                            let stripped = stripLeadingPunctuation(afterCode)
                            if !stripped.isEmpty { cleaned = stripped }
                        }
                    }
                }

                // 2) If description begins with the title itself, strip it.
                if !normalizedTitle.isEmpty,
                   let titleRange = cleaned.range(of: normalizedTitle, options: [.caseInsensitive, .anchored]) {
                    let afterTitle = cleaned[titleRange.upperBound...]
                    let stripped = stripLeadingPunctuation(afterTitle)
                    if !stripped.isEmpty { cleaned = stripped }
                }

                // 3) Handle Acalog print-friendly/header artifacts.
                let lower = cleaned.lowercased()
                if lower.contains("print-friendly page") || lower.hasPrefix("help ") {
                    if !normalizedCode.isEmpty,
                       let r = cleaned.range(of: normalizedCode, options: [.caseInsensitive]) {
                        var after = cleaned[r.upperBound...]
                        if let dash = after.range(of: "[-–—]", options: .regularExpression) {
                            after = after[dash.upperBound...]
                        }
                        let stripped = stripLeadingPunctuation(after)
                        if !stripped.isEmpty { cleaned = stripped }
                    }
                }

                return cleaned
            }

            func extractCreditsFromTitleAndClean(_ rawTitle: String) -> (cleanTitle: String, extractedCredits: Double?) {
                var title = rawTitle
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !title.isEmpty else { return ("", nil) }

                // Look for patterns like "0.5", "1.5" at the end of the title, optionally in parentheses
                // and optionally followed by a units token.
                let patterns = [
                    "(?i)\\(\\s*(\\d+\\.5)\\s*(credits?|cr\\.?|units?)?\\s*\\)$",
                    "(?i)\\b(\\d+\\.5)\\b\\s*(credits?|cr\\.?|units?)?\\s*$"
                ]

                for p in patterns {
                      guard let re = Self.cachedRegex(p) else { continue }
                    let nsRange = NSRange(title.startIndex..<title.endIndex, in: title)
                    guard let m = re.firstMatch(in: title, range: nsRange), m.numberOfRanges >= 2,
                          let valRange = Range(m.range(at: 1), in: title) else { continue }
                    let valStr = String(title[valRange])
                    guard let val = Double(valStr) else { continue }

                    if let fullRange = Range(m.range(at: 0), in: title) {
                        title.removeSubrange(fullRange)
                    }
                    title = title
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return (title, val)
                }

                return (title, nil)
            }

            // 1) Create or update UniversityEntity
            let universityRequest = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
            universityRequest.predicate = NSPredicate(format: "name == %@", schoolProfile.schoolName)
            universityRequest.fetchLimit = 1

            let university: UniversityEntity
            if let existing = try context.fetch(universityRequest).first {
                university = existing
                #if DEBUG
                DebugLogger.shared.coreData("Updating existing university: \(schoolProfile.schoolName)")
                #endif
            } else {
                university = UniversityEntity(context: context)
                university.id = UUID()
                university.name = schoolProfile.schoolName
                #if DEBUG
                DebugLogger.shared.coreData("Creating new university: \(schoolProfile.schoolName)")
                #endif
            }

            university.catalogURL = schoolProfile.catalogURL
            university.lastCatalogSync = Date()
            university.catalogFormat = "github"

            // 2) Pre-fetch departments for quick linking
            let deptRequest = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
            deptRequest.predicate = NSPredicate(format: "university == %@", university)
            deptRequest.fetchBatchSize = 500
            deptRequest.returnsObjectsAsFaults = true
            let depts = (try? context.fetch(deptRequest)) ?? []

            func deptKey(_ s: String) -> String {
                normalize(s).lowercased()
            }

            var departmentLookup: [String: DepartmentEntity] = [:]
            departmentLookup.reserveCapacity(depts.count * 2)
            for d in depts {
                if let name = d.name as String? {
                    let k = deptKey(name)
                    if !k.isEmpty { departmentLookup[k] = d }
                }
                if let code = d.code, !code.isEmpty {
                    let k = deptKey(code)
                    if !k.isEmpty { departmentLookup[k] = d }
                }
            }

            // 3) Lightweight existence check: fetch only courseCode + objectID.
            //    Full CourseCatalogEntity objects are faulted in on-demand only when we need to update them.
            //    For catalogs with 5,000+ courses this avoids pre-loading hundreds of MB of Core Data state
            //    just to check which course codes already exist.
            let codesRequest = NSFetchRequest<NSDictionary>(entityName: "CourseCatalogEntity")
            codesRequest.resultType = .dictionaryResultType
            codesRequest.predicate = NSPredicate(format: "university == %@", university)
            let oidExpr = NSExpressionDescription()
            oidExpr.name = "objectID"
            oidExpr.expression = NSExpression.expressionForEvaluatedObject()
            oidExpr.expressionResultType = .objectIDAttributeType
            codesRequest.propertiesToFetch = ["courseCode", oidExpr]
            let existingDicts = (try? context.fetch(codesRequest)) ?? []

            // courseCode (normalized) → NSManagedObjectID for O(1) lookups during the import loop.
            var existingByCode: [String: NSManagedObjectID] = [:]
            existingByCode.reserveCapacity(existingDicts.count)
            for dict in existingDicts {
                if let code = dict["courseCode"] as? String,
                   let oid  = dict["objectID"] as? NSManagedObjectID {
                    existingByCode[normalizeCourseCode(code)] = oid
                }
            }

            // Track scraped codes for ghost detection
            let scrapedCourseCodes = Set(schoolProfile.courses.map { normalizeCourseCode($0.courseCode) })

            // 4) De-dupe incoming courses upfront by normalized key
            var incomingByCode: [String: CatalogCourse] = [:]
            incomingByCode.reserveCapacity(schoolProfile.courses.count)

            func incomingQuality(_ c: CatalogCourse) -> Int {
                var score = 0
                if !normalize(c.title).isEmpty { score += 2 }
                if c.credits > 0 { score += 2 }
                if !normalize(c.description).isEmpty { score += 2 }
                if c.prerequisites != nil || !(normalize(c.prerequisiteText).isEmpty) { score += 1 }
                if !normalize(c.department).isEmpty { score += 1 }
                return score
            }

            for c in schoolProfile.courses {
                let key = normalizeCourseCode(c.courseCode)
                if let existing = incomingByCode[key] {
                    if incomingQuality(c) > incomingQuality(existing) {
                        incomingByCode[key] = c
                    }
                } else {
                    incomingByCode[key] = c
                }
            }

            let incomingCourses = Array(incomingByCode.values)
            #if DEBUG
            DebugLogger.shared.coreData("Importing \(incomingCourses.count) unique courses (raw=\(schoolProfile.courses.count))")
            #endif

            // 5) Import courses in chunks with periodic saves to keep memory stable
            let chunkSize = 2_000
            var processed = 0

            for chunkStart in stride(from: 0, to: incomingCourses.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, incomingCourses.count)
                let chunk = incomingCourses[chunkStart..<chunkEnd]

                var batchInserts: [BatchCourseInsert] = []
                batchInserts.reserveCapacity(chunk.count)

                autoreleasepool {
                    for catalogCourse in chunk {
                        let courseKey = normalizeCourseCode(catalogCourse.courseCode)

                        let course: CourseCatalogEntity
                        if let existingOID = existingByCode[courseKey],
                           let existing = context.object(with: existingOID) as? CourseCatalogEntity {
                            course = existing
                            course.isArchived = false
                            // Keep stored code canonical so uniqueness constraints are effective.
                            if course.courseCode != courseKey {
                                course.courseCode = courseKey
                            }
                        } else {
                            // For new courses, prefer NSBatchInsertRequest for speed when we don't need the objectID.
                            // If the course needs LLM processing, we create it normally so we can queue its objectID.
                            let extracted = extractCreditsFromTitleAndClean(catalogCourse.title)
                            let incomingTitle = normalize(extracted.cleanTitle)
                            let incomingDescriptionRaw = normalize(catalogCourse.description)
                            let incomingDescription = sanitizeCatalogDescription(incomingDescriptionRaw, courseCode: catalogCourse.courseCode, title: catalogCourse.title)
                            let incomingDepartment = normalize(catalogCourse.department)
                            let incomingCredits = catalogCourse.credits
                            let incomingCreditsValue: Double? = extracted.extractedCredits ?? (incomingCredits > 0 ? Double(incomingCredits) : nil)

                            let titleIsGood = !incomingTitle.isEmpty && incomingTitle.caseInsensitiveCompare(courseKey) != .orderedSame
                            let finalTitle = titleIsGood ? incomingTitle : courseKey
                            let descriptionIsInvalid = isInvalidCatalogDescription(incomingDescription)
                            let finalDescription: String? = descriptionIsInvalid ? nil : incomingDescription
                            let finalDepartment: String? = incomingDepartment.isEmpty ? nil : incomingDepartment
                            let finalCredits: Int16 = incomingCredits > 0 ? Int16(incomingCredits) : Int16(0)

                            var prerequisiteCodes: String? = nil
                            var prerequisiteRulesJSON: String? = nil
                            var prerequisiteParsingStatus: String? = nil
                            var prerequisiteValidationStatus: String? = nil
                            var prerequisiteConfidence: String? = nil
                            var invalidPrerequisiteCodes: String? = nil

                            if let prereqRule = catalogCourse.prerequisites {
                                let encoder = JSONEncoder()
                                if let jsonData = try? encoder.encode(prereqRule),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    prerequisiteRulesJSON = jsonString
                                    prerequisiteCodes = CoreDataManager.extractCourseCodesFromPrereqs(prereqRule)

                                    let validationResult = catalogValidator.validate(
                                        rule: prereqRule,
                                        forUniversity: schoolProfile.schoolName,
                                        courseCode: courseKey
                                    )

                                    prerequisiteValidationStatus = validationResult.isValid ? "valid" : "invalid"
                                    prerequisiteConfidence = CoreDataManager.confidenceToString(validationResult.confidence)
                                    invalidPrerequisiteCodes = validationResult.invalidCourseCodes.joined(separator: ", ")
                                    prerequisiteParsingStatus = "parsed"
                                }
                            } else if let prereqText = catalogCourse.prerequisiteText {
                                let (parsedRule, needsLLM, _) = intelligenceService.parsePrerequisite(
                                    prereqText,
                                    courseCode: courseKey
                                )

                                if let rule = parsedRule {
                                    let encoder = JSONEncoder()
                                    if let jsonData = try? encoder.encode(rule),
                                       let jsonString = String(data: jsonData, encoding: .utf8) {
                                        prerequisiteRulesJSON = jsonString
                                        prerequisiteCodes = CoreDataManager.extractCourseCodesFromPrereqs(rule)

                                        let validationResult = catalogValidator.validate(
                                            rule: rule,
                                            forUniversity: schoolProfile.schoolName,
                                            courseCode: courseKey
                                        )

                                        prerequisiteValidationStatus = validationResult.isValid ? "valid" : "invalid"
                                        prerequisiteConfidence = CoreDataManager.confidenceToString(validationResult.confidence)
                                        invalidPrerequisiteCodes = validationResult.invalidCourseCodes.joined(separator: ", ")
                                        prerequisiteParsingStatus = "parsed"
                                    }
                                } else if needsLLM {
                                    // Needs objectID later, so create normally.
                                    course = CourseCatalogEntity(context: context)
                                    course.id = UUID()
                                    course.courseCode = courseKey
                                    course.university = university
                                    course.isArchived = false
                                    existingByCode[courseKey] = course.objectID

                                    course.title = finalTitle
                                    course.descriptionText = finalDescription
                                    course.credits = finalCredits
                                    course.creditsValue = incomingCreditsValue ?? Double(finalCredits)
                                    course.department = finalDepartment
                                    course.lastUpdated = Date()

                                    if let dept = finalDepartment {
                                        let key = deptKey(dept)
                                        if let deptEntity = departmentLookup[key] {
                                            course.departmentEntity = deptEntity
                                        }
                                    }

                                    course.prerequisiteParsingStatus = "pending_llm"
                                    course.prerequisiteCodes = prereqText
                                    coursesNeedingLLM.append((courseObjectID: course.objectID, text: prereqText, courseCode: courseKey))

                                    // Register the new objectID so subsequent iterations don't re-insert the same course.
                                    existingByCode[courseKey] = course.objectID

                                    if let coreqs = catalogCourse.corequisites {
                                        course.corequisiteCodes = coreqs.joined(separator: ", ")
                                    }
                                    if let offered = catalogCourse.typicallyOffered {
                                        course.typicallyOffered = offered.joined(separator: ", ")
                                    }

                                    continue
                                } else {
                                    prerequisiteParsingStatus = "failed"
                                    prerequisiteCodes = prereqText
                                }
                            }

                            let corequisiteCodes = catalogCourse.corequisites?.joined(separator: ", ")
                            let typicallyOffered = catalogCourse.typicallyOffered?.joined(separator: ", ")

                            var deptEntity: DepartmentEntity? = nil
                            if let dept = finalDepartment {
                                let key = deptKey(dept)
                                deptEntity = departmentLookup[key]
                            }

                            batchInserts.append(
                                BatchCourseInsert(
                                    courseCode: courseKey,
                                    title: finalTitle,
                                    descriptionText: finalDescription,
                                    credits: finalCredits,
                                    creditsValue: incomingCreditsValue,
                                    department: finalDepartment,
                                    departmentEntity: deptEntity,
                                    prerequisiteCodes: prerequisiteCodes,
                                    prerequisiteRulesJSON: prerequisiteRulesJSON,
                                    prerequisiteParsingStatus: prerequisiteParsingStatus,
                                    prerequisiteValidationStatus: prerequisiteValidationStatus,
                                    prerequisiteConfidence: prerequisiteConfidence,
                                    invalidPrerequisiteCodes: invalidPrerequisiteCodes,
                                    corequisiteCodes: corequisiteCodes,
                                    typicallyOffered: typicallyOffered,
                                    lastUpdated: Date()
                                )
                            )

                            continue
                        }

                        let extracted = extractCreditsFromTitleAndClean(catalogCourse.title)
                        let incomingTitle = normalize(extracted.cleanTitle)
                        let incomingDescriptionRaw = normalize(catalogCourse.description)
                        let incomingDescription = sanitizeCatalogDescription(incomingDescriptionRaw, courseCode: catalogCourse.courseCode, title: catalogCourse.title)
                        let incomingDepartment = normalize(catalogCourse.department)
                        let incomingCredits = catalogCourse.credits
                        let incomingCreditsValue: Double? = extracted.extractedCredits ?? (incomingCredits > 0 ? Double(incomingCredits) : nil)

                        let existingCode = normalize(course.courseCode)
                        let existingTitle = normalize(course.title)
                        let existingDescription = normalize(course.descriptionText)
                        let existingDepartment = normalize(course.department)
                        let existingCredits = Int(course.credits)

                        let existingTitleIsLowQuality = existingTitle.isEmpty || (!existingCode.isEmpty && existingTitle.caseInsensitiveCompare(existingCode) == .orderedSame)
                        let incomingTitleIsGood = !incomingTitle.isEmpty && (existingCode.isEmpty || incomingTitle.caseInsensitiveCompare(existingCode) != .orderedSame)

                        if existingTitleIsLowQuality, incomingTitleIsGood {
                            course.title = incomingTitle
                        }

                        let finalTitle = normalize(course.title)
                        if finalTitle.isEmpty {
                            course.title = !incomingTitle.isEmpty ? incomingTitle : existingCode
                        }

                        let existingDescriptionIsInvalid = isInvalidCatalogDescription(existingDescription)
                        let incomingDescriptionIsInvalid = isInvalidCatalogDescription(incomingDescription)
                        if existingDescriptionIsInvalid && !incomingDescriptionIsInvalid {
                            course.descriptionText = incomingDescription
                        }

                        if existingCredits <= 0, incomingCredits > 0 {
                            course.credits = Int16(incomingCredits)
                            course.creditsValue = incomingCreditsValue ?? Double(incomingCredits)
                        }

                        if course.creditsValue <= 0, let v = incomingCreditsValue {
                            course.creditsValue = v
                        }

                        if existingDepartment.isEmpty, !incomingDepartment.isEmpty {
                            course.department = incomingDepartment
                        }

                        course.lastUpdated = Date()

                        // Link to DepartmentEntity using pre-fetched lookup
                        if !incomingDepartment.isEmpty {
                            let key = deptKey(incomingDepartment)
                            if let deptEntity = departmentLookup[key] {
                                course.departmentEntity = deptEntity
                            }
                        }

                        // Parse prerequisites with intelligence service
                        if let prereqRule = catalogCourse.prerequisites {
                            let encoder = JSONEncoder()
                            if let jsonData = try? encoder.encode(prereqRule),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                course.prerequisiteRulesJSON = jsonString
                                course.prerequisiteCodes = CoreDataManager.extractCourseCodesFromPrereqs(prereqRule)

                                let validationResult = catalogValidator.validate(
                                    rule: prereqRule,
                                    forUniversity: schoolProfile.schoolName,
                                    courseCode: catalogCourse.courseCode
                                )

                                course.prerequisiteValidationStatus = validationResult.isValid ? "valid" : "invalid"
                                course.prerequisiteConfidence = CoreDataManager.confidenceToString(validationResult.confidence)
                                course.invalidPrerequisiteCodes = validationResult.invalidCourseCodes.joined(separator: ", ")
                                course.prerequisiteParsingStatus = "parsed"
                            }
                        } else if let prereqText = catalogCourse.prerequisiteText {
                            let (parsedRule, needsLLM, _) = intelligenceService.parsePrerequisite(
                                prereqText,
                                courseCode: courseKey
                            )

                            if let rule = parsedRule {
                                let encoder = JSONEncoder()
                                if let jsonData = try? encoder.encode(rule),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    course.prerequisiteRulesJSON = jsonString
                                    course.prerequisiteCodes = CoreDataManager.extractCourseCodesFromPrereqs(rule)

                                    let validationResult = catalogValidator.validate(
                                        rule: rule,
                                        forUniversity: schoolProfile.schoolName,
                                        courseCode: catalogCourse.courseCode
                                    )

                                    course.prerequisiteValidationStatus = validationResult.isValid ? "valid" : "invalid"
                                    course.prerequisiteConfidence = CoreDataManager.confidenceToString(validationResult.confidence)
                                    course.invalidPrerequisiteCodes = validationResult.invalidCourseCodes.joined(separator: ", ")
                                    course.prerequisiteParsingStatus = "parsed"
                                }
                            } else if needsLLM {
                                course.prerequisiteParsingStatus = "pending_llm"
                                course.prerequisiteCodes = prereqText
                                coursesNeedingLLM.append((courseObjectID: course.objectID, text: prereqText, courseCode: courseKey))
                            } else {
                                course.prerequisiteParsingStatus = "failed"
                                course.prerequisiteCodes = prereqText
                            }
                        }

                        if let coreqs = catalogCourse.corequisites {
                            course.corequisiteCodes = coreqs.joined(separator: ", ")
                        }
                        if let offered = catalogCourse.typicallyOffered {
                            course.typicallyOffered = offered.joined(separator: ", ")
                        }
                    }
                }

                if !batchInserts.isEmpty {
                    let entity = NSEntityDescription.entity(forEntityName: "CourseCatalogEntity", in: context)
                    if let entity {
                        var i = 0
                        let request = NSBatchInsertRequest(entity: entity, managedObjectHandler: { obj in
                            guard i < batchInserts.count else { return true }
                            let item = batchInserts[i]
                            i += 1

                            guard let course = obj as? CourseCatalogEntity else { return false }
                            course.id = UUID()
                            course.courseCode = item.courseCode
                            course.title = item.title
                            course.descriptionText = item.descriptionText
                            course.credits = item.credits
                            course.creditsValue = item.creditsValue ?? Double(item.credits)
                            course.department = item.department
                            course.prerequisiteCodes = item.prerequisiteCodes
                            course.prerequisiteRulesJSON = item.prerequisiteRulesJSON
                            course.prerequisiteParsingStatus = item.prerequisiteParsingStatus
                            course.prerequisiteValidationStatus = item.prerequisiteValidationStatus
                            course.prerequisiteConfidence = item.prerequisiteConfidence
                            course.invalidPrerequisiteCodes = item.invalidPrerequisiteCodes
                            course.corequisiteCodes = item.corequisiteCodes
                            course.typicallyOffered = item.typicallyOffered
                            course.lastUpdated = item.lastUpdated
                            course.isArchived = false
                            // Important: do NOT set relationships inside NSBatchInsertRequest.
                            // Core Data may abort() if relationship values are set during batch insert.
                            return false
                        })
                        request.resultType = .objectIDs

                        if let result = try? context.execute(request) as? NSBatchInsertResult,
                           let insertedIDs = result.result as? [NSManagedObjectID],
                           !insertedIDs.isEmpty {
                            // Apply relationships after insertion (safe + prevents Core Data abort()).
                            for (objectID, item) in zip(insertedIDs, batchInserts) {
                                guard let course = context.object(with: objectID) as? CourseCatalogEntity else { continue }
                                course.university = university

                                if let department = item.department, !department.isEmpty {
                                    let key = deptKey(department)
                                    if let deptEntity = departmentLookup[key] {
                                        course.departmentEntity = deptEntity
                                    }
                                }
                            }

                            batchInsertedCourseObjectIDs.append(contentsOf: insertedIDs)
                        }
                    }
                }

                processed += chunk.count
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        DebugLogger.shared.coreData(
                            "Course import chunk save failed at \(processed)/\(incomingCourses.count): \(error.localizedDescription)",
                            level: .error
                        )
                        throw error
                    }
                }

                #if DEBUG
                DebugLogger.shared.coreData("Import progress: \(processed)/\(incomingCourses.count)")
                #endif
            }

            // 6) Import degree requirements using a pre-fetched map to avoid per-row fetches
            let reqFetch = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
            reqFetch.predicate = NSPredicate(format: "university == %@", university)
            reqFetch.fetchBatchSize = 500
            reqFetch.returnsObjectsAsFaults = true
            let existingReqs = (try? context.fetch(reqFetch)) ?? []

            func reqKey(major: String, category: String) -> String {
                "\(normalize(major).lowercased())||\(normalize(category).lowercased())"
            }

            var reqByKey: [String: DegreeRequirementEntity] = [:]
            reqByKey.reserveCapacity(existingReqs.count)
            for r in existingReqs {
                let k = reqKey(major: r.major ?? "", category: r.requirementCategory ?? "")
                if !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reqByKey[k] = r
                }
            }

            #if DEBUG
            DebugLogger.shared.coreData("Importing \(schoolProfile.degreeRequirements.count) degree requirements...")
            #endif

            for (index, degreeReq) in schoolProfile.degreeRequirements.enumerated() {
                let k = reqKey(major: degreeReq.major, category: degreeReq.category)
                let requirement: DegreeRequirementEntity

                if let existing = reqByKey[k] {
                    requirement = existing
                } else {
                    requirement = DegreeRequirementEntity(context: context)
                    requirement.id = UUID()
                    requirement.major = degreeReq.major
                    requirement.requirementCategory = degreeReq.category
                    requirement.university = university
                    reqByKey[k] = requirement
                }

                requirement.degreeType = degreeReq.degreeType
                requirement.sectionOrder = Int16(index)
                requirement.creditsRequired = Int16(degreeReq.creditsRequired)
                requirement.descriptionText = degreeReq.description
                requirement.lastUpdated = Date()

                if let courses = degreeReq.requiredCourses {
                    requirement.requiredCourses = courses.joined(separator: ", ")
                }
            }

            // 7) Archive ghost courses (O(1) lookups)
            let existingCourseKeys = Set(existingByCode.keys)
            let ghostKeys = existingCourseKeys.subtracting(scrapedCourseCodes)
            if !ghostKeys.isEmpty {
                #if DEBUG
                DebugLogger.shared.coreData("Found \(ghostKeys.count) courses no longer in catalog; archiving")
                #endif
                for ghostKey in ghostKeys {
                    guard let ghostOID = existingByCode[ghostKey],
                          let ghostCourse = context.object(with: ghostOID) as? CourseCatalogEntity else { continue }

                    let hasActiveEnrollments = (ghostCourse.enrollments as? Set<CourseEntity>)?.contains { !$0.isCompleted } ?? false
                    if hasActiveEnrollments {
                        #if DEBUG
                        DebugLogger.shared.coreData("Archiving \(ghostCourse.courseCode ?? ghostKey) (active enrollments)")
                        #endif
                    }
                    ghostCourse.isArchived = true
                    ghostCourse.lastUpdated = Date()
                }
            }

            try context.save()

            return (coursesNeedingLLM, batchInsertedCourseObjectIDs)
        }

        // Update active university on the main context for UI.
        finalizeImportOnMainContext(
            batchInsertedCourseObjectIDs: batchInsertedCourseObjectIDs,
            universityName: schoolProfile.schoolName
        )

        // 8) Process complex prerequisites in background (if any)
        if !coursesNeedingLLM.isEmpty {
            #if DEBUG
            DebugLogger.shared.coreData("Queued \(coursesNeedingLLM.count) courses for LLM processing")
            #endif
            processComplexPrerequisitesInBackground(
                courses: coursesNeedingLLM.map { (course: $0.courseObjectID, text: $0.text, courseCode: $0.courseCode) },
                university: schoolProfile.schoolName
            )
        }

        os_signpost(.end, log: log, name: "ImportSchoolCatalog", signpostID: spid)
    }

    private func finalizeImportOnMainContext(
        batchInsertedCourseObjectIDs: [NSManagedObjectID],
        universityName: String
    ) {
        let context = self.viewContext
        context.perform {
            if !batchInsertedCourseObjectIDs.isEmpty {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSInsertedObjectsKey: batchInsertedCourseObjectIDs],
                    into: [context]
                )
            }
            // Invalidate the requirement backfill cache — new import may have richer requirement data.
            CoreDataManager.shared.requirementBackfillCache.removeAll()
            let request = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
            request.predicate = NSPredicate(format: "name == %@", universityName)
            request.fetchLimit = 1
            if let uni = try? context.fetch(request).first {
                CoreDataManager.shared.setActiveUniversity(uni)
            }
            CoreDataManager.shared.objectWillChange.send()
        }
    }
    
    /// Process complex prerequisites with LLM in background
    private func processComplexPrerequisitesInBackground(
        courses: [(course: NSManagedObjectID, text: String, courseCode: String)],
        university: String
    ) {
        let batchWithURIs: [(text: String, courseCode: String, courseURI: URL)] = courses.map {
            (text: $0.text, courseCode: $0.courseCode, courseURI: $0.course.uriRepresentation())
        }

        Task(priority: .utility) {
            let results = await IntelligenceService.parseComplexPrerequisites(
                batchWithURIs,
                progressCallback: { parsed, total in
                    #if DEBUG
                    DebugLogger.shared.coreData("LLM parsing progress: \(parsed)/\(total)")
                    #endif
                }
            )

            guard !results.isEmpty else {
                return
            }

            let container = await MainActor.run { CoreDataManager.shared.container }
            let context = container.newBackgroundContext()
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

            await context.perform {
                guard let coordinator = context.persistentStoreCoordinator else {
                    return
                }

                let validator = CatalogPrerequisiteValidator(context: context)
                for (uri, rule) in results {
                    guard let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
                          let course = try? context.existingObject(with: objectID) as? CourseCatalogEntity else {
                        continue
                    }
                
                    let encoder = JSONEncoder()
                    if let jsonData = try? encoder.encode(rule),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        course.prerequisiteRulesJSON = jsonString
                        course.prerequisiteCodes = CoreDataManager.extractCourseCodesFromPrereqs(rule)

                        let validationResult = validator.validate(
                            rule: rule,
                            forUniversity: university,
                            courseCode: course.courseCode ?? ""
                        )

                        course.prerequisiteValidationStatus = validationResult.isValid ? "valid" : "invalid"
                        course.prerequisiteConfidence = CoreDataManager.confidenceToString(validationResult.confidence)
                        course.invalidPrerequisiteCodes = validationResult.invalidCourseCodes.joined(separator: ", ")
                        course.prerequisiteParsingStatus = "parsed"
                    }
                }

                do {
                    try context.save()
                    #if DEBUG
                    DebugLogger.shared.coreData("Successfully processed \(results.count) complex prerequisites")
                    #endif
                } catch {
                    #if DEBUG
                    DebugLogger.shared.coreData("Error saving LLM results: \(error)", level: .error)
                    #endif
                }
            }
        }
    }
    
    /// Helper to convert confidence enum to string
    private static func confidenceToString(_ confidence: CatalogPrerequisiteValidator.ValidationConfidence) -> String {
        switch confidence {
        case .valid: return "high"
        case .partiallyValid: return "medium"
        case .invalid: return "low"
        case .needsReview: return "needs_review"
        }
    }
    
    /// Helper to extract course codes from prerequisite rules
    private static func extractCourseCodesFromPrereqs(_ rule: PrerequisiteRule) -> String {
        var codes: [String] = []
        
        func traverse(_ rule: PrerequisiteRule) {
            switch rule {
            case .course(let req):
                codes.append(req.courseCode)
            case .and(let rules), .or(let rules):
                for subRule in rules {
                    traverse(subRule)
                }
            }
        }
        
        traverse(rule)
        return codes.joined(separator: ", ")
    }
    
    /// Fetch all degree requirements for a specific university
    func fetchDegreeRequirements(for universityName: String) -> [DegreeRequirementEntity] {
        let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
        request.predicate = NSPredicate(format: "university.name == %@", universityName)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \DegreeRequirementEntity.major, ascending: true),
            NSSortDescriptor(keyPath: \DegreeRequirementEntity.requirementCategory, ascending: true)
        ]
        request.fetchBatchSize = 200
        request.returnsObjectsAsFaults = true
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch degree requirements: \(error.localizedDescription)")

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Catalog Load Failed",
                    message: "Could not load degree requirements. \(error.localizedDescription)",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
            return []
        }
    }
    
    /// Fetch all majors for a specific university
    func fetchMajors(for universityName: String) -> [String] {
        let requirements = fetchDegreeRequirements(for: universityName)
        let uniqueMajors = Set(requirements.map { $0.major ?? "" })
        return Array(uniqueMajors).filter { !$0.isEmpty }.sorted()
    }
    
    /// Fetch courses from catalog for a specific university
    func fetchCatalogCourses(for universityName: String) -> [CourseCatalogEntity] {
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(format: "university.name == %@", universityName)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CourseCatalogEntity.courseCode, ascending: true)]
        request.fetchBatchSize = 500
        request.returnsObjectsAsFaults = true
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Failed to fetch catalog courses: \(error.localizedDescription)")

            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: "Catalog Load Failed",
                    message: "Could not load catalog courses. \(error.localizedDescription)",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
            return []
        }
    }
    
    /// Check if a university catalog has been downloaded
    func hasUniversityCatalog(name: String) -> Bool {
        // For UI purposes, consider a catalog "available" only if we actually have program data.
        // This prevents empty dropdowns when a UniversityEntity exists but majors/minors
        // haven't been imported yet.
        let majorRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        majorRequest.predicate = NSPredicate(format: "university.name == %@", name)

        do {
            return try viewContext.count(for: majorRequest) > 0
        } catch {
            return false
        }
    }
    
    /// Export local catalog modifications as JSON file
    /// This allows users to contribute their corrections back to GitHub
    func exportCatalogModifications(for universityName: String) throws -> URL {
        let university = try fetchUniversity(name: universityName)
        
        // Fetch all courses for this university
        let courses = fetchCatalogCourses(for: universityName)
        
        // Convert to CatalogCourse format
        let catalogCourses = courses.compactMap { courseEntity -> CatalogCourse? in
            guard let courseCode = courseEntity.courseCode,
                  let title = courseEntity.title else { return nil }
            
            var prereqRule: PrerequisiteRule? = nil
            if let prereqJSON = courseEntity.prerequisiteRulesJSON,
               let jsonData = prereqJSON.data(using: .utf8) {
                prereqRule = try? JSONDecoder().decode(PrerequisiteRule.self, from: jsonData)
            }
            
            let corequisites = courseEntity.corequisiteCodes?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            let typicallyOffered = courseEntity.typicallyOffered?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            return CatalogCourse(
                id: courseEntity.id ?? UUID(),
                courseCode: courseCode,
                title: title,
                description: courseEntity.descriptionText,
                credits: Int(courseEntity.credits),
                department: courseEntity.department,
                prerequisites: prereqRule,
                corequisites: corequisites,
                typicallyOffered: typicallyOffered
            )
        }
        
        // Fetch degree requirements
        let requirements = fetchDegreeRequirements(for: universityName)
        let degreeReqs = requirements.compactMap { reqEntity -> DegreeRequirement? in
            guard let degreeType = reqEntity.degreeType,
                  let major = reqEntity.major,
                  let category = reqEntity.requirementCategory else { return nil }
            
            let requiredCourses = reqEntity.requiredCourses?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            return DegreeRequirement(
                id: reqEntity.id ?? UUID(),
                degreeType: degreeType,
                major: major,
                category: category,
                requiredCourses: requiredCourses,
                creditsRequired: Int(reqEntity.creditsRequired),
                description: reqEntity.descriptionText,
                selectFrom: nil,
                selectCount: nil
            )
        }
        
        // Create SchoolProfile
        let profile = SchoolProfile(
            schoolID: universityName.replacingOccurrences(of: " ", with: "_").lowercased(),
            schoolName: universityName,
            catalogURL: university.catalogURL ?? "",
            version: "1.0.0-user-export",
            lastUpdated: Date(),
            courses: catalogCourses,
            degreeRequirements: degreeReqs,
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(profile)
        
        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(profile.schoolID)_export_\(Int(Date().timeIntervalSince1970)).json"
        let fileURL = tempDir.appendingPathComponent(filename)
        try jsonData.write(to: fileURL)
        
        print("[CoreData] Exported catalog to: \(fileURL.path)")
        return fileURL
    }

    /// Export the scraper-imported program + requirement data as a CSV.
    /// Format:
    /// Degree Name | Department | Major or Minor | Requirement Category | Mode | Course
    @MainActor
    func exportScrapedCatalogCSV(for universityName: String) async throws -> [URL] {
        // Best-effort: ensure CourseCatalogEntity has descriptions so CSV can populate the column.
        try await refreshCourseCatalogDescriptionsIfNeeded(universityName: universityName)
        let auditURL = try await scrapeAllProgramRequirementsForExport(universityName: universityName)
        let csvURL = try exportScrapedCatalogCSVFromCoreData(universityName: universityName)
        return [csvURL, auditURL]
    }

    /// Export the scraper-imported program + requirement data as a CSV using only what's already
    /// stored in Core Data. This performs no additional scraping/network requests.
    @MainActor
    func exportScrapedCatalogCSVFromExistingCoreData(for universityName: String) throws -> URL {
        try exportScrapedCatalogCSVFromCoreData(universityName: universityName)
    }

    /// Export the scraper-imported program + requirement data as a CSV using what's already stored
    /// in Core Data, but will perform a best-effort catalog scrape/import if course descriptions are missing.
    @MainActor
    func exportScrapedCatalogCSVFromExistingCoreData(for universityName: String) async throws -> URL {
        try await refreshCourseCatalogDescriptionsIfNeeded(universityName: universityName)
        return try exportScrapedCatalogCSVFromCoreData(universityName: universityName)
    }

    @MainActor
    private func refreshCourseCatalogDescriptionsIfNeeded(universityName: String) async throws {
        let university = try fetchUniversity(name: universityName)
        let catalogURL = (university.catalogURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalogURL.isEmpty else { return }

        // If we already have at least one description, assume the catalog has been enriched.
        let descRequest = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        descRequest.predicate = NSPredicate(
            format: "university == %@ AND descriptionText != nil AND descriptionText != ''",
            university
        )
        descRequest.fetchLimit = 1
        if ((try? viewContext.count(for: descRequest)) ?? 0) > 0 { return }

        let logger = DebugLogger.shared
        logger.scraper("📦 Export: refreshing course catalog descriptions from \(catalogURL)", level: .info)

        func normalized(_ value: String?) -> String {
            (value ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let scraperService = WebScraperService()
        var courses = try await scraperService.scrapeAcalog(url: catalogURL)
        if courses.isEmpty {
            courses = (try? await scraperService.scrapeBanner(url: catalogURL)) ?? []
        }
        guard !courses.isEmpty else {
            logger.scraper("⚠️ Export refresh found 0 courses; leaving descriptions blank", level: .warn)
            return
        }

        let describedCount = courses.reduce(into: 0) { acc, c in
            if !normalized(c.description).isEmpty { acc += 1 }
        }
        logger.scraper("📚 Export refresh scraped \(courses.count) courses (with descriptions: \(describedCount))", level: .info)

        // If we got courses but *no* descriptions, attempt the ModernCampus per-course preview crawl.
        if describedCount == 0 {
            do {
                let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(catalogURL)
                let catalogID: String
                if let catoidHint, !catoidHint.isEmpty {
                    catalogID = catoidHint
                } else {
                    catalogID = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL)
                }
                let crawled = try await ModernCampusEngine.fetchAllCourses(baseURL: normalizedCatalogURL, catoid: catalogID)
                let crawledDescribed = crawled.reduce(into: 0) { acc, c in
                    if !normalized(c.description).isEmpty { acc += 1 }
                }

                if !crawled.isEmpty, crawledDescribed > 0 {
                    courses = crawled
                    logger.scraper("✅ ModernCampus crawl enriched descriptions: \(crawledDescribed)/\(crawled.count)", level: .info)
                } else {
                    logger.scraper("⚠️ ModernCampus crawl did not yield descriptions (\(crawledDescribed)/\(crawled.count))", level: .warn)
                }
            } catch {
                logger.scraper("⚠️ ModernCampus crawl failed during export refresh: \(error)", level: .warn)
            }
        }

        let schoolID = university.id?.uuidString ?? universityName
        let profile = SchoolProfile(
            schoolID: schoolID,
            schoolName: universityName,
            catalogURL: catalogURL,
            version: "1.0.0-export-refresh",
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

        try await importSchoolCatalog(profile)

        // Post-import diagnostic: count how many catalog rows now have descriptions.
        let totalRequest = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        totalRequest.predicate = NSPredicate(format: "university == %@", university)
        let totalCount = (try? viewContext.count(for: totalRequest)) ?? 0

        let describedRequest = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        describedRequest.predicate = NSPredicate(
            format: "university == %@ AND descriptionText != nil AND descriptionText != ''",
            university
        )
        let describedRows = (try? viewContext.fetch(describedRequest)) ?? []
        let describedCountAfter = describedRows.reduce(into: 0) { acc, row in
            let desc = (row.descriptionText ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = desc.lowercased()
            let looksInvalid = lower.contains("resource not found") && (lower.contains("unable to locate the resource") || lower.contains("we were unable to locate"))
            if !desc.isEmpty, !looksInvalid {
                acc += 1
            }
        }
        logger.scraper("📦 Export refresh import complete: described rows now \(describedCountAfter)/\(totalCount)", level: .info)
    }

    private func exportScrapedCatalogCSVFromCoreData(universityName: String) throws -> URL {
        _ = try fetchUniversity(name: universityName)

        func canonicalizeProgramURLForMatch(_ urlString: String) -> String {
            let cleaned = urlString
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return "" }
            guard var components = URLComponents(string: cleaned) else { return cleaned }

            // Match how requirements are stored by the scraper (and tolerate older rows).
            if let items = components.queryItems, !items.isEmpty {
                let filtered = items
                    .filter { $0.name.lowercased() != "returnto" }
                    .sorted {
                        let aName = $0.name.lowercased()
                        let bName = $1.name.lowercased()
                        if aName != bName { return aName < bName }
                        let aVal = ($0.value ?? "").lowercased()
                        let bVal = ($1.value ?? "").lowercased()
                        return aVal < bVal
                    }
                components.queryItems = filtered.isEmpty ? nil : filtered
            }

            // Fragments like "#core_123" should not affect program identity.
            components.fragment = nil

            var rebuilt = components.string ?? cleaned
            if rebuilt.hasSuffix("?") { rebuilt.removeLast() }
            return rebuilt
        }

        func csvEscape(_ value: String) -> String {
            if value.contains("\"") {
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            if value.contains(",") || value.contains("\n") || value.contains("\r") {
                return "\"\(value)\""
            }
            return value
        }

        func extractCatoidFromURLString(_ urlString: String) -> String {
            let cleaned = urlString
                .replacingOccurrences(of: "\u{00A0}", with: "")
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, let comps = URLComponents(string: cleaned) else { return "" }
            return comps.queryItems?.first(where: { $0.name.lowercased() == "catoid" })?.value ?? ""
        }

        func parseSourceCatoidsField(_ raw: String?) -> [String] {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return trimmed
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func formatCreditsNumber(_ value: Double) -> String {
            if value <= 0 { return "" }
            if abs(value.rounded() - value) < 0.0001 {
                return String(Int(value.rounded()))
            }
            return String(format: "%.1f", value)
        }

        func normalizeDegreeToken(_ s: String) -> String {
            s
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: " ", with: "")
        }

        func degreeDisplayToken(_ s: String?) -> String {
            let token = normalizeDegreeToken(s ?? "")
            return token
        }

        func extractCombinedDegreeTypeFromProgramName(_ name: String) -> String {
            // Many catalogs encode combined degrees in the *program name* rather than a single degreeType field,
            // e.g. "Accounting BS/Accounting MS" or "Biomedical Sciences BS/PharmD".
            let normalized = name
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .uppercased()
                .replacingOccurrences(of: ".", with: "")

            // Split on common separators and whitespace.
            let separators = CharacterSet(charactersIn: "/,+;&")
                .union(.whitespacesAndNewlines)
            let parts = normalized
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Keep this list intentionally conservative: only tokens we are confident are degree acronyms.
            let known: Set<String> = [
                "AA", "AS", "AAS",
                "BA", "BS", "BFA", "BM",
                "MA", "MS", "MBA", "MENG", "MPH",
                "PHD", "JD", "MD", "DMD", "DDS", "DPT",
                "PHARMD"
            ]

            var tokens: [String] = []
            tokens.reserveCapacity(2)

            for p in parts {
                if known.contains(p) {
                    if !tokens.contains(p) { tokens.append(p) }
                    continue
                }

                // Tolerate a few common multi-letter forms that appear as tokens.
                // (e.g. "PHARM" + "D" can appear if the catalog inserts spaces)
                if p == "PHARM", !tokens.contains("PHARMD") {
                    // handled by lookahead below
                    continue
                }
            }

            // Handle spaced PharmD variants: "PHARM" "D" => "PHARMD".
            if !tokens.contains("PHARMD") {
                for idx in 0..<(max(parts.count - 1, 0)) {
                    if parts[idx] == "PHARM", parts[idx + 1] == "D" {
                        tokens.append("PHARMD")
                        break
                    }
                }
            }

            if tokens.count >= 2 {
                return tokens.joined(separator: "/")
            }
            return ""
        }

        func resolvedDegreeTypeText(programName: String, storedDegreeType: String?) -> String {
            let stored = (storedDegreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if stored.contains("/") { return stored }
            let derived = extractCombinedDegreeTypeFromProgramName(programName)
            if !derived.isEmpty { return derived }
            return stored
        }

        func displayProgramName(name: String, degreeType: String?, isMinor: Bool) -> String {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMinor { return n }

            // Combined programs already embed degree information in the name.
            if n.contains("/") { return n }

            let dt = degreeDisplayToken(degreeType)
            if dt.isEmpty { return n }
            return "\(n), \(dt)"
        }

        func splitCourseList(_ raw: String?) -> [String] {
            guard let raw else { return [] }
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func parseProgramURLsField(_ raw: String?) -> [String] {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return trimmed
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func programCandidateURLs(for program: MajorEntity) -> [(raw: String, canonical: String, catoid: String)] {
            var urls: [String] = []
            urls.reserveCapacity(4)

            let primary = (program.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !primary.isEmpty { urls.append(primary) }

            let extras = parseProgramURLsField(program.programURLs)
            if !extras.isEmpty { urls.append(contentsOf: extras) }

            // Canonicalize + de-dupe by canonical URL (fall back to raw if needed).
            var seen = Set<String>()
            var out: [(raw: String, canonical: String, catoid: String)] = []
            out.reserveCapacity(urls.count)

            for raw in urls {
                let canonical = canonicalizeProgramURLForMatch(raw)
                let key = canonical.isEmpty ? raw : canonical
                guard !key.isEmpty else { continue }
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                let catoid = extractCatoidFromURLString(!canonical.isEmpty ? canonical : raw)
                out.append((raw: raw, canonical: canonical, catoid: catoid))
            }

            return out
        }

        func normalizedNonEmpty(_ raw: String?) -> String {
            let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v
        }

        func combinedRow(
            section: String,
            degreeName: String,
            department: String,
            majorOrMinor: String,
            requirementCategory: String,
            mode: String,
            courseCode: String,
            courseTitle: String,
            credits: String,
            programURL: String,
            degreeType: String,
            entity: String,
            issue: String,
            degreeLevel: String = "",
            sourceCatoid: String = ""
        ) -> String {
            [
                csvEscape(section),
                csvEscape(universityName),
                csvEscape(degreeName),
                csvEscape(department),
                csvEscape(majorOrMinor),
                csvEscape(requirementCategory),
                csvEscape(mode),
                csvEscape(courseCode),
                csvEscape(courseTitle),
                csvEscape(""),
                csvEscape(credits),
                csvEscape(programURL),
                csvEscape(degreeType),
                csvEscape(entity),
                csvEscape(issue),
                csvEscape(degreeLevel),
                csvEscape(sourceCatoid)
            ].joined(separator: ",")
        }

        func combinedRowWithDescription(
            section: String,
            degreeName: String,
            department: String,
            majorOrMinor: String,
            requirementCategory: String,
            mode: String,
            courseCode: String,
            courseTitle: String,
            courseDescription: String,
            credits: String,
            programURL: String,
            degreeType: String,
            entity: String,
            issue: String,
            degreeLevel: String = "",
            sourceCatoid: String = ""
        ) -> String {
            [
                csvEscape(section),
                csvEscape(universityName),
                csvEscape(degreeName),
                csvEscape(department),
                csvEscape(majorOrMinor),
                csvEscape(requirementCategory),
                csvEscape(mode),
                csvEscape(courseCode),
                csvEscape(courseTitle),
                csvEscape(courseDescription),
                csvEscape(credits),
                csvEscape(programURL),
                csvEscape(degreeType),
                csvEscape(entity),
                csvEscape(issue),
                csvEscape(degreeLevel),
                csvEscape(sourceCatoid)
            ].joined(separator: ",")
        }

        // Fetch programs
        let programRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        programRequest.predicate = NSPredicate(format: "university.name == %@", universityName)
        programRequest.sortDescriptors = [
            NSSortDescriptor(key: "isMinor", ascending: true),
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "degreeType", ascending: true)
        ]
        let programs = (try? viewContext.fetch(programRequest)) ?? []

        // Fetch all requirements once, then group by (programURL, degreeType)
        let reqRequest = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
        reqRequest.predicate = NSPredicate(format: "university.name == %@", universityName)
        reqRequest.sortDescriptors = [
            NSSortDescriptor(key: "programURL", ascending: true),
            NSSortDescriptor(key: "degreeType", ascending: true),
            NSSortDescriptor(key: "sectionOrder", ascending: true)
        ]
        let allRequirements = (try? viewContext.fetch(reqRequest)) ?? []

        var reqsByKey: [String: [DegreeRequirementEntity]] = [:]
        reqsByKey.reserveCapacity(allRequirements.count)
        for r in allRequirements {
            let url = canonicalizeProgramURLForMatch(r.programURL ?? "")
            guard !url.isEmpty else { continue }
            let dt = normalizeDegreeToken(r.degreeType ?? "")
            let key = "\(url)|\(dt)"
            reqsByKey[key, default: []].append(r)
        }

        func departmentString(for program: MajorEntity) -> String {
            if let depts = program.departments as? Set<DepartmentEntity>, !depts.isEmpty {
                let sorted = depts
                    .compactMap { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .sorted()
                if let first = sorted.first { return first }
            }

            let resolved = (program.resolvedDepartment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolved.isEmpty { return resolved }
            return ""
        }

        // Build combined CSV (one row per course, including requirement category + mode,
        // plus AUDIT rows).
        var lines: [String] = []
        lines.append("Section,University,Degree Name,Department,Major or Minor,Requirement Category,Mode,Course Code,Course Title,Course Description,Credits,Program URL,Degree Type,Entity,Issue,Degree Level,Source Catoid")

        var auditLines: [String] = []
        auditLines.reserveCapacity(256)
        var seenAuditKeys = Set<String>()

        func emitAudit(
            degreeName: String,
            department: String,
            majorOrMinor: String,
            requirementCategory: String,
            mode: String,
            courseCode: String,
            courseTitle: String,
            credits: String,
            programURL: String,
            degreeType: String,
            entity: String,
            issue: String,
            degreeLevel: String = "",
            sourceCatoid: String = ""
        ) {
            let key = [
                degreeName,
                department,
                majorOrMinor,
                requirementCategory,
                mode,
                courseCode,
                courseTitle,
                credits,
                programURL,
                degreeType,
                entity,
                issue,
                degreeLevel,
                sourceCatoid
            ].joined(separator: "|")
            guard !seenAuditKeys.contains(key) else { return }
            seenAuditKeys.insert(key)

            auditLines.append(
                combinedRow(
                    section: "AUDIT",
                    degreeName: degreeName,
                    department: department,
                    majorOrMinor: majorOrMinor,
                    requirementCategory: requirementCategory,
                    mode: mode,
                    courseCode: courseCode,
                    courseTitle: courseTitle,
                    credits: credits,
                    programURL: programURL,
                    degreeType: degreeType,
                    entity: entity,
                    issue: issue,
                    degreeLevel: degreeLevel,
                    sourceCatoid: sourceCatoid
                )
            )
        }

        // Audit CourseCatalogEntity rows for partial/incomplete fields.
        let catalogRequest = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        catalogRequest.predicate = NSPredicate(format: "university.name == %@", universityName)
        catalogRequest.sortDescriptors = [NSSortDescriptor(key: "courseCode", ascending: true)]
        let catalogCourses = (try? viewContext.fetch(catalogRequest)) ?? []

        func isInvalidCatalogDescription(_ value: String) -> Bool {
            let lower = value
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if lower.isEmpty { return true }
            if lower.contains("resource not found") && (lower.contains("unable to locate the resource") || lower.contains("we were unable to locate")) {
                return true
            }
            if lower.contains("home page") && lower.contains("search page") && lower.contains("unable to locate") {
                return true
            }
            if lower.contains("print-friendly page") && (lower.contains("undergraduate catalog") || lower.contains("graduate catalog")) {
                return true
            }
            return false
        }

        func sanitizeCatalogDescriptionForExport(_ value: String, courseCode: String) -> String {
            let cleaned = value
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return "" }
            let lower = cleaned.lowercased()
            guard lower.contains("print-friendly page") || lower.hasPrefix("help ") else { return cleaned }

            if !courseCode.isEmpty,
               let r = cleaned.range(of: courseCode, options: [.caseInsensitive]) {
                var after = cleaned[r.upperBound...]
                if let dash = after.range(of: "[-–—]", options: .regularExpression) {
                    after = after[dash.upperBound...]
                }
                return String(after)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return cleaned
        }

        func stripComponentSuffixFromCourseCode(_ normalizedCode: String) -> String {
            // If the code looks like "DEPT 101SEM" or "CSE 115LR", also allow matching "DEPT 101".
            // This helps when requirements omit the component suffix but catalog rows include it.
            let pattern = "^([A-Z]{2,6})\\s+([0-9]{2,4})([A-Z]{1,6})$"
                        guard let re = Self.cachedRegex(pattern) else { return normalizedCode }
            let nsRange = NSRange(normalizedCode.startIndex..<normalizedCode.endIndex, in: normalizedCode)
            guard let m = re.firstMatch(in: normalizedCode, range: nsRange), m.numberOfRanges >= 3,
                  let deptRange = Range(m.range(at: 1), in: normalizedCode),
                  let numRange = Range(m.range(at: 2), in: normalizedCode) else {
                return normalizedCode
            }
            let dept = String(normalizedCode[deptRange])
            let num = String(normalizedCode[numRange])
            return "\(dept) \(num)"
        }

        // Build quick lookups so requirement rows can include course descriptions + credits.
        // We keep an exact map (for audit counts) and an expanded map (for matching).
        var exactDescriptionByCode: [String: String] = [:]
        exactDescriptionByCode.reserveCapacity(catalogCourses.count)

        var descriptionByCode: [String: String] = [:]
        descriptionByCode.reserveCapacity(catalogCourses.count)

        var creditsTextByCode: [String: String] = [:]
        creditsTextByCode.reserveCapacity(catalogCourses.count)

        var totalCatalogRowsWithAnyData = 0
        var totalCatalogRowsWithDescription = 0
        for c in catalogCourses {
            let code = normalizeCourseCode(c.courseCode ?? "")
            let title = normalizedNonEmpty(c.title)
            let creditsText: String = {
                let v = c.creditsValue
                if v > 0 { return formatCreditsNumber(v) }
                let base = Int(c.credits)
                return base > 0 ? String(base) : ""
            }()
            let rawDesc = normalizedNonEmpty(c.descriptionText)
            let desc = isInvalidCatalogDescription(rawDesc) ? "" : sanitizeCatalogDescriptionForExport(rawDesc, courseCode: code)

            let hasAny = !code.isEmpty || !title.isEmpty || !creditsText.isEmpty || !desc.isEmpty
            if !hasAny { continue }

            totalCatalogRowsWithAnyData += 1
            if !desc.isEmpty { totalCatalogRowsWithDescription += 1 }

            guard !code.isEmpty, !desc.isEmpty else { continue }

            if exactDescriptionByCode[code] == nil {
                exactDescriptionByCode[code] = desc
            }

            if descriptionByCode[code] == nil {
                descriptionByCode[code] = desc
            }

            if !creditsText.isEmpty, creditsTextByCode[code] == nil {
                creditsTextByCode[code] = creditsText
            }

            let stripped = stripComponentSuffixFromCourseCode(code)
            if stripped != code, descriptionByCode[stripped] == nil {
                descriptionByCode[stripped] = desc
            }
            if stripped != code, !creditsText.isEmpty, creditsTextByCode[stripped] == nil {
                creditsTextByCode[stripped] = creditsText
            }
        }

        func courseDescription(for courseCode: String) -> String {
            let code = normalizeCourseCode(courseCode)
            guard !code.isEmpty else { return "" }
            if let direct = descriptionByCode[code] { return direct }
            let stripped = stripComponentSuffixFromCourseCode(code)
            if let fallback = descriptionByCode[stripped] { return fallback }
            return ""
        }

        // Always include at least one AUDIT row so exports are self-diagnosing.
        auditLines.append(
            combinedRowWithDescription(
                section: "AUDIT",
                degreeName: "",
                department: "",
                majorOrMinor: "",
                requirementCategory: "",
                mode: "",
                courseCode: "",
                courseTitle: "",
                courseDescription: "",
                credits: "",
                programURL: "",
                degreeType: "",
                entity: "CourseCatalogEntity",
                issue: "AUDIT SUMMARY: catalog courses: \(catalogCourses.count); described rows: \(totalCatalogRowsWithDescription)/\(totalCatalogRowsWithAnyData); unique described codes: \(exactDescriptionByCode.count)"
            )
        )

        // Include an AUDIT summary for programs so exports clearly show multi-catalog coverage.
        do {
            var byLevel: [String: Int] = [:]
            var byCatoid: [String: Int] = [:]
            var programsWithRequirements = 0
            var programsWithoutRequirements = 0
            
            for p in programs {
                let level = (p.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let keyLevel = level.isEmpty ? "(empty)" : level
                byLevel[keyLevel, default: 0] += 1

                let catoids = parseSourceCatoidsField(p.sourceCatoids)
                if !catoids.isEmpty {
                    for c in catoids {
                        let keyCatoid = c.isEmpty ? "(none)" : c
                        byCatoid[keyCatoid, default: 0] += 1
                    }
                } else {
                    let rawURL = (p.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let canonicalURL = canonicalizeProgramURLForMatch(rawURL)
                    let catoid = extractCatoidFromURLString(!canonicalURL.isEmpty ? canonicalURL : rawURL)
                    let keyCatoid = catoid.isEmpty ? "(none)" : catoid
                    byCatoid[keyCatoid, default: 0] += 1
                }
                
                // Count programs with/without requirements
                let candidates = programCandidateURLs(for: p)
                var hasAnyReqs = false
                for candidate in candidates {
                    let canonicalURL = candidate.canonical.isEmpty ? canonicalizeProgramURLForMatch(candidate.raw) : candidate.canonical
                    let degreeKey = normalizeDegreeToken(p.degreeType ?? "")
                    let exactKey = "\(canonicalURL)|\(degreeKey)"
                    if reqsByKey[exactKey] != nil {
                        hasAnyReqs = true
                        break
                    }
                    let anyReqs = allRequirements.contains { r in
                        canonicalizeProgramURLForMatch(r.programURL ?? "") == canonicalURL
                    }
                    if anyReqs {
                        hasAnyReqs = true
                        break
                    }
                }
                if hasAnyReqs {
                    programsWithRequirements += 1
                } else {
                    programsWithoutRequirements += 1
                }
            }

            let levelSummary = byLevel
                .sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            let catoidSummary = byCatoid
                .sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")

            auditLines.append(
                combinedRowWithDescription(
                    section: "AUDIT",
                    degreeName: "",
                    department: "",
                    majorOrMinor: "",
                    requirementCategory: "",
                    mode: "",
                    courseCode: "",
                    courseTitle: "",
                    courseDescription: "",
                    credits: "",
                    programURL: "",
                    degreeType: "",
                    entity: "MajorEntity",
                    issue: "AUDIT SUMMARY: programs: \(programs.count) (with requirements: \(programsWithRequirements), without: \(programsWithoutRequirements)); by degreeLevel: [\(levelSummary)]; by catoid: [\(catoidSummary)]"
                )
            )
            
            // Add detailed AUDIT rows for programs without requirements
            if programsWithoutRequirements > 0 {
                for p in programs {
                    let rawName = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if rawName.isEmpty { continue }
                    
                    let candidates = programCandidateURLs(for: p)
                    var hasAnyReqs = false
                    for candidate in candidates {
                        let canonicalURL = candidate.canonical.isEmpty ? canonicalizeProgramURLForMatch(candidate.raw) : candidate.canonical
                        let degreeKey = normalizeDegreeToken(p.degreeType ?? "")
                        let exactKey = "\(canonicalURL)|\(degreeKey)"
                        if reqsByKey[exactKey] != nil {
                            hasAnyReqs = true
                            break
                        }
                        let anyReqs = allRequirements.contains { r in
                            canonicalizeProgramURLForMatch(r.programURL ?? "") == canonicalURL
                        }
                        if anyReqs {
                            hasAnyReqs = true
                            break
                        }
                    }
                    
                    if !hasAnyReqs {
                        let isMinor = p.isMinor
                        let majorOrMinor = isMinor ? "Minor" : "Major"
                        let dept = departmentString(for: p)
                        let degreeTypeText = resolvedDegreeTypeText(programName: rawName, storedDegreeType: p.degreeType)
                        let degreeName = displayProgramName(name: rawName, degreeType: degreeTypeText, isMinor: isMinor)
                        let degreeLevelText = (p.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let combinedCatoids = parseSourceCatoidsField(p.sourceCatoids)
                            .sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
                            .joined(separator: ";")
                        
                        auditLines.append(
                            combinedRowWithDescription(
                                section: "AUDIT",
                                degreeName: degreeName,
                                department: dept,
                                majorOrMinor: majorOrMinor,
                                requirementCategory: "",
                                mode: "",
                                courseCode: "",
                                courseTitle: "",
                                courseDescription: "",
                                credits: "",
                                programURL: (p.programURL ?? ""),
                                degreeType: degreeTypeText,
                                entity: "MajorEntity",
                                issue: "Program saved to database but no requirements found",
                                degreeLevel: degreeLevelText,
                                sourceCatoid: combinedCatoids
                            )
                        )
                    }
                }
            }
        }

        // Since CourseCatalogEntity is de-duped by (university, courseCode), include per-catalog
        // course scrape completion as an AUDIT summary by catoid.
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CatalogScrapeStateEntity")
            request.predicate = NSPredicate(format: "university.name == %@", universityName)
            let states = (try? viewContext.fetch(request)) ?? []

            var byCatoid: [String: Int] = [:]
            for s in states {
                let catoid = (s.value(forKey: "catoid") as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let count: Int = {
                    if let i = s.value(forKey: "courseCount") as? Int { return i }
                    if let i = s.value(forKey: "courseCount") as? Int32 { return Int(i) }
                    if let i = s.value(forKey: "courseCount") as? Int64 { return Int(i) }
                    return 0
                }()

                let key = catoid.isEmpty ? "(none)" : catoid
                byCatoid[key] = max(byCatoid[key] ?? 0, count)
            }

            if !byCatoid.isEmpty {
                let summary = byCatoid
                    .sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "; ")

                auditLines.append(
                    combinedRowWithDescription(
                        section: "AUDIT",
                        degreeName: "",
                        department: "",
                        majorOrMinor: "",
                        requirementCategory: "",
                        mode: "",
                        courseCode: "",
                        courseTitle: "",
                        courseDescription: "",
                        credits: "",
                        programURL: "",
                        degreeType: "",
                        entity: "CatalogScrapeStateEntity",
                        issue: "AUDIT SUMMARY: course scrape states by catoid: [\(summary)]"
                    )
                )
            }
        }

        for c in catalogCourses {
            let code = normalizedNonEmpty(c.courseCode)
            let title = normalizedNonEmpty(c.title)
            let creditsText: String = {
                let v = c.creditsValue
                if v > 0 { return formatCreditsNumber(v) }
                let base = Int(c.credits)
                return base > 0 ? String(base) : ""
            }()
            let rawDesc = normalizedNonEmpty(c.descriptionText)
            let desc = isInvalidCatalogDescription(rawDesc) ? "" : sanitizeCatalogDescriptionForExport(rawDesc, courseCode: normalizeCourseCode(code))

            let hasAny = !code.isEmpty || !title.isEmpty || !creditsText.isEmpty || !desc.isEmpty
            if !hasAny { continue }

            var missing: [String] = []
            if code.isEmpty { missing.append("courseCode") }
            if title.isEmpty { missing.append("title") }
            if desc.isEmpty { missing.append("description") }
            if creditsText.isEmpty { missing.append("credits") }
            guard !missing.isEmpty else { continue }

            emitAudit(
                degreeName: "",
                department: "",
                majorOrMinor: "",
                requirementCategory: "",
                mode: "",
                courseCode: code,
                courseTitle: title,
                credits: creditsText,
                programURL: "",
                degreeType: "",
                entity: "CourseCatalogEntity",
                issue: "Partial course row: missing \(missing.joined(separator: ", "))"
            )
        }

        for p in programs {
            let rawName = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if rawName.isEmpty { continue }

            let isMinor = p.isMinor
            let majorOrMinor = isMinor ? "Minor" : "Major"
            let dept = departmentString(for: p)

            let degreeTypeText = resolvedDegreeTypeText(programName: rawName, storedDegreeType: p.degreeType)
            let degreeName = displayProgramName(name: rawName, degreeType: degreeTypeText, isMinor: isMinor)
            let degreeKey = normalizeDegreeToken(degreeTypeText)
            let degreeLevelText = (p.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let candidates = programCandidateURLs(for: p)
            if candidates.isEmpty {
                emitAudit(
                    degreeName: degreeName,
                    department: dept,
                    majorOrMinor: majorOrMinor,
                    requirementCategory: "",
                    mode: "",
                    courseCode: "",
                    courseTitle: "",
                    credits: "",
                    programURL: "",
                    degreeType: degreeTypeText,
                    entity: "MajorEntity",
                    issue: "Missing programURL",
                    degreeLevel: degreeLevelText,
                    sourceCatoid: ""
                )
                continue
            }

            var emittedAnyForProgram = false

            for candidate in candidates {
                let rawURL = candidate.raw
                let canonicalURL = candidate.canonical.isEmpty ? canonicalizeProgramURLForMatch(rawURL) : candidate.canonical
                let sourceCatoid = candidate.catoid

                if canonicalURL.isEmpty {
                    emitAudit(
                        degreeName: degreeName,
                        department: dept,
                        majorOrMinor: majorOrMinor,
                        requirementCategory: "",
                        mode: "",
                        courseCode: "",
                        courseTitle: "",
                        credits: "",
                        programURL: rawURL,
                        degreeType: degreeTypeText,
                        entity: "MajorEntity",
                        issue: "Missing programURL",
                        degreeLevel: degreeLevelText,
                        sourceCatoid: sourceCatoid
                    )
                    continue
                }

                // Prefer matching this program's degreeType; fall back to any degreeType for the same URL.
                var matchingReqs: [DegreeRequirementEntity] = []
                let exactKey = "\(canonicalURL)|\(degreeKey)"
                if let found = reqsByKey[exactKey] {
                    matchingReqs = found
                } else if degreeKey.isEmpty {
                    // If no degree type is known, merge all degree types for that URL.
                    matchingReqs = allRequirements.filter { r in
                        canonicalizeProgramURLForMatch(r.programURL ?? "") == canonicalURL
                    }
                } else {
                    // Broader fallback: any requirements for this URL.
                    matchingReqs = allRequirements.filter { r in
                        canonicalizeProgramURLForMatch(r.programURL ?? "") == canonicalURL
                    }
                }

                var emittedAny = false
                for r in matchingReqs.sorted(by: { $0.sectionOrder < $1.sectionOrder }) {
                let category = (r.requirementCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if category.isEmpty {
                    emitAudit(
                        degreeName: degreeName,
                        department: dept,
                        majorOrMinor: majorOrMinor,
                        requirementCategory: "",
                        mode: "",
                        courseCode: "",
                        courseTitle: "",
                        credits: "",
                        programURL: canonicalURL,
                        degreeType: degreeTypeText,
                        entity: "DegreeRequirementEntity",
                        issue: "Missing requirementCategory",
                        degreeLevel: degreeLevelText,
                        sourceCatoid: sourceCatoid
                    )
                }

                let reqProgramURL = normalizedNonEmpty(r.programURL)
                if reqProgramURL.isEmpty {
                    emitAudit(
                        degreeName: degreeName,
                        department: dept,
                        majorOrMinor: majorOrMinor,
                        requirementCategory: category,
                        mode: "",
                        courseCode: "",
                        courseTitle: "",
                        credits: "",
                        programURL: canonicalURL,
                        degreeType: degreeTypeText,
                        entity: "DegreeRequirementEntity",
                        issue: "Missing programURL on requirements row",
                        degreeLevel: degreeLevelText,
                        sourceCatoid: sourceCatoid
                    )
                }

                // Try detailed format first (includes titles and credits)
                if let detailedJSON = r.requiredCoursesDetailedJSON {
                    if let detailedCourses = decodeDetailedCourseList(detailedJSON), !detailedCourses.isEmpty {
                        for detail in detailedCourses {
                            let code = detail.code.trimmingCharacters(in: .whitespacesAndNewlines)
                            let title = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let creditsText = detail.credits ?? creditsTextByCode[normalizeCourseCode(code)] ?? ""

                            lines.append(
                                combinedRowWithDescription(
                                    section: "CATALOG",
                                    degreeName: degreeName,
                                    department: dept,
                                    majorOrMinor: majorOrMinor,
                                    requirementCategory: category,
                                    mode: "required",
                                    courseCode: code,
                                    courseTitle: title,
                                    courseDescription: courseDescription(for: code),
                                    credits: creditsText,
                                    programURL: canonicalURL,
                                    degreeType: degreeTypeText,
                                    entity: "",
                                    issue: "",
                                    degreeLevel: degreeLevelText,
                                    sourceCatoid: sourceCatoid
                                )
                            )
                            emittedAny = true

                            let hasAny = !code.isEmpty || !title.isEmpty || detail.credits != nil
                            if hasAny {
                                var missing: [String] = []
                                if code.isEmpty { missing.append("code") }
                                if title.isEmpty { missing.append("title") }
                                if detail.credits == nil { missing.append("credits") }
                                if !missing.isEmpty {
                                    emitAudit(
                                        degreeName: degreeName,
                                        department: dept,
                                        majorOrMinor: majorOrMinor,
                                        requirementCategory: category,
                                        mode: "required",
                                        courseCode: code,
                                        courseTitle: title,
                                        credits: creditsText,
                                        programURL: canonicalURL,
                                        degreeType: degreeTypeText,
                                        entity: "DegreeRequirementEntity.requiredCoursesDetailedJSON",
                                        issue: "Partial course detail: missing \(missing.joined(separator: ", "))",
                                        degreeLevel: degreeLevelText,
                                        sourceCatoid: sourceCatoid
                                    )
                                }
                            }
                        }
                    } else {
                        emitAudit(
                            degreeName: degreeName,
                            department: dept,
                            majorOrMinor: majorOrMinor,
                            requirementCategory: category,
                            mode: "required",
                            courseCode: "",
                            courseTitle: "",
                            credits: "",
                            programURL: canonicalURL,
                            degreeType: degreeTypeText,
                            entity: "DegreeRequirementEntity.requiredCoursesDetailedJSON",
                            issue: "Invalid or empty requiredCoursesDetailedJSON",
                            degreeLevel: degreeLevelText,
                            sourceCatoid: sourceCatoid
                        )
                    }
                } else {
                    // Fallback to legacy format (codes only)
                    let required = splitCourseList(r.requiredCourses)
                    if !required.isEmpty {
                        for course in required {
                            lines.append(
                                combinedRowWithDescription(
                                    section: "CATALOG",
                                    degreeName: degreeName,
                                    department: dept,
                                    majorOrMinor: majorOrMinor,
                                    requirementCategory: category,
                                    mode: "required",
                                    courseCode: course,
                                    courseTitle: "",
                                    courseDescription: courseDescription(for: course),
                                    credits: creditsTextByCode[normalizeCourseCode(course)] ?? "",
                                    programURL: canonicalURL,
                                    degreeType: degreeTypeText,
                                    entity: "",
                                    issue: "",
                                    degreeLevel: degreeLevelText,
                                    sourceCatoid: sourceCatoid
                                )
                            )
                            emittedAny = true
                        }
                    }
                }

                // Handle select-from courses
                if let selectDetailedJSON = r.selectFromDetailedJSON {
                    if let selectDetailed = decodeDetailedCourseList(selectDetailedJSON), !selectDetailed.isEmpty {
                        for detail in selectDetailed {
                            let code = detail.code.trimmingCharacters(in: .whitespacesAndNewlines)
                            let title = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let creditsText = detail.credits ?? creditsTextByCode[normalizeCourseCode(code)] ?? ""

                            lines.append(
                                combinedRowWithDescription(
                                    section: "CATALOG",
                                    degreeName: degreeName,
                                    department: dept,
                                    majorOrMinor: majorOrMinor,
                                    requirementCategory: category,
                                    mode: "select",
                                    courseCode: code,
                                    courseTitle: title,
                                    courseDescription: courseDescription(for: code),
                                    credits: creditsText,
                                    programURL: canonicalURL,
                                    degreeType: degreeTypeText,
                                    entity: "",
                                    issue: "",
                                    degreeLevel: degreeLevelText,
                                    sourceCatoid: sourceCatoid
                                )
                            )
                            emittedAny = true

                            let hasAny = !code.isEmpty || !title.isEmpty || detail.credits != nil
                            if hasAny {
                                var missing: [String] = []
                                if code.isEmpty { missing.append("code") }
                                if title.isEmpty { missing.append("title") }
                                if detail.credits == nil { missing.append("credits") }
                                if !missing.isEmpty {
                                    emitAudit(
                                        degreeName: degreeName,
                                        department: dept,
                                        majorOrMinor: majorOrMinor,
                                        requirementCategory: category,
                                        mode: "select",
                                        courseCode: code,
                                        courseTitle: title,
                                        credits: creditsText,
                                        programURL: canonicalURL,
                                        degreeType: degreeTypeText,
                                        entity: "DegreeRequirementEntity.selectFromDetailedJSON",
                                        issue: "Partial course detail: missing \(missing.joined(separator: ", "))",
                                        degreeLevel: degreeLevelText,
                                        sourceCatoid: sourceCatoid
                                    )
                                }
                            }
                        }
                    } else {
                        emitAudit(
                            degreeName: degreeName,
                            department: dept,
                            majorOrMinor: majorOrMinor,
                            requirementCategory: category,
                            mode: "select",
                            courseCode: "",
                            courseTitle: "",
                            credits: "",
                            programURL: canonicalURL,
                            degreeType: degreeTypeText,
                            entity: "DegreeRequirementEntity.selectFromDetailedJSON",
                            issue: "Invalid or empty selectFromDetailedJSON",
                            degreeLevel: degreeLevelText,
                            sourceCatoid: sourceCatoid
                        )
                    }
                } else {
                    // Fallback to legacy format
                    let selectFrom = decodeJSONCourseList(r.selectFromJSON).map(normalizeCourseCode).filter { !$0.isEmpty }
                    if !selectFrom.isEmpty {
                        for course in selectFrom {
                            lines.append(
                                combinedRowWithDescription(
                                    section: "CATALOG",
                                    degreeName: degreeName,
                                    department: dept,
                                    majorOrMinor: majorOrMinor,
                                    requirementCategory: category,
                                    mode: "select",
                                    courseCode: course,
                                    courseTitle: "",
                                    courseDescription: courseDescription(for: course),
                                    credits: creditsTextByCode[normalizeCourseCode(course)] ?? "",
                                    programURL: canonicalURL,
                                    degreeType: degreeTypeText,
                                    entity: "",
                                    issue: "",
                                    degreeLevel: degreeLevelText,
                                    sourceCatoid: sourceCatoid
                                )
                            )
                            emittedAny = true
                        }
                    }
                }

                // If a category exists but contains no extractable courses, still emit a row for auditability.
                let requiredDetailedCount = r.requiredCoursesDetailedJSON.flatMap { decodeDetailedCourseList($0)?.count } ?? 0
                let selectDetailedCount = r.selectFromDetailedJSON.flatMap { decodeDetailedCourseList($0)?.count } ?? 0
                let hasRequiredCourses = requiredDetailedCount > 0 || !splitCourseList(r.requiredCourses).isEmpty
                let hasSelectCourses = selectDetailedCount > 0 || !decodeJSONCourseList(r.selectFromJSON).isEmpty
                
                if !hasRequiredCourses, !hasSelectCourses, !category.isEmpty {
                    lines.append(
                        combinedRow(
                            section: "CATALOG",
                            degreeName: degreeName,
                            department: dept,
                            majorOrMinor: majorOrMinor,
                            requirementCategory: category,
                            mode: "",
                            courseCode: "",
                            courseTitle: "",
                            credits: "",
                            programURL: canonicalURL,
                            degreeType: degreeTypeText,
                            entity: "",
                            issue: "",
                            degreeLevel: degreeLevelText,
                            sourceCatoid: sourceCatoid
                        )
                    )
                    emittedAny = true
                }
                }

                if !emittedAny {
                    lines.append(
                        combinedRow(
                            section: "CATALOG",
                            degreeName: degreeName,
                            department: dept,
                            majorOrMinor: majorOrMinor,
                            requirementCategory: "",
                            mode: "",
                            courseCode: "",
                            courseTitle: "",
                            credits: "",
                            programURL: canonicalURL,
                            degreeType: degreeTypeText,
                            entity: "",
                            issue: "",
                            degreeLevel: degreeLevelText,
                            sourceCatoid: sourceCatoid
                        )
                    )
                }

                emittedAnyForProgram = true
            }

            if !emittedAnyForProgram {
                let combinedCatoids = parseSourceCatoidsField(p.sourceCatoids)
                    .sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
                    .joined(separator: ";")
                emitAudit(
                    degreeName: degreeName,
                    department: dept,
                    majorOrMinor: majorOrMinor,
                    requirementCategory: "",
                    mode: "",
                    courseCode: "",
                    courseTitle: "",
                    credits: "",
                    programURL: (p.programURL ?? ""),
                    degreeType: degreeTypeText,
                    entity: "DegreeRequirementEntity",
                    issue: "No requirements found",
                    degreeLevel: degreeLevelText,
                    sourceCatoid: combinedCatoids
                )
            }
        }

        // Append audit rows after all catalog rows.
        lines.append(contentsOf: auditLines)

        let csvText = lines.joined(separator: "\n")
        let csvData = Data(csvText.utf8)

        let tempDir = FileManager.default.temporaryDirectory
        let safeName = universityName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = "\(safeName)_scraped_catalog_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = tempDir.appendingPathComponent(filename)
        try csvData.write(to: fileURL)
        print("[CoreData] Exported scraped catalog CSV to: \(fileURL.path)")
        return fileURL
    }

    @MainActor
    private func scrapeAllProgramRequirementsForExport(universityName: String) async throws -> URL {
        let university = try fetchUniversity(name: universityName)
        let logger = DebugLogger.shared

        func canonicalizeForScrape(_ urlString: String) -> String {
            // Remove returnto and fragments to make program identity stable.
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            guard var components = URLComponents(string: trimmed) else { return trimmed }
            if let items = components.queryItems, !items.isEmpty {
                let filtered = items.filter { $0.name.lowercased() != "returnto" }
                components.queryItems = filtered.isEmpty ? nil : filtered
            }
            components.fragment = nil
            var rebuilt = components.string ?? trimmed
            if rebuilt.hasSuffix("?") { rebuilt.removeLast() }
            return rebuilt
        }

        // Fetch programs for this university.
        let programRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        programRequest.predicate = NSPredicate(format: "university == %@", university)
        programRequest.sortDescriptors = [
            NSSortDescriptor(key: "isMinor", ascending: true),
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "degreeType", ascending: true)
        ]
        let programs = (try? viewContext.fetch(programRequest)) ?? []

        struct AuditRow {
            let degreeName: String
            let degreeType: String
            let programURL: String
            let signature: String
            let categories: Int
            let requiredCount: Int
            let selectCount: Int
            let uniqueCount: Int
            let error: String
        }

        func degreeNameFor(_ p: MajorEntity) -> String {
            let rawName = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dt = (p.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isMinor { return rawName }
            if dt.isEmpty { return rawName }
            // Keep display consistent with export.
            let token = dt.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
            return "\(rawName), \(token)"
        }

        var rows: [AuditRow] = []
        rows.reserveCapacity(programs.count)

        for p in programs {
            let rawURL = (p.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalURL = canonicalizeForScrape(rawURL)
            let dt = (p.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let majorName = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let degreeName = degreeNameFor(p)

            guard !canonicalURL.isEmpty else {
                rows.append(
                    AuditRow(
                        degreeName: degreeName,
                        degreeType: dt,
                        programURL: rawURL,
                        signature: "",
                        categories: 0,
                        requiredCount: 0,
                        selectCount: 0,
                        uniqueCount: 0,
                        error: "Missing programURL"
                    )
                )
                continue
            }

            do {
                let scraper = UniversalCatalogScraper()
                let parsed = try await scraper.scrapeProgramRequirementsWithDiagnostics(programURL: canonicalURL)

                // Persist snapshot to DegreeRequirementEntity keyed by canonicalURL + degreeType.
                let requirements = parsed.requirements
                let diagnostics = parsed.diagnostics
                let newHash = stableRequirementsHash(requirements)

                let existingRequest = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
                existingRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "university == %@", university),
                    NSPredicate(format: "programURL == %@", canonicalURL),
                    NSPredicate(format: "degreeType == %@", dt.isEmpty ? "Unknown" : dt)
                ])
                let existingRows = (try? viewContext.fetch(existingRequest)) ?? []

                var processedCategories = Set<String>()
                for (i, category) in requirements.enumerated() {
                    let cat = category.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cat.isEmpty else { continue }
                    processedCategories.insert(cat)

                    let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                        NSPredicate(format: "university == %@", university),
                        NSPredicate(format: "programURL == %@", canonicalURL),
                        NSPredicate(format: "degreeType == %@", dt.isEmpty ? "Unknown" : dt),
                        NSPredicate(format: "requirementCategory == %@", cat)
                    ])
                    let existing = try? viewContext.fetch(request).first
                    let entity = existing ?? DegreeRequirementEntity(context: viewContext)
                    if existing == nil {
                        entity.id = UUID()
                        entity.university = university
                    }

                    entity.programURL = canonicalURL
                    entity.major = majorName
                    entity.degreeType = dt.isEmpty ? "Unknown" : dt
                    entity.requirementCategory = cat
                    entity.sectionOrder = Int16(i)
                    entity.creditsRequired = Int16(category.creditsRequired)
                    entity.descriptionText = category.description

                    if let required = category.requiredCourses, !required.isEmpty {
                        entity.requiredCourses = required.joined(separator: ", ")
                    } else {
                        entity.requiredCourses = nil
                    }

                    if let selectFrom = category.selectFrom, !selectFrom.isEmpty {
                        entity.selectFromJSON = encodeJSONCourseList(selectFrom)
                        if let c = category.selectCount {
                            entity.selectCount = Int16(c)
                        } else {
                            entity.selectCount = 0
                        }
                    } else {
                        entity.selectFromJSON = nil
                        entity.selectCount = 0
                    }

                    entity.requirementsHash = newHash
                    entity.lastScrapedAt = Date()
                    entity.lastUpdated = Date()
                }

                for row in existingRows {
                    let cat = (row.requirementCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cat.isEmpty, !processedCategories.contains(cat) {
                        viewContext.delete(row)
                    }
                }

                save()

                rows.append(
                    AuditRow(
                        degreeName: degreeName,
                        degreeType: dt,
                        programURL: canonicalURL,
                        signature: diagnostics.signature,
                        categories: diagnostics.categoriesFound,
                        requiredCount: diagnostics.requiredCourseCount,
                        selectCount: diagnostics.selectCourseCount,
                        uniqueCount: diagnostics.uniqueCourseCount,
                        error: ""
                    )
                )
            } catch {
                logger.scraper("❌ Batch requirements scrape failed for \(canonicalURL): \(error)", level: .error)
                rows.append(
                    AuditRow(
                        degreeName: degreeName,
                        degreeType: dt,
                        programURL: canonicalURL,
                        signature: "",
                        categories: 0,
                        requiredCount: 0,
                        selectCount: 0,
                        uniqueCount: 0,
                        error: error.localizedDescription
                    )
                )
            }
        }

        func csvEscape(_ value: String) -> String {
            if value.contains("\"") {
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            if value.contains(",") || value.contains("\n") || value.contains("\r") {
                return "\"\(value)\""
            }
            return value
        }

        // Sort by signature then degree name so similar layouts are grouped.
        rows.sort { (a, b) in
            if a.signature != b.signature { return a.signature < b.signature }
            return a.degreeName < b.degreeName
        }

        var lines: [String] = []
        lines.append("Degree Name,Degree Type,Program URL,Layout Signature,Categories,Required Courses,Select Courses,Unique Courses,Error")
        for r in rows {
            lines.append([
                csvEscape(r.degreeName),
                csvEscape(r.degreeType),
                csvEscape(r.programURL),
                csvEscape(r.signature),
                String(r.categories),
                String(r.requiredCount),
                String(r.selectCount),
                String(r.uniqueCount),
                csvEscape(r.error)
            ].joined(separator: ","))
        }

        let csvText = lines.joined(separator: "\n")
        let csvData = Data(csvText.utf8)

        let tempDir = FileManager.default.temporaryDirectory
        let safeName = universityName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = "\(safeName)_requirements_audit_\(Int(Date().timeIntervalSince1970)).csv"
        let fileURL = tempDir.appendingPathComponent(filename)
        try csvData.write(to: fileURL)
        print("[CoreData] Exported requirements audit CSV to: \(fileURL.path)")
        return fileURL
    }
    
    private func fetchUniversity(name: String) throws -> UniversityEntity {
        let request = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
        request.predicate = NSPredicate(format: "name == %@", name)
        
        let results = try viewContext.fetch(request)
        guard let university = results.first else {
            throw NSError(domain: "CoreData", code: 404, userInfo: [NSLocalizedDescriptionKey: "University not found"])
        }
        return university
    }

    // MARK: - Policy Corrections

    /// Applies a user-provided correction to the locally stored school policies.
    /// This is intentionally best-effort: it updates only the requested policy and preserves the others.
    @MainActor
    func applyPolicyCorrection(
        universityName: String,
        policyName: String,
        correctedValue: String
    ) throws {
        let request = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
        request.predicate = NSPredicate(format: "name == %@", universityName)
        request.fetchLimit = 1

        guard let university = try viewContext.fetch(request).first else {
            throw NSError(domain: "CoreData", code: 404, userInfo: [NSLocalizedDescriptionKey: "University not found"])
        }

        let existing = activeSchoolPolicies(for: university) ?? SchoolPolicies(
            transferCreditLimit: nil,
            minorTransferLimit: nil,
            maxCreditsPerSemester: nil,
            minCreditsForFullTime: nil,
            gradeForCredit: nil,
            repeatCoursePolicy: nil
        )

        func parseFirstInt(_ input: String) -> Int? {
            let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            if let re = Self.cachedRegex("\\d+") {
                let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                if let match = re.firstMatch(in: cleaned, range: nsRange),
                   let r = Range(match.range(at: 0), in: cleaned) {
                    return Int(cleaned[r])
                }
            }
            return Int(cleaned)
        }

        func normalizedKey(_ raw: String) -> String {
            raw
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let key = normalizedKey(policyName)
        let trimmedValue = correctedValue.trimmingCharacters(in: .whitespacesAndNewlines)

        var transfer = existing.transferCreditLimit
        var minorTransfer = existing.minorTransferLimit
        var maxPerSem = existing.maxCreditsPerSemester
        var minFullTime = existing.minCreditsForFullTime
        var grade = existing.gradeForCredit
        var repeatPolicy = existing.repeatCoursePolicy

        switch key {
        case "transfer credit limit", "transfer credits limit", "transfer credit":
            transfer = parseFirstInt(trimmedValue)
        case "minor transfer limit", "minor transfer credits limit":
            minorTransfer = parseFirstInt(trimmedValue)
        case "max credits per semester", "max credits sem", "max credits / sem", "max credits per sem":
            maxPerSem = parseFirstInt(trimmedValue)
        case "min credits full time", "min credits for full time", "min credits fulltime":
            minFullTime = parseFirstInt(trimmedValue)
        case "grade for credit", "minimum grade for credit":
            grade = trimmedValue.isEmpty ? nil : trimmedValue.uppercased()
        case "repeat course policy":
            repeatPolicy = trimmedValue.isEmpty ? nil : trimmedValue
        default:
            throw NSError(domain: "CoreData", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported policy: \(policyName)"])
        }

        let updated = SchoolPolicies(
            transferCreditLimit: transfer,
            minorTransferLimit: minorTransfer,
            maxCreditsPerSemester: maxPerSem,
            minCreditsForFullTime: minFullTime,
            gradeForCredit: grade,
            repeatCoursePolicy: repeatPolicy
        )

        setActiveSchoolPolicies(updated, for: university)
        try viewContext.save()
    }

    // MARK: - School policies source of truth

    private static let schoolPoliciesDefaultsKey = "coreData.university.schoolPolicies.v1"

    /// Single source of truth for school policies. Policies are keyed by stable university UUID.
    @MainActor
    func activeSchoolPolicies() -> SchoolPolicies? {
        guard let university = getActiveUniversity() else { return nil }
        return activeSchoolPolicies(for: university)
    }

    /// Reads school policies for a specific university from the persisted policy store.
    @MainActor
    func activeSchoolPolicies(for university: UniversityEntity) -> SchoolPolicies? {
        guard let uid = university.id?.uuidString else { return nil }
        guard let dataByUniversity = UserDefaults.standard.dictionary(forKey: Self.schoolPoliciesDefaultsKey) as? [String: Data] else {
            return nil
        }
        guard let encoded = dataByUniversity[uid] else { return nil }
        return try? JSONDecoder().decode(SchoolPolicies.self, from: encoded)
    }

    /// Persists school policies for a specific university in the shared policy store.
    @MainActor
    func setActiveSchoolPolicies(_ policies: SchoolPolicies, for university: UniversityEntity) {
        guard let uid = university.id?.uuidString else { return }
        guard let encoded = try? JSONEncoder().encode(policies) else { return }
        var dataByUniversity = (UserDefaults.standard.dictionary(forKey: Self.schoolPoliciesDefaultsKey) as? [String: Data]) ?? [:]
        dataByUniversity[uid] = encoded
        UserDefaults.standard.set(dataByUniversity, forKey: Self.schoolPoliciesDefaultsKey)
    }

    // MARK: - Incremental scrape helpers

    @MainActor
    func catalogPresence(universityName: String) async -> (courses: Int, departments: Int, majors: Int, minors: Int) {
        func count(entityName: String, predicate: NSPredicate?) -> Int {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            request.resultType = .countResultType
            request.predicate = predicate
            return (try? viewContext.count(for: request)) ?? 0
        }

        let courses = count(
            entityName: "CourseCatalogEntity",
            predicate: NSPredicate(format: "university.name == %@", universityName)
        )
        let departments = count(
            entityName: "DepartmentEntity",
            predicate: NSPredicate(format: "university.name == %@", universityName)
        )
        let majors = count(
            entityName: "MajorEntity",
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university.name == %@", universityName),
                NSPredicate(format: "isMinor == NO")
            ])
        )
        let minors = count(
            entityName: "MajorEntity",
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university.name == %@", universityName),
                NSPredicate(format: "isMinor == YES")
            ])
        )

        return (courses: courses, departments: departments, majors: majors, minors: minors)
    }

    /// Returns quick counts for what is already stored in Core Data, to avoid re-scraping data
    /// that is already present.
    ///
    /// Notes:
    /// - Courses: We persist per-catalog course scrape completion in `CatalogScrapeStateEntity`.
    ///   This gives exact incremental behavior per `catoid` without duplicating catalog courses.
    /// - Programs/requirements *do* carry `catoid` in their URLs, so we count per catalog via URL predicates.
    @MainActor
    func scrapeCoverage(universityName: String, catoids: [String]) async -> (totalCourses: Int, coursesByCatoid: [String: Int], programsByCatoid: [String: Int], requirementsByCatoid: [String: Int]) {
        func count(entityName: String, predicate: NSPredicate?) -> Int {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            request.resultType = .countResultType
            request.predicate = predicate
            return (try? viewContext.count(for: request)) ?? 0
        }

        let totalCourses = count(
            entityName: "CourseCatalogEntity",
            predicate: NSPredicate(format: "university.name == %@", universityName)
        )

        var coursesByCatoid: [String: Int] = [:]
        coursesByCatoid.reserveCapacity(catoids.count)
        for catoid in catoids {
            if coursesByCatoid[catoid] == nil {
                coursesByCatoid[catoid] = 0
            }
        }
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CatalogScrapeStateEntity")
            request.predicate = NSPredicate(format: "university.name == %@", universityName)
            let states = try viewContext.fetch(request)
            for state in states {
                guard let catoid = state.value(forKey: "catoid") as? String else { continue }
                if coursesByCatoid[catoid] == nil { continue }
                let rawCount = state.value(forKey: "courseCount")
                if let c32 = rawCount as? Int32 {
                    coursesByCatoid[catoid] = Int(c32)
                } else if let c64 = rawCount as? Int64 {
                    coursesByCatoid[catoid] = Int(c64)
                } else if let c = rawCount as? Int {
                    coursesByCatoid[catoid] = c
                }
            }
        } catch {
            // Best effort only.
        }

        var programsByCatoid: [String: Int] = [:]
        var requirementsByCatoid: [String: Int] = [:]
        programsByCatoid.reserveCapacity(catoids.count)
        requirementsByCatoid.reserveCapacity(catoids.count)

        let allProgramsForUniversity: [MajorEntity] = {
            let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
            request.predicate = NSPredicate(format: "university.name == %@", universityName)
            return (try? viewContext.fetch(request)) ?? []
        }()

        // Programs can be multi-catalog while keeping a stable primary `programURL`.
        // Count with exact catoid token matching to avoid partial-match false positives.
        for catoid in catoids {
            let needle = "catoid=\(catoid)"
            programsByCatoid[catoid] = allProgramsForUniversity.filter {
                majorMatchesCatoid($0, targetCatoid: catoid)
            }.count

            // Requirements remain keyed by `programURL`, so this stays URL-based.
            requirementsByCatoid[catoid] = count(
                entityName: "DegreeRequirementEntity",
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "university.name == %@", universityName),
                    NSPredicate(format: "programURL CONTAINS[c] %@", needle)
                ])
            )
        }

        return (totalCourses: totalCourses, coursesByCatoid: coursesByCatoid, programsByCatoid: programsByCatoid, requirementsByCatoid: requirementsByCatoid)
    }

    /// Returns true if requirements reference courses with a given subject prefix (e.g., "LAW")
    /// but the stored catalog course rows for that prefix are missing/incomplete.
    ///
    /// This is used to trigger a targeted course rescrape for parallel catalogs (e.g., Law catalog)
    /// so cross-catalog requirements can be fully described.
    @MainActor
    func shouldForceCourseRescrapeForSubject(universityName: String, subjectPrefix: String) -> Bool {
        let prefix = subjectPrefix
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !prefix.isEmpty else { return false }

        func count(entityName: String, predicate: NSPredicate?) -> Int {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            request.resultType = .countResultType
            request.predicate = predicate
            return (try? viewContext.count(for: request)) ?? 0
        }

        // 1) Do any requirement fields reference this prefix?
        // Use CONTAINS so we catch both "LAW 500" and JSON-encoded lists.
        let reqPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "university.name == %@", universityName),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "requiredCourses CONTAINS[cd] %@", prefix),
                NSPredicate(format: "requiredCoursesDetailedJSON CONTAINS[cd] %@", prefix),
                NSPredicate(format: "selectFromJSON CONTAINS[cd] %@", prefix),
                NSPredicate(format: "selectFromDetailedJSON CONTAINS[cd] %@", prefix)
            ])
        ])
        let referenced = count(entityName: "DegreeRequirementEntity", predicate: reqPredicate)
        guard referenced > 0 else { return false }

        // 2) Are we missing catalog rows for this prefix entirely?
        // NOTE: normalizeCourseCode canonicalizes to "PREFIX NNN" so a BEGINSWITH check is safe.
        let fullPrefix = "\(prefix) "
        let totalForPrefix = count(
            entityName: "CourseCatalogEntity",
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university.name == %@", universityName),
                NSPredicate(format: "courseCode BEGINSWITH[cd] %@", fullPrefix)
            ])
        )
        if totalForPrefix == 0 { return true }

        // 3) Or are many of them incomplete (missing description or credits)?
        let incompleteForPrefix = count(
            entityName: "CourseCatalogEntity",
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university.name == %@", universityName),
                NSPredicate(format: "courseCode BEGINSWITH[cd] %@", fullPrefix),
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "descriptionText == nil OR descriptionText == ''"),
                    NSPredicate(format: "credits <= 0")
                ])
            ])
        )
        return incompleteForPrefix > 0
    }

    /// Persist (or update) the per-catalog course scrape completion marker.
    ///
    /// This is what enables "perfect incremental" behavior for courses across multi-catalog ModernCampus sites.
    @MainActor
    func upsertCourseScrapeState(universityName: String, catoid: String, catalogTitle: String?, courseCount: Int, scrapedAt: Date = Date()) async {
        guard !universityName.isEmpty, !catoid.isEmpty else { return }
        do {
            let university = try fetchUniversity(name: universityName)

            let request = NSFetchRequest<NSManagedObject>(entityName: "CatalogScrapeStateEntity")
            request.fetchLimit = 1
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university == %@", university),
                NSPredicate(format: "catoid == %@", catoid)
            ])

            let existing = try viewContext.fetch(request).first
            let state = existing ?? NSManagedObject(entity: NSEntityDescription.entity(forEntityName: "CatalogScrapeStateEntity", in: viewContext)!, insertInto: viewContext)

            if existing == nil {
                state.setValue(UUID(), forKey: "id")
                state.setValue(university, forKey: "university")
                state.setValue(catoid, forKey: "catoid")
            }

            if let catalogTitle, !catalogTitle.isEmpty {
                state.setValue(catalogTitle, forKey: "catalogTitle")
            }
            state.setValue(Int32(max(0, courseCount)), forKey: "courseCount")
            state.setValue(scrapedAt, forKey: "lastScrapedAt")

            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            // Best effort; incremental markers shouldn't break scraping.
        }
    }
}

// MARK: - Course Catalog Operations

extension CoreDataManager {
    /// Search courses in the catalog
    func searchCatalogCourses(query: String, limit: Int = 50) -> [CourseCatalogEntity] {
        guard let university = getActiveUniversity() else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        if trimmed.isEmpty {
            request.predicate = NSPredicate(
                format: "(isArchived == NO OR isArchived == nil) AND university == %@",
                university
            )
        } else {
            // Build a spaced variant so "MGS410" also matches "MGS 410":
            // insert a space before the first digit run when no space is present.
            let spacedVariant: String? = {
                guard !trimmed.contains(" "),
                      trimmed.first?.isLetter == true,
                      let range = trimmed.range(of: #"(?<=[A-Za-z])(?=\d)"#, options: .regularExpression) else { return nil }
                var s = trimmed
                s.insert(" ", at: range.lowerBound)
                return s
            }()

            if let sv = spacedVariant {
                request.predicate = NSPredicate(
                    format: "(isArchived == NO OR isArchived == nil) AND (courseCode CONTAINS[cd] %@ OR courseCode CONTAINS[cd] %@ OR title CONTAINS[cd] %@) AND university == %@",
                    trimmed, sv, trimmed, university
                )
            } else {
                request.predicate = NSPredicate(
                    format: "(isArchived == NO OR isArchived == nil) AND (courseCode CONTAINS[cd] %@ OR title CONTAINS[cd] %@) AND university == %@",
                    trimmed, trimmed, university
                )
            }
        }
        request.sortDescriptors = [NSSortDescriptor(key: "courseCode", ascending: true)]
        request.fetchLimit = max(limit * 4, 200)

        let fetched = (try? viewContext.fetch(request)) ?? []

        // If the catalog rows are incomplete (common when requirements scraping is richer than the
        // course-catalog scrape), backfill from DegreeRequirementEntity detailed course info.
        backfillCatalogCoursesFromRequirementsIfNeeded(fetched, university: university)

        return dedupeCatalogCourses(fetched, limit: limit)
    }

    func activeUniversityHasCatalogCourses() -> Bool {
        guard let university = getActiveUniversity() else { return false }
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(
            format: "(isArchived == NO OR isArchived == nil) AND university == %@",
            university
        )
        request.fetchLimit = 1
        return ((try? viewContext.count(for: request)) ?? 0) > 0
    }

    private struct RequirementCourseInfo {
        let title: String?
        let credits: Int?
    }

    private func backfillCatalogCoursesFromRequirementsIfNeeded(_ courses: [CourseCatalogEntity], university: UniversityEntity) {
        guard !courses.isEmpty else { return }

        // Quick check: if none are missing core fields, skip the expensive requirements scan.
        let needsBackfill = courses.contains { c in
            let code = normalizeCourseCode(c.courseCode ?? "")
            let title = (c.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTitle = normalizeCourseCode(title)
            return Int(c.credits) <= 0 || title.isEmpty || (!code.isEmpty && normalizedTitle == code)
        }
        guard needsBackfill else { return }

        // Use session-level cache to avoid re-fetching all requirements on every keystroke.
        let univID = university.objectID
        let bestByCode: [String: RequirementCourseInfo]
        if let cached = requirementBackfillCache[univID] {
            bestByCode = cached
        } else {
            // Build best-known details per course code from scraped requirements.
            let reqRequest = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
            reqRequest.predicate = NSPredicate(format: "university == %@", university)
            reqRequest.fetchLimit = 0
            let reqs = (try? viewContext.fetch(reqRequest)) ?? []

            var built: [String: RequirementCourseInfo] = [:]
            built.reserveCapacity(256)

            func consider(_ detail: CourseDetail) {
                let code = normalizeCourseCode(detail.code)
                guard !code.isEmpty else { return }

                let rawTitle = (detail.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String? = {
                    guard !rawTitle.isEmpty else { return nil }
                    if normalizeCourseCode(rawTitle) == code { return nil }
                    return rawTitle
                }()
                let credits: Int? = {
                    guard let c = detail.credits, !c.isEmpty else { return nil }
                    // Try to extract the first number from credit strings like "3" or "1-6"
                    if let match = c.range(of: "\\d+", options: .regularExpression),
                       let num = Int(c[match]), num > 0 {
                        return num
                    }
                    return nil
                }()

                guard title != nil || credits != nil else { return }

                let candidate = RequirementCourseInfo(title: title, credits: credits)
                if let current = built[code] {
                    let currentScore = (current.credits != nil ? 2 : 0) + (current.title != nil ? 1 : 0)
                    let candidateScore = (candidate.credits != nil ? 2 : 0) + (candidate.title != nil ? 1 : 0)
                    if candidateScore > currentScore {
                        built[code] = candidate
                    }
                } else {
                    built[code] = candidate
                }
            }

            for req in reqs {
                if let detailed = decodeDetailedCourseList(req.requiredCoursesDetailedJSON) {
                    for d in detailed { consider(d) }
                }
                if let detailed = decodeDetailedCourseList(req.selectFromDetailedJSON) {
                    for d in detailed { consider(d) }
                }
            }

            requirementBackfillCache[univID] = built
            bestByCode = built
        }

        guard !bestByCode.isEmpty else { return }

        var changed = false
        for c in courses {
            let code = normalizeCourseCode(c.courseCode ?? "")
            guard !code.isEmpty, let info = bestByCode[code] else { continue }

            if Int(c.credits) <= 0, let credits = info.credits, credits > 0 {
                c.credits = Int16(credits)
                changed = true
            }

            let currentTitle = (c.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCurrentTitle = normalizeCourseCode(currentTitle)
            let titleIsLowQuality = currentTitle.isEmpty || normalizedCurrentTitle == code
            if titleIsLowQuality, let title = info.title, !title.isEmpty {
                c.title = title
                changed = true
            }
        }

        if changed {
            save()
        }
    }

    private func dedupeCatalogCourses(_ courses: [CourseCatalogEntity], limit: Int) -> [CourseCatalogEntity] {
        var bestByCode: [String: CourseCatalogEntity] = [:]

        for course in courses {
            let rawCode = (course.courseCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeCourseCode(rawCode)
            guard !key.isEmpty else { continue }

            if let currentBest = bestByCode[key] {
                if catalogCourseQualityScore(course) > catalogCourseQualityScore(currentBest) {
                    bestByCode[key] = course
                }
            } else {
                bestByCode[key] = course
            }
        }

        let sorted = bestByCode.values.sorted {
            let a = ($0.courseCode ?? "")
            let b = ($1.courseCode ?? "")
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }

        return Array(sorted.prefix(limit))
    }

    private func catalogCourseQualityScore(_ course: CourseCatalogEntity) -> Int {
        let code = (course.courseCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (course.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = normalizeCourseCode(code)
        let normalizedTitle = normalizeCourseCode(title)

        var score = 0
        if Int(course.credits) > 0 { score += 3 }
        if !title.isEmpty && !normalizedTitle.isEmpty && normalizedTitle != normalizedCode { score += 2 }
        if let desc = course.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        return score
    }
    
    /// Get course from catalog by code
    func getCatalogCourse(code: String) -> CourseCatalogEntity? {
        guard let university = getActiveUniversity() else { return nil }
        
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(
            format: "courseCode == %@ AND university == %@",
            code, university
        )
        request.fetchLimit = 50

        let matches = (try? viewContext.fetch(request)) ?? []
        if matches.isEmpty { return nil }
        if matches.count == 1 { return matches[0] }

        // Prefer the highest-quality row when duplicates exist.
        return matches.max(by: { catalogCourseQualityScore($0) < catalogCourseQualityScore($1) })
    }

    // MARK: - GenEd Helpers

    private func normalizeCourseCode(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        // Canonicalize common catalog variants:
        // - "CSE410LEC" / "CSE 410LEC" / "CSE 410" -> "CSE 410"
        // - "MTH 131LR" -> "MTH 131"
        if let re = Self.cachedRegex("\\b([A-Z]{2,6})\\s*[-–]?\\s*([0-9]{2,4})\\b") {
            let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            if let m = re.firstMatch(in: cleaned, range: nsRange), m.numberOfRanges >= 3,
               let r1 = Range(m.range(at: 1), in: cleaned),
               let r2 = Range(m.range(at: 2), in: cleaned) {
                return "\(cleaned[r1]) \(cleaned[r2])"
            }
        }

        return cleaned
    }

    private func plannedCourse(for normalizedCode: String) -> CourseEntity? {
        let needle = normalizeCourseCode(normalizedCode)
        guard !needle.isEmpty else { return nil }
        return plans
            .flatMap { $0.semestersArray }
            .flatMap { $0.coursesArray }
            .first(where: { normalizeCourseCode($0.code ?? "") == needle })
    }

    private func defaultSemesterForNewCourses() -> SemesterEntity? {
        let semesters = plans.flatMap { $0.semestersArray }
        let planned = semesters.filter { $0.isPlanned }
        return planned.sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.seasonOrder < $1.seasonOrder
        }.first
    }

    /// Adds the course to the plan (if missing) and tags it for GenEd.
    /// - Behavior:
    ///   - If the course already exists in any planned semester, it is just tagged `countsTowardGenEd = true`.
    ///   - Otherwise it is created in the earliest planned semester.
    func addOrTagGenEdCourse(from catalogCourse: CourseCatalogEntity) {
        addCatalogCourse(from: catalogCourse, targetSemesterID: nil, tagAsGenEd: true)
    }

    /// Adds a catalog course to the plan (if missing), optionally tagging it for GenEd.
    /// - If `targetSemesterID` is provided, the course is created in that semester.
    /// - Otherwise it is created in the earliest planned semester.
    /// - If the course already exists anywhere in the plan, it is updated (linked + optional GenEd tag) and not duplicated.
    func addCatalogCourse(from catalogCourse: CourseCatalogEntity, targetSemesterID: NSManagedObjectID?, tagAsGenEd: Bool) {
        let code = normalizeCourseCode(catalogCourse.courseCode ?? "")
        guard !code.isEmpty else { return }

        if let existing = plannedCourse(for: code) {
            if tagAsGenEd { existing.countsTowardGenEd = true }
            if existing.catalogCourse == nil { existing.catalogCourse = catalogCourse }
            if existing.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                existing.name = (catalogCourse.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if existing.creditsInt == 0 {
                let resolved = resolvedCatalogCredits(for: catalogCourse)
                if resolved > 0 { existing.credits = Int16(resolved) }
            }
            save()
            return
        }

        let targetSemester: SemesterEntity? = {
            guard let targetSemesterID else { return nil }
            return (try? viewContext.existingObject(with: targetSemesterID)) as? SemesterEntity
        }()

        guard let semester = targetSemester ?? defaultSemesterForNewCourses() else {
            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Add a Semester First",
                    message: "Create a planned semester before adding courses from the catalog.",
                    isDismissible: true,
                    autoDismissAfter: 6
                )
            }
            return
        }

        let resolvedCredits = resolvedCatalogCredits(for: catalogCourse)
        let newCourse = addCourse(
            to: semester,
            code: code,
            name: (catalogCourse.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            credits: resolvedCredits,
            status: "Planned",
            gradingType: "Letter Grade",
            professor: nil
        )

        if tagAsGenEd { newCourse.countsTowardGenEd = true }
        newCourse.catalogCourse = catalogCourse
        save()

        // Retroactively claim any floating calendar events that match this course code.
        let capturedCode = newCourse.code ?? code
        let semesterObjectID = semester.objectID
        Task { @MainActor in
            guard let sem = (CoreDataManager.shared.viewContext.object(with: semesterObjectID)) as? SemesterEntity else { return }
            await CalendarCourseLinker.shared.scanAndLink(forCode: capturedCode, in: sem)
        }
    }

    private func resolvedCatalogCredits(for course: CourseCatalogEntity) -> Int {
        let base = Int(course.credits)
        if base > 0 { return base }

        guard let desc = course.descriptionText?.lowercased() else { return 0 }
        // Common formats: "3 credits", "Credits: 3", "Credit hours: 4"
        let patterns = [
            "credits?\\s*[:\\-]?\\s*(\\d{1,2})",
            "(\\d{1,2})\\s*credits?",
            "credit\\s*hours?\\s*[:\\-]?\\s*(\\d{1,2})"
        ]
        for p in patterns {
            if let re = Self.cachedRegex(p) {
                let nsRange = NSRange(desc.startIndex..<desc.endIndex, in: desc)
                if let m = re.firstMatch(in: desc, range: nsRange), m.numberOfRanges >= 2,
                   let r1 = Range(m.range(at: 1), in: desc),
                   let value = Int(desc[r1]) {
                    return value
                }
            }
        }

        return 0
    }

    func upsertCourseOverride(
        courseCode: String,
        courseName: String?,
        credits: Double?,
        professor: String?,
        semesterText: String?,
        status: String,
        grade: String?,
        gradingType: String,
        externalURL: String?
    ) {
        guard let university = getActiveUniversity() else { return }
        let normalizedCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return }

        let existing = getCourseOverride(courseCode: normalizedCode)
        let overrideEntity = existing ?? {
            let created = CourseOverrideEntity(context: viewContext)
            created.id = UUID()
            created.courseCode = normalizedCode
            created.university = university
            created.lastUpdated = Date()
            return created
        }()

        if let courseName {
            overrideEntity.courseName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if existing == nil {
            overrideEntity.courseName = ""
        }

        if let credits {
            overrideEntity.credits = credits
        } else if existing == nil {
            overrideEntity.credits = 0.0
        }
        overrideEntity.professor = professor?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideEntity.semesterText = semesterText?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideEntity.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideEntity.grade = grade?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideEntity.gradingType = gradingType.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideEntity.externalURL = externalURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrideEntity.lastUpdated = Date()

        // Also propagate grade to the matching CourseEntity so recomputeProfileAcademics
        // can read it for live GPA calculation.
        let courseRequest = NSFetchRequest<CourseEntity>(entityName: "CourseEntity")
        courseRequest.predicate = NSPredicate(format: "code ==[c] %@", normalizedCode)
        courseRequest.fetchLimit = 1
        if let liveEntity = (try? viewContext.fetch(courseRequest))?.first {
            liveEntity.grade = overrideEntity.grade
            if let s = overrideEntity.status, !s.isEmpty { liveEntity.status = s }
            liveEntity.isCompleted = (liveEntity.status == "Completed")
        }

        recomputeProfileAcademics()   // update GPA/credits with new grade in memory
        save()
    }

    /// Persists instructor/professor contact details extracted from a syllabus.
    ///
    /// Writes to `CourseOverrideEntity` (so user edits survive re-scrapes) and also updates the planned
    /// `CourseEntity` if it exists, so the dashboard reflects the latest instructor details.
    @discardableResult
    func upsertCourseInstructorContact(
        courseCode: String,
        professorName: String?,
        email: String?,
        contactMethod: String?,
        officeHours: String?,
        overwriteExisting: Bool = false
    ) -> Bool {
        let normalizedCode = courseCode
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedCode.isEmpty else { return false }

        let trimmedName = professorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContact = contactMethod?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOfficeHours = officeHours?.trimmingCharacters(in: .whitespacesAndNewlines)

        var didChange = false

        if let university = resolvedUniversityForOverrides() {
            let overrideEntity = getCourseOverride(courseCode: normalizedCode) ?? {
                let created = CourseOverrideEntity(context: viewContext)
                created.id = UUID()
                created.courseCode = normalizedCode
                created.university = university
                created.lastUpdated = Date()
                return created
            }()

            func shouldWrite(_ current: String?) -> Bool {
                if overwriteExisting { return true }
                return (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            if let trimmedName, !trimmedName.isEmpty, shouldWrite(overrideEntity.professor) {
                overrideEntity.professor = trimmedName
                didChange = true
            }
            if let trimmedEmail, !trimmedEmail.isEmpty, shouldWrite(overrideEntity.professorEmail) {
                overrideEntity.professorEmail = trimmedEmail
                didChange = true
            }
            if let trimmedContact, !trimmedContact.isEmpty, shouldWrite(overrideEntity.professorContactMethod) {
                overrideEntity.professorContactMethod = trimmedContact
                didChange = true
            }
            if let trimmedOfficeHours, !trimmedOfficeHours.isEmpty, shouldWrite(overrideEntity.professorOfficeHours) {
                overrideEntity.professorOfficeHours = trimmedOfficeHours
                didChange = true
            }

            if didChange {
                overrideEntity.lastUpdated = Date()
            }
        }

        // Update planned course row (if present).
        let request = NSFetchRequest<CourseEntity>(entityName: "CourseEntity")
        request.fetchLimit = 1
        request.sortDescriptors = []
        request.predicate = NSPredicate(format: "code ==[c] %@", normalizedCode)
        if let planned = (try? viewContext.fetch(request))?.first {
            func shouldWrite(_ current: String?) -> Bool {
                if overwriteExisting { return true }
                return (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            if let trimmedName, !trimmedName.isEmpty, shouldWrite(planned.professor) {
                planned.professor = trimmedName
                didChange = true
            }
            if let trimmedEmail, !trimmedEmail.isEmpty, shouldWrite(planned.professorEmail) {
                planned.professorEmail = trimmedEmail
                didChange = true
            }
            if let trimmedContact, !trimmedContact.isEmpty, shouldWrite(planned.professorContactMethod) {
                planned.professorContactMethod = trimmedContact
                didChange = true
            }
            if let trimmedOfficeHours, !trimmedOfficeHours.isEmpty, shouldWrite(planned.professorOfficeHours) {
                planned.professorOfficeHours = trimmedOfficeHours
                didChange = true
            }
        }

        if didChange {
            save()
        }

        return didChange
    }

    @discardableResult
    func updateCourseOverrideSyllabus(
        courseCode: String,
        fileName: String?,
        bookmarkData: Data?,
        fileSizeBytes: Int64?,
        uploadedAt: Date?
    ) -> Bool {
        guard let university = resolvedUniversityForOverrides() else { return false }
        let normalizedCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return false }

        let overrideEntity = getCourseOverride(courseCode: normalizedCode) ?? {
            let created = CourseOverrideEntity(context: viewContext)
            created.id = UUID()
            created.courseCode = normalizedCode
            created.university = university
            created.lastUpdated = Date()
            return created
        }()

        overrideEntity.syllabusFileName = fileName
        overrideEntity.syllabusFileBookmarkData = bookmarkData
        overrideEntity.syllabusFileSizeBytes = fileSizeBytes ?? 0
        overrideEntity.syllabusUploadedAt = uploadedAt
        overrideEntity.lastUpdated = Date()

        save()
        return true
    }
    
    /// Get all courses for a department
    func getCoursesByDepartment(_ department: String) -> [CourseCatalogEntity] {
        guard let university = getActiveUniversity() else { return [] }
        
        let request = NSFetchRequest<CourseCatalogEntity>(entityName: "CourseCatalogEntity")
        request.predicate = NSPredicate(
            format: "department == %@ AND university == %@",
            department, university
        )
        request.sortDescriptors = [NSSortDescriptor(key: "courseCode", ascending: true)]
        
        return (try? viewContext.fetch(request)) ?? []
    }
    
    /// Get degree requirements for a major
    func getDegreeRequirements(major: String, degreeType: String) -> [DegreeRequirementEntity] {
        guard let university = getActiveUniversity() else { return [] }
        
        let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
        request.predicate = NSPredicate(
            format: "major == %@ AND degreeType == %@ AND university == %@",
            major, degreeType, university
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: "sectionOrder", ascending: true),
            NSSortDescriptor(key: "requirementCategory", ascending: true)
        ]
        
        return (try? viewContext.fetch(request)) ?? []
    }

    func getDegreeRequirementsForMajorDisplay(_ majorDisplay: String) -> [DegreeRequirementEntity] {
        guard let university = getActiveUniversity() else { return [] }

        let cleaned = cleanedProgramNameFromDisplay(majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines))
        let majorKey = cleaned.isEmpty ? majorDisplay.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
        if majorKey.isEmpty { return [] }

        let degreeTypeRaw = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = degreeTypeCandidates(from: degreeTypeRaw)
        if !degreeTypeRaw.isEmpty, !candidates.contains(degreeTypeRaw) {
            candidates.insert(degreeTypeRaw, at: 0)
        }

        func fetch(matchingDegreeTypes: [String]?) -> [DegreeRequirementEntity] {
            let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
            var preds: [NSPredicate] = [
                NSPredicate(format: "university == %@", university),
                NSPredicate(format: "major == %@", majorKey)
            ]

            if let matchingDegreeTypes, !matchingDegreeTypes.isEmpty {
                let degreePreds = matchingDegreeTypes.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                preds.append(NSCompoundPredicate(orPredicateWithSubpredicates: degreePreds))
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
            request.sortDescriptors = [
                NSSortDescriptor(key: "sectionOrder", ascending: true),
                NSSortDescriptor(key: "requirementCategory", ascending: true)
            ]
            return (try? viewContext.fetch(request)) ?? []
        }

        // 1) Try to match degree type candidates.
        if !candidates.isEmpty {
            let exactish = fetch(matchingDegreeTypes: candidates)
            if !exactish.isEmpty { return exactish }
        }

        // 2) Fallback to any degree type for this major.
        return fetch(matchingDegreeTypes: nil)
    }

    /// Computes major requirement progress for multiple majors without blocking SwiftUI rendering.
    ///
    /// This runs Core Data fetches + JSON parsing on a background context, then returns plain value types.
    func computeMajorRequirementsProgressSummariesAsync(
        majorDisplays: [String],
        degreeTypeRaw: String
    ) async -> [String: CourseProgressSummary] {
        let trimmedDegreeType = degreeTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputDisplays = majorDisplays
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !inputDisplays.isEmpty else { return [:] }

        let container = self.container
        // Pure Sendable helpers (avoid capturing non-Sendable `self` in concurrently-executed closures)
        let sendableDecodeJSON: @Sendable (String?) -> [String] = { json in
            guard let json, !json.isEmpty else { return [] }
            guard let data = json.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        let sendableDecodeDetailed: @Sendable (String?) -> [CourseDetail]? = { json in
            guard let json, !json.isEmpty else { return nil }
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([CourseDetail].self, from: data)
        }
        let sendableDegreeTypeCandidates: @Sendable (String) -> [String] = { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }

            var candidates: [String] = []
            candidates.append(trimmed)

            // If the raw value itself is a combined token (e.g., "BS/MS"), also include components.
            let splitParts = trimmed
                .replacingOccurrences(of: " ", with: "")
                .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            if splitParts.count >= 2 { candidates.append(contentsOf: splitParts) }

            // Extract acronym inside parentheses, e.g. "Bachelor of Science (BS)" -> "BS".
            if let open = trimmed.firstIndex(of: "("),
               let close = trimmed.firstIndex(of: ")"),
               open < close {
                let inner = String(trimmed[trimmed.index(after: open)..<close])
                let innerParts = inner
                    .replacingOccurrences(of: " ", with: "")
                    .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
                    .map { String($0) }
                    .filter { !$0.isEmpty }
                if !innerParts.isEmpty { candidates.append(contentsOf: innerParts) }
            }

            var seen: Set<String> = []
            var unique: [String] = []
            for c in candidates where !c.isEmpty {
                if seen.insert(c.lowercased()).inserted { unique.append(c) }
            }
            return unique
        }
        let sendableCleanedProgramName: @Sendable (String) -> String = { display in
            let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return trimmed }

            // Primary case: UI strings like "Anthropology, BA".
            if let comma = trimmed.lastIndex(of: ",") {
                let suffix = trimmed[trimmed.index(after: comma)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if suffix.count <= 8,
                   suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                    return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return trimmed
            }

            // Fallback: tolerate display strings without a comma (e.g., "Accounting BS" / "Accounting B.S.")
            // Strip only if it matches the provided degreeTypeRaw (not profile state).
            let candidates = sendableDegreeTypeCandidates(trimmedDegreeType)
            guard !candidates.isEmpty else { return trimmed }

            let normalizedDisplay = trimmed.replacingOccurrences(of: ".", with: "")
            for token in candidates.sorted(by: { $0.count > $1.count }) {
                let normalizedToken = token.replacingOccurrences(of: ".", with: "")
                if normalizedToken.isEmpty { continue }

                // Match "... TOKEN" suffix (case-insensitive, tolerant of dots).
                let pattern = "\\s+" + NSRegularExpression.escapedPattern(for: normalizedToken) + "$"
                if normalizedDisplay.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    // Remove the last whitespace-delimited token.
                    if let lastSpace = trimmed.lastIndex(of: " ") {
                        return String(trimmed[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            return trimmed
        }
        
        return await withCheckedContinuation { continuation in
            let ctx = container.newBackgroundContext()
            ctx.name = "coreData.computeMajorReqProgress"
            ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

            ctx.perform {
                // Resolve the active university deterministically (matches `getActiveUniversity()`).
                let ureq = NSFetchRequest<UniversityEntity>(entityName: "UniversityEntity")
                ureq.predicate = NSPredicate(format: "isActive == YES")
                ureq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
                let university = (try? ctx.fetch(ureq))?.first

                guard let university else {
                    continuation.resume(returning: [:])
                    return
                }

                // Snapshot completed course codes.
                func normalizeCode(_ raw: String) -> String {
                    raw
                        .replacingOccurrences(of: "\u{00A0}", with: " ")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                }

                var completed: Set<String> = []

                let creq = NSFetchRequest<CourseEntity>(entityName: "CourseEntity")
                creq.predicate = NSPredicate(format: "isCompleted == YES AND code != nil")
                if let courses = try? ctx.fetch(creq) {
                    for c in courses {
                        let code = normalizeCode(c.code ?? "")
                        if !code.isEmpty { completed.insert(code) }
                    }
                }

                // Include completed overrides for the active university.
                let oreq = NSFetchRequest<CourseOverrideEntity>(entityName: "CourseOverrideEntity")
                oreq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "university == %@", university),
                    NSPredicate(format: "status == %@", "Completed"),
                    NSPredicate(format: "courseCode != nil")
                ])
                if let overrides = try? ctx.fetch(oreq) {
                    for ov in overrides {
                        let code = normalizeCode(ov.courseCode ?? "")
                        if !code.isEmpty { completed.insert(code) }
                    }
                }

                func summary(for requirements: [DegreeRequirementEntity]) -> CourseProgressSummary {
                    var total = 0
                    var done = 0

                    for req in requirements {
                        let selectCount = Int(req.selectCount)
                        if selectCount > 0 {
                            total += selectCount

                            var selectCodes: [String] = []
                            if let selectDetailedJSON = req.selectFromDetailedJSON,
                               let selectDetailed = sendableDecodeDetailed(selectDetailedJSON),
                               !selectDetailed.isEmpty {
                                selectCodes = selectDetailed.map { $0.code }
                            } else {
                                let legacySelect = sendableDecodeJSON(req.selectFromJSON)
                                if !legacySelect.isEmpty { selectCodes = legacySelect }
                            }

                            if selectCodes.isEmpty,
                               let detailedJSON = req.requiredCoursesDetailedJSON,
                               let detailed = sendableDecodeDetailed(detailedJSON),
                               !detailed.isEmpty {
                                selectCodes = detailed.map { $0.code }
                            }

                            if selectCodes.isEmpty {
                                let legacyRequiredCodes: [String] = (req.requiredCourses ?? "")
                                    .split(separator: ",")
                                    .map { normalizeCode(String($0)) }
                                    .filter { !$0.isEmpty }
                                if !legacyRequiredCodes.isEmpty { selectCodes = legacyRequiredCodes }
                            }

                            let uniqueSelectable = Set(selectCodes.map(normalizeCode)).filter { !$0.isEmpty }
                            let completedCount = uniqueSelectable.filter { completed.contains($0) }.count
                            done += min(completedCount, selectCount)
                            continue
                        }

                        if let detailedJSON = req.requiredCoursesDetailedJSON,
                           let detailed = sendableDecodeDetailed(detailedJSON),
                           !detailed.isEmpty {
                            total += detailed.count
                            done += detailed.filter { completed.contains(normalizeCode($0.code)) }.count
                            continue
                        }

                        let legacyCodes: [String] = (req.requiredCourses ?? "")
                            .split(separator: ",")
                            .map { normalizeCode(String($0)) }
                            .filter { !$0.isEmpty }
                        if !legacyCodes.isEmpty {
                            total += legacyCodes.count
                            done += legacyCodes.filter { completed.contains($0) }.count
                            continue
                        }
                    }

                    let fraction = total > 0 ? Double(done) / Double(total) : 0
                    return CourseProgressSummary(done: done, total: total, fraction: fraction)
                }

                var candidates = sendableDegreeTypeCandidates(trimmedDegreeType)
                if !trimmedDegreeType.isEmpty, !candidates.contains(trimmedDegreeType) {
                    candidates.insert(trimmedDegreeType, at: 0)
                }

                func fetchRequirements(for majorDisplay: String) -> [DegreeRequirementEntity] {
                    let cleaned = sendableCleanedProgramName(majorDisplay)
                    let majorKey = cleaned.isEmpty ? majorDisplay : cleaned
                    if majorKey.isEmpty { return [] }

                    func fetch(matchingDegreeTypes: [String]?) -> [DegreeRequirementEntity] {
                        let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
                        var preds: [NSPredicate] = [
                            NSPredicate(format: "university == %@", university),
                            NSPredicate(format: "major == %@", majorKey)
                        ]

                        if let matchingDegreeTypes, !matchingDegreeTypes.isEmpty {
                            let degreePreds = matchingDegreeTypes.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                            preds.append(NSCompoundPredicate(orPredicateWithSubpredicates: degreePreds))
                        }

                        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
                        request.sortDescriptors = [
                            NSSortDescriptor(key: "sectionOrder", ascending: true),
                            NSSortDescriptor(key: "requirementCategory", ascending: true)
                        ]
                        return (try? ctx.fetch(request)) ?? []
                    }

                    if !candidates.isEmpty {
                        let exactish = fetch(matchingDegreeTypes: candidates)
                        if !exactish.isEmpty { return exactish }
                    }
                    return fetch(matchingDegreeTypes: nil)
                }

                var out: [String: CourseProgressSummary] = [:]
                for display in inputDisplays {
                    let reqs = fetchRequirements(for: display)
                    out[display] = summary(for: reqs)
                }

                continuation.resume(returning: out)
            }
        }
    }

    // MARK: - Program requirements (on-demand)

    /// Resolves the `MajorEntity` for the currently selected primary major.
    ///
    /// Note: `ProfileEntity.major` may be a display string (e.g., "Computer Science, BA").
    func resolveSelectedMajorEntity() -> MajorEntity? {
        let logger = DebugLogger.shared
        
        guard let university = getActiveUniversity() else {
            logger.log("[Resolve] No active university")
            return nil
        }
        logger.log("[Resolve] University: '\(university.name ?? "nil")' (objectID: \(university.objectID))")
        
        guard let rawMajor = profile?.major?.trimmingCharacters(in: .whitespacesAndNewlines), !rawMajor.isEmpty else {
            logger.log("[Resolve] No major selected in profile")
            return nil
        }

        logger.log("[Resolve] Starting resolution for: '\(rawMajor)'")

        let cleanedName = cleanedProgramNameFromDisplay(rawMajor)
        logger.log("[Resolve] Cleaned name: '\(cleanedName)'")
        let degreeLevel = (profile?.degreeLevel ?? "Undergraduate").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeTypeRaw = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeCandidates = degreeTypeCandidates(from: degreeTypeRaw)

        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "university == %@", university),
            NSPredicate(format: "isMinor == NO"),
            NSPredicate(format: "degreeLevel ==[c] %@", degreeLevel),
            NSPredicate(format: "name == %@", cleanedName)
        ])

        let results = (try? viewContext.fetch(request)) ?? []
        logger.log("[Resolve] Exact name match found \(results.count) results")
        if results.isEmpty {
            // Debug: show what IS in the database
            let debugReq = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
            debugReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "university == %@", university),
                NSPredicate(format: "isMinor == NO"),
                NSPredicate(format: "degreeLevel ==[c] %@", degreeLevel)
            ])
            debugReq.fetchLimit = 10
            let allMajors = (try? viewContext.fetch(debugReq)) ?? []
            logger.log("[Resolve] Available majors in DB (\(allMajors.count) fetched, limit=10):")
            for m in allMajors {
                logger.log("  - name='\(m.name ?? "nil")' degreeType='\(m.degreeType ?? "nil")' degreeLevel='\(m.degreeLevel ?? "nil")' hasURL=\(!(m.programURL ?? "").isEmpty)")
            }
            
            // Also check total count
            let totalCount = (try? viewContext.count(for: debugReq)) ?? -1
            logger.log("[Resolve] Total matching majors in DB: \(totalCount)")
        }
        if results.count == 1 {
            let entity = results.first
            logger.log("[Resolve] ✓ Found exact match: name='\(entity?.name ?? "nil")' url='\(entity?.programURL ?? "nil")'")
            return entity
        }

        // If multiple variants exist (BA/BS), pick the one that matches the profile degreeType.
        if results.count > 1, !degreeCandidates.isEmpty {
            logger.log("[Resolve] Found \(results.count) matches, filtering by degreeType...")
            if let match = results.first(where: { entity in
                let stored = (entity.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return degreeCandidates.contains(where: { cand in
                    let c = cand.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                    let s = stored.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                    return !c.isEmpty && c == s
                })
            }) {
                return match
            }
        }

        // Fallback: if we couldn't resolve by exact name match, do a normalized-name lookup.
        // This helps when existing DB rows stored names like "Accounting, B.S." but the UI displays "Accounting, BS".
        if results.isEmpty {
            func normalizeDegreeToken(_ value: String) -> String {
                return value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: " ", with: "")
            }

            let degreeTokenSet: Set<String> = Set(degreeCandidates.map(normalizeDegreeToken)).subtracting([""])

            func normalizeProgramNameForLookup(_ raw: String) -> String {
                var s = raw
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                func maybeStripDegreeSuffix(_ input: String) -> String {
                    var out = input

                    // Strip trailing parenthetical degree token: "... (BS)" or "... (B.S.)".
                    if let open = out.lastIndex(of: "("), let close = out.lastIndex(of: ")"), open < close {
                        let inner = out[out.index(after: open)..<close]
                        let token = normalizeDegreeToken(String(inner))
                        if !token.isEmpty, degreeTokenSet.contains(token) {
                            out = String(out[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
                            out = out.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                        }
                    }

                    // Strip trailing comma degree token: "..., BS" or "..., B.S.".
                    if let comma = out.lastIndex(of: ",") {
                        let suffix = out[out.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
                        if suffix.count <= 8, suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                            let token = normalizeDegreeToken(String(suffix))
                            if !token.isEmpty, degreeTokenSet.contains(token) {
                                out = String(out[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    } else {
                        // Strip trailing space degree token: "... BS" or "... B.S.".
                        let parts = out.split(separator: " ")
                        if parts.count >= 2 {
                            let last = String(parts.last ?? "")
                            if last.count <= 8, last.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                                let token = normalizeDegreeToken(last)
                                if !token.isEmpty, degreeTokenSet.contains(token) {
                                    out = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            }
                        }
                    }

                    return out
                }

                if !degreeTokenSet.isEmpty {
                    s = maybeStripDegreeSuffix(s)
                }

                return s
                    .lowercased()
                    .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let desired = normalizeProgramNameForLookup(rawMajor)
            if !desired.isEmpty {
                func fetchFallbackCandidates(narrowByDegreeType: Bool) -> [MajorEntity] {
                    let req = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
                    var preds: [NSPredicate] = [
                        NSPredicate(format: "university == %@", university),
                        NSPredicate(format: "isMinor == NO"),
                        NSPredicate(format: "degreeLevel ==[c] %@", degreeLevel)
                    ]
                    if narrowByDegreeType, !degreeCandidates.isEmpty {
                        let subpreds = degreeCandidates.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                        preds.append(NSCompoundPredicate(orPredicateWithSubpredicates: subpreds))
                    }
                    req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
                    return (try? viewContext.fetch(req)) ?? []
                }

                // Prefer narrowing by degree type, but fall back to a broader set if it yields nothing.
                // This avoids missing matches when stored degreeType formatting differs (e.g., "B.S." vs "BS").
                var allCandidates = fetchFallbackCandidates(narrowByDegreeType: true)
                var normalizedMatches = allCandidates.filter { entity in
                    let name = (entity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return false }
                    return normalizeProgramNameForLookup(name) == desired
                }

                if normalizedMatches.isEmpty {
                    logger.log("[Resolve] No matches with degreeType filter, trying without...")
                    allCandidates = fetchFallbackCandidates(narrowByDegreeType: false)
                    normalizedMatches = allCandidates.filter { entity in
                        let name = (entity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return false }
                        return normalizeProgramNameForLookup(name) == desired
                    }
                    logger.log("[Resolve] Normalized matches without degreeType: \(normalizedMatches.count)")
                }

                if normalizedMatches.count == 1 {
                    return normalizedMatches.first
                }
                if normalizedMatches.count > 1, !degreeCandidates.isEmpty {
                    if let match = normalizedMatches.first(where: { entity in
                        let stored = (entity.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return degreeCandidates.contains(where: { cand in
                            let c = normalizeDegreeToken(cand)
                            let s = normalizeDegreeToken(stored)
                            return !c.isEmpty && c == s
                        })
                    }) {
                        return match
                    }
                }

                let final = normalizedMatches.first
                logger.log("[Resolve] Returning normalized match: name='\(final?.name ?? "nil")' url='\(final?.programURL ?? "nil")'")
                return final
            }
        }

        let fallback = results.first
        logger.log("[Resolve] Returning fallback result: name='\(fallback?.name ?? "nil")' url='\(fallback?.programURL ?? "nil")'")
        return fallback
    }

    private func resolveProgramEntity(
        programDisplay: String,
        isMinor: Bool,
        degreeLevelHint: String?,
        degreeTypeHint: String?
    ) -> MajorEntity? {
        let logger = DebugLogger.shared
        guard let university = getActiveUniversity() else { return nil }

        let raw = programDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let cleanedName = cleanedProgramNameFromDisplay(raw)
        let degreeLevel = (degreeLevelHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeTypeRaw = (degreeTypeHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeCandidates = degreeTypeCandidates(from: degreeTypeRaw)

        var preds: [NSPredicate] = [
            NSPredicate(format: "university == %@", university),
            NSPredicate(format: "isMinor == %@", NSNumber(value: isMinor)),
            NSPredicate(format: "name == %@", cleanedName)
        ]
        if !degreeLevel.isEmpty {
            preds.append(NSPredicate(format: "degreeLevel ==[c] %@", degreeLevel))
        }

        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)

        let results = (try? viewContext.fetch(request)) ?? []
        if results.count <= 1 { return results.first }

        // For majors, disambiguate BA/BS variants when we can.
        if !isMinor, !degreeCandidates.isEmpty {
            func normalizeDegreeToken(_ value: String) -> String {
                value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: " ", with: "")
            }
            if let match = results.first(where: { entity in
                let stored = normalizeDegreeToken(entity.degreeType ?? "")
                return degreeCandidates.contains(where: { normalizeDegreeToken($0) == stored && !stored.isEmpty })
            }) {
                return match
            }
        }

        logger.log("[Resolve] Multiple matches for program='\(cleanedName)' isMinor=\(isMinor); using first")
        return results.first
    }

    func resolveProgramProgramURL(programDisplay: String, isMinor: Bool) -> String? {
        let degreeLevelHint = isMinor ? "Undergraduate" : (profile?.degreeLevel ?? "")
        let degreeTypeHint = isMinor ? nil : (profile?.degreeType ?? "")
        let entity = resolveProgramEntity(
            programDisplay: programDisplay,
            isMinor: isMinor,
            degreeLevelHint: degreeLevelHint,
            degreeTypeHint: degreeTypeHint
        )
        let url = (entity?.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return canonicalizeAcalogURL(url, removingQueryItems: ["returnto"])
    }

    func resolveSelectedMinorProgramURL() -> String? {
        let minor = (profile?.minor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !minor.isEmpty, minor.lowercased() != "none" else { return nil }
        return resolveProgramProgramURL(programDisplay: minor, isMinor: true)
    }

    func resolveSelectedMajorProgramURL() -> String? {
        let entity = resolveSelectedMajorEntity()
        let url = (entity?.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
#if DEBUG
            let major = (profile?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let degreeType = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let degreeLevel = (profile?.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (entity?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedDT = (entity?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            print("[CoreData][Resolve] No programURL for selected major. profile.major='\(major)' degreeType='\(degreeType)' degreeLevel='\(degreeLevel)' resolved.name='\(resolvedName)' resolved.degreeType='\(resolvedDT)'")
#endif
            return nil
        }
        return canonicalizeAcalogURL(url, removingQueryItems: ["returnto"])
    }

    /// Robust major entity resolution for any display name (primary or secondary).
    ///
    /// Uses the same multi-pass fuzzy lookup as `resolveSelectedMajorEntity()` so that complex
    /// concentration strings like "Business Administration BS - Marketing Concentration, BS" resolve
    /// correctly even when the stored `MajorEntity.name` formatting differs slightly.
    private func resolveNonMinorMajorEntity(display rawMajor: String) -> MajorEntity? {
        let rawMajor = rawMajor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawMajor.isEmpty else { return nil }
        guard let university = getActiveUniversity() else { return nil }

        let cleanedName    = cleanedProgramNameFromDisplay(rawMajor)
        let degreeLevel    = (profile?.degreeLevel ?? "Undergraduate").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeTypeRaw  = (profile?.degreeType  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeCandidates = degreeTypeCandidates(from: degreeTypeRaw)

        // 1) Exact name match.
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "university == %@",   university),
            NSPredicate(format: "isMinor == NO"),
            NSPredicate(format: "degreeLevel ==[c] %@", degreeLevel),
            NSPredicate(format: "name == %@", cleanedName)
        ])
        let results = (try? viewContext.fetch(request)) ?? []

        if results.count == 1 { return results.first }
        if results.count > 1, !degreeCandidates.isEmpty {
            if let match = results.first(where: { entity in
                let stored = (entity.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return degreeCandidates.contains(where: { cand in
                    let c = cand.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                    let s = stored.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                    return !c.isEmpty && c == s
                })
            }) { return match }
            return results.first
        }

        // 2) Fuzzy normalized-name fallback (matches "Business Administration BS - MIS Concentration"
        //    even if stored with subtly different formatting).
        func normalizeDegreeToken(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                 .uppercased()
                 .replacingOccurrences(of: ".", with: "")
                 .replacingOccurrences(of: " ", with: "")
        }
        let degreeTokenSet: Set<String> = Set(degreeCandidates.map(normalizeDegreeToken)).subtracting([""])

        func normalizeProgramNameForLookup(_ raw: String) -> String {
            var s = raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Strip trailing comma/space degree token (e.g., ", BS" / " BS").
            if let comma = s.lastIndex(of: ",") {
                let suffix = s[s.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if suffix.count <= 8, suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                    let token = normalizeDegreeToken(String(suffix))
                    if !token.isEmpty, degreeTokenSet.contains(token) {
                        s = String(s[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } else {
                let parts = s.split(separator: " ")
                if parts.count >= 2, let last = parts.last.map(String.init) {
                    if last.count <= 8, last.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                        let token = normalizeDegreeToken(last)
                        if !token.isEmpty, degreeTokenSet.contains(token) {
                            s = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
            }
            return s.lowercased()
                    .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let desired = normalizeProgramNameForLookup(rawMajor)
        guard !desired.isEmpty else { return results.first }

        func fetchFuzzy(narrowByDegreeType: Bool) -> [MajorEntity] {
            let req = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
            var preds: [NSPredicate] = [
                NSPredicate(format: "university == %@",   university),
                NSPredicate(format: "isMinor == NO"),
                NSPredicate(format: "degreeLevel ==[c] %@", degreeLevel)
            ]
            if narrowByDegreeType, !degreeCandidates.isEmpty {
                let subpreds = degreeCandidates.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                preds.append(NSCompoundPredicate(orPredicateWithSubpredicates: subpreds))
            }
            req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
            return (try? viewContext.fetch(req)) ?? []
        }

        for useNarrow in [true, false] {
            let candidates = fetchFuzzy(narrowByDegreeType: useNarrow)
            let matches = candidates.filter { entity in
                let name = (entity.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !name.isEmpty && normalizeProgramNameForLookup(name) == desired
            }
            if matches.count == 1 { return matches.first }
            if matches.count > 1 {
                if !degreeCandidates.isEmpty, let match = matches.first(where: { entity in
                    let stored = (entity.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return degreeCandidates.contains(where: { cand in
                        let c = normalizeDegreeToken(cand); let s = normalizeDegreeToken(stored)
                        return !c.isEmpty && c == s
                    })
                }) { return match }
                return matches.first
            }
        }
        return results.first
    }

    /// Robust URL resolver for any non-minor major display name.
    /// Equivalent to `resolveSelectedMajorProgramURL()` but for display names other than `profile.major`.
    func resolveNonMinorMajorProgramURL(display: String) -> String? {
        let entity = resolveNonMinorMajorEntity(display: display)
        let url = (entity?.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return canonicalizeAcalogURL(url, removingQueryItems: ["returnto"])
    }

    func minorRequirementsCourseProgress(forMinorDisplay minorDisplay: String) -> CourseProgressSummary {
        let trimmed = minorDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else {
            return CourseProgressSummary(done: 0, total: 0, fraction: 0)
        }
        guard let programURL = resolveProgramProgramURL(programDisplay: trimmed, isMinor: true) else {
            return CourseProgressSummary(done: 0, total: 0, fraction: 0)
        }
        let reqs = getDegreeRequirements(programURL: programURL, degreeType: "Minor")
        return courseProgressSummary(requirements: reqs)
    }

    func getDegreeRequirements(programURL: String, degreeType: String) -> [DegreeRequirementEntity] {
        guard let university = getActiveUniversity() else { return [] }
        let canonicalURL = canonicalizeAcalogURL(programURL, removingQueryItems: ["returnto"])

        func fetch(matchingDegreeTypes candidates: [String]?) -> [DegreeRequirementEntity] {
            let request = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
            var preds: [NSPredicate] = [
                NSPredicate(format: "university == %@", university),
                NSPredicate(format: "programURL == %@", canonicalURL)
            ]

            if let candidates, !candidates.isEmpty {
                let degreePreds = candidates.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                preds.append(NSCompoundPredicate(orPredicateWithSubpredicates: degreePreds))
            }

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
            request.sortDescriptors = [
                NSSortDescriptor(key: "sectionOrder", ascending: true),
                NSSortDescriptor(key: "requirementCategory", ascending: true)
            ]
            return (try? viewContext.fetch(request)) ?? []
        }

        let trimmedDegreeType = degreeType.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Exact match first.
        if !trimmedDegreeType.isEmpty {
            let exact = fetch(matchingDegreeTypes: [trimmedDegreeType])
            if !exact.isEmpty { return exact }
        }

        // 2) Try common formatting variations (e.g., "BS" vs "B.S.").
        var candidates = degreeTypeCandidates(from: trimmedDegreeType)
        if !trimmedDegreeType.isEmpty, !candidates.contains(trimmedDegreeType) {
            candidates.insert(trimmedDegreeType, at: 0)
        }
        if !candidates.isEmpty {
            let tolerant = fetch(matchingDegreeTypes: candidates)
            if !tolerant.isEmpty { return tolerant }
        }

        // 3) Fallback: if degree type mismatches entirely, show whatever we have for this program page.
        return fetch(matchingDegreeTypes: nil)
    }

    struct CourseProgressSummary: Equatable {
        let done: Int
        let total: Int
        let fraction: Double

        var remaining: Int { max(0, total - done) }
    }

    func majorRequirementsCourseProgress() -> CourseProgressSummary {
        guard let programURL = resolveSelectedMajorProgramURL() else {
            return CourseProgressSummary(done: 0, total: 0, fraction: 0)
        }
        let degreeType = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reqs = getDegreeRequirements(programURL: programURL, degreeType: degreeType)
        return courseProgressSummary(requirements: reqs)
    }

    func majorRequirementsCourseProgress(forMajorDisplay majorDisplay: String) -> CourseProgressSummary {
        let reqs = getDegreeRequirementsForMajorDisplay(majorDisplay)
        return courseProgressSummary(requirements: reqs)
    }

    func courseProgressSummary(requirements: [DegreeRequirementEntity]) -> CourseProgressSummary {
        func normalizeCode(_ raw: String) -> String {
            raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }

        // Pre-build O(n) sets so each isCourseCompleted check is O(1) instead of O(n×m).
        let completedPlanCodes: Set<String> = Set(
            plans.flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
                .filter { $0.isCompleted }
                .compactMap { $0.code.map(normalizeCode) }
                .filter { !$0.isEmpty }
        )

        func isCourseCompleted(courseCode raw: String) -> Bool {
            let needle = normalizeCode(raw)
            guard !needle.isEmpty else { return false }

            if let overrideEntity = getCourseOverride(courseCode: needle) {
                let s = (overrideEntity.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if s == "Completed" { return true }
            }

            return completedPlanCodes.contains(needle)
        }

        var total = 0
        var done = 0

        for req in requirements {
            let selectCount = Int(req.selectCount)
            if selectCount > 0 {
                total += selectCount

                var selectCodes: [String] = []

                if let selectDetailedJSON = req.selectFromDetailedJSON,
                   let selectDetailed = decodeDetailedCourseList(selectDetailedJSON),
                   !selectDetailed.isEmpty {
                    selectCodes = selectDetailed.map { $0.code }
                } else {
                    let legacySelect = decodeJSONCourseList(req.selectFromJSON)
                    if !legacySelect.isEmpty {
                        selectCodes = legacySelect
                    }
                }

                // Some scrapes store select-from options in requiredCourses*; fall back to those.
                if selectCodes.isEmpty,
                   let detailedJSON = req.requiredCoursesDetailedJSON,
                   let detailed = decodeDetailedCourseList(detailedJSON),
                   !detailed.isEmpty {
                    selectCodes = detailed.map { $0.code }
                }
                if selectCodes.isEmpty {
                    let legacyRequiredCodes: [String] = (req.requiredCourses ?? "")
                        .split(separator: ",")
                        .map { normalizeCode(String($0)) }
                        .filter { !$0.isEmpty }
                    if !legacyRequiredCodes.isEmpty {
                        selectCodes = legacyRequiredCodes
                    }
                }

                let uniqueSelectable = Set(selectCodes.map(normalizeCode)).filter { !$0.isEmpty }
                let completedCount = uniqueSelectable.filter { isCourseCompleted(courseCode: $0) }.count
                done += min(completedCount, selectCount)
                continue
            }

            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailed = decodeDetailedCourseList(detailedJSON),
               !detailed.isEmpty {
                total += detailed.count
                done += detailed.filter { isCourseCompleted(courseCode: $0.code) }.count
                continue
            }

            let legacyCodes: [String] = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { normalizeCode(String($0)) }
                .filter { !$0.isEmpty }
            if !legacyCodes.isEmpty {
                total += legacyCodes.count
                done += legacyCodes.filter { isCourseCompleted(courseCode: $0) }.count
                continue
            }

        }

        let fraction = total > 0 ? Double(done) / Double(total) : 0
        return CourseProgressSummary(done: done, total: total, fraction: fraction)
    }

    // MARK: - GPA

    struct GPASummary: Equatable {
        let gpa: Double
        let creditsCounted: Double
        let coursesCounted: Int
    }

    private func gradePoints(for rawGrade: String) -> Double? {
        let g = rawGrade
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !g.isEmpty else { return nil }

        // Ignore non-GPA symbols.
        if ["P", "PASS", "S", "SAT", "SATISFACTORY"].contains(g) { return nil }
        if ["W", "WITHDRAW", "WD", "I", "INC", "INCOMPLETE"].contains(g) { return nil }

        // Common US 4.0 scale.
        switch g {
        case "A+": return 4.0
        case "A": return 4.0
        case "A-": return 3.7
        case "B+": return 3.3
        case "B": return 3.0
        case "B-": return 2.7
        case "C+": return 2.3
        case "C": return 2.0
        case "C-": return 1.7
        case "D+": return 1.3
        case "D": return 1.0
        case "D-": return 0.7
        case "F": return 0.0
        default:
            return nil
        }
    }

    private func isLetterGraded(_ gradingType: String?) -> Bool {
        let t = (gradingType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return t.caseInsensitiveCompare("Letter Grade") == .orderedSame
    }

    /// Public wrapper for GPA calculations that need to match the app's rules.
    func isLetterGradedForGPA(_ gradingType: String?) -> Bool {
        isLetterGraded(gradingType)
    }

    private func eligibleCourseCodes(from requirements: [DegreeRequirementEntity]) -> Set<String> {
        var codes: Set<String> = []

        for req in requirements {
            if let detailedJSON = req.requiredCoursesDetailedJSON,
               let detailed = decodeDetailedCourseList(detailedJSON),
               !detailed.isEmpty {
                for d in detailed {
                    let c = normalizeCourseCode(d.code)
                    if !c.isEmpty { codes.insert(c) }
                }
            } else {
                let legacyCodes: [String] = (req.requiredCourses ?? "")
                    .split(separator: ",")
                    .map { normalizeCourseCode(String($0)) }
                    .filter { !$0.isEmpty }
                for c in legacyCodes {
                    codes.insert(c)
                }
            }

            let selectCodes = decodeJSONCourseList(req.selectFromJSON)
                .map { normalizeCourseCode($0) }
                .filter { !$0.isEmpty }
            for c in selectCodes {
                codes.insert(c)
            }
        }

        return codes
    }

    func majorGPASummary(requirements: [DegreeRequirementEntity]) -> GPASummary? {
        let eligibleCodes = eligibleCourseCodes(from: requirements)
        guard !eligibleCodes.isEmpty else { return nil }

        let completedPlannedCourses: [CourseEntity] = plans
            .flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
            .filter { $0.isCompleted }

        func courseRecencyKey(_ course: CourseEntity) -> (Int, Int) {
            // Higher = more recent.
            let year = Int(course.semester?.year ?? 0)
            let season = Int(course.semester?.seasonOrder ?? 0)
            return (year, season)
        }

        var plannedByCode: [String: CourseEntity] = [:]
        for course in completedPlannedCourses {
            let code = normalizeCourseCode(course.code ?? "")
            guard eligibleCodes.contains(code) else { continue }

            if let existing = plannedByCode[code] {
                if courseRecencyKey(course) > courseRecencyKey(existing) {
                    plannedByCode[code] = course
                }
            } else {
                plannedByCode[code] = course
            }
        }

        var qualityPoints: Double = 0
        var creditsCounted: Double = 0
        var coursesCounted: Int = 0

        for code in eligibleCodes {
            if let planned = plannedByCode[code] {
                guard isLetterGraded(planned.gradingType) else { continue }
                guard let grade = planned.grade, let gp = gradePoints(for: grade) else { continue }
                let credits = Double(planned.creditsInt)
                guard credits > 0 else { continue }

                qualityPoints += gp * credits
                creditsCounted += credits
                coursesCounted += 1
                continue
            }

            if let overrideEntity = getCourseOverride(courseCode: code) {
                let s = (overrideEntity.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard s == "Completed" else { continue }
                guard isLetterGraded(overrideEntity.gradingType) else { continue }
                guard let grade = overrideEntity.grade, let gp = gradePoints(for: grade) else { continue }
                let credits = overrideEntity.credits
                guard credits > 0 else { continue }

                qualityPoints += gp * credits
                creditsCounted += credits
                coursesCounted += 1
            }
        }

        guard creditsCounted > 0 else { return nil }
        return GPASummary(
            gpa: qualityPoints / creditsCounted,
            creditsCounted: creditsCounted,
            coursesCounted: coursesCounted
        )
    }

    func minorGPASummary(minorName: String) -> GPASummary? {
        let trimmed = minorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "none" else { return nil }

        let prefix = trimmed.prefix(4).uppercased()
        guard !prefix.isEmpty else { return nil }

        let completedCourses: [CourseEntity] = plans
            .flatMap { $0.semestersArray.flatMap { $0.coursesArray } }
            .filter { $0.isCompleted }

        var qualityPoints: Double = 0
        var creditsCounted: Double = 0
        var coursesCounted: Int = 0

        for course in completedCourses {
            guard let codeRaw = course.code else { continue }
            let code = normalizeCourseCode(codeRaw)
            guard code.hasPrefix(prefix) else { continue }
            guard isLetterGraded(course.gradingType) else { continue }
            guard let grade = course.grade, let gp = gradePoints(for: grade) else { continue }
            let credits = Double(course.creditsInt)
            guard credits > 0 else { continue }

            qualityPoints += gp * credits
            creditsCounted += credits
            coursesCounted += 1
        }

        guard creditsCounted > 0 else { return nil }
        return GPASummary(
            gpa: qualityPoints / creditsCounted,
            creditsCounted: creditsCounted,
            coursesCounted: coursesCounted
        )
    }

    @MainActor
    func refreshSelectedMajorRequirementsIfNeeded(force: Bool = false) async {
        let logger = DebugLogger.shared
        guard let programURL = resolveSelectedMajorProgramURL() else {
            logger.scraper("📚 Requirements: no programURL for selected major")
            return
        }

        let majorName = cleanedProgramNameFromDisplay((profile?.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        let degreeType = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        await refreshProgramRequirementsIfNeeded(
            programURL: programURL,
            major: majorName.isEmpty ? (profile?.major ?? "") : majorName,
            degreeType: degreeType.isEmpty ? "Unknown" : degreeType,
            force: force
        )
    }

    @MainActor
    func refreshProgramRequirementsIfNeeded(
        programURL: String,
        major: String,
        degreeType: String,
        force: Bool = false,
        minimumRefreshIntervalSeconds: TimeInterval = {
            #if DEBUG
            // Make scraper iteration fast in Debug builds.
            return 30
            #else
            return 24 * 60 * 60
            #endif
        }()
    ) async {
        let logger = DebugLogger.shared
        guard let university = getActiveUniversity() else {
            logger.scraper("📚 Requirements: no active university")
            return
        }

        let canonicalURL = canonicalizeAcalogURL(programURL, removingQueryItems: ["returnto"])

        // Find existing snapshot state
        let existingRequest = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
        existingRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "university == %@", university),
            NSPredicate(format: "programURL == %@", canonicalURL),
            NSPredicate(format: "degreeType == %@", degreeType)
        ])
        let existingRows = (try? viewContext.fetch(existingRequest)) ?? []
        let existingHash = existingRows.first?.requirementsHash
        let existingLastScraped = existingRows.first?.lastScrapedAt

        if !force, let last = existingLastScraped {
            let age = Date().timeIntervalSince(last)
            if age < minimumRefreshIntervalSeconds {
                logger.scraper("📚 Requirements: skip scrape (fresh) major=\(major) degreeType=\(degreeType) age=\(Int(age))s")
                return
            }
        }

        logger.logSection("📚 PROGRAM REQUIREMENTS SCRAPE")
        logger.scraper("Major=\(major) degreeType=\(degreeType)")
        logger.scraper("ProgramURL=\(canonicalURL)")

        do {
            let scraper = UniversalCatalogScraper()
            var parsed = try await scraper.scrapeProgramRequirements(programURL: canonicalURL)
            parsed = enrichDegreeRequirementsFromCatalog(parsed)
            updateCatalogTitlesFromRequirements(parsed)
            logger.scraper("Parsed rows=\(parsed.count)")

            let newHash = stableRequirementsHash(parsed)
            logger.scraper("Existing hash=\(existingHash ?? "nil")")
            logger.scraper("New hash=\(newHash)")

            if !force, let existingHash, existingHash == newHash {
                for row in existingRows {
                    row.lastScrapedAt = Date()
                    row.lastUpdated = Date()
                }
                save()
                logger.scraper("✅ Requirements unchanged; updated lastScrapedAt")
                return
            }

            // Requirements changed: replace snapshot for (university, programURL, degreeType).
            for row in existingRows {
                viewContext.delete(row)
            }

            var inserted = 0
            for (index, category) in parsed.enumerated() {
                let cat = category.category.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cat.isEmpty else { continue }

                let entity = DegreeRequirementEntity(context: viewContext)
                entity.id = UUID()
                entity.university = university
                entity.programURL = canonicalURL
                entity.major = major
                entity.degreeType = degreeType
                entity.requirementCategory = cat
                entity.sectionOrder = Int16(index)
                entity.creditsRequired = Int16(category.creditsRequired)
                entity.descriptionText = category.description

                if let required = category.requiredCourses, !required.isEmpty {
                    entity.requiredCourses = required.joined(separator: ", ")
                } else {
                    entity.requiredCourses = nil
                }

                if let detailed = category.requiredCoursesDetailed, !detailed.isEmpty {
                    entity.requiredCoursesDetailedJSON = encodeDetailedCourseList(detailed)
                } else {
                    entity.requiredCoursesDetailedJSON = nil
                }

                if let selectFrom = category.selectFrom, !selectFrom.isEmpty {
                    entity.selectFromJSON = encodeJSONCourseList(selectFrom)
                    entity.selectCount = Int16(category.selectCount ?? 0)
                } else {
                    entity.selectFromJSON = nil
                    entity.selectCount = 0
                }

                if let selectDetailed = category.selectFromDetailed, !selectDetailed.isEmpty {
                    entity.selectFromDetailedJSON = encodeDetailedCourseList(selectDetailed)
                } else {
                    entity.selectFromDetailedJSON = nil
                }

                entity.requirementsHash = newHash
                entity.lastScrapedAt = Date()
                entity.lastUpdated = Date()
                inserted += 1
            }

            save()
            logger.scraper("✅ Requirements saved. rows=\(inserted)")

            // Notify user that their requirements changed
            DispatchQueue.main.async {
                AppNotificationCenter.shared.post(
                    kind: .warning,
                    title: "Degree Requirements Updated",
                    message: "\(major) requirements have changed since your last sync. Review the Detailed Audit."
                )
            }
        } catch {
            logger.scraper("❌ Requirements scrape failed: \(error)", level: .error)
            logger.logError(error)
        }
    }

    private func enrichDegreeRequirementsFromCatalog(_ requirements: [DegreeRequirement]) -> [DegreeRequirement] {
        func bestDetail(_ d: CourseDetail) -> CourseDetail {
            let code = normalizeCourseCode(d.code)
            guard !code.isEmpty else { return d }
            guard let catalog = getCatalogCourse(code: code) else { return d }

            let title = (d.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let catalogTitle = (catalog.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let bestTitle: String? = {
                // Treat title==code as missing.
                if title.isEmpty { return catalogTitle.isEmpty ? nil : catalogTitle }
                if normalizeCourseCode(title) == code { return catalogTitle.isEmpty ? nil : catalogTitle }
                return title
            }()

            let bestCredits: String? = {
                // If detail has credits, use it
                if let c = d.credits, !c.isEmpty { return c }

                // Otherwise try catalog (prefer resolved credits, which may parse from description).
                let resolved = resolvedCatalogCredits(for: catalog)
                if resolved > 0 { return String(resolved) }

                // Fallback to stored integer credits.
                let cc = Int(catalog.credits)
                return cc > 0 ? String(cc) : nil
            }()

            return CourseDetail(code: code, title: bestTitle, credits: bestCredits)
        }

        return requirements.map { r in
            let requiredDetailed = r.requiredCoursesDetailed?.map(bestDetail)
            let selectDetailed = r.selectFromDetailed?.map(bestDetail)

            return DegreeRequirement(
                id: r.id,
                degreeType: r.degreeType,
                major: r.major,
                category: r.category,
                requiredCourses: r.requiredCourses,
                requiredCoursesDetailed: requiredDetailed,
                creditsRequired: r.creditsRequired,
                description: r.description,
                selectFrom: r.selectFrom,
                selectFromDetailed: selectDetailed,
                selectCount: r.selectCount
            )
        }
    }

    private func updateCatalogTitlesFromRequirements(_ requirements: [DegreeRequirement]) {
        // If the catalog was derived from program codes (title==code), requirements parsing
        // may provide better titles. Apply them opportunistically.
        let allDetails = (requirements.flatMap { ($0.requiredCoursesDetailed ?? []) + ($0.selectFromDetailed ?? []) })
        guard !allDetails.isEmpty else { return }

        for detail in allDetails {
            let code = normalizeCourseCode(detail.code)
            guard !code.isEmpty else { continue }
            guard let title = detail.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }

            guard let catalog = getCatalogCourse(code: code) else { continue }
            let current = (catalog.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || normalizeCourseCode(current) == code {
                catalog.title = title
                catalog.lastUpdated = Date()
            }
        }
    }

    nonisolated private func cleanedProgramNameFromDisplay(_ display: String) -> String {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        // Primary case: UI strings like "Anthropology, BA".
        if let comma = trimmed.lastIndex(of: ",") {
            let suffix = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
            // If it looks like a degree token, strip it.
            if suffix.count <= 8, suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                return String(trimmed[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmed
        }

        // Fallback: tolerate display strings without a comma (e.g., "Accounting BS" / "Accounting B.S.")
        // but only strip if it matches the currently selected degreeType.
        let dtRaw = (profile?.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = degreeTypeCandidates(from: dtRaw)
        guard !candidates.isEmpty else { return trimmed }

        let parts = trimmed.split(separator: " ")
        guard parts.count >= 2 else { return trimmed }
        let last = String(parts.last ?? "")
        guard last.count <= 8, last.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil else { return trimmed }

        func normalizeToken(_ s: String) -> String {
            s.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        }

        let lastNorm = normalizeToken(last)
        if candidates.contains(where: { normalizeToken($0) == lastNorm }) {
            return parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func canonicalizeAcalogURL(_ urlString: String, removingQueryItems: Set<String>) -> String {
        // Some scraped hrefs can contain embedded whitespace/newlines or NBSPs.
        // Normalize aggressively so program identity matches across scrapes/imports.
        let cleaned = urlString
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }
        guard var components = URLComponents(string: cleaned) else { return cleaned }

        // Normalize query items:
        // - remove noise (e.g. returnto)
        // - sort for stable identity
        let remove = Set(removingQueryItems.map { $0.lowercased() })
        if let items = components.queryItems, !items.isEmpty {
            let filtered = items
                .filter { !remove.contains($0.name.lowercased()) }
                .sorted {
                    let aName = $0.name.lowercased()
                    let bName = $1.name.lowercased()
                    if aName != bName { return aName < bName }
                    let aVal = ($0.value ?? "").lowercased()
                    let bVal = ($0.value ?? "").lowercased()
                    return aVal < bVal
                }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Fragments like "#core_123" should not affect program identity.
        components.fragment = nil

        var rebuilt = components.string ?? cleaned
        if rebuilt.hasSuffix("?") { rebuilt.removeLast() }
        return rebuilt
    }

    private struct RequirementFingerprint: Codable {
        let order: Int
        let category: String
        let requiredCourses: [String]?
        let requiredCoursesDetailed: [CourseDetail]?
        let selectFrom: [String]?
        let selectFromDetailed: [CourseDetail]?
        let selectCount: Int?
        let creditsRequired: Int
        let description: String?
    }

    private func stableRequirementsHash(_ requirements: [DegreeRequirement]) -> String {
        let normalized: [RequirementFingerprint] = requirements.enumerated().map { (idx, r) in
            RequirementFingerprint(
                order: idx,
                category: r.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                requiredCourses: r.requiredCourses?.map(normalizeCourseCode).sorted(),
                requiredCoursesDetailed: r.requiredCoursesDetailed?.sorted(by: { $0.code < $1.code }),
                selectFrom: r.selectFrom?.map(normalizeCourseCode).sorted(),
                selectFromDetailed: r.selectFromDetailed?.sorted(by: { $0.code < $1.code }),
                selectCount: r.selectCount,
                creditsRequired: r.creditsRequired,
                description: r.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(normalized)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func encodeJSONCourseList(_ codes: [String]) -> String? {
        let cleaned = codes.map(normalizeCourseCode).filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(cleaned) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    nonisolated func decodeJSONCourseList(_ json: String?) -> [String] {
        guard let json, !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    
    nonisolated func decodeDetailedCourseList(_ json: String?) -> [CourseDetail]? {
        guard let json, !json.isEmpty else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([CourseDetail].self, from: data)
    }
    
    func encodeDetailedCourseList(_ courses: [CourseDetail]) -> String? {
        guard let data = try? JSONEncoder().encode(courses),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// Get all available majors
    func getAvailableMajors() -> [String] {
        guard let university = getActiveUniversity() else { return [] }
        
        let request = NSFetchRequest<NSDictionary>(entityName: "DegreeRequirementEntity")
        request.predicate = NSPredicate(format: "university == %@", university)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["major"]
        request.returnsDistinctResults = true
        
        guard let results = try? viewContext.fetch(request) else { return [] }
        
        return results.compactMap { $0["major"] as? String }.sorted()
    }
    
    /// Link a course enrollment to catalog course
    func linkCourseToCatalog(_ course: CourseEntity, catalogCode: String) {
        if let catalogCourse = getCatalogCourse(code: catalogCode) {
            course.catalogCourse = catalogCourse
            
            // Auto-fill information from catalog
            if course.name?.isEmpty ?? true {
                course.name = catalogCourse.title
            }
            if course.credits == 0 {
                course.credits = catalogCourse.credits
            }

            save()
        }
    }
    
    /// Get all courses that a student has completed
    func getCompletedCourses(for plan: PlanEntity) -> [CourseEntity] {
        guard let semesters = plan.semesters as? Set<SemesterEntity> else { return [] }
        
        var completed: [CourseEntity] = []
        for semester in semesters {
            if let courses = semester.courses as? Set<CourseEntity> {
                completed.append(contentsOf: courses.filter { $0.isCompleted })
            }
        }
        
        return completed
    }
    
    /// Check if student meets prerequisites for a course
    func checkPrerequisites(for catalogCourse: CourseCatalogEntity, plan: PlanEntity) -> PrerequisiteValidationResult {
        let validator = PrerequisiteValidator(coreDataManager: self)
        let completedCourses = getCompletedCourses(for: plan)
        return validator.validatePrerequisites(for: catalogCourse, completedCourses: completedCourses)
    }
    
    /// Get graduation readiness status
    func getGraduationStatus(for plan: PlanEntity) -> GraduationValidationResult? {
        guard let university = getActiveUniversity() else { return nil }
        
        let validator = GraduationValidator(coreDataManager: self)
        return validator.validateGraduationReadiness(for: plan, university: university)
    }
    
    // MARK: - Department Management
    
    /// Save departments for a university (cross-references existing, overwrites with newest)
    func saveDepartments(_ departments: [(name: String, code: String?, school: String?)], for universityName: String) throws {
        let context = container.viewContext
        
        guard let university = try? fetchUniversity(name: universityName) else {
            print("[CoreData] ❌ University not found: \(universityName)")
            return
        }
        
        print("[CoreData] Saving \(departments.count) departments for \(universityName)")
        
        // 1. Deduplicate incoming departments by normalized key
        // We prefer the entry that has a 'school' (College) defined, and the shortest/cleanest name.
        var uniqueIncoming: [String: (name: String, code: String?, school: String?)] = [:]
        
        for dept in departments {
            let key = normalizeProgramDepartmentKey(dept.name)
            if key.count < 3 { continue } // Skip noise
            
            if let existing = uniqueIncoming[key] {
                // If we already have this dept, only overwrite if the new one is "better"
                // Better means: has a school (College) when the existing one doesn't
                if (existing.school == nil && dept.school != nil) {
                    uniqueIncoming[key] = dept
                }
                // Or if both have/don't have school, prefer the one without "Department" in the name if it's shorter
                else if (existing.school == nil) == (dept.school == nil) && dept.name.count < existing.name.count {
                    uniqueIncoming[key] = dept
                }
            } else {
                uniqueIncoming[key] = dept
            }
        }
        
        print("[CoreData] Consolidated to \(uniqueIncoming.count) unique departments")
        
        // LOG: Show what we're about to save
        print("[CoreData] 📋 Department names to save:")
        for (_, deptData) in uniqueIncoming.sorted(by: { $0.key < $1.key }).prefix(10) {
            print("[CoreData]    • '\(deptData.name)' (College: \(deptData.school ?? "nil"))")
        }
        if uniqueIncoming.count > 10 {
            print("[CoreData]    ... and \(uniqueIncoming.count - 10) more")
        }

        // 2. Fetch ALL existing departments to perform smart merging
        let existingRequest = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        existingRequest.predicate = NSPredicate(format: "university == %@", university)
        let existingDepartments = (try? context.fetch(existingRequest)) ?? []
        
        // Map existing entities by normalized key
        var existingMap: [String: [DepartmentEntity]] = [:]
        for existing in existingDepartments {
            guard let name = existing.name else { continue }
            let key = normalizeProgramDepartmentKey(name)
            existingMap[key, default: []].append(existing)
        }
        
        var processedKeys = Set<String>()
        
        // 3. Process each unique incoming department
        for (key, deptData) in uniqueIncoming {
            processedKeys.insert(key)
            
            let entities = existingMap[key] ?? []
            let primaryEntity: DepartmentEntity
            
            if let first = entities.first {
                // Update the first matching entity
                primaryEntity = first
                print("[CoreData]   🔄 Updating: \(deptData.name) (was \(first.name ?? ""))")
                
                // If there are duplicates (e.g. "Economics" AND "Economics Department"), delete the extras
                if entities.count > 1 {
                    print("[CoreData]   🧹 Cleaning up \(entities.count - 1) duplicate(s) for \(deptData.name)")
                    for i in 1..<entities.count {
                        context.delete(entities[i])
                    }
                }
            } else {
                // Create new
                print("[CoreData]   ➕ Creating: \(deptData.name)")
                primaryEntity = DepartmentEntity(context: context)
                primaryEntity.id = UUID()
                primaryEntity.university = university
            }
            
            // Update fields - LOG the actual name being saved
            print("[CoreData]   💾 Saving name: '\(deptData.name)'")
            primaryEntity.name = deptData.name
            primaryEntity.code = deptData.code
            // Only update school if the new data has it, or if we don't have one yet
            if let newSchool = deptData.school {
                primaryEntity.school = newSchool
            }
            primaryEntity.lastUpdated = Date()
        }
        
        // 4. Remove stale artifacts that weren't in the new scrape
        for (key, entities) in existingMap {
            if !processedKeys.contains(key) {
                for entity in entities {
                    // Check if this looks like an artifact we want to purge
                    if let name = entity.name, (name.lowercased().contains("department") || name.lowercased().contains("page")) {
                        print("[CoreData]   ⚠️ Deleting stale artifact: \(name)")
                        context.delete(entity)
                    }
                }
            }
        }
        
        try context.save()
        print("[CoreData] ✅ Saved departments successfully")
    }
    
    /// Fetch departments for a university
    func fetchDepartments(for universityName: String) -> [String] {
        let request = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        request.predicate = NSPredicate(format: "university.name == %@", universityName)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        guard let departments = try? viewContext.fetch(request) else { return [] }

        // Return all known departments for the university.
        // Some catalogs don't prefix with “College of” / “School of”, and filtering here
        // can incorrectly produce an empty dropdown.
        return departments.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Fetch departments for a university, filtered to only those that have at least one
    /// program/major at the given degree level.
    ///
    /// This is used to keep the Department dropdown consistent with the selected degree level
    /// (Undergraduate vs Graduate vs PhD), especially for schools like UB where the graduate
    /// catalog organizes programs under schools on the Programs tab.
    func fetchDepartments(for universityName: String, degreeLevel: String) -> [String] {
        let level = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return fetchDepartments(for: universityName) }

        let majorsReq = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        majorsReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "university.name == %@", universityName),
            NSPredicate(format: "degreeLevel == %@", level),
            NSPredicate(format: "isMinor == NO")
        ])
        let majors = (try? viewContext.fetch(majorsReq)) ?? []
        guard !majors.isEmpty else { return [] }

        // Collect department names from linked DepartmentEntity relationships first.
        var names = Set<String>()
        names.reserveCapacity(128)
        for m in majors {
            if let deptSet = m.departments as? Set<DepartmentEntity> {
                for d in deptSet {
                    let departmentName = cleanedOwnershipLabel(d.name)
                    let groupName = cleanedOwnershipLabel(d.school)
                    if shouldIncludeDepartmentLabel(departmentName, groupLabel: groupName) {
                        names.insert(departmentName)
                    }
                }
            }

            // Fallback: use resolved ownership fields when relationships aren't populated.
            let rd = cleanedOwnershipLabel(m.resolvedDepartment)
            let rc = cleanedOwnershipLabel(m.resolvedCollege)
            if shouldIncludeDepartmentLabel(rd, groupLabel: rc) {
                names.insert(rd)
            }
        }

        return Array(names)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func cleanedOwnershipLabel(_ raw: String?) -> String {
        (raw ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedOwnershipKey(_ raw: String?) -> String {
        cleanedOwnershipLabel(raw).lowercased()
    }

    private func isLikelySchoolOrCollegeLabel(_ label: String) -> Bool {
        let normalized = normalizedOwnershipKey(label)
        if normalized.isEmpty { return false }
        return normalized.hasPrefix("school of ") ||
            normalized.hasPrefix("college of ") ||
            normalized.hasPrefix("faculty of ") ||
            normalized.hasPrefix("division of ")
    }

    private func shouldIncludeDepartmentLabel(_ departmentLabel: String, groupLabel: String?) -> Bool {
        guard !departmentLabel.isEmpty else { return false }
        if isLikelySchoolOrCollegeLabel(departmentLabel) { return false }
        let groupKey = normalizedOwnershipKey(groupLabel)
        if !groupKey.isEmpty, normalizedOwnershipKey(departmentLabel) == groupKey {
            return false
        }
        return true
    }

    /// Fetch departments grouped by `DepartmentEntity.school` (college/school header).
    ///
    /// - Returns: Ordered list of groups, each with a header (college/school) and its departments.
    /// - Notes:
    ///   - This is intended for the Department dropdown UI, where headers are non-selectable.
    ///   - Departments without a known grouping are returned under a "(Other)" header.
    func fetchDepartmentGroups(for universityName: String) -> [(group: String, departments: [String])] {
        let request = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        request.predicate = NSPredicate(format: "university.name == %@", universityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "school", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        guard let departments = try? viewContext.fetch(request) else { return [] }

        // Stable grouping with a nice fallback bucket.
        // Use a normalized key so the same school/college doesn't appear twice due to NBSP/whitespace.
        var buckets: [String: Set<String>] = [:]
        var displayNameByKey: [String: String] = [:]
        for d in departments {
            let name = cleanedOwnershipLabel(d.name)
            let rawGroup = cleanedOwnershipLabel(d.school)
            let displayGroup = rawGroup.isEmpty ? "(Other)" : rawGroup
            let key = displayGroup == "(Other)" ? "(other)" : normalizedOwnershipKey(displayGroup)

            guard shouldIncludeDepartmentLabel(name, groupLabel: displayGroup) else { continue }

            // Preserve a nice display name for the header.
            if displayNameByKey[key] == nil {
                displayNameByKey[key] = displayGroup
            }

            buckets[key, default: []].insert(name)
        }

        // Keep ordering stable: (Other) last, otherwise alphabetical.
        let groups = buckets.keys.sorted { a, b in
            if a == "(other)" { return false }
            if b == "(other)" { return true }
            let da = displayNameByKey[a] ?? a
            let db = displayNameByKey[b] ?? b
            return da.localizedCaseInsensitiveCompare(db) == .orderedAscending
        }

        return groups.map { key in
            let display = displayNameByKey[key] ?? (key == "(other)" ? "(Other)" : key)
            return (group: display, departments: Array(buckets[key] ?? []).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        }
    }

    /// Fetch departments grouped for a university *and* filtered to the selected degree level.
    ///
    /// For the Department dropdown UI we want a stable grouping header → department rows, but
    /// the set of available departments should depend on `ProfileEntity.degreeLevel`.
    func fetchDepartmentGroups(for universityName: String, degreeLevel: String, sourceCatoid: String? = nil) -> [(group: String, departments: [String])] {
        let level = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return fetchDepartmentGroups(for: universityName) }

        let majorsReq = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        var predicates: [NSPredicate] = [
            NSPredicate(format: "university.name == %@", universityName),
            NSPredicate(format: "degreeLevel == %@", level),
            NSPredicate(format: "isMinor == NO")
        ]

        majorsReq.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        var majors = (try? viewContext.fetch(majorsReq)) ?? []
        if let sourceCatoid, !sourceCatoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            majors = majors.filter { majorMatchesCatoid($0, targetCatoid: sourceCatoid) }
        }
        guard !majors.isEmpty else { return [] }

        // Group using the best available ownership info:
        // - Prefer DepartmentEntity.school when present
        // - Otherwise fall back to MajorEntity.resolvedCollege
        // - Otherwise bucket under (Other)
        var buckets: [String: Set<String>] = [:]
        var displayNameByKey: [String: String] = [:]

        for m in majors {
            // Prefer linked departments (many-to-many).
            if let deptSet = m.departments as? Set<DepartmentEntity>, !deptSet.isEmpty {
                for d in deptSet {
                    let deptName = (d.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !deptName.isEmpty else { continue }

                    let rawGroup = cleanedOwnershipLabel(d.school)
                    let resolvedCollege = cleanedOwnershipLabel(m.resolvedCollege)
                    let groupDisplay = rawGroup.isEmpty ? resolvedCollege : rawGroup
                    let finalDisplay = groupDisplay.isEmpty ? "(Other)" : groupDisplay
                    let cleanedDeptName = cleanedOwnershipLabel(deptName)
                    guard shouldIncludeDepartmentLabel(cleanedDeptName, groupLabel: finalDisplay) else { continue }
                    let key = finalDisplay == "(Other)" ? "(other)" : normalizedOwnershipKey(finalDisplay)

                    if displayNameByKey[key] == nil { displayNameByKey[key] = finalDisplay }
                    buckets[key, default: []].insert(cleanedDeptName)
                }
                continue
            }

            // No linked departments: use resolved ownership fields.
            let deptName = cleanedOwnershipLabel(m.resolvedDepartment)
            // Don't fall back to resolvedCollege here; that produces bogus "departments".
            guard !deptName.isEmpty else { continue }

            let groupDisplay = cleanedOwnershipLabel(m.resolvedCollege)
            let finalDisplay = groupDisplay.isEmpty ? "(Other)" : groupDisplay
            guard shouldIncludeDepartmentLabel(deptName, groupLabel: finalDisplay) else { continue }
            let key = finalDisplay == "(Other)" ? "(other)" : normalizedOwnershipKey(finalDisplay)
            if displayNameByKey[key] == nil { displayNameByKey[key] = finalDisplay }
            buckets[key, default: []].insert(deptName)
        }

        let groupKeys = buckets.keys.sorted { a, b in
            if a == "(other)" { return false }
            if b == "(other)" { return true }
            let da = displayNameByKey[a] ?? a
            let db = displayNameByKey[b] ?? b
            return da.localizedCaseInsensitiveCompare(db) == .orderedAscending
        }

        return groupKeys.map { key in
            let display = displayNameByKey[key] ?? (key == "(other)" ? "(Other)" : key)
            let departments = Array(buckets[key] ?? [])
                .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return (group: display, departments: departments)
        }
    }

#if DEBUG
    /// Debug helper: For departments that have no `school` (and therefore show up under "(Other)"),
    /// return a mapping of departmentName -> list of referencing programs (name + URL + mapping fields).
    /// This makes it easy to see *where* those departments came from.
    func debugOtherDepartmentSources(for universityName: String) -> [String: [String]] {
        let deptRequest = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        deptRequest.predicate = NSPredicate(format: "university.name == %@", universityName)

        guard let departments = try? viewContext.fetch(deptRequest) else { return [:] }

        let otherDepartments = departments.compactMap { d -> DepartmentEntity? in
            let school = d.school?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard school.isEmpty else { return nil }
            guard let name = d.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return d
        }

        guard !otherDepartments.isEmpty else { return [:] }

        let majorRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        majorRequest.predicate = NSPredicate(format: "university.name == %@", universityName)
        let majors = (try? viewContext.fetch(majorRequest)) ?? []

        // Index majors by linked department objectID for fast lookup.
        var majorsByDeptId: [NSManagedObjectID: [MajorEntity]] = [:]
        for m in majors {
            if let deptSet = m.departments as? Set<DepartmentEntity> {
                for dept in deptSet {
                    majorsByDeptId[dept.objectID, default: []].append(m)
                }
            }
        }

        var result: [String: [String]] = [:]
        for dept in otherDepartments {
            let deptName = dept.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(unnamed)"

            let linkedMajors = majorsByDeptId[dept.objectID] ?? []
            let lines = linkedMajors
                .sorted { ($0.name ?? "") < ($1.name ?? "") }
                .map { m -> String in
                    let programName = m.name ?? "(unnamed program)"
                    let isMinor = m.isMinor ? "Minor" : "Major"
                    let url = m.programURL ?? "nil"
                    let resolvedDept = m.resolvedDepartment ?? "nil"
                    let resolvedCollege = m.resolvedCollege ?? "nil"
                    let source = m.mappingSource ?? "nil"
                    let conf = m.mappingConfidence
                    let confStr = conf == 0 ? "0" : String(conf)
                    return "\(programName) [\(isMinor)] | url=\(url) | resolvedDept=\(resolvedDept) | resolvedCollege=\(resolvedCollege) | source=\(source) | conf=\(confStr)"
                }

            result[deptName] = lines
        }

        return result
    }
#endif
    
    // MARK: - Major Management

    private func normalizeProgramDepartmentKey(_ value: String) -> String {
        var normalized = value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        // Remove common suffixes/prefixes that cause duplication
        let removeList = [
            " department page",
            " department",
            " program",
            " office",
            " page"
        ]
        
        for term in removeList {
            if normalized.hasSuffix(term) {
                normalized = String(normalized.dropLast(term.count))
            }
        }
        
        if normalized.hasPrefix("department of ") {
            normalized = String(normalized.dropFirst("department of ".count))
        }
        
        return normalized
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Save majors and minors for a university (cross-references existing, overwrites with newest)
    func saveMajors(
        _ majors: [(
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
        )],
        for universityName: String
    ) throws {
        let context = container.viewContext
        let logger = DebugLogger.shared
        
        logger.log("[SaveMajors] Starting save for \(majors.count) programs (university=\(universityName))")
        
        guard let university = try? fetchUniversity(name: universityName) else {
            logger.log("[SaveMajors] ❌ University not found: \(universityName)")
            print("[CoreData] ❌ University not found: \(universityName)")
            return
        }
        
        logger.log("[SaveMajors] ✓ University entity found")
        print("[CoreData] Saving \(majors.count) majors/minors for \(universityName)")
        print("[CoreData] Cross-referencing with existing programs...")
        
        // Fetch all existing majors for this university
        let existingRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        existingRequest.predicate = NSPredicate(format: "university == %@", university)
        let existingMajors = (try? context.fetch(existingRequest)) ?? []
        
        print("[CoreData] Found \(existingMajors.count) existing programs")
        
        // Track which programs we've processed
        var processedKeys = Set<String>()

        func normalizeDegreeTypeKey(_ value: String?) -> String {
            let trimmed = (value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            return trimmed
                .uppercased()
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: " ", with: "")
        }

        func extractCombinedDegreeTypeFromProgramName(_ rawName: String) -> String {
            // Some catalogs present combined programs where the degree information is encoded in the program name,
            // e.g. "Accounting BS/Accounting MS" or "Biomedical Sciences BS/PharmD".
            let normalized = rawName
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .uppercased()
                .replacingOccurrences(of: ".", with: "")

            let separators = CharacterSet(charactersIn: "/,+;&")
                .union(.whitespacesAndNewlines)
            let parts = normalized
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let known: Set<String> = [
                "AA", "AS", "AAS",
                "BA", "BS", "BFA", "BM",
                "MA", "MS", "MBA", "MENG", "MPH",
                "PHD", "JD", "MD", "DMD", "DDS", "DPT",
                "PHARMD"
            ]

            var tokens: [String] = []
            tokens.reserveCapacity(2)

            for p in parts {
                if known.contains(p), !tokens.contains(p) {
                    tokens.append(p)
                }
            }

            // Handle spaced PharmD variants: "PHARM" "D" => "PHARMD".
            if !tokens.contains("PHARMD"), parts.count >= 2 {
                for idx in 0..<(parts.count - 1) {
                    if parts[idx] == "PHARM", parts[idx + 1] == "D" {
                        tokens.append("PHARMD")
                        break
                    }
                }
            }

            if tokens.count >= 2 {
                return tokens.joined(separator: "/")
            }
            return ""
        }

        func normalizeProgramNameForStorage(_ raw: String, degreeType: String?) -> String {
            var s = raw
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Collapse PharmCAS-admissions variants that the catalog sometimes lists separately.
            // We treat these as the same underlying Pharmacy PharmD program for dropdown purposes.
            if s.range(of: "pharmcas", options: [.caseInsensitive]) != nil {
                s = s
                    .replacingOccurrences(of: ": PharmCAS", with: "", options: [.caseInsensitive])
                    .replacingOccurrences(of: "PharmD: PharmCAS", with: "PharmD", options: [.caseInsensitive])
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // If the scraped name redundantly ends with the same degree token, remove it
            // so display stays consistent (we append degreeType later for non-combined degrees).
            let dt = normalizeDegreeTypeKey(degreeType)
            if !dt.isEmpty {
                let upper = s.uppercased()
                if upper.hasSuffix(" \(dt)") {
                    s = String(s.dropLast(dt.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                func normalizeDegreeToken(_ value: String) -> String {
                    value
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: " ", with: "")
                }

                // Also strip trailing comma degree tokens like ", B.S." or ", BS".
                if let comma = s.lastIndex(of: ",") {
                    let suffix = s[s.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if suffix.count <= 8, suffix.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                        if normalizeDegreeToken(String(suffix)) == normalizeDegreeToken(dt) {
                            s = String(s[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } else {
                    // Or strip trailing space degree tokens like "... B.S.".
                    let parts = s.split(separator: " ")
                    if parts.count >= 2 {
                        let last = String(parts.last ?? "")
                        if last.count <= 8, last.range(of: "^[A-Za-z.]+$", options: .regularExpression) != nil {
                            if normalizeDegreeToken(last) == normalizeDegreeToken(dt) {
                                s = parts.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }
            }

            return s
        }

        func extractCatoid(from urlString: String?) -> String {
            let trimmed = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let comps = URLComponents(string: trimmed) else { return "" }
            return comps.queryItems?.first(where: { $0.name.lowercased() == "catoid" })?.value ?? ""
        }

        func mergeURL(_ urlString: String, into existing: String?) -> String? {
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return existing }

            var set = Set<String>()
            let current = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty {
                for part in current.split(separator: ",") {
                    let v = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { set.insert(v) }
                }
            }

            set.insert(trimmed)
            let joined = set.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }).joined(separator: ",")
            return joined.isEmpty ? nil : joined
        }

        func mergeCatoid(_ catoid: String, into existing: String?) -> String? {
            let trimmed = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return existing }

            var set = Set<String>()
            let current = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty {
                for part in current.split(separator: ",") {
                    let v = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { set.insert(v) }
                }
            }

            set.insert(trimmed)
            let joined = set.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }).joined(separator: ",")
            return joined.isEmpty ? nil : joined
        }
        
        for major in majors {
            let cleanedName = normalizeProgramNameForStorage(major.name, degreeType: major.degreeType)

            // Create a unique key for each program
            // IMPORTANT: include degreeType so variants like "Computer Science" BA vs BS don't overwrite.
            var storedDegreeType = normalizeDegreeTypeKey(major.degreeType)
            let combinedFromName = extractCombinedDegreeTypeFromProgramName(major.name)
            if !combinedFromName.isEmpty {
                storedDegreeType = combinedFromName
            }

            let programKey = "\(cleanedName)|\(major.degreeLevel)|\(major.isMinor)|\(storedDegreeType)"
            processedKeys.insert(programKey)
            
            let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
            if storedDegreeType.isEmpty {
                request.predicate = NSPredicate(
                    format: "name == %@ AND degreeLevel == %@ AND isMinor == %@ AND university == %@ AND (degreeType == nil OR degreeType == '')",
                    cleanedName, major.degreeLevel, NSNumber(value: major.isMinor), university
                )
            } else {
                request.predicate = NSPredicate(
                    format: "name == %@ AND degreeLevel == %@ AND isMinor == %@ AND university == %@ AND degreeType == %@",
                    cleanedName, major.degreeLevel, NSNumber(value: major.isMinor), university, storedDegreeType
                )
            }
            
            let existing = try? context.fetch(request).first
            let majorEntity = existing ?? MajorEntity(context: context)
            
            if existing == nil {
                print("[CoreData]   ➕ Creating new program: \(major.name) (\(major.isMinor ? "Minor" : "Major"))")
                majorEntity.id = UUID()
                majorEntity.university = university
            } else {
                print("[CoreData]   🔄 Updating existing program: \(major.name) (\(major.isMinor ? "Minor" : "Major"))")
            }
            
            // Always update with newest data
            majorEntity.name = cleanedName
            majorEntity.degreeLevel = major.degreeLevel
            // Normalize stored degreeType for consistent querying/deduping.
            majorEntity.degreeType = storedDegreeType.isEmpty ? nil : storedDegreeType
            majorEntity.isMinor = major.isMinor
            majorEntity.lastUpdated = Date()

            // Program URL + resolved mapping metadata (detail scraping)
            // Keep `programURL` stable to avoid flapping between catalogs during multi-catalog scrapes.
            // Track multi-catalog coverage in `sourceCatoids`.
            let incomingURL = (major.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let existingURL = (majorEntity.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if existing == nil || existingURL.isEmpty {
                majorEntity.programURL = incomingURL.isEmpty ? nil : incomingURL
            }

            if !incomingURL.isEmpty {
                majorEntity.programURLs = mergeURL(incomingURL, into: majorEntity.programURLs)
            }

            let incomingCatoid = extractCatoid(from: incomingURL)
            if !incomingCatoid.isEmpty {
                majorEntity.sourceCatoids = mergeCatoid(incomingCatoid, into: majorEntity.sourceCatoids)
            }
            majorEntity.resolvedDepartment = major.resolvedDepartment
            majorEntity.resolvedCollege = major.resolvedCollege
            if let conf = major.mappingConfidence {
                majorEntity.mappingConfidence = conf
            }
            majorEntity.mappingSource = major.mappingSource
            
            // Link to department(s) if specified (either from grouped listings OR from resolved mapping)
            // Many-to-many: one program can be listed under multiple departments.
            // Many-to-many migration: `MajorEntity.department` no longer exists.
            // Use resolvedDepartment (plus the incoming raw department string from the scrape payload).
            let deptCandidates = [major.resolvedDepartment, major.department].compactMap { $0 }
                .compactMap { $0 }

            var matchedDepartments: [DepartmentEntity] = []
            for deptName in deptCandidates {
                let normalizedInput = normalizeProgramDepartmentKey(deptName)

                // 1) Exact match on name/code/school.
                let deptRequest = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
                deptRequest.predicate = NSPredicate(
                    format: "(name == %@ OR code == %@ OR school == %@) AND university == %@",
                    deptName, deptName, deptName, university
                )

                if let deptEntity = try? context.fetch(deptRequest).first {
                    matchedDepartments.append(deptEntity)
                    continue
                }

                // 2) Fuzzy match: try to find a department whose name/school appears in the scraped department string.
                // This helps when catalogs use broader labels like "College of Engineering" in one place and
                // "Engineering" or a longer formal name in another.
                let allDeptRequest = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
                allDeptRequest.predicate = NSPredicate(format: "university == %@", university)
                let allDepartments = (try? context.fetch(allDeptRequest)) ?? []

                let matched = allDepartments.first { dept in
                    let candidates = [dept.name, dept.code, dept.school]
                        .compactMap { $0 }
                        .map { normalizeProgramDepartmentKey($0) }
                        .filter { !$0.isEmpty }

                    return candidates.contains { c in
                        normalizedInput.contains(c) || c.contains(normalizedInput)
                    }
                }

                if let matched {
                    matchedDepartments.append(matched)
                }
            }

            if !matchedDepartments.isEmpty {
                majorEntity.departments = NSSet(array: Array(Set(matchedDepartments)))
            } else {
                majorEntity.departments = nil
            }
            
            // Persist requirements if provided from initial scrape
            if let requirements = major.requirements, !requirements.isEmpty, let programURL = major.url {
                let canonicalURL = canonicalizeAcalogURL(programURL, removingQueryItems: ["returnto"])
                let degreeTypeForRequirements = storedDegreeType.isEmpty ? "Unknown" : storedDegreeType
                
                // Delete existing requirements for this program to avoid duplicates
                let existingReqRequest = NSFetchRequest<DegreeRequirementEntity>(entityName: "DegreeRequirementEntity")
                existingReqRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "university == %@", university),
                    NSPredicate(format: "programURL == %@", canonicalURL),
                    NSPredicate(format: "degreeType == %@", degreeTypeForRequirements)
                ])
                let existingReqs = (try? context.fetch(existingReqRequest)) ?? []
                for req in existingReqs {
                    context.delete(req)
                }
                
                // Create new requirement entities
                let newHash = stableRequirementsHash(requirements)
                for (index, category) in requirements.enumerated() {
                    let cat = category.category.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cat.isEmpty else { continue }
                    
                    let entity = DegreeRequirementEntity(context: context)
                    entity.id = UUID()
                    entity.university = university
                    entity.programURL = canonicalURL
                    entity.major = cleanedName
                    entity.degreeType = degreeTypeForRequirements
                    entity.requirementCategory = cat
                    entity.sectionOrder = Int16(index)
                    entity.creditsRequired = Int16(category.creditsRequired)
                    entity.descriptionText = category.description
                    
                    if let required = category.requiredCourses, !required.isEmpty {
                        entity.requiredCourses = required.joined(separator: ", ")
                    } else {
                        entity.requiredCourses = nil
                    }
                    
                    // Store detailed course information (new format)
                    if let requiredDetailed = category.requiredCoursesDetailed, !requiredDetailed.isEmpty {
                        entity.requiredCoursesDetailedJSON = encodeDetailedCourseList(requiredDetailed)
                    } else {
                        entity.requiredCoursesDetailedJSON = nil
                    }
                    
                    if let selectFrom = category.selectFrom, !selectFrom.isEmpty {
                        entity.selectFromJSON = encodeJSONCourseList(selectFrom)
                        if let c = category.selectCount {
                            entity.selectCount = Int16(c)
                        } else {
                            entity.selectCount = 0
                        }
                    } else {
                        entity.selectFromJSON = nil
                        entity.selectCount = 0
                    }
                    
                    // Store detailed select-from information (new format)
                    if let selectDetailed = category.selectFromDetailed, !selectDetailed.isEmpty {
                        entity.selectFromDetailedJSON = encodeDetailedCourseList(selectDetailed)
                    } else {
                        entity.selectFromDetailedJSON = nil
                    }
                    
                    entity.requirementsHash = newHash
                    entity.lastScrapedAt = Date()
                    entity.lastUpdated = Date()
                }
            }
        }
        
        // Archive programs that no longer exist in the new scrape.
        // IMPORTANT: For multi-catalog universities (UB), we scrape catalogs incrementally.
        // We must NOT delete programs from other catalogs during a single-catalog scrape.
        // Only delete if the program's source catoid(s) overlap with the incoming scrape.
        let incomingCatoids = Set(majors.compactMap { extractCatoid(from: $0.url ?? "") }.filter { !$0.isEmpty })
        let isSingleCatalogScrape = incomingCatoids.count == 1
        
        for existing in existingMajors {
            guard let name = existing.name else { continue }
            let existingDegreeTypeKey = normalizeDegreeTypeKey(existing.degreeType)
            let programKey = "\(name)|\(existing.degreeLevel ?? "Unknown")|\(existing.isMinor)|\(existingDegreeTypeKey)"
            
            if !processedKeys.contains(programKey) {
                // Check if this program belongs to a catalog we're currently scraping
                let existingCatoids = parseSourceCatoidsField(existing.sourceCatoids)
                let shouldDelete: Bool
                
                if incomingCatoids.isEmpty {
                    // No catoid provenance on incoming rows means the scrape is ambiguous.
                    // Preserve existing rows to avoid deleting programs from unrelated catalogs.
                    shouldDelete = false
                } else if isSingleCatalogScrape, let scrapedCatoid = incomingCatoids.first {
                    // Single-catalog scrape: only delete if program belongs to this catalog
                    shouldDelete = existingCatoids.contains(scrapedCatoid)
                } else {
                    // Multi-catalog scrape: only delete if program belongs exclusively to scraped catalogs
                    // (i.e., it doesn't have any catoids outside our scrape set)
                    let existingSet = Set(existingCatoids)
                    shouldDelete = !existingSet.isEmpty && existingSet.isSubset(of: incomingCatoids)
                }
                
                if shouldDelete {
                    print("[CoreData]   ⚠️ Program '\(name)' (\(existing.isMinor ? "Minor" : "Major")) no longer in catalog, deleting...")
                    context.delete(existing)
                } else {
                    print("[CoreData]   ⏭️ Program '\(name)' (\(existing.isMinor ? "Minor" : "Major")) preserved (belongs to different catalog)")
                }
            }
        }
        
        func parseSourceCatoidsField(_ raw: String?) -> [String] {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return trimmed
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        
        try context.save()
        logger.log("[SaveMajors] ✓ Core Data save completed successfully")
        logger.log("[SaveMajors] Saved \(majors.count) programs with \(majors.filter { $0.requirements != nil }.count) having requirements")
        
        // Verify the save actually persisted by immediately fetching
        let verifyRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        verifyRequest.predicate = NSPredicate(format: "university == %@", university)
        let verifyCount = (try? context.count(for: verifyRequest)) ?? -1
        logger.log("[SaveMajors] ⚠️ VERIFICATION: Immediate count after save = \(verifyCount)")
        
        // Also check in viewContext to see if it's visible there
        let viewVerifyRequest = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        viewVerifyRequest.predicate = NSPredicate(format: "university == %@", university)
        let viewCount = (try? viewContext.count(for: viewVerifyRequest)) ?? -1
        logger.log("[SaveMajors] ⚠️ VERIFICATION: Count in viewContext = \(viewCount)")
        
        print("[CoreData] ✅ Saved \(majors.count) programs successfully")
    }

    func saveMajors(
        _ majors: [(
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
            requirements: [DegreeRequirement]?,
            sourceCatalogCatoid: String?
        )],
        for universityName: String
    ) throws {
        let downgraded: [(
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
        )] = majors.map { major in
            let sourceCatoid = (major.sourceCatalogCatoid ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let urlWithCatoid: String? = {
                guard !sourceCatoid.isEmpty else { return major.url }
                guard let rawURL = major.url?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !rawURL.isEmpty else { return major.url }
                guard var comps = URLComponents(string: rawURL) else { return major.url }
                var items = comps.queryItems ?? []
                if let idx = items.firstIndex(where: { $0.name.lowercased() == "catoid" }) {
                    items[idx] = URLQueryItem(name: "catoid", value: sourceCatoid)
                } else {
                    items.append(URLQueryItem(name: "catoid", value: sourceCatoid))
                }
                comps.queryItems = items
                return comps.string ?? major.url
            }()

            return (
                name: major.name,
                degreeLevel: major.degreeLevel,
                degreeType: major.degreeType,
                isMinor: major.isMinor,
                department: major.department,
                url: urlWithCatoid,
                resolvedDepartment: major.resolvedDepartment,
                resolvedCollege: major.resolvedCollege,
                mappingConfidence: major.mappingConfidence,
                mappingSource: major.mappingSource,
                requirements: major.requirements
            )
        }
        try saveMajors(downgraded, for: universityName)
    }
    
    /// Fetch majors for a university, degree level, and optionally department/degree type.
    /// - Note: For majors (not minors), results include degree type appended (e.g., "Anthropology, BA").
    private func normalizedCatoidToken(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func catoidToken(fromURLString rawURL: String?) -> String {
        let raw = (rawURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let comps = URLComponents(string: raw) else { return "" }
        return comps.queryItems?
            .first(where: {
                $0.name.compare("catoid", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func catoidTokenSet(fromCSV raw: String?) -> Set<String> {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return Set(
            value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func catoidTokenSet(fromProgramURLsCSV raw: String?) -> Set<String> {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        var out = Set<String>()
        for part in value.split(separator: ",") {
            let token = catoidToken(fromURLString: String(part))
            if !token.isEmpty {
                out.insert(token)
            }
        }
        return out
    }

    private func majorMatchesCatoid(_ major: MajorEntity, targetCatoid: String) -> Bool {
        let token = normalizedCatoidToken(targetCatoid)
        guard !token.isEmpty else { return true }

        if catoidTokenSet(fromCSV: major.sourceCatoids).contains(token) {
            return true
        }
        if catoidToken(fromURLString: major.programURL)
            .compare(token, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return true
        }
        if catoidTokenSet(fromProgramURLsCSV: major.programURLs).contains(token) {
            return true
        }
        return false
    }

    func fetchMajors(
        for universityName: String,
        degreeLevel: String,
        department: String? = nil,
        degreeType: String? = nil,
        includeMinors: Bool = false,
        sourceCatoid: String? = nil
    ) -> [String] {
        // Removed excessive logging - was being called repeatedly
        
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        
        var predicates: [NSPredicate] = [
            NSPredicate(format: "university.name == %@", universityName),
            NSPredicate(format: "degreeLevel == %@", degreeLevel),
            NSPredicate(format: "isMinor == %@", NSNumber(value: includeMinors))
        ]
        
        if let dept = department, !dept.isEmpty {
            // Normalize the department name for more flexible matching
            let normalizedDept = normalizeProgramDepartmentKey(dept)

            // Tokenized fallback: require *all* significant tokens to appear across department fields.
            // This catches common formatting differences like "&" vs "and", punctuation, and extra words.
            let stopwords: Set<String> = [
                "and", "of", "the", "for", "in", "to", "on", "at", "a", "an"
            ]
            let deptTokens = normalizedDept
                .split(separator: " ")
                .map { String($0) }
                .filter { token in
                    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.count < 3 { return false }
                    return !stopwords.contains(t)
                }

            let tokenAndPredicate: NSPredicate? = {
                guard !deptTokens.isEmpty else { return nil }
                let perToken: [NSPredicate] = deptTokens.map { token in
                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                        NSPredicate(format: "ANY departments.name CONTAINS[cd] %@", token),
                        NSPredicate(format: "resolvedDepartment CONTAINS[cd] %@", token)
                    ])
                }
                return NSCompoundPredicate(andPredicateWithSubpredicates: perToken)
            }()
            
            // Match either through the linked DepartmentEntity OR through resolved text mappings.
            // Try multiple matching strategies to handle cleaned names
            var deptSubpredicates: [NSPredicate] = [
                // Exact matches
                NSPredicate(format: "ANY departments.name == %@", dept),
                NSPredicate(format: "ANY departments.code == %@", dept),
                NSPredicate(format: "resolvedDepartment == %@", dept),
                // Case-insensitive matches
                NSPredicate(format: "ANY departments.name ==[cd] %@", dept),
                NSPredicate(format: "resolvedDepartment ==[cd] %@", dept),
                // Contains normalized (for partial matches)
                NSPredicate(format: "ANY departments.name CONTAINS[cd] %@", normalizedDept),
                NSPredicate(format: "resolvedDepartment CONTAINS[cd] %@", normalizedDept)
            ]

            if let tokenAndPredicate {
                deptSubpredicates.append(tokenAndPredicate)
            }

            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: deptSubpredicates))
        }

        // Apply degreeType filter only for majors (not minors), and only if a degree type is selected.
        // Be tolerant of callers passing full labels like "Bachelor of Science (BS)" while Core Data stores acronyms like "BS".
        if !includeMinors, let dtRaw = degreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !dtRaw.isEmpty {
            let candidates = degreeTypeCandidates(from: dtRaw)
            if !candidates.isEmpty {
                let subpreds = candidates.map { NSPredicate(format: "degreeType ==[c] %@", $0) }
                predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: subpreds))
            }
        }


        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        guard var majors = try? viewContext.fetch(request) else {
            return []
        }

        if let sourceCatoid, !sourceCatoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            majors = majors.filter { majorMatchesCatoid($0, targetCatoid: sourceCatoid) }
        }
        
        // Return major names with degree type appended (e.g., "Anthropology, BA")
        // Use a Set to prevent duplicates
        var uniqueMajors = Set<String>()
        
        for major in majors {
            guard let name = major.name else { continue }
            
            // For majors (not minors), append the degree type if available
            if !includeMinors, let degreeType = major.degreeType, !degreeType.isEmpty {
                // Check if the name already ends with a degree type pattern to avoid double-appending
                var trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                // Some catalogs store/display names with a trailing comma (e.g. "Anthropology,")
                // which would render as ",," when we append the degree type.
                trimmedName = trimmedName
                    .replacingOccurrences(of: ",\\s*$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Combined degrees already embed degree information (e.g., "Accounting BS/Accounting MS").
                // Don't append a trailing ", BS".
                if trimmedName.contains("/") {
                    uniqueMajors.insert(trimmedName)
                    continue
                }
                
                // If name already ends with ", DEGREE" pattern, don't append again
                if trimmedName.hasSuffix(", \(degreeType)") {
                    uniqueMajors.insert(trimmedName)
                } else if trimmedName.contains(",") {
                    // Name already has a trailing comma-suffix; keep as-is if it's just a differently formatted degree token (e.g., "B.S." vs "BS").
                    let suffixRaw = trimmedName.split(separator: ",").last.map { String($0) } ?? ""
                    let suffix = suffixRaw.trimmingCharacters(in: .whitespacesAndNewlines)

                    func normalizeDegreeToken(_ s: String) -> String {
                        s.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
                    }

                    if !suffix.isEmpty, normalizeDegreeToken(suffix) == normalizeDegreeToken(degreeType) {
                        uniqueMajors.insert(trimmedName)
                    } else {
                        uniqueMajors.insert("\(trimmedName), \(degreeType)")
                    }
                } else {
                    // Append degree type
                    uniqueMajors.insert("\(trimmedName), \(degreeType)")
                }
            } else {
                uniqueMajors.insert(name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        return Array(uniqueMajors).sorted()
    }

    nonisolated private func degreeTypeCandidates(from raw: String) -> [String] {
        var candidates: [String] = []

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        candidates.append(trimmed)

        // If the raw value itself is a combined token (e.g., "BS/MS"), also include components.
        // This makes lookups tolerant when Core Data stores only one side or when the UI passes a combined label.
        let splitParts = trimmed
            .replacingOccurrences(of: " ", with: "")
            .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
            .map { String($0) }
            .filter { !$0.isEmpty }
        if splitParts.count >= 2 {
            candidates.append(contentsOf: splitParts)
        }

        // Extract acronym inside parentheses, e.g. "Bachelor of Science (BS)" -> "BS".
        if let open = trimmed.firstIndex(of: "("), let close = trimmed.firstIndex(of: ")"), open < close {
            let inner = String(trimmed[trimmed.index(after: open)..<close])
            let parts = inner
                .replacingOccurrences(of: " ", with: "")
                .split(whereSeparator: { $0 == "/" || $0 == "," || $0 == ";" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            candidates.append(contentsOf: parts)
        }

        // Normalize common variants (periods/spaces) -> uppercase acronym (e.g., "Ph.D." -> "PHD").
        let normalized = trimmed
            .uppercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")

        if !normalized.isEmpty {
            candidates.append(normalized)

            // Also split the normalized form (covers things like "B.S./M.S." -> "BS/MS").
            let normalizedSplit = normalized
                .split(whereSeparator: { $0 == "/" || $0 == "+" || $0 == "," || $0 == ";" || $0 == "&" })
                .map { String($0) }
                .filter { !$0.isEmpty }
            if normalizedSplit.count >= 2 {
                candidates.append(contentsOf: normalizedSplit)
            }
        }

        // De-dupe while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for c in candidates {
            let t = c.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if seen.contains(t) { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

#if DEBUG
    /// Debug helper: export all programs currently stored for a university as TSV.
    /// This is useful for verifying the DB matches the catalog list after import.
    func debugExportProgramsTSV(for universityName: String) -> URL? {
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        request.predicate = NSPredicate(format: "university.name == %@", universityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "isMinor", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        guard let programs = try? viewContext.fetch(request) else { return nil }

        func classify(_ name: String, isMinor: Bool) -> String {
            if isMinor { return "MINOR" }
            if name.contains("/") { return "COMBINED" }
            return "MAJOR"
        }

        var lines: [String] = []
        lines.append("type\tname\tdegreeType\tdegreeLevel\tresolvedCollege\tresolvedDepartment\turl")

        for p in programs {
            let name = (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            let typ = classify(name, isMinor: p.isMinor)
            let dt = (p.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dl = (p.degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rc = (p.resolvedCollege ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rd = (p.resolvedDepartment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = (p.programURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("\(typ)\t\(name)\t\(dt)\t\(dl)\t\(rc)\t\(rd)\t\(url)")
        }

        let safeName = universityName
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = "\(safeName)_programs.tsv"

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let outURL = docs.appendingPathComponent(fileName)

        do {
            try lines.joined(separator: "\n").write(to: outURL, atomically: true, encoding: .utf8)
            return outURL
        } catch {
            return nil
        }
    }
#endif
    
    /// Fetches the degree type for a specific major
    func fetchDegreeType(for majorName: String, universityName: String) -> String? {
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        
        // The majorName might be "Computer Science, BS" or just "Computer Science"
        // We need to extract the actual name part
        let cleanName: String
        if majorName.contains(", ") {
            cleanName = majorName.components(separatedBy: ", ").first ?? majorName
        } else {
            cleanName = majorName
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "university.name == %@", universityName),
            NSPredicate(format: "name == %@", cleanName),
            NSPredicate(format: "isMinor == NO")
        ])
        request.fetchLimit = 1
        
        guard let major = try? viewContext.fetch(request).first else { return nil }
        return major.degreeType
    }

    // MARK: - Department grouping helpers (College header → departments)

    /// Update `DepartmentEntity.school` (used as the grouping header in the UI) by mining
    /// `MajorEntity.resolvedCollege` + `MajorEntity.resolvedDepartment` mappings.
    ///
    /// Rationale:
    /// - ModernCampus catalogs frequently expose program ownership (department/college) more reliably
    ///   on program detail pages than on the department directory page.
    /// - The UI needs a stable grouping key: *college header → department rows*.
    ///
    /// Behavior:
    /// - For each department, find the most common resolvedCollege among majors mapped to that department
    ///   (direct `department` relationship preferred; fallback to `resolvedDepartment` text match).
    /// - Writes the winning college into `DepartmentEntity.school`.
    func updateDepartmentSchoolsFromProgramOwnership(for universityName: String) {
        let context = container.viewContext
        guard let university = try? fetchUniversity(name: universityName) else {
            print("[CoreData] ❌ University not found: \(universityName)")
            return
        }

        let deptsReq = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        deptsReq.predicate = NSPredicate(format: "university == %@", university)
        let departments = (try? context.fetch(deptsReq)) ?? []
        if departments.isEmpty { return }

        let majorsReq = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        majorsReq.predicate = NSPredicate(format: "university == %@", university)
        let majors = (try? context.fetch(majorsReq)) ?? []
        if majors.isEmpty { return }

        func norm(_ s: String) -> String { normalizeProgramDepartmentKey(s) }

        // Build counts: deptNameKey -> collegeName -> count
        var counts: [String: [String: Int]] = [:]
        for m in majors {
            guard let college = m.resolvedCollege?.trimmingCharacters(in: .whitespacesAndNewlines), !college.isEmpty else { continue }

            // Prefer the linked DepartmentEntity.
            if let deptSet = m.departments as? Set<DepartmentEntity> {
                let deptNames = deptSet.compactMap { $0.name }.filter { !$0.isEmpty }
                if !deptNames.isEmpty {
                    // Count the college for every linked department.
                    for deptName in deptNames {
                        let key = norm(deptName)
                        counts[key, default: [:]][college, default: 0] += 1
                    }
                    continue
                }
            }

            // Fallback: resolvedDepartment textual match.
            if let rawDept = m.resolvedDepartment?.trimmingCharacters(in: .whitespacesAndNewlines), !rawDept.isEmpty {
                let key = norm(rawDept)
                counts[key, default: [:]][college, default: 0] += 1
            }
        }

        var updated = 0
        for dept in departments {
            guard let deptName = dept.name?.trimmingCharacters(in: .whitespacesAndNewlines), !deptName.isEmpty else { continue }
            let key = norm(deptName)
            guard let collegeCounts = counts[key], !collegeCounts.isEmpty else { continue }

            // Choose the most frequent college.
            let winner = collegeCounts.max { a, b in
                if a.value != b.value { return a.value < b.value }
                return a.key.count < b.key.count
            }?.key

            guard let winner, !winner.isEmpty else { continue }
            if dept.school != winner {
                dept.school = winner
                dept.lastUpdated = Date()
                updated += 1
            }
        }

        if context.hasChanges {
            do {
                try context.save()
                print("[CoreData] ✅ Updated \(updated) department grouping records (\(universityName))")
            } catch {
                print("[CoreData] ❌ Failed updating department grouping: \(error)")
            }
        }
    }

    // MARK: - UB org unit → program mapping persistence

    /// Persist org-unit→program mapping results by updating the relevant `MajorEntity` rows.
    ///
    /// This intentionally reuses the existing schema:
    /// - `MajorEntity.departments` for resolved DepartmentEntity link(s) (many-to-many)
    /// - `MajorEntity.resolvedDepartment` / `resolvedCollege` / `mappingConfidence` / `mappingSource` for traceability.
    ///
    /// - Parameter mappings: key is program URL (or name if no URL), value is resolved ownership.
    func persistProgramOwnershipMappings(
        for universityName: String,
        mappings: [String: (department: String?, college: String?, confidence: Double?, source: String?)]
    ) {
        guard !mappings.isEmpty else { return }
        let context = container.viewContext
        guard let university = try? fetchUniversity(name: universityName) else {
            print("[CoreData] ❌ University not found: \(universityName)")
            return
        }

        // Preload departments for fuzzy linking.
        let deptsReq = NSFetchRequest<DepartmentEntity>(entityName: "DepartmentEntity")
        deptsReq.predicate = NSPredicate(format: "university == %@", university)
        let allDepartments = (try? context.fetch(deptsReq)) ?? []

        let majorsReq = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        majorsReq.predicate = NSPredicate(format: "university == %@", university)
        let majors = (try? context.fetch(majorsReq)) ?? []

        var updated = 0
        for major in majors {
            let key = (major.programURL?.isEmpty == false) ? major.programURL! : (major.name ?? "")
            guard let mapping = mappings[key] else { continue }

            major.resolvedDepartment = mapping.department
            major.resolvedCollege = mapping.college
            if let c = mapping.confidence { major.mappingConfidence = c }
            major.mappingSource = mapping.source
            major.lastUpdated = Date()

            // Link DepartmentEntity if a department string exists.
            if let deptName = mapping.department, !deptName.isEmpty {
                let normalizedInput = normalizeProgramDepartmentKey(deptName)
                let matched = allDepartments.first { dept in
                    let candidates = [dept.name, dept.code, dept.school]
                        .compactMap { $0 }
                        .map { normalizeProgramDepartmentKey($0) }
                        .filter { !$0.isEmpty }
                    return candidates.contains { c in
                        normalizedInput.contains(c) || c.contains(normalizedInput)
                    }
                }
                if let matched {
                    var existing = (major.departments as? Set<DepartmentEntity>) ?? []
                    existing.insert(matched)
                    major.departments = NSSet(set: existing)
                }
            }

            updated += 1
        }

        if context.hasChanges {
            do {
                try context.save()
                print("[CoreData] ✅ Persisted ownership mappings for \(updated) programs (\(universityName))")
            } catch {
                print("[CoreData] ❌ Failed to persist ownership mappings: \(error)")
            }
        }
    }

    /// Read back a department→program list mapping from Core Data.
    ///
    /// This is useful for UB where we want a stable relationship map between org units and programs.
    func fetchProgramMappingByDepartment(for universityName: String, degreeLevel: String? = nil, includeMinors: Bool = true) -> [String: [String]] {
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        var preds: [NSPredicate] = [NSPredicate(format: "university.name == %@", universityName)]
        if let degreeLevel, !degreeLevel.isEmpty {
            preds.append(NSPredicate(format: "degreeLevel == %@", degreeLevel))
        }
        if !includeMinors {
            preds.append(NSPredicate(format: "isMinor == NO"))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        guard let majors = try? viewContext.fetch(request) else { return [:] }

        var out: [String: [String]] = [:]
        for m in majors {
            guard let name = m.name, !name.isEmpty else { continue }

            if let deptSet = m.departments as? Set<DepartmentEntity> {
                let names = deptSet.compactMap { $0.name }.filter { !$0.isEmpty }
                if !names.isEmpty {
                    // Many-to-many: include this program under every linked department.
                    for deptName in names {
                        out[deptName, default: []].append(name)
                    }
                    continue
                }
            }

            let fallbackDept = m.resolvedDepartment ?? m.resolvedCollege ?? "(Unmapped)"
            out[fallbackDept, default: []].append(name)
        }
        // Stable ordering
        for k in out.keys {
            out[k]?.sort()
        }
        return out
    }
    
    /// Fetch minors for a university and degree level (no department restriction)
    func fetchMinors(for universityName: String, degreeLevel: String, sourceCatoid: String? = nil) -> [String] {
        // Minors are always Undergraduate, independent of degree level selection.
        // Backward compatibility: older imports stored minors under degreeLevel == "Minor".
        let undergrad = fetchMajors(
            for: universityName,
            degreeLevel: "Undergraduate",
            department: nil,
            degreeType: nil,
            includeMinors: true,
            sourceCatoid: sourceCatoid
        )
        let legacy = fetchMajors(
            for: universityName,
            degreeLevel: "Minor",
            department: nil,
            degreeType: nil,
            includeMinors: true,
            sourceCatoid: sourceCatoid
        )
        return Array(Set(undergrad + legacy)).sorted()
    }

    /// Fetch certificate programs for a university (graduate/professional only).
    ///
    /// This is used by the Academic Identity UI when a non-undergraduate degree level is selected.
    /// Certificates are identified by either a stored `degreeType` that contains "certificate" (e.g.,
    /// "Advanced Certificate") or a program `name` that contains "certificate".
    func fetchCertificates(for universityName: String, sourceCatoid: String? = nil) -> [String] {
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        var predicates: [NSPredicate] = [
            NSPredicate(format: "university.name == %@", universityName),
            NSPredicate(format: "isMinor == NO"),
            NSPredicate(format: "degreeLevel != %@", "Undergraduate"),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "degreeType CONTAINS[cd] %@", "certificate"),
                NSPredicate(format: "name CONTAINS[cd] %@", "certificate")
            ])
        ]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        var majors = (try? viewContext.fetch(request)) ?? []
        if let sourceCatoid, !sourceCatoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            majors = majors.filter { majorMatchesCatoid($0, targetCatoid: sourceCatoid) }
        }
        var unique = Set<String>()
        for m in majors {
            guard let name = m.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            unique.insert(name)
        }
        return Array(unique).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Fetch all unique degree types from majors for a university
    func fetchDegreeTypes(for universityName: String, degreeLevel: String) -> [String] {
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        request.predicate = NSPredicate(
            format: "university.name == %@ AND degreeLevel == %@ AND isMinor == NO",
            universityName, degreeLevel
        )
        
        guard let majors = try? viewContext.fetch(request) else { return [] }
        
        // Extract unique degree types
        var degreeTypes = Set<String>()
        for major in majors {
            if let degreeType = major.degreeType, !degreeType.isEmpty {
                degreeTypes.insert(degreeType)
            }
        }
        
        return Array(degreeTypes).sorted()
    }
    
    // MARK: - Testing Helper
    
    /// Delete all catalog data (departments, majors, courses) - for testing only
    func deleteAllCatalogData() {
#if !DEBUG
        print("[CoreData] ⚠️ deleteAllCatalogData() is disabled in Release builds")
        return
#else
        let context = container.viewContext
        
        print("[CoreData] 🗑️ [TEST MODE] Deleting all catalog data...")
        
        // Delete all departments
        let deptRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "DepartmentEntity")
        let deptDelete = NSBatchDeleteRequest(fetchRequest: deptRequest)
        
        // Delete all majors
        let majorRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MajorEntity")
        let majorDelete = NSBatchDeleteRequest(fetchRequest: majorRequest)
        
        // Delete all catalog courses
        let catalogCourseRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CourseCatalogEntity")
        let catalogCourseDelete = NSBatchDeleteRequest(fetchRequest: catalogCourseRequest)

        // Delete all scraped degree requirements
        let reqRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "DegreeRequirementEntity")
        let reqDelete = NSBatchDeleteRequest(fetchRequest: reqRequest)
        
        do {
            try context.execute(deptDelete)
            try context.execute(majorDelete)
            try context.execute(catalogCourseDelete)
            try context.execute(reqDelete)
            try context.save()
            
            // Refresh the context to reflect changes
            context.refreshAllObjects()
            
            print("[CoreData] ✅ All catalog data deleted successfully")
        } catch {
            print("[CoreData] ❌ Failed to delete catalog data: \(error.localizedDescription)")
        }
#endif
    }
    
    /// Debug: Get all programs for a university with their degreeLevel
    func debugGetAllPrograms(for universityName: String) -> [(name: String, degreeLevel: String?, isMinor: Bool, resolvedDepartment: String?, resolvedCollege: String?)] {
        let request = NSFetchRequest<MajorEntity>(entityName: "MajorEntity")
        request.predicate = NSPredicate(format: "university.name == %@", universityName)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        let programs = (try? viewContext.fetch(request)) ?? []
        return programs.map { program in
            (
                name: program.name ?? "",
                degreeLevel: program.degreeLevel,
                isMinor: program.isMinor,
                resolvedDepartment: program.resolvedDepartment,
                resolvedCollege: program.resolvedCollege
            )
        }
    }
}

// MARK: - CalendarEventEntity Fetch Helpers

extension CalendarEventEntity {
    static func upcomingRequest(days: Int = 8) -> NSFetchRequest<CalendarEventEntity> {
        let request = NSFetchRequest<CalendarEventEntity>(entityName: "CalendarEventEntity")
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
        request.predicate = NSPredicate(
            format: "startDate >= %@ AND startDate < %@",
            start as NSDate,
            end as NSDate
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CalendarEventEntity.startDate, ascending: true)
        ]
        request.fetchLimit = 50
        return request
    }
}
