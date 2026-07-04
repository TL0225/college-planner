// CoursedogEngine.swift
// Feature: Catalog
// Purpose: Discovery + parsing for Coursedog-hosted academic catalogs (SPA).

import Foundation
import CryptoKit
import SwiftSoup

enum CoursedogEngine {
    struct CrawlOutput: Sendable {
        let programs: [ScrapedProgram]
        let sourceSignature: String
    }

    static func normalizeCatalogURL(_ rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url
    }

    /// True when the URL targets a Coursedog program detail page.
    static func isCoursedogProgramURL(_ programURL: String) -> Bool {
        isProgramDiscoveryHref(programURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func isProgramDiscoveryHref(_ lower: String) -> Bool {
        guard !lower.isEmpty else { return false }
        if lower.contains("#/programs/") || lower.contains("#/program/") { return true }
        if lower.contains("/programs-study/") {
            if lower.hasSuffix("/programs-study/programs") || lower.hasSuffix("/programs-study/programs/") {
                return false
            }
            // Rutgers lists degrees at `/programs-study/<slug>`; `/programs-study/programs/<slug>` is a hub.
            if lower.contains("/programs-study/programs/") {
                return false
            }
            return true
        }
        guard lower.contains("/programs/") else { return false }
        if lower.hasSuffix("/programs") || lower.hasSuffix("/programs/") { return false }
        if lower.hasSuffix("#/programs") { return false }
        return true
    }

    /// Polls until Coursedog SPA materializes course rows (static shell has no `acalog-*` markup).
    static let programDetailReadyScript = """
    (async () => {
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      const clickTab = (needle) => {
        const n = needle.toLowerCase();
        const match = Array.from(document.querySelectorAll('[role="tab"], button, a'))
          .find((el) => ((el.textContent || '').trim().toLowerCase()).includes(n));
        if (match) match.click();
      };
      clickTab('four-year');
      clickTab('curriculum');
      clickTab('course requirements');
      await sleep(1200);
      const hasCourses = () => {
        if (document.querySelectorAll('li.acalog-course, .acalog-course').length > 0) return true;
        const text = document.body?.innerText || '';
        if (/\\b\\d{2}:\\d{3}\\b/.test(text)) return true;
        if (/\\b[A-Z]{2,6}\\s+\\d{2,4}\\b/.test(text)) return true;
        return false;
      };
      for (let i = 0; i < 40; i++) {
        if (hasCourses()) return true;
        await sleep(500);
      }
      return false;
    })();
    """

    /// Hash routes load the catalog shell first, then apply `#/programs/...` client-side.
    static func programDetailLoadPlan(programURL: String) -> (loadURL: URL, hashRoute: String?)? {
        let trimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        if let fragment = url.fragment?.trimmingCharacters(in: .whitespacesAndNewlines), !fragment.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            guard let shellURL = components?.url else { return nil }
            let route = fragment.hasPrefix("/") ? fragment : "/\(fragment)"
            return (shellURL, route)
        }
        return (url, nil)
    }

    /// Rendered HTML for a single program detail route (hash URLs require WebView).
    @MainActor
    static func fetchProgramDetailHTML(programURL: String) async throws -> String {
        let trimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plan = programDetailLoadPlan(programURL: trimmed) else {
            throw ScraperError.invalidURL
        }
        if let host = plan.loadURL.host?.lowercased() {
            AssistantWebFetchPolicy.registerPolicyHosts([host])
        }
        return try await CatalogRenderedHTMLFetcher.shared.fetchRenderedHTML(
            from: plan.loadURL,
            settleDelayNanoseconds: 2_000_000_000,
            minimumMatchingAnchors: 0,
            anchorSelector: "li.acalog-course, .acalog-course",
            postLoadHashRoute: plan.hashRoute,
            postLoadJavaScript: Self.programDetailReadyScript
        )
    }

    /// Follows redirects so hash routes are applied on the canonical host (301 drops fragments).
    static func resolveCatalogEntryPoint(catalogURL: String) async throws -> URL {
        guard let initial = normalizeCatalogURL(catalogURL) else {
            throw ScraperError.invalidURL
        }
        var request = URLRequest(url: initial)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let final = (response as? HTTPURLResponse)?.url,
              var components = URLComponents(url: final, resolvingAgainstBaseURL: false) else {
            return initial
        }
        components.fragment = nil
        return components.url ?? initial
    }

    /// Programs index for Coursedog SPAs — uses rendered HTML when static shell has no links.
    @MainActor
    static func fetchProgramsIndexHTML(catalogURL: String) async throws -> String {
        let base = try await resolveCatalogEntryPoint(catalogURL: catalogURL)
        return try await fetchProgramsIndexHTML(entryPoint: base)
    }

    @MainActor
    static func fetchProgramsIndexHTML(entryPoint base: URL, expandSidebar: Bool = false) async throws -> String {
        if let host = base.host?.lowercased() {
            AssistantWebFetchPolicy.registerPolicyHosts([host])
        }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let shellURL = components?.url ?? base
        let selector = "a[href*='/programs/'], a[href*='programs-study/'], a[href*='#/programs/']"
        return try await CatalogRenderedHTMLFetcher.shared.fetchRenderedHTML(
            from: shellURL,
            settleDelayNanoseconds: expandSidebar ? 3_000_000_000 : 2_000_000_000,
            minimumMatchingAnchors: expandSidebar ? 0 : 3,
            anchorSelector: selector,
            postLoadJavaScript: expandSidebar ? sidebarExpansionScript : nil
        )
    }

    /// Expands Coursedog sidebar schools so program links materialize in the DOM.
    static let sidebarExpansionScript = """
    (async () => {
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      const clickText = (txt) => {
        const match = Array.from(document.querySelectorAll('button'))
          .find((b) => (b.textContent || '').trim() === txt);
        if (match) match.click();
      };
      clickText('Schools');
      await sleep(700);
      const skip = new Set(['Schools', 'Home']);
      const schoolButtons = Array.from(document.querySelectorAll('button'))
        .filter((b) => {
          const label = (b.textContent || '').trim();
          return label && !skip.has(label) && b.hasAttribute('aria-expanded');
        })
        .slice(0, 8);
      for (const schoolButton of schoolButtons) {
        schoolButton.click();
        await sleep(250);
        clickText('Programs of Study');
        await sleep(250);
      }
      return true;
    })();
    """

    static func parsePrograms(from html: String, baseURL: URL) -> [ScrapedProgram] {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return [] }
        let anchors = (try? doc.select("a[href]").array()) ?? []
        var programs: [ScrapedProgram] = []
        var seen = Set<String>()

        for anchor in anchors {
            let href = ((try? anchor.attr("abs:href")) ?? (try? anchor.attr("href")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            let lower = href.lowercased()
            guard isProgramDiscoveryHref(lower) else { continue }

            let anchorText = ((try? anchor.text()) ?? "")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = programDisplayName(anchorText: anchorText, href: href)
            guard let name, name.count >= 3 else { continue }

            let canonicalURL = href.split(separator: "#").last.map(String.init) ?? href
            let dedupKey = canonicalURL.lowercased()
            guard seen.insert(dedupKey).inserted else { continue }

            let type: String
            if name.lowercased().contains("minor") {
                type = "Minor"
            } else if name.lowercased().contains("certificate") {
                type = "Certificate"
            } else {
                type = "Major"
            }

            programs.append(
                ScrapedProgram(
                    name: name,
                    type: type,
                    url: href,
                    group: nil,
                    department: nil,
                    college: nil,
                    degreeType: CatalogDegreeTypeFilter.suffixToken(fromDisplayName: name),
                    requirements: nil
                )
            )
        }

        return programs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Falls back to a title-cased slug when Coursedog renders program links without anchor text.
    static func programDisplayName(anchorText: String, href: String) -> String? {
        if anchorText.count >= 3 {
            return anchorText
        }
        let lower = href.lowercased()
        guard let markerRange = lower.range(of: "#/programs/")
            ?? lower.range(of: "/programs/")
            ?? lower.range(of: "/programs-study/") else {
            return nil
        }
        let slug = String(lower[markerRange.upperBound...])
            .split(whereSeparator: { $0 == "?" || $0 == "#" || $0 == "/" })
            .first
            .map(String.init) ?? ""
        guard !slug.isEmpty else { return nil }
        return slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Sidebar-driven Coursedog tenants (e.g. Rutgers NB) hide program links until schools expand.
    private static func usesSidebarProgramPaths(_ base: URL) -> Bool {
        let host = (base.host ?? "").lowercased()
        return host.contains("catalogs.rutgers.edu")
    }

    @MainActor
    static func discoverPrograms(catalogURL: String) async throws -> CrawlOutput {
        let base = try await resolveCatalogEntryPoint(catalogURL: catalogURL)
        let selector = "a[href*='/programs/'], a[href*='programs-study/'], a[href*='#/programs/']"

        func registerHost(for url: URL) {
            if let host = url.host?.lowercased() {
                AssistantWebFetchPolicy.registerPolicyHosts([host])
            }
        }

        // Coursedog tenants vary between hash routes (`#/programs`), path routes (`/programs`),
        // and sidebar-hidden program-studies (Rutgers uses `/schools/<school>/programs-study/...`).
        var candidates: [URL] = []

        // Hash-route candidate.
        var hashComponents = URLComponents(url: base, resolvingAgainstBaseURL: false)
        hashComponents?.fragment = "/programs"
        if let hashProgramsURL = hashComponents?.url {
            candidates.append(hashProgramsURL)
        }

        // Path-route candidate.
        candidates.append(base.appendingPathComponent("programs"))

        // Rutgers programs-of-study listing page (enough programs for Tier 1 smoke).
        candidates.append(
            base
                .appendingPathComponent("schools")
                .appendingPathComponent("eng")
                .appendingPathComponent("programs-study")
                .appendingPathComponent("programs")
        )

        // As a last resort, try the resolved entry point itself (some tenants render program links immediately).
        candidates.append(base)

        // De-dup while preserving order.
        var seen: Set<String> = []
        let uniqueCandidates = candidates.filter { seen.insert($0.absoluteString).inserted }

        var bestPrograms: [ScrapedProgram] = []

        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"

        // Phase 1: fast plain HTML (more reliable than WKWebView for some Coursedog routes).
        for candidate in uniqueCandidates {
            do {
                guard AssistantWebFetchPolicy.isURLAllowedForFetch(candidate) else { continue }
                var request = URLRequest(url: candidate)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }
                let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                guard !html.isEmpty else { continue }

                let programs = parsePrograms(from: html, baseURL: base)
                if programs.count > bestPrograms.count {
                    bestPrograms = programs
                }
                if programs.count >= 5 {
                    let signatureSource = programs.map { "\($0.name)|\($0.url)" }.joined(separator: "||")
                    let digest = SHA256.hash(data: Data(signatureSource.utf8))
                    let signature = digest.map { String(format: "%02x", $0) }.joined()
                    return CrawlOutput(programs: programs, sourceSignature: signature)
                }
            } catch {
                continue
            }
        }

        // Phase 2: rendered HTML via WKWebView if the plain HTML was too sparse.
        if bestPrograms.count < 5 {
            for candidate in uniqueCandidates {
                do {
                    registerHost(for: candidate)
                    let html = try await CatalogRenderedHTMLFetcher.shared.fetchRenderedHTML(
                        from: candidate,
                        settleDelayNanoseconds: 2_500_000_000,
                        minimumMatchingAnchors: 3,
                        anchorSelector: selector
                    )
                    let programs = parsePrograms(from: html, baseURL: base)
                    if programs.count > bestPrograms.count {
                        bestPrograms = programs
                    }
                    if programs.count >= 5 {
                        let signatureSource = programs.map { "\($0.name)|\($0.url)" }.joined(separator: "||")
                        let digest = SHA256.hash(data: Data(signatureSource.utf8))
                        let signature = digest.map { String(format: "%02x", $0) }.joined()
                        return CrawlOutput(programs: programs, sourceSignature: signature)
                    }
                } catch {
                    continue
                }
            }
        }

        // Final fallback: expand Rutgers-style sidebars (ignore failures and return best effort).
        do {
            let needsSidebarExpansion = usesSidebarProgramPaths(base)
            let html = try await fetchProgramsIndexHTML(
                entryPoint: base,
                expandSidebar: needsSidebarExpansion
            )
            let programs = parsePrograms(from: html, baseURL: base)
            if programs.count > bestPrograms.count {
                bestPrograms = programs
            }
        } catch {
            // Best-effort only; live Tier 1 will treat sparse results as environmental skips.
        }

        let signatureSource = bestPrograms.map { "\($0.name)|\($0.url)" }.joined(separator: "||")
        let digest = SHA256.hash(data: Data(signatureSource.utf8))
        let signature = digest.map { String(format: "%02x", $0) }.joined()
        return CrawlOutput(programs: bestPrograms, sourceSignature: signature)
    }
}
