import Foundation
import CoreData
import Combine

/// Core Data stack configuration (macOS 26+).
///
/// Notes (Apple guidance):
/// - SQLite stores default to WAL; we keep WAL for performance and reliability.
/// - We intentionally do NOT enable persistent history tracking (per project direction).
@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    /// `true` once the persistent store has finished loading (potentially off-main).
    @Published private(set) var isStoreLoaded: Bool = false

    /// A `nonisolated` bridge so non-isolated callers (e.g., `CoreDataManager.init`)
    /// can observe store-load completion without crossing the main-actor boundary.
    nonisolated(unsafe) let storeLoadPublisher = CurrentValueSubject<Bool, Never>(false)

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Creates a persistence controller.
    /// - Parameter inMemory: Use an in-memory store (tests/previews).
    nonisolated init(inMemory: Bool = false) {
        let c = NSPersistentContainer(name: "CollegeDataModel")
        container = c

        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
            // Keep in-memory stores fast/small.
            description.shouldAddStoreAsynchronously = false
        } else {
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = true  // load off the main thread

            let storeURL = Self.defaultStoreURL()
            Self.migrateLegacyStoreIfNeeded(to: storeURL)
            description.url = storeURL

            // Make WAL explicit (it is the default for Core Data SQLite, but this documents intent).
            description.setOption(
                ["journal_mode": "WAL"] as NSDictionary,
                forKey: NSSQLitePragmasOption
            )
        }

        // Lightweight migration defaults.
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        c.persistentStoreDescriptions = [description]

        // The completion handler fires on a private queue for async stores.
        // Hop back to the main actor to publish `isStoreLoaded`.
        c.loadPersistentStores { [weak self] _, error in
            if let error {
                // IMPORTANT:
                // If the store fails to load (e.g., migration failure), continuing would make the app
                // appear empty, and users may re-scrape/overwrite their existing data.
                // Failing fast keeps the on-disk store untouched and prevents accidental data loss.
                assertionFailure("Core Data failed to load: \(error)")
                fatalError("Core Data failed to load: \(error)")
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.configureContexts()
                self.isStoreLoaded = true
                self.storeLoadPublisher.send(true)
            }
        }
    }

    nonisolated private static func defaultStoreURL() -> URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("CollegeDataModel.sqlite")
    }

    /// If previous versions stored the SQLite file at a different location, move it into the
    /// current canonical store URL so upgrades don't look like a wipe.
    nonisolated private static func migrateLegacyStoreIfNeeded(to targetURL: URL) {
        let fm = FileManager.default

        guard !fm.fileExists(atPath: targetURL.path) else {
            return
        }

        let appSupportRoot = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        // Candidate legacy locations from earlier iterations.
        let candidates: [URL] = [
            // Unsandboxed / older ad-hoc locations.
            appSupportRoot?.appendingPathComponent("CollegeDataModel.sqlite"),
            appSupportRoot?.appendingPathComponent("College", isDirectory: true).appendingPathComponent("CollegeDataModel.sqlite"),
            // Legacy filename.
            appSupportRoot?.appendingPathComponent("College.sqlite"),
        ].compactMap { $0 }.filter { $0.path != targetURL.path }

        guard let sourceURL = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            return
        }

        do {
            try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return
        }

        moveSQLiteTrio(from: sourceURL, to: targetURL)
    }

    nonisolated private static func moveSQLiteTrio(from sourceURL: URL, to targetURL: URL) {
        let fm = FileManager.default

        func companionURLs(for sqliteURL: URL) -> [URL] {
            [
                sqliteURL,
                sqliteURL.appendingPathExtension("-wal"),
                sqliteURL.appendingPathExtension("-shm"),
            ]
        }

        let fromURLs = companionURLs(for: sourceURL)
        let toURLs = companionURLs(for: targetURL)

        for (from, to) in zip(fromURLs, toURLs) {
            guard fm.fileExists(atPath: from.path) else { continue }

            // Best-effort; if move fails (e.g., cross-volume), fall back to copy + delete.
            do {
                if fm.fileExists(atPath: to.path) {
                    try? fm.removeItem(at: to)
                }
                try fm.moveItem(at: from, to: to)
            } catch {
                do {
                    if fm.fileExists(atPath: to.path) {
                        try? fm.removeItem(at: to)
                    }
                    try fm.copyItem(at: from, to: to)
                    try? fm.removeItem(at: from)
                } catch {
                    // If we can't migrate, do nothing (don't delete the source).
                }
            }
        }
    }

    nonisolated static func inMemory() -> PersistenceController {
        PersistenceController(inMemory: true)
    }

    nonisolated func newBackgroundContext(name: String? = nil) -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.automaticallyMergesChangesFromParent = true
        context.undoManager = nil
        context.name = name
        return context
    }

    private func configureContexts() {
        let context = container.viewContext
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.automaticallyMergesChangesFromParent = true
        context.undoManager = nil
        context.name = "viewContext"
    }
}

