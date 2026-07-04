// FaviconStore.swift
// Feature: Core
// Purpose: Resolves and caches website favicons for sidebar shortcut rows.
// Data: Disk cache under Application Support; no third-party icon services (privacy).

import SwiftUI
import AppKit

/// Resolves a site's icon by probing the site itself (apple-touch-icon / favicon), caching the
/// first hit in memory and on disk. Deliberately avoids third-party favicon services so a user's
/// shortcut hosts are never sent to Google/DuckDuckGo/etc.
@MainActor
final class FaviconStore {
    static let shared = FaviconStore()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var negative: Set<String> = []
    private let maxNegativeEntries = 256
    private var trackedMemoryEntries = 0

    var memoryEntryCount: Int { trackedMemoryEntries }

    private init() {
        memory.countLimit = 128
    }

    func evictMemoryCache() {
        memory.removeAllObjects()
        negative.removeAll()
        trackedMemoryEntries = 0
    }

    private lazy var cacheDir: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("College/Favicons", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Synchronous memory-cache lookup so rows can show a cached icon without flashing.
    func cachedIcon(for siteURL: URL?) -> NSImage? {
        guard let host = siteURL?.host?.lowercased(), !host.isEmpty else { return nil }
        return memory.object(forKey: host as NSString)
    }

    func icon(for siteURL: URL?) async -> NSImage? {
        guard let host = siteURL?.host?.lowercased(), !host.isEmpty else { return nil }

        if let img = memory.object(forKey: host as NSString) { return img }
        if negative.contains(host) { return nil }

        if let dir = cacheDir {
            let fileURL = dir.appendingPathComponent(host + ".png")
            if let data = try? Data(contentsOf: fileURL), let img = NSImage(data: data) {
                memory.setObject(img, forKey: host as NSString)
                trackedMemoryEntries += 1
                return img
            }
        }

        if let existing = inFlight[host] { return await existing.value }
        let task = Task<NSImage?, Never> { [weak self] in
            await self?.fetch(host: host) ?? nil
        }
        inFlight[host] = task
        let result = await task.value
        inFlight[host] = nil

        if let result {
            memory.setObject(result, forKey: host as NSString)
            trackedMemoryEntries += 1
            persist(result, host: host)
        } else {
            if negative.count >= maxNegativeEntries, let first = negative.first {
                negative.remove(first)
            }
            negative.insert(host)
        }
        return result
    }

    private func fetch(host: String) async -> NSImage? {
        let candidatePaths = [
            "apple-touch-icon.png",
            "apple-touch-icon-precomposed.png",
            "favicon.ico",
            "favicon.png",
        ]
        for path in candidatePaths {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = "/" + path
            guard let url = components.url else { continue }

            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            if let image = NSImage(data: data), image.size.width >= 8, image.size.height >= 8 {
                return image
            }
        }
        return nil
    }

    private func persist(_ image: NSImage, host: String) {
        guard let dir = cacheDir,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(host + ".png"))
    }
}
