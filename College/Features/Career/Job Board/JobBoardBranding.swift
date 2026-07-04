// JobBoardBranding.swift
// Feature: Career
// Purpose: Career module — JobBoardCompanyLogoStore.
// Data: CollegePersistence / repositories when applicable.

import AppKit
import Combine
import Foundation

enum JobBoardBranding {
    /// Public Workday career sites expose a board logo at `{careersPageURL}/assets/logo`.
    static func logoURL(careersURLString: String) -> URL? {
        let trimmed = careersURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var base = trimmed
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/assets/logo")
    }
}

@MainActor
final class JobBoardCompanyLogoStore: ObservableObject {
    static let shared = JobBoardCompanyLogoStore()

    @Published private(set) var imagesBySlug: [String: NSImage] = [:]

    private var inFlight = Set<String>()

    private init() {}

    func image(for company: JobBoardCompany) -> NSImage? {
        imagesBySlug[company.normalizedSlug]
    }

    func loadLogoIfNeeded(for company: JobBoardCompany) {
        let slug = company.normalizedSlug
        guard imagesBySlug[slug] == nil, !inFlight.contains(slug) else { return }
        let url = JobBoardScraperRegistry.logoURL(for: company)
            ?? JobBoardBranding.logoURL(careersURLString: company.careersURL)
        guard let url else { return }

        inFlight.insert(slug)
        Task {
            defer { inFlight.remove(slug) }
            guard let image = await Self.fetchLogo(from: url) else { return }
            imagesBySlug[slug] = image
        }
    }

    private static func fetchLogo(from url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let image = NSImage(data: data) else { return nil }
            return resizedIcon(image, maxDimension: 32)
        } catch {
            return nil
        }
    }

    private static func resizedIcon(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let original = image.size
        guard original.width > 0, original.height > 0 else { return image }
        let scale = min(maxDimension / original.width, maxDimension / original.height, 1)
        let target = NSSize(
            width: max(1, original.width * scale),
            height: max(1, original.height * scale)
        )
        let output = NSImage(size: target)
        output.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: original),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        return output
    }
}
