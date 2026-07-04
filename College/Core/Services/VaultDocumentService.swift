// VaultDocumentService.swift
// Feature: Core
// Purpose: Core module — IndexItem.
// Data: CollegePersistence / repositories when applicable.

// VaultDocumentService.swift
// Centralised helper for all "Apple platform" document features:
//   • QLThumbnailGenerator  – rich per-file thumbnails
//   • CoreSpotlight         – system-wide searchability
//   • NSSharingServicePicker – Share Sheet / AirDrop
//   • NSPrintOperation      – Print via PDF
//   • NSUserActivity        – Handoff / Continuity

import AppKit
import Combine
import QuickLookThumbnailing
import CoreSpotlight
import PDFKit
import os

// MARK: - Thumbnail cache

/// In-memory cache of rendered thumbnails keyed by document UUID string.
/// Thread-safe via MainActor isolation.
@MainActor
final class VaultThumbnailCache: ObservableObject {
    static let shared = VaultThumbnailCache()
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let maxEntries = 256
    private init() {}

    var entryCount: Int { cache.count }

    func image(for key: String) -> NSImage? { cache[key] }

    /// Generates a thumbnail for `url` and stores it under `key`.
    /// No-ops if a generation is already in flight for the same key.
    func generate(for url: URL, key: String, size: CGSize = CGSize(width: 200, height: 200)) {
        guard cache[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2,
            representationTypes: .thumbnail
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(key) }
            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                if self.cache.count >= self.maxEntries, let oldest = self.cache.keys.first {
                    self.cache.removeValue(forKey: oldest)
                }
                self.cache[key] = rep.nsImage
                self.objectWillChange.send()
            } catch { }
        }
    }

    func evict(key: String) { cache.removeValue(forKey: key) }
    func evictAll() { cache.removeAll() }
}

// MARK: - Spotlight

/// Indexes and removes vault documents from CoreSpotlight so they appear in
/// system-wide Spotlight searches.
enum VaultSpotlightService {
    private static let domainID = "com.timothy.college.vault"
    private static let logger = Logger(subsystem: "Timothy.College", category: "Spotlight")

    struct IndexItem {
        let id: UUID
        let name: String
        let category: String
        let tags: [String]
        let notes: String?
        let addedAt: Date
        let fileURL: URL?
    }

    static func index(_ item: IndexItem) {
        Task { @MainActor in
            await BackgroundServiceOnDemand.run(id: "vault_spotlight_index") {
                indexImpl(item)
            }
        }
    }

    private static func indexImpl(_ item: IndexItem) {
        let attr = CSSearchableItemAttributeSet(contentType: .content)
        attr.title = item.name
        attr.contentDescription = [item.category, item.tags.joined(separator: ", "), item.notes]
            .compactMap { $0.map { $0.isEmpty ? nil : $0 } ?? nil }
            .joined(separator: " · ")
        attr.keywords = item.tags + [item.category]
        attr.addedDate = item.addedAt
        if let url = item.fileURL { attr.contentURL = url }

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: domainID,
            attributeSet: attr
        )
        CSSearchableIndex.default().indexSearchableItems([searchableItem]) { error in
            if let error {
                logger.warning("Spotlight index failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func remove(ids: [UUID]) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: ids.map(\.uuidString)) { error in
                if let error {
                    logger.warning("Spotlight delete failed: \(error.localizedDescription, privacy: .public)")
                }
            }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID]) { _ in }
    }
}

// MARK: - Share

/// Presents the macOS Share Sheet (NSSharingServicePicker) anchored to a view.
@MainActor
enum VaultShareService {

    /// Share a decrypted file URL using the system Share Sheet.
    /// `sourceView` is the NSView the picker should anchor to (usually the button that was clicked).
    static func share(url: URL, from sourceView: NSView) {
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: sourceView, preferredEdge: .minY)
    }

    /// Convenience overload that presents from the key window's content view
    /// when no specific anchor is available.
    static func share(url: URL) {
        guard let window = NSApp.keyWindow,
              let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let rect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }
}

// MARK: - Print

/// Prints a PDF file using NSPrintOperation.
enum VaultPrintService {

    @MainActor
    static func print(url: URL) {
        guard let pdfDoc = PDFDocument(url: url),
              let pdfPage = pdfDoc.page(at: 0) else {
            // Fallback: open in Preview which will offer its own print dialog.
            NSWorkspace.shared.open(url)
            return
        }

        // Build a PDFView to hand to NSPrintOperation
        let pdfView = PDFView()
        pdfView.document = pdfDoc
        let size = pdfPage.bounds(for: .mediaBox).size
        pdfView.frame = CGRect(origin: .zero, size: size)

        let printInfo = NSPrintInfo.shared
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.paperSize = size

        let op = NSPrintOperation(view: pdfView, printInfo: printInfo)
        op.showsProgressPanel = true
        op.run()
    }
}

// MARK: - Handoff / NSUserActivity

/// Creates an NSUserActivity representing an open vault document so macOS can
/// offer Handoff / Spotlight Quick-Open for it.
enum VaultHandoffService {
    static let activityType = "com.timothy.college.vault.openDocument"

    static func makeActivity(documentID: UUID, fileName: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = "Viewing \(fileName)"
        activity.userInfo = ["documentID": documentID.uuidString]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false
        return activity
    }
}

// MARK: - Password-locked PDF helper

/// Attempts to open a PDFDocument at `url`.
/// If the document is locked, returns `.locked`. Otherwise returns `.open(doc)`.
enum PDFOpenResult {
    case open(PDFDocument)
    case locked(PDFDocument)
    case failed
}

func openPDF(at url: URL) -> PDFOpenResult {
    guard let doc = PDFDocument(url: url) else { return .failed }
    return doc.isLocked ? .locked(doc) : .open(doc)
}
