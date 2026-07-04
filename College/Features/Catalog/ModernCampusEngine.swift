// ModernCampusEngine.swift
// Feature: Catalog
// Purpose: Catalog module — ScrapedProgram.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import os
import SwiftSoup

// MARK: - Data Models

nonisolated struct ScrapedProgram: Codable, Hashable, Sendable {
	let name: String
	let type: String // Major, Minor, Certificate, etc.
	let url: String
	let group: String?
	let department: String? // Department this program belongs to
	let college: String?    // College this program belongs to
	let degreeType: String? // BS, BA, MS, MA, PhD, etc.
	let requirements: [DegreeRequirement]? // Requirements scraped from program page
	/// Honors / track variant id when this row is not the baseline program (e.g. `honors`).
	let trackVariant: String?
	/// Canonical baseline program URL for track-variant rows.
	let parentProgramURL: String?

	init(
		name: String,
		type: String,
		url: String,
		group: String? = nil,
		department: String? = nil,
		college: String? = nil,
		degreeType: String? = nil,
		requirements: [DegreeRequirement]? = nil,
		trackVariant: String? = nil,
		parentProgramURL: String? = nil
	) {
		self.name = name
		self.type = type
		self.url = url
		self.group = group
		self.department = department
		self.college = college
		self.degreeType = degreeType
		self.requirements = requirements
		self.trackVariant = trackVariant
		self.parentProgramURL = parentProgramURL
	}
	
	// Custom Hashable/Equatable conformance (exclude requirements from hash/equality)
	func hash(into hasher: inout Hasher) {
		hasher.combine(name)
		hasher.combine(type)
		hasher.combine(url)
		hasher.combine(group)
		hasher.combine(department)
		hasher.combine(college)
		hasher.combine(degreeType)
		hasher.combine(trackVariant)
		hasher.combine(parentProgramURL)
	}
	
	static func == (lhs: ScrapedProgram, rhs: ScrapedProgram) -> Bool {
		lhs.name == rhs.name &&
		lhs.type == rhs.type &&
		lhs.url == rhs.url &&
		lhs.group == rhs.group &&
		lhs.department == rhs.department &&
		lhs.college == rhs.college &&
		lhs.degreeType == rhs.degreeType &&
		lhs.trackVariant == rhs.trackVariant &&
		lhs.parentProgramURL == rhs.parentProgramURL
	}
}

nonisolated struct ScrapedDepartment: Codable, Hashable, Sendable {
	let name: String
	let code: String?
}

nonisolated struct ModernCampusCatalogDescriptor: Hashable, Sendable {
	let catoid: String
	let title: String
}

// CatalogCourse is defined in CatalogModels.swift

// MARK: - Helpers

// DebugLogger is defined in DebugLogger.swift

// MARK: - Engine

/// Robust API client for Modern Campus (Acalog)
class ModernCampusEngine {
	private struct RegexKey: Hashable {
		let pattern: String
		let options: NSRegularExpression.Options.RawValue
	}

	nonisolated(unsafe) private static var regexCache: [RegexKey: NSRegularExpression] = [:]
	// OSAllocatedUnfairLock is non-blocking — avoids thread-pool starvation under high concurrency.
	nonisolated(unsafe) private static var regexCacheLock = OSAllocatedUnfairLock()

	private static func cachedRegex(
		_ pattern: String,
		options: NSRegularExpression.Options = []
	) -> NSRegularExpression? {
		let key = RegexKey(pattern: pattern, options: options.rawValue)
		if let cached = regexCacheLock.withLock({ regexCache[key] }) {
			return cached
		}
		guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
		regexCacheLock.withLock { regexCache[key] = regex }
		return regex
	}
	// MARK: - Robots.txt compliance
	// ModernCampus catalogs commonly ship a robots.txt that disallows:
	//   Disallow: /search_advanced.php
	// for User-agent: *
	// We treat this as a hard rule for our scraper.
	private static let allowRobotsDisallowedEndpoints = false

	// MARK: - HTML Fetching
	
	// A tuned session to reduce connection churn and improve performance on repeated catalog crawling.
	// Note: We do NOT automatically add a crawl-delay here because robots policies vary per site.
	// We only hard-block known disallowed endpoints (see robots compliance section).
	private static let tunedSession: URLSession = {
		let config = URLSessionConfiguration.default
		config.requestCachePolicy = .returnCacheDataElseLoad
		config.urlCache = URLCache(
			memoryCapacity: 50 * 1024 * 1024,
			diskCapacity: 250 * 1024 * 1024,
			diskPath: "ModernCampusEngineURLCache"
		)
		config.timeoutIntervalForRequest = 30
		config.timeoutIntervalForResource = 60
		config.httpMaximumConnectionsPerHost = 16
		config.waitsForConnectivity = true
		return URLSession(configuration: config)
	}()

	private struct CourseCacheEntry {
		let courses: [CatalogCourse]
		let cachedAt: Date
	}

	nonisolated(unsafe) private static var courseCache: [String: CourseCacheEntry] = [:]
	nonisolated(unsafe) private static var inFlightCourseFetchTasks: [String: Task<[CatalogCourse], Error>] = [:]
	nonisolated(unsafe) private static var courseCacheLock = OSAllocatedUnfairLock()
	private static let courseCacheTTL: TimeInterval = 15 * 60

	nonisolated(unsafe) private static var discoveryTelemetryCounts: [String: Int] = [:]
	nonisolated(unsafe) private static var discoveryTelemetryLock = OSAllocatedUnfairLock()

	private static func courseCacheKey(baseURL: String, catoid: String) -> String {
		"\(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(catoid.trimmingCharacters(in: .whitespacesAndNewlines))"
	}

	private static func cachedCourses(forKey key: String) -> [CatalogCourse]? {
		courseCacheLock.withLock {
			guard let entry = courseCache[key] else { return nil }
			if Date().timeIntervalSince(entry.cachedAt) > courseCacheTTL {
				courseCache.removeValue(forKey: key)
				return nil
			}
			return entry.courses
		}
	}

	/// Clears in-memory course fetch caches (e.g. after a large multi-catalog onboarding import).
	static func clearAllCourseCachesForMemoryPressure() {
		courseCacheLock.withLock {
			courseCache.removeAll(keepingCapacity: false)
		}
	}

	/// Snapshot of per-run HTTP/discovery counters for ingest observability.
	static func snapshotDiscoveryTelemetryCounts() -> [String: Int] {
		discoveryTelemetryLock.withLock {
			discoveryTelemetryCounts
		}
	}

	/// Resets discovery telemetry at the start of a Modern Campus ingest run.
	static func resetDiscoveryTelemetryCounts() {
		discoveryTelemetryLock.withLock {
			discoveryTelemetryCounts.removeAll(keepingCapacity: false)
		}
	}

	private static func recordDiscoveryTelemetry(_ key: String) {
		discoveryTelemetryLock.withLock {
			discoveryTelemetryCounts[key, default: 0] += 1
		}
	}

	private static func recordDiscoveryTelemetry(_ key: String, count: Int) {
		guard count > 0 else { return }
		discoveryTelemetryLock.withLock {
			discoveryTelemetryCounts[key, default: 0] += count
		}
	}
	
	private static func makeHTMLRequest(for url: URL) -> URLRequest {
		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		// Ensure we have a per-request timeout even if the session config changes.
		// This prevents a single hung preview page from stalling a full-catalog crawl.
		request.timeoutInterval = 30
		request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
		request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
		request.setValue("CollegeApp/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
		return request
	}
	
	// MARK: - Concurrency utilities
	
	/// Simple async semaphore for bounding concurrency in TaskGroups.
	/// This prevents large catalogs from spawning hundreds of concurrent requests.
	/// `internal` so UniversalCatalogScraper can reuse the same type.
	/// A concurrency-limiting semaphore that suspends callers when no slots are available.
	///
	/// Implemented as a lock-guarded class (rather than an actor) so that `release()` is
	/// synchronous and can be called from `defer` blocks without spawning an extra `Task`.
	/// The lock is held only for pointer-width bookkeeping — never around I/O — so contention
	/// is negligible.
	final class AsyncSemaphore: @unchecked Sendable {
		private let lock = OSAllocatedUnfairLock()
		private var available: Int
		private var waiters: [CheckedContinuation<Void, Never>] = []

		init(value: Int) {
			self.available = max(1, value)
		}

		func acquire() async {
			// Fast path: slot available — grab it under the lock and return immediately.
			// If no slot, append the continuation and suspend until release() resumes it.
			await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
				lock.withLock {
					if available > 0 {
						available -= 1
						cont.resume()
					} else {
						waiters.append(cont)
					}
				}
			}
		}

		/// Synchronous release — safe to call from `defer` without `await`.
		func release() {
			let next: CheckedContinuation<Void, Never>? = lock.withLock {
				if !waiters.isEmpty {
					return waiters.removeFirst()
				}
				available += 1
				return nil
			}
			next?.resume() // resume outside the lock to avoid priority inversion
		}
	}

	/// Caps concurrent in-flight GETs when an origin declares `Crawl-delay` in robots.txt.
	/// With no declared delay, returns `max`. Otherwise scales down (~one slot per second of delay).
	static func effectiveConcurrency(declaredCrawlDelay: TimeInterval, max maxConcurrency: Int) -> Int {
		effectiveConcurrency(
			declaredCrawlDelay: declaredCrawlDelay,
			politeness: .interactiveBackground,
			max: maxConcurrency
		)
	}

	/// Crawl-delay-aware concurrency that mirrors fetch politeness.
	static func effectiveConcurrency(
		declaredCrawlDelay: TimeInterval,
		politeness: CatalogFetchPoliteness,
		max maxConcurrency: Int
	) -> Int {
		let ceiling = Swift.max(1, maxConcurrency)
		let delay = effectiveCrawlDelay(declaredCrawlDelay, politeness: politeness)
		guard delay > 0 else { return ceiling }
		return Swift.max(1, min(ceiling, Int(floor(4.0 / delay))))
	}

	private static func effectiveCrawlDelay(_ declaredCrawlDelay: TimeInterval, politeness: CatalogFetchPoliteness) -> TimeInterval {
		let declared = Swift.max(0, declaredCrawlDelay)
		switch politeness {
		case .interactiveUserFacing:
			return min(declared, 3.0)
		case .interactiveBackground:
			return min(declared, 8.0)
		case .bulk, .catalogSkeleton:
			return declared
		}
	}

	/// Caps concurrent WKWebView WAF fallbacks — one rendered fetch at a time app-wide.
	private static let renderedHTMLFallbackSemaphore = AsyncSemaphore(value: 1)

	/// Heuristic: distinguish Cloudflare / bot challenges from normal Acalog pages that mention JavaScript in `<noscript>`.
	static func htmlLooksLikeWAFOrJSChallenge(_ html: String) -> Bool {
		let lower = html.lowercased()
		let hasCatalogBody =
			lower.contains("id=\"acalog-content\"") ||
			lower.contains("preview_program.php") ||
			lower.contains("preview_course") ||
			lower.contains("undergraduate catalog")
		if hasCatalogBody { return false }

		let challengeMarkers = [
			"just a moment",
			"checking your browser",
			"cf-browser-verification",
			"challenge-platform",
			"attention required! | cloudflare",
			"/cdn-cgi/challenge-platform/",
		]
		return challengeMarkers.contains(where: { lower.contains($0) })
	}

	private static func fetchRenderedHTMLFallback(for url: URL) async throws -> String {
		await renderedHTMLFallbackSemaphore.acquire()
		defer { renderedHTMLFallbackSemaphore.release() }

		if let host = url.host?.lowercased() {
			AssistantWebFetchPolicy.registerPolicyHosts([host])
		}

		return try await CatalogRenderedHTMLFetcher.shared.fetchRenderedHTML(from: url)
	}
	
	/// Public HTML fetching function for use by external scrapers.
	static func fetchHTMLPublic(_ urlString: String) async throws -> String {
		return try await fetchHTML(urlString)
	}

	/// Public HTML fetch honoring a caller-specified `robots.txt` crawl-delay politeness.
	static func fetchHTMLPublic(_ urlString: String, politeness: CatalogFetchPoliteness) async throws -> String {
		return try await fetchHTML(urlString, politeness: politeness)
	}

	/// Private HTML fetching function for internal use.
	///
	/// **Politeness**: every GET first passes through ``CatalogOriginRobotsThrottle`` so the
	/// crawler honors per-origin `robots.txt` `Crawl-delay` (a no-op when none is declared,
	/// which is the common case). This is applied once per call, before the retry loop.
	///
	/// **Retry policy**: Up to 3 attempts with exponential backoff (1 s → 2 s → 4 s).
	/// University catalog servers are notoriously flaky; a single timeout should not drop
	/// a course or fail an entire batch.
	private static func fetchHTML(
		_ urlString: String,
		politeness: CatalogFetchPoliteness = .interactiveBackground
	) async throws -> String {
		guard let url = URL(string: urlString) else {
			throw ScraperError.invalidURL
		}

		// Honor per-origin crawl-delay before hitting the network. Serialized per host with
		// jittered spacing; returns immediately for origins that declare no crawl-delay.
		await CatalogOriginRobotsThrottle.applyPoliteDelayBeforeFetch(url: url, politeness: politeness)

		let request = makeHTMLRequest(for: url)
		var lastError: Error = ScraperError.invalidResponse
		let retryableStatusCodes: Set<Int> = [429, 502, 503, 504]

		func backoffDelaySeconds(for attempt: Int) -> Double {
			let base = Double(1 << attempt)
			let jitter = Double.random(in: 0...0.25)
			return base + jitter
		}
		for attempt in 0..<3 {
			do {
				let (data, response) = try await tunedSession.data(for: request)
				guard let httpResponse = response as? HTTPURLResponse else {
					throw NSError(
						domain: "ModernCampusEngine.Network",
						code: -1,
						userInfo: [NSLocalizedDescriptionKey: "Received non-HTTP response for \(urlString)"]
					)
				}

				let statusCode = httpResponse.statusCode
				if !(200...299).contains(statusCode) {
					if statusCode == 403 || statusCode == 429 || statusCode == 503 {
						let body = String(data: data, encoding: .utf8) ?? ""
						if htmlLooksLikeWAFOrJSChallenge(body) {
							recordDiscoveryTelemetry("http.waf_detected.status.\(statusCode)")
							do {
								let rendered = try await fetchRenderedHTMLFallback(for: url)
								if !htmlLooksLikeWAFOrJSChallenge(rendered) {
									recordDiscoveryTelemetry("http.waf_rendered_success")
									return rendered
								}
								recordDiscoveryTelemetry("http.waf_rendered_still_blocked")
							} catch {
								recordDiscoveryTelemetry("http.waf_rendered_failed")
							}
						}
					}
					guard retryableStatusCodes.contains(statusCode) else {
						recordDiscoveryTelemetry("http.fail.status.\(statusCode)")
						throw NSError(
							domain: "ModernCampusEngine.HTTP",
							code: statusCode,
							userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode) for \(urlString)"]
						)
					}

					lastError = NSError(
						domain: "ModernCampusEngine.HTTP",
						code: statusCode,
						userInfo: [NSLocalizedDescriptionKey: "Retryable HTTP \(statusCode) for \(urlString)"]
					)

					recordDiscoveryTelemetry("http.retry.status.\(statusCode)")
					guard attempt < 2 else {
						recordDiscoveryTelemetry("http.fail.retryable_status_exhausted")
						break
					}

					let retryAfterSeconds: Double? = {
						guard (statusCode == 429 || statusCode == 503),
							  let raw = httpResponse.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
							  let seconds = Double(raw),
							  seconds > 0 else {
							return nil
						}
						return seconds
					}()

					let delaySeconds = max(backoffDelaySeconds(for: attempt), retryAfterSeconds ?? 0)
					if retryAfterSeconds != nil {
						recordDiscoveryTelemetry("http.retry_after_header")
					}
					try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
					continue
				}

				guard let html = String(data: data, encoding: .utf8) else {
					throw ScraperError.invalidResponse
				}
				if htmlLooksLikeWAFOrJSChallenge(html) {
					recordDiscoveryTelemetry("http.waf_detected")
					do {
						let rendered = try await fetchRenderedHTMLFallback(for: url)
						if !htmlLooksLikeWAFOrJSChallenge(rendered) {
							recordDiscoveryTelemetry("http.waf_rendered_success")
							return rendered
						}
						recordDiscoveryTelemetry("http.waf_rendered_still_blocked")
					} catch {
						recordDiscoveryTelemetry("http.waf_rendered_failed")
					}
				}
				return html
			} catch {
				lastError = error
				let isTransientURLError: Bool = {
					guard let urlError = error as? URLError else { return false }
					return urlError.code == .timedOut || urlError.code == .networkConnectionLost
				}()

				guard isTransientURLError, attempt < 2 else {
					recordDiscoveryTelemetry("http.fail.network_or_nonretryable")
					throw error
				}

				recordDiscoveryTelemetry("http.retry.network")
				let delaySeconds = backoffDelaySeconds(for: attempt)
				try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
			}
		}
		recordDiscoveryTelemetry("http.fail.exhausted")
		throw lastError
	}
	
	// MARK: - URL Helpers
	
	/// Extract a query parameter value from a URL string
	private static func extractQueryParameter(_ param: String, from urlString: String) -> String? {
		guard let url = URLComponents(string: urlString) else { return nil }
		return url.queryItems?.first(where: { $0.name == param })?.value
	}

	// MARK: - Sidebar parsing
	private struct SidebarLink: Hashable {
		let label: String
		let href: String
		let navoid: String?
	}

	/// Parse the ModernCampus sidebar navigation from an index HTML page.
	///
	/// ModernCampus catalogs commonly render navigation like:
	/// - <table class="block_n2_links link_table"> ...
	/// - each nav row contains <div class="n2_links"> ... <a href="content.php?catoid=...&navoid=...">Label</a>
	private static func parseSidebarLinksFromIndexHTML(_ html: String, forCatoid catoid: String) -> [SidebarLink] {
		guard let doc = try? SwiftSoup.parse(html) else { return [] }
		let anchors = ModernCampusSidebarParsing.anchors(in: doc)
		if anchors.isEmpty { return [] }

		var out: [SidebarLink] = []
		for a in anchors {
			let hrefRaw = (try? a.attr("href")) ?? ""
			let labelRaw = (try? a.text()) ?? ""
			let label = decodeHTMLEntities(labelRaw)
				.replacingOccurrences(of: "\u{00A0}", with: " ")
				.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !label.isEmpty else { continue }

			let href = hrefRaw.replacingOccurrences(of: "&amp;", with: "&")
			let hrefCatoid = extractQueryParameter("catoid", from: href)
			// Some sites may omit catoid in hrefs; allow those through.
			if let hrefCatoid, hrefCatoid != catoid { continue }

			let navoid = extractQueryParameter("navoid", from: href)
			out.append(SidebarLink(label: label, href: href, navoid: navoid))
		}

		// Preserve sidebar order, but de-dupe exact duplicates.
		var seen = Set<SidebarLink>()
		var ordered: [SidebarLink] = []
		for item in out {
			if seen.contains(item) { continue }
			seen.insert(item)
			ordered.append(item)
		}
		return ordered
	}

	// MARK: - Tests / Debug-only entrypoints
	#if DEBUG || COLLEGE_TEST_HOOKS
	/// Small, stable test surface for choosing the best `navoid` from index HTML.
	///
	/// - Parameters:
	///   - html: Raw index HTML.
	///   - catoid: Catalog id to prefer.
	///   - intent: Either "programs" or "orgUnits".
	/// - Returns: (navoid, label, score) if a suitable candidate was found.
	static func invoke_bestNavoidFromIndex_forTests(
		_ html: String,
		catoid: String,
		intent: String
	) -> (navoid: String, label: String, score: Int)? {
		let pairs = (try? discoverIndexNavoidsFromIndexHTML_forTests(html: html, catoid: catoid)) ?? [:]
		guard !pairs.isEmpty else { return nil }

		struct Candidate {
			let navoid: String
			let label: String
			let score: Int
		}

		func scoreLabel(_ label: String) -> Int {
			let lower = label.lowercased()
			var score = 0
			switch intent {
			case "orgUnits":
				if lower.contains("departments") { score += 8 }
				if lower.contains("program") { score += 6 }
				if lower.contains("departments & programs") || lower.contains("departments and programs") { score += 6 }
				if lower.contains("academic units") { score += 5 }
				if lower.contains("colleges") || lower.contains("schools") { score += 4 }
			case "programs":
				if lower == "majors" { score += 10 }
				if lower.contains("majors") { score += 9 }
				if lower.contains("minors") { score += 7 }
				if lower.contains("program") { score += 5 }
			default:
				break
			}
			return score
		}

		let candidates: [Candidate] = pairs.compactMap { (navoid, label) in
			let score = scoreLabel(label)
			guard score > 0 else { return nil }
			return Candidate(navoid: navoid, label: label, score: score)
		}

		let best = candidates.sorted {
			if $0.score != $1.score { return $0.score > $1.score }
			return $0.label.count > $1.label.count
		}.first
		guard let best else { return nil }
		return (best.navoid, best.label, best.score)
	}

	/// Lightweight extraction of `content.php?catoid=...&navoid=...` links from an HTML string.
	private static func discoverIndexNavoidsFromIndexHTML_forTests(html: String, catoid: String) throws -> [String: String] {
		let doc = try SwiftSoup.parse(html)
		let links = try doc.select("a[href*='content.php']")
		var navoids: [String: String] = [:]
		for link in links.array() {
			let href = try link.attr("href").replacingOccurrences(of: "&amp;", with: "&")
			let text = decodeHTMLEntities(try link.text())
				.replacingOccurrences(of: "\u{00A0}", with: " ")
				.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !text.isEmpty else { continue }

			guard let navoid = extractQueryParameter("navoid", from: href) else { continue }
			if let hrefCatoid = extractQueryParameter("catoid", from: href), hrefCatoid != catoid {
				continue
			}
			navoids[navoid] = text
		}
		return navoids
	}

	/// Test helper: parse course anchors from the Course Descriptions HTML page.
	///
	/// This is intentionally minimal (enough for the unit tests).
	static func invoke_parseCoursesFromCourseDescriptionsHTML_forTests(_ html: String) -> [CatalogCourse] {
		parseCoursesFromCourseDescriptionsHTML(html)
	}

	/// Test helper: parse a preview_course(_nopop) HTML page into a detailed CatalogCourse.
	static func invoke_parseCourseDetailFromPreviewHTML_forTests(
		_ html: String,
		fallbackCourseCode: String,
		fallbackTitle: String,
		fallbackDepartment: String? = nil
	) -> CatalogCourse? {
		let fallback = CourseLinkStub(
			courseCode: fallbackCourseCode,
			title: fallbackTitle,
			department: fallbackDepartment,
			href: "preview_course_nopop.php"
		)
		return parseCourseDetailFromPreviewHTML(html, fallback: fallback)
	}

	/// Test helper: parse UB Colleges/Schools buckets from "Departments & Programs" content page HTML.
	///
	/// This uses the same internal filtering rules as `fetchDepartmentsFromContentPage(..)` but without networking.
	static func invoke_parseDepartmentsFromContentPage_forTests(_ html: String) -> [ScrapedDepartment] {
		guard let doc = try? SwiftSoup.parse(html) else { return [] }
		let content = (try? doc.select("#acalog-content").first()) ?? doc
		let anchors = (try? content.select("a[href]").array()) ?? []

		var items: [ScrapedDepartment] = []
		for a in anchors {
			let href = ((try? a.attr("href")) ?? "").replacingOccurrences(of: "&amp;", with: "&")
			let name = decodeHTMLEntities((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			let lower = name.lowercased()

			let looksLikeOrgUnit =
				name.hasPrefix("College of ") ||
				name.hasPrefix("School of ") ||
				name.hasPrefix("Graduate School") ||
				name.hasPrefix("Jacobs School") ||
				name == "Other Departments" ||
				lower == "other departments"

			if name.count < 3 { continue }
			if lower.contains("back to top") { continue }
			if lower.contains("print") { continue }
			if lower.contains("help") { continue }
			if lower.contains("catalog home") { continue }
			if lower.contains("skip to") { continue }
			if lower == "departments & programs" || lower == "departments and programs" { continue }
			if lower == "courses" || lower == "majors and combined degrees" { continue }
			if lower == "minors, certificates and micro-credentials" { continue }
			if href.lowercased().contains("help.php") { continue }
			if href.lowercased().contains("preview_entity.php") { continue }
			if !looksLikeOrgUnit { continue }

			items.append(ScrapedDepartment(name: name, code: nil))
		}
		return Array(Set(items)).sorted { $0.name < $1.name }
	}

	/// Public, deterministic helper for UB: extract the bucket list (org unit headings) from a Departments & Programs HTML page.
	static func parseUBBucketListFromDepartmentsHTMLPublic(_ html: String) -> [String] {
		let buckets = invoke_parseDepartmentsFromContentPage_forTests(html).map { $0.name }
		return buckets
	}

	/// Public, deterministic helper for UB: group preview_entity names by the preceding bucket heading (h2).
	static func parseUBBucketEntitiesFromDepartmentsHTMLPublic(_ html: String, baseURL: String) -> [String: [String]] {
		guard let doc = try? SwiftSoup.parse(html) else { return [:] }
		let content = (try? doc.select("#acalog-content").first()) ?? doc

		var currentBucket: String?
		var out: [String: [String]] = [:]

		// Walk direct children; UB pages are relatively flat in #acalog-content.
		let children = content.children().array()
		for el in children {
			let tag = el.tagName()
			if tag == "h2" {
				let bucket = decodeHTMLEntities((try? el.text()) ?? "")
					.replacingOccurrences(of: "\u{00A0}", with: " ")
					.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
					.trimmingCharacters(in: .whitespacesAndNewlines)
				if !bucket.isEmpty {
					currentBucket = bucket
					out[bucket, default: []] = out[bucket, default: []]
				}
				continue
			}

			guard let bucket = currentBucket else { continue }
			let links = (try? el.select("a[href*=preview_entity]").array()) ?? []
			if links.isEmpty { continue }
			for a in links {
				let name = decodeHTMLEntities((try? a.text()) ?? "")
					.replacingOccurrences(of: "\u{00A0}", with: " ")
					.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
					.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !name.isEmpty else { continue }
				out[bucket, default: []].append(name)
			}
		}

		// Deterministic ordering.
		return out.mapValues { Array(Set($0)).sorted() }
	}

	/// Public helper used by tests: parse program anchors from a majors/minors content page HTML.
	static func parseProgramsFromContentHTMLPublic(_ html: String, baseURL: URL, assumedType: String) -> [ScrapedProgram] {
		// Reuse the search page program parser, which already looks for preview_program anchors.
		let programs = parseProgramHTML(html, baseURL: baseURL.absoluteString)
		if programs.isEmpty { return [] }

		// Tests want the type to be deterministic based on assumedType when parsing a content page.
		let normalizedType = assumedType.trimmingCharacters(in: .whitespacesAndNewlines)
		return programs.map { p in
			ScrapedProgram(
				name: p.name,
				type: normalizedType.isEmpty ? p.type : normalizedType,
				url: p.url,
				group: p.group,
				department: p.department,
				college: p.college,
				degreeType: p.degreeType
			)
		}
	}

	static func debugProgramAnchorSummaryPublic(_ html: String) -> String {
		guard let doc = try? SwiftSoup.parse(html) else { return "parse failed" }
		let content = (try? doc.select("#acalog-content").first()) ?? doc
		let anchors = (try? content.select("a[href]").array()) ?? []
		let previewPrograms = anchors.filter { ((try? $0.attr("href")) ?? "").contains("preview_program") }
		let sample = previewPrograms.prefix(5).compactMap { a -> String? in
			let href = (try? a.attr("href")) ?? ""
			let text = (try? a.text()) ?? ""
			return "\(text) -> \(href)"
		}
		return "anchors=\(anchors.count), preview_program=\(previewPrograms.count), sample=\(sample)"
	}

	/// Public helper for tests: extract best-effort (department, college, confidence) from a program detail HTML page.
	static func extractProgramOwnershipTuplePublic(_ html: String) -> (department: String?, college: String?, confidence: Double)? {
		// Prefer UniversalCatalogScraper’s proven ownership extraction logic.
		// It’s an actor; call synchronously via a small local parser when possible.
		// For tests we keep a light heuristic: search for "Department" and "College" keywords in text.
		let text = decodeHTMLEntities(html)
			.replacingOccurrences(of: "\u{00A0}", with: " ")
			.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		func extract(after needle: String) -> String? {
			guard let r = text.range(of: needle, options: [.caseInsensitive]) else { return nil }
			let tail = String(text[r.upperBound...])
			// Stop at comma/period/newline-ish markers.
			let stopChars = CharacterSet(charactersIn: ",.\n")
			let prefix = tail.prefix { ch in
				let scalars = String(ch).unicodeScalars
				return !scalars.contains(where: { stopChars.contains($0) })
			}
			let cleaned = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
			return cleaned.isEmpty ? nil : cleaned
		}

		let dept = extract(after: "Department")
		let college = extract(after: "College")
		let hasSomething = (dept != nil) || (college != nil)
		guard hasSomething else { return nil }
		let confidence: Double = (dept != nil && college != nil) ? 0.9 : 0.6
		return (department: dept, college: college, confidence: confidence)
	}

	static func debugProgramOwnershipTracePublic(_ html: String) -> String {
		let ownership = extractProgramOwnershipTuplePublic(html)
		return "dept=\(ownership?.department ?? "nil"), college=\(ownership?.college ?? "nil"), conf=\(ownership?.confidence ?? 0)"
	}

	static func invoke_parseProgramHTML_forTests(_ html: String, baseURL: String) -> [ScrapedProgram] {
		parseProgramHTML(html, baseURL: baseURL)
	}

	static func invoke_parseProgramCatalogRequirementSheetFromHTML_forTests(_ html: String) -> ProgramCatalogRequirementSheet {
		parseProgramCatalogRequirementSheetFromHTML(html)
	}
	#endif

	// MARK: - Types
	enum SearchTarget {
		case programs
		case courses
		case hierarchy
	}

	// MARK: - Modern Campus Navigation
	// Intentionally no hardcoded navoid overrides. All page discovery should flow
	// from the catalog URL in `schools.json` + parsing the ModernCampus sidebar/index.

	/// Debug/compatibility entrypoint used by `ModernCampusAPI`.
	/// This is not used by the main import pipeline but is handy when manually testing discovery.
	static func scrapeCatalog(baseURL: String) async {
		let logger = DebugLogger.shared
		let (normalizedBaseURL, catoidHint) = normalizeCatalogEntryPoint(baseURL)
		let catoidHintSuffix = catoidHint.flatMap { $0.isEmpty ? nil : " (catoid hint: \($0))" } ?? ""
		logger.log("🚀 Starting scrape for: \(normalizedBaseURL)" + catoidHintSuffix)

		do {
			let catoid: String
			if let catoidHint, !catoidHint.isEmpty {
				catoid = catoidHint
			} else {
				catoid = try await discoverCurrentCatalogID(baseURL: normalizedBaseURL)
			}
			logger.log("✅ Using Catalog ID: \(catoid)")

			let searchLocations = try await discoverSearchLocations(baseURL: normalizedBaseURL, catoid: catoid)

			let departments = try await fetchDepartments(baseURL: normalizedBaseURL, catoid: catoid)
			logger.log("🏫 Found \(departments.count) Departments")

			let collegesAndSchools = try await fetchCollegesAndSchools(baseURL: normalizedBaseURL, catoid: catoid)
			logger.log("🏛️ Found \(collegesAndSchools.count) Colleges/Schools")

			let progLoc = searchLocations[.programs] ?? "3"
			logger.log("🔎 Scraping Programs using Location ID: \(progLoc)")
			let programs = try await fetchPrograms(baseURL: normalizedBaseURL, catoid: catoid, locationID: progLoc)
			logger.log("🎓 Found \(programs.count) Programs")
		} catch {
			logger.log("🔥 Critical Failure: \(error)")
		}
	}

	private struct ProgramPageNavoids {
		var majors: String?
		var minors: String?
	}

	/// Accepts inputs like:
	/// - "https://catalogs.buffalo.edu" (base)
	/// - "https://catalogs.buffalo.edu/index.php?catoid=17" (entry-point)
	/// and returns (baseURL, catoidHint).
	private static func normalizeCatalogEntryPoint(_ baseURL: String) -> (normalizedBaseURL: String, catoidHint: String?) {
		func trimTrailingSlash(_ s: String) -> String {
			s.hasSuffix("/") ? String(s.dropLast()) : s
		}

		guard let comps = URLComponents(string: baseURL) else {
			return (trimTrailingSlash(baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), nil)
		}

		let catoidHint = comps.queryItems?.first(where: { $0.name.lowercased() == "catoid" })?.value

		// Normalize to scheme://host[:port]
		let scheme = comps.scheme ?? "https"
		let host = comps.host ?? baseURL
		let portPart = comps.port.map { ":\($0)" } ?? ""

		let normalized = trimTrailingSlash("\(scheme)://\(host)\(portPart)")
		return (normalized, catoidHint)
	}

	/// Public wrapper for callers outside ModernCampusEngine.
	/// - Important: Prefer this whenever you accept a manifest/catalog URL from user data.
	static func normalizeCatalogEntryPointForCaller(_ baseURL: String) -> (normalizedBaseURL: String, catoidHint: String?) {
		normalizeCatalogEntryPoint(baseURL)
	}

	/// Replaces or appends `catoid` on Acalog URLs so links match the catalog used during scrape (avoids stale catoid in stored `programURL`).
	static func acalogURLForcingCatoid(_ urlString: String, catoid: String) -> String {
		let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return trimmed }
		let cat = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cat.isEmpty else { return trimmed }
		guard var comps = URLComponents(string: trimmed) else { return trimmed }
		var items = comps.queryItems ?? []
		items.removeAll { $0.name.lowercased() == "catoid" }
		items.append(URLQueryItem(name: "catoid", value: cat))
		comps.queryItems = items
		return comps.string ?? trimmed
	}

	// MARK: - Index Discovery Helpers
	
	/// Scans the index page and returns all content.php navoid links
	private static func discoverIndexNavoids(baseURL: String, catoid: String) async throws -> [String: String] {
		let indexURL = "\(baseURL)/index.php?catoid=\(catoid)"
		let html = try await fetchHTML(indexURL)
		let doc = try SwiftSoup.parse(html)
		
		var navoids: [String: String] = [:]
		let links = try doc.select("a[href*='content.php'],a[href*='CONTENT.PHP']")
		for link in links {
			let hrefRaw = (try link.attr("href"))
				.replacingOccurrences(of: "&amp;", with: "&")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			let text = (try link.text()).trimmingCharacters(in: .whitespacesAndNewlines)
			guard !hrefRaw.isEmpty else { continue }

			// Make relative hrefs parseable.
			let parseableHref: String = {
				if hrefRaw.starts(with: "http://") || hrefRaw.starts(with: "https://") {
					return hrefRaw
				}
				let cleaned = hrefRaw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
				return "https://x/\(cleaned)"
			}()

			guard let comps = URLComponents(string: parseableHref) else { continue }
			let navoid = comps.queryItems?.first(where: { $0.name.lowercased() == "navoid" })?.value ?? ""
			guard !navoid.isEmpty else { continue }
			// Keep the first seen label unless we find a longer/more descriptive one.
			if let existing = navoids[navoid] {
				if text.count > existing.count {
					navoids[navoid] = text
				}
			} else {
				navoids[navoid] = text
			}
		}
		return navoids
	}
	
	/// Discovers the navoid for the "Departments & Programs" or similar page
	private static func discoverDepartmentsNavoid(baseURL: String, catoid: String) async throws -> String? {
		let pairs = try await discoverIndexNavoids(baseURL: baseURL, catoid: catoid)
		
		for (navoid, label) in pairs {
			let lower = label.lowercased()
			if lower.contains("department") && (lower.contains("program") || lower.contains("programmes")) {
				return navoid
			}
		}
		
		// Fallback: just "departments"
		for (navoid, label) in pairs {
			if label.lowercased().contains("departments") {
				return navoid
			}
		}
		
		return nil
	}

	// MARK: - Colleges / Schools (names-only)

	/// Returns the names of Colleges and/or Schools for the catalog.
	///
	/// Notes:
	/// - This is intentionally NOT the same as academic departments.
	/// - We only return the headings/names; we do not require department links.
	static func fetchCollegesAndSchools(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
		let logger = DebugLogger.shared

		// 1) Scan the index for content.php links using the shared helper (more robust parsing/decoding).
		let indexURL = "\(baseURL)/index.php?catoid=\(catoid)"
		logger.log("🔎 Colleges/Schools: loading index \(indexURL)")
		let pairs = try await discoverIndexNavoids(baseURL: baseURL, catoid: catoid)
		if pairs.isEmpty {
			logger.log("⚠️ Colleges/Schools: index scan returned 0 content.php links")
		}

		// 2) Find the nav link for something like "Colleges and Schools" / "Colleges" / "Schools" / "Academic Units".
		let keywords = [
			"colleges and schools",
			"colleges & schools",
			"schools / colleges",
			"schools/colleges",
			"schools and colleges",
			"academic units and programs",
			"academic units",
			"academic unit",
			"schools",
			"colleges"
		]

		struct Candidate {
			let navoid: String
			let text: String
			let score: Int
		}

		var candidates: [Candidate] = []
		for (navoid, label) in pairs {
			let lower = label.lowercased()
			guard keywords.contains(where: { lower.contains($0) }) else { continue }

			var score = 0
			if lower.contains("colleges and schools") || lower.contains("colleges & schools") { score += 10 }
			if lower.contains("schools / colleges") || lower.contains("schools/colleges") { score += 9 }
			if lower.contains("schools and colleges") { score += 9 }
			if lower.contains("academic units and programs") { score += 7 }
			if lower.contains("academic units") { score += 4 }
			if lower.contains("colleges") { score += 3 }
			if lower.contains("schools") { score += 3 }

			candidates.append(Candidate(navoid: navoid, text: label, score: score))
		}

		let sortedCandidates = candidates.sorted {
			if $0.score != $1.score { return $0.score > $1.score }
			return $0.text.count > $1.text.count
		}
		let targetNavoid = sortedCandidates.first?.navoid

		guard let navoid = targetNavoid else {
			logger.log("⚠️ Could not find a Colleges/Schools nav link on index page")
			recordDiscoveryTelemetry("colleges.nav_missing")
			logger.log("🔎 Hint: expected to find a content.php link containing 'Colleges'/'Schools'/'Academic Units' with catoid=\(catoid)")
			let top = pairs.values
				.map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
				.filter { !$0.isEmpty }
				.sorted()
			logger.log("🔎 Index link labels (sample): \(top.prefix(25).joined(separator: " | "))")

			// Fallback: derive college/school-like group headings from the Departments & Programs page.
			if let departmentsNavoid = try? await discoverDepartmentsNavoid(baseURL: baseURL, catoid: catoid) {
				let contentURLString = "\(baseURL)/content.php?catoid=\(catoid)&navoid=\(departmentsNavoid)"
				logger.log("🔎 Colleges/Schools fallback: deriving from Departments page \(contentURLString)")
				recordDiscoveryTelemetry("colleges.departments_fallback_attempt")
				if let cHtml = try? await fetchHTML(contentURLString) {
					let derived = deriveCollegesAndSchoolsFromDepartmentsPage(cHtml)
					if !derived.isEmpty {
						logger.log("✅ Colleges/Schools derived groups: \(derived.prefix(10).joined(separator: " | "))")
						recordDiscoveryTelemetry("colleges.departments_fallback_success")
						let items = derived.map { ScrapedDepartment(name: $0, code: nil) }
						return Array(Set(items)).sorted { $0.name < $1.name }
					}
				}
			}

			return []
		}

		// 3. Fetch the content page and parse headings.
		let contentURLString = "\(baseURL)/content.php?catoid=\(catoid)&navoid=\(navoid)"
		logger.log("🔎 Colleges/Schools: loading content \(contentURLString)")
		let cHtml = try await fetchHTML(contentURLString)

		let names = parseCollegesAndSchoolsHTML(cHtml)
		if names.isEmpty {
			logger.log("⚠️ Colleges/Schools page returned 0 names: \(contentURLString)")
			recordDiscoveryTelemetry("colleges.parse_empty")
			logger.log("🔎 Colleges/Schools HTML snippet: \(cHtml.prefix(400))")
		} else {
			logger.log("✅ Colleges/Schools parsed names: \(names.prefix(10).joined(separator: " | "))")
			recordDiscoveryTelemetry("colleges.parse_success")
		}

		let items = names.map { ScrapedDepartment(name: $0, code: nil) }
		return Array(Set(items)).sorted { $0.name < $1.name }
	}

	/// Fallback parser used when the index doesn't expose an explicit Colleges/Schools nav page.
	///
	/// Strategy:
	/// - For UB specifically, the "Departments & Programs" page (navoid discovered dynamically)
	///   is a grouped index where the FIRST section contains the true colleges/schools,
	///   followed by subject/department links.
	/// - Extract the high-level org units by looking for standalone anchors that match
	///   known college/school naming patterns (e.g., "College of ...", "School of ...",
	///   "Graduate School of ...", etc.) and ignore the rest.
	/// - Return unique group names in display order (best-effort).
	private static func deriveCollegesAndSchoolsFromDepartmentsPage(_ html: String) -> [String] {
		// UB's Departments & Programs page contains the college/school list as plain links,
		// and then a much longer subject list. We want ONLY the top-level org units.
		guard let doc = try? SwiftSoup.parse(html) else { return [] }
		guard let anchors = try? doc.select("a[href]") else { return [] }

		var groupsInOrder: [String] = []
		var seen: Set<String> = []

		for a in anchors.array() {
			let text = decodeHTMLEntities(
				(try? a.text()) ?? ""
			)
				.replacingOccurrences(of: "\u{00A0}", with: " ")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if text.isEmpty { continue }

			let lowerText = text.lowercased()
			if lowerText.contains("back to top") { continue }
			if lowerText == "departments & programs" || lowerText == "departments and programs" { continue }
			if lowerText == "courses" { continue }
			if lowerText.hasPrefix("print") { continue }
			if lowerText.hasPrefix("help") { continue }

			// UB college/school anchors are standalone names; subject lines are also anchors
			// but typically don't start with "College of" / "School of".
			let cleaned = text
				.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard cleaned.count >= 6 else { continue }

			let lowerClean = cleaned.lowercased()
			let isOrgUnitName =
				lowerClean.hasPrefix("college of ") ||
				lowerClean.hasPrefix("school of ") ||
				lowerClean.hasPrefix("graduate school") ||
				lowerClean.hasPrefix("jacobs school") ||
				lowerClean.contains("school of medicine") ||
				lowerClean.contains("school of management")
			guard isOrgUnitName else { continue }

			if !seen.contains(cleaned) {
				seen.insert(cleaned)
				groupsInOrder.append(cleaned)
			}
		}

		// UB expected: ~11 items. If we got far more than that, we likely started
		// accidentally including subjects; in that case, clamp to the first 20 to reduce UI harm.
		if groupsInOrder.count > 20 {
			return Array(groupsInOrder.prefix(20))
		}

		return groupsInOrder
	}

	// MARK: - Index Page Navoid Discovery

	/// Ranked navoids for course-description index pages (best first). Used to try the next candidate when the top pick parses zero stubs.
	private static func rankedCourseDescriptionNavoids(baseURL: String, catoid: String) async throws -> [String] {
		let logger = DebugLogger.shared
		let navoids = try await discoverIndexNavoids(baseURL: baseURL, catoid: catoid)
		if navoids.isEmpty { return [] }

		struct Candidate {
			let navoid: String
			let label: String
			let score: Int
		}

		var candidates: [Candidate] = []
		for (navoid, label) in navoids {
			let lower = label.lowercased()
			var score = 0
			if lower.contains("course descriptions") { score += 10 }
			if lower.contains("course description") { score += 9 }
			if lower == "courses" { score += 6 }
			if lower.contains("courses") { score += 4 }
			if lower.contains("catalog") { score += 1 }

			if score > 0 {
				candidates.append(Candidate(navoid: navoid, label: label, score: score))
			}
		}

		let sorted = candidates.sorted {
			if $0.score != $1.score { return $0.score > $1.score }
			return $0.label.count > $1.label.count
		}

		var ordered: [String] = []
		var seen: Set<String> = []
		for c in sorted {
			if seen.insert(c.navoid).inserted {
				ordered.append(c.navoid)
				logger.log("📚 Course Descriptions candidate: navoid=\(c.navoid), label=\(c.label), score=\(c.score)")
			}
		}

		if !ordered.isEmpty {
			recordDiscoveryTelemetry("course_navoid.keyword")
		}

		if ordered.isEmpty {
			logger.log("📚 No keyword match for Course Descriptions navoid; trying LLM classifier fallback")
			recordDiscoveryTelemetry("course_navoid.llm_attempt")
			if let llmNavoid = await classifySidebarForCoursesWithLLM(navoids: navoids, logger: logger) {
				logger.log("📚 LLM sidebar classifier → navoid=\(llmNavoid)")
				recordDiscoveryTelemetry("course_navoid.llm_success")
				return [llmNavoid]
			}
			recordDiscoveryTelemetry("course_navoid.llm_failed")
			return []
		}

		return ordered
	}

	/// Discover the Course Descriptions navoid by scanning the index page for relevant nav labels.
	private static func discoverCourseDescriptionsNavoid(baseURL: String, catoid: String) async throws -> String? {
		let ranked = try await rankedCourseDescriptionNavoids(baseURL: baseURL, catoid: catoid)
		return ranked.first
	}

	/// Uses the local LLM to classify which sidebar link most likely points to the
	/// course descriptions / course catalog page when keyword scoring returns no candidate.
	///
	/// Returns the navoid string if the model confidently identifies a match, nil otherwise.
	private static func classifySidebarForCoursesWithLLM(navoids: [String: String], logger: DebugLogger) async -> String? {
		guard AppleSiliconPlatform.isMLXCompatible else {
			logger.log("⚠️ LLM sidebar classifier skipped — \(AppleSiliconPlatform.mlxRequirementMessage)")
			return nil
		}

		// Ensure the JSON worker is installed, downloading if not yet present.
		let spec = ModelSpec.jsonWorker
		guard let modelPath = try? await ModelManager.shared.ensureModelInstalled(spec, progress: { _ in }) else { return nil }

		// Build a compact navoid→label listing for the prompt.
		let listing = navoids.map { "- navoid \($0.key): \"\($0.value)\"" }.sorted().joined(separator: "\n")
		let prompt = """
/no_think
You are helping identify navigation pages in a university course catalog website.
Below is a list of sidebar navigation links (navoid ID and label).

\(listing)

Which navoid ID most likely leads to the page listing all available courses (course descriptions / course catalog)?
Return ONLY JSON in this exact format with no other text: {"navoid": "123"}
If none seem relevant, return: {"navoid": null}
"""

		do {
			let raw = try await withThrowingTaskGroup(of: String.self) { group in
				group.addTask {
					try await LocalLLMRunner.shared.generateJSON(prompt: prompt, modelPath: modelPath, maxTokens: 64)
				}
				group.addTask {
					try await Task.sleep(nanoseconds: 15_000_000_000)
					throw LocalLLMRunnerError.generationFailed
				}
				guard let result = try await group.next() else {
					throw LocalLLMRunnerError.generationFailed
				}
				group.cancelAll()
				return result
			}

			// Parse {"navoid": "123"} or {"navoid": null}
			if let data = raw.data(using: .utf8),
			   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				if let navoid = json["navoid"] as? String, !navoid.isEmpty, navoids[navoid] != nil {
					return navoid
				}
			}
		} catch {
			logger.log("⚠️ LLM sidebar classifier failed: \(error)")
		}

		return nil
	}

	// MARK: - Courses (Robots-compliant)

	/// Robots-compliant full course scraping for ModernCampus/Acalog catalogs.
	///
	/// Strategy:
	/// 1) Find the "Course Descriptions" (or "Courses") sidebar `navoid` from index.php.
	/// 2) Load content.php?catoid=...&navoid=...
	/// 3) Detect pagination (filter[cpage]) and gather preview links across all pages
	/// 4) Crawl each preview page for details (bounded concurrency)
	static func fetchAllCourses(
		baseURL: String,
		catoid: String,
		politeness: CatalogFetchPoliteness = .interactiveBackground
	) async throws -> [CatalogCourse] {
		let key = courseCacheKey(baseURL: baseURL, catoid: catoid)
		if let cached = cachedCourses(forKey: key) {
			recordDiscoveryTelemetry("courses.cache_hit")
			return cached
		}

		if let inFlight = courseCacheLock.withLock({ inFlightCourseFetchTasks[key] }) {
			recordDiscoveryTelemetry("courses.inflight_join")
			return try await inFlight.value
		}

		let task = Task<[CatalogCourse], Error> {
			try await fetchAllCoursesUncached(baseURL: baseURL, catoid: catoid, politeness: politeness)
		}

		courseCacheLock.withLock {
			inFlightCourseFetchTasks[key] = task
		}

		do {
			let courses = try await task.value
			courseCacheLock.withLock {
				inFlightCourseFetchTasks.removeValue(forKey: key)
				courseCache[key] = CourseCacheEntry(courses: courses, cachedAt: Date())
			}
			recordDiscoveryTelemetry("courses.cache_store")
			return courses
		} catch {
			_ = courseCacheLock.withLock {
				inFlightCourseFetchTasks.removeValue(forKey: key)
			}
			throw error
		}
	}

	/// Incremental course delivery — yields preview batches as they are fetched (no full-catalog buffer).
	static func streamCourseBatches(
		baseURL: String,
		catoid: String,
		batchSize: Int = 250,
		politeness: CatalogFetchPoliteness = .interactiveBackground
	) -> AsyncThrowingStream<[CatalogCourse], Error> {
		AsyncThrowingStream { continuation in
			Task {
				do {
					try await streamCoursePreviewBatches(
						baseURL: baseURL,
						catoid: catoid,
						batchSize: batchSize,
						politeness: politeness
					) { batch in
						continuation.yield(batch)
					}
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}
		}
	}

	private static func discoverCourseLinkStubs(
		baseURL: String,
		catoid: String,
		politeness: CatalogFetchPoliteness
	) async throws -> [CourseLinkStub] {
		let logger = DebugLogger.shared
		let navoidCandidates = try await rankedCourseDescriptionNavoids(baseURL: baseURL, catoid: catoid)
		if navoidCandidates.isEmpty {
			logger.log("📚 Courses(content): no Course Descriptions navoid discovered")
			return []
		}

		var chosenNavoid: String?
		var firstHTML = ""
		var maxPage = 1
		let declaredCrawlDelay: TimeInterval
		if let base = URL(string: baseURL) {
			declaredCrawlDelay = await CatalogOriginRobotsThrottle.declaredCrawlDelaySeconds(for: base)
		} else {
			declaredCrawlDelay = 0
		}

		for (idx, navoid) in navoidCandidates.enumerated() {
			guard let pageURL = makeCourseDescriptionsContentURLString(baseURL: baseURL, catoid: catoid, navoid: navoid, cpage: nil) else {
				continue
			}
			logger.log("📚 Courses(content): loading course descriptions page: \(pageURL)")
			let html = try await fetchHTML(pageURL, politeness: politeness)
			let pages = discoverMaxCourseDescriptionsPage(from: html)
			let stubs = parseCourseLinkStubsFromCourseDescriptionsHTML(html)
			logger.log("📚 Courses(content): navoid=\(navoid) page1 stubs=\(stubs.count) pages=\(pages)")

			if stubs.isEmpty && pages <= 1 {
				if idx + 1 < navoidCandidates.count {
					logger.log("📚 Courses(content): trying next course-index navoid candidate…")
				}
				continue
			}

			chosenNavoid = navoid
			firstHTML = html
			maxPage = pages
			break
		}

		guard let navoid = chosenNavoid, !firstHTML.isEmpty else {
			logger.log("📚 Courses(content): parsed 0 stubs across \(navoidCandidates.count) navoid candidate(s)")
			return []
		}

		if maxPage > 1 {
			logger.log("📚 Courses(content): detected pagination, pages=\(maxPage)")
		}

		var stubsByCode: [String: CourseLinkStub] = [:]
		func mergeStubs(_ stubs: [CourseLinkStub]) {
			for s in stubs {
				if let existing = stubsByCode[s.courseCode] {
					if s.title.count > existing.title.count {
						stubsByCode[s.courseCode] = s
					}
				} else {
					stubsByCode[s.courseCode] = s
				}
			}
		}

		mergeStubs(parseCourseLinkStubsFromCourseDescriptionsHTML(firstHTML))
		if maxPage > 1 {
			let pages = Array(2...maxPage)
			let pageFetchConcurrency = effectiveConcurrency(
				declaredCrawlDelay: declaredCrawlDelay,
				politeness: politeness,
				max: 4
			)
			let pageFetchSemaphore = AsyncSemaphore(value: pageFetchConcurrency)
			var stubsByPage: [Int: [CourseLinkStub]] = [:]

			await withTaskGroup(of: (Int, [CourseLinkStub]).self) { group in
				for page in pages {
					guard let pageURLString = makeCourseDescriptionsContentURLString(baseURL: baseURL, catoid: catoid, navoid: navoid, cpage: page) else {
						continue
					}
					group.addTask {
						await pageFetchSemaphore.acquire()
						defer { pageFetchSemaphore.release() }
						do {
							let pageHTML = try await fetchHTML(pageURLString, politeness: politeness)
							let pageStubs = parseCourseLinkStubsFromCourseDescriptionsHTML(pageHTML)
							return (page, pageStubs)
						} catch {
							return (page, [])
						}
					}
				}
				for await (page, pageStubs) in group {
					stubsByPage[page] = pageStubs
				}
			}
			for page in pages {
				mergeStubs(stubsByPage[page] ?? [])
			}
		}

		let stubs = Array(stubsByCode.values).sorted { $0.courseCode < $1.courseCode }
		logger.log("📚 Courses(content): total unique stubs=\(stubs.count)")
		return stubs
	}

	private static func streamCoursePreviewBatches(
		baseURL: String,
		catoid: String,
		batchSize: Int,
		politeness: CatalogFetchPoliteness,
		yieldBatch: ([CatalogCourse]) -> Void
	) async throws {
		let stubs = try await discoverCourseLinkStubs(baseURL: baseURL, catoid: catoid, politeness: politeness)
		guard !stubs.isEmpty else { return }

		let declaredCrawlDelay: TimeInterval
		if let base = URL(string: baseURL) {
			declaredCrawlDelay = await CatalogOriginRobotsThrottle.declaredCrawlDelaySeconds(for: base)
		} else {
			declaredCrawlDelay = 0
		}

		let indices = Array(stubs.indices)
		let maxConcurrency = effectiveConcurrency(
			declaredCrawlDelay: declaredCrawlDelay,
			politeness: politeness,
			max: min(16, max(1, tunedSession.configuration.httpMaximumConnectionsPerHost))
		)

		var pendingBatch: [CatalogCourse] = []
		pendingBatch.reserveCapacity(batchSize)
		let size = max(1, batchSize)

		await withTaskGroup(of: CatalogCourse.self) { group in
			var nextIndexIterator = indices.makeIterator()

			func enqueueNext() {
				guard let i = nextIndexIterator.next() else { return }
				let stub = stubs[i]
				group.addTask {
					if Task.isCancelled { return stub.asCatalogCourse() }
					guard let detailURL = makeAbsoluteURLString(baseURL: baseURL, href: stub.href) else {
						return stub.asCatalogCourse()
					}
					do {
						let detailHTML = try await fetchHTML(detailURL, politeness: politeness)
						if let detailed = parseCourseDetailFromPreviewHTML(detailHTML, fallback: stub) {
							return detailed
						}
						return stub.asCatalogCourse()
					} catch {
						return stub.asCatalogCourse()
					}
				}
			}

			for _ in 0..<min(maxConcurrency, indices.count) {
				enqueueNext()
			}

			while let course = await group.next() {
				pendingBatch.append(course)
				if pendingBatch.count >= size {
					yieldBatch(pendingBatch)
					pendingBatch.removeAll(keepingCapacity: true)
				}
				enqueueNext()
			}
		}

		if !pendingBatch.isEmpty {
			yieldBatch(pendingBatch)
		}
	}

	private static func fetchAllCoursesUncached(
		baseURL: String,
		catoid: String,
		politeness: CatalogFetchPoliteness = .interactiveBackground
	) async throws -> [CatalogCourse] {
		var collected: [CatalogCourse] = []
		try await streamCoursePreviewBatches(
			baseURL: baseURL,
			catoid: catoid,
			batchSize: 250,
			politeness: politeness
		) { batch in
			collected.append(contentsOf: batch)
		}
		let deduped = dedupeCatalogCourses(collected)
		DebugLogger.shared.log("📚 Courses(content): parsed \(deduped.count) courses")
		return deduped
	}

	private static func makeCourseDescriptionsContentURLString(
		baseURL: String,
		catoid: String,
		navoid: String,
		cpage: Int?
	) -> String? {
		guard var components = URLComponents(string: "\(baseURL)/content.php") else { return nil }
		var items: [URLQueryItem] = [
			URLQueryItem(name: "catoid", value: catoid),
			URLQueryItem(name: "navoid", value: navoid)
		]
		if let cpage, cpage > 1 {
			// ModernCampus pagination is typically encoded as filter%5Bcpage%5D=N.
			items.append(URLQueryItem(name: "filter[cpage]", value: String(cpage)))
		}
		components.queryItems = items
		return components.url?.absoluteString
	}

	/// Try to detect the number of pages for the course descriptions index.
	///
	/// Many catalogs paginate with query `filter[cpage]=N` (encoded as `filter%5Bcpage%5D=N`).
	/// We intentionally keep this heuristic conservative to avoid accidentally iterating huge page ranges.
	private static func discoverMaxCourseDescriptionsPage(from html: String) -> Int {
		guard let doc = try? SwiftSoup.parse(html) else { return 1 }

		// Prefer explicit pagination controls.
		let paginationContainer = (try? doc.select("div.pagination, ul.pagination, nav.pagination, .pagination").first())
		if let paginationContainer {
			let anchors = (try? paginationContainer.select("a[href]").array()) ?? []
			var best = 1
			for a in anchors {
				let t = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
				if let v = Int(t), v > best { best = v }
			}
			if best > 1 { return best }
		}

		// Fallback: scan hrefs for filter[cpage]=N.
		let anchors = (try? doc.select("a[href*='filter%5Bcpage%5D='], a[href*='filter[cpage]=']").array()) ?? []
		var maxFound = 1
		let re = cachedRegex("filter(?:%5B|\\[)cpage(?:%5D|\\])=(\\d+)", options: [.caseInsensitive])
		for a in anchors {
			let href = ((try? a.attr("href")) ?? "").replacingOccurrences(of: "&amp;", with: "&")
			guard let re else { continue }
			let nsRange = NSRange(href.startIndex..<href.endIndex, in: href)
			guard let m = re.firstMatch(in: href, range: nsRange), m.numberOfRanges >= 2,
				  let r1 = Range(m.range(at: 1), in: href),
				  let v = Int(href[r1]) else { continue }
			if v > maxFound { maxFound = v }
		}

		// Guardrail: if a site uses a different meaning for cpage, don't run wild.
		if maxFound > 200 { return 1 }
		return maxFound
	}

	private nonisolated struct CourseLinkStub: Hashable, Sendable {
		let courseCode: String
		let title: String
		let department: String?
		let href: String

		nonisolated func asCatalogCourse() -> CatalogCourse {
			CatalogCourse(
				courseCode: courseCode,
				title: title,
				description: nil,
				credits: 0,
				department: department,
				prerequisites: nil,
				prerequisiteText: nil,
				corequisites: nil,
				typicallyOffered: nil
			)
		}
	}

	nonisolated private static func makeAbsoluteURLString(baseURL: String, href: String) -> String? {
		let cleanedHref = href
			.replacingOccurrences(of: "&amp;", with: "&")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleanedHref.isEmpty else { return nil }
		if cleanedHref.lowercased().hasPrefix("http://") || cleanedHref.lowercased().hasPrefix("https://") {
			return cleanedHref
		}
		guard let base = URL(string: baseURL) else { return nil }
		// IMPORTANT: Do NOT use `appendingPathComponent` here because many ModernCampus hrefs include
		// query strings (e.g., preview_course_nopop.php?catoid=...&coid=...). Treat them as relative URLs.
		return URL(string: cleanedHref, relativeTo: base)?.absoluteURL.absoluteString
	}

	nonisolated private static func isModernCampusResourceNotFoundPage(_ html: String) -> Bool {
		let lower = html
			.replacingOccurrences(of: "\u{00A0}", with: " ")
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.lowercased()
		return lower.contains("resource not found") &&
			(lower.contains("unable to locate the resource") || lower.contains("we were unable to locate"))
	}

	private static func parseCourseLinkStubsFromCourseDescriptionsHTML(_ html: String) -> [CourseLinkStub] {
		guard let doc = try? SwiftSoup.parse(html) else { return [] }
		let contentCandidate = (try? doc.select("#acalog-content").first())
		// Some catalogs (including UB) use id="acalog-content" on the page title (e.g., <h1>Courses</h1>),
		// not on a wrapping container. In that case, parsing within that element yields 0 anchors.
		let content: Element
		if let el = contentCandidate {
			let tag = el.tagName().lowercased()
			if tag == "div" || tag == "section" || tag == "main" {
				content = el
			} else {
				content = doc
			}
		} else {
			content = doc
		}
		// Some catalogs use direct href=preview_course(_nopop).php links.
		// Others render href="#" and rely on onclick handlers like hideCatalogData()/showCourse().
		// We support both so we can crawl preview pages without executing JS.
		let anchors = (try? content.select("a[href*=preview_course],a[href*=preview_course_nopop],a[onclick*=hideCatalogData],a[onclick*=showCourse]").array()) ?? []

		var out: [CourseLinkStub] = []
		out.reserveCapacity(anchors.count)

		func hrefFromOnclick(_ onclick: String) -> String? {
			let cleaned = onclick.replacingOccurrences(of: "\n", with: " ")
			// hideCatalogData('19', '3', '139936', ...)
			if let re = cachedRegex("(?i)hideCatalogData\\(\\s*'?(\\d+)'?\\s*,\\s*'?(\\d+)'?\\s*,\\s*'?(\\d+)'?"),
			   let m = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)),
			   m.numberOfRanges >= 4,
			   let catoidRange = Range(m.range(at: 1), in: cleaned),
			   let coidRange = Range(m.range(at: 3), in: cleaned) {
				let catoid = String(cleaned[catoidRange])
				let coid = String(cleaned[coidRange])
				return "preview_course_nopop.php?catoid=\(catoid)&coid=\(coid)"
			}
			// showCourse('17', '106865', ...)
			if let re = cachedRegex("(?i)showCourse\\(\\s*'?(\\d+)'?\\s*,\\s*'?(\\d+)'?"),
			   let m = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)),
			   m.numberOfRanges >= 3,
			   let catoidRange = Range(m.range(at: 1), in: cleaned),
			   let coidRange = Range(m.range(at: 2), in: cleaned) {
				let catoid = String(cleaned[catoidRange])
				let coid = String(cleaned[coidRange])
				return "preview_course_nopop.php?catoid=\(catoid)&coid=\(coid)"
			}
			return nil
		}

		for a in anchors {
			let rawHrefAttr = ((try? a.attr("href")) ?? "")
				.replacingOccurrences(of: "&amp;", with: "&")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			let onclick = ((try? a.attr("onclick")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

			let hrefRaw: String = {
				// Prefer a real preview_course(_nopop) href when present.
				if !rawHrefAttr.isEmpty,
				   rawHrefAttr != "#",
				   rawHrefAttr.contains("preview_course") || rawHrefAttr.contains("preview_course_nopop") {
					return rawHrefAttr
				}
				// Fall back to onclick-derived preview_course_nopop.php?catoid=...&coid=...
				return hrefFromOnclick(onclick) ?? ""
			}()
			guard !hrefRaw.isEmpty else { continue }

			let rawText = (try? a.text()) ?? ""
			let decoded = decodeHTMLEntities(rawText)
				.replacingOccurrences(of: "\u{00A0}", with: " ")
				.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !decoded.isEmpty else { continue }

			// Expected: "DEPT 101SEM - Title".
			let parts = decoded.components(separatedBy: "-")
			guard let left = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !left.isEmpty else { continue }
			let title = parts.dropFirst().joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
			guard !title.isEmpty else { continue }

			let leftTokens = left.split(separator: " ")
			guard leftTokens.count >= 2 else { continue }
			let dept = String(leftTokens[0]).uppercased()
			let numberWithSuffix = String(leftTokens[1]).uppercased()
			guard !numberWithSuffix.isEmpty else { continue }

			let courseCode = "\(dept) \(numberWithSuffix)"
			out.append(CourseLinkStub(courseCode: courseCode, title: title, department: dept, href: hrefRaw))
		}

		var bestByCode: [String: CourseLinkStub] = [:]
		for c in out {
			let key = c.courseCode
			if let existing = bestByCode[key] {
				if c.title.count > existing.title.count {
					bestByCode[key] = c
				}
			} else {
				bestByCode[key] = c
			}
		}
		return Array(bestByCode.values).sorted { $0.courseCode < $1.courseCode }
	}

	nonisolated private static func parseCreditsFromText(_ text: String) -> Int {
		let lowered = text.lowercased()
		let patterns = [
			// Credits: 3 / Credits - 3 / Credits: 3-4
			"credits?\\s*[:\\-]?\\s*(\\d{1,3})(?:\\s*[\\-\\u2013]\\s*\\d{1,3})?",
			// Credit Hours: 3 / Credit hours - 1-4
			"credit\\s*hours?\\s*[:\\-]?\\s*(\\d{1,3})(?:\\s*[\\-\\u2013]\\s*\\d{1,3})?",
			// 3 credits / 3-4 credits
			"(\\d{1,3})\\s*(?:[\\-\\u2013]\\s*\\d{1,3}\\s*)?credits?",
			// 3 cr / 3 credit hours
			"(\\d{1,3})\\s*(?:cr\\.?|credit\\s*hours?)\\b"
		]
		for p in patterns {
			guard let re = cachedRegex(p) else { continue }
			let nsRange = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
			guard let m = re.firstMatch(in: lowered, range: nsRange), m.numberOfRanges >= 2,
				  let r1 = Range(m.range(at: 1), in: lowered),
				  let v = Int(lowered[r1]), v > 0 else { continue }
			return v
		}
		return 0
	}

	nonisolated private static func parsePrerequisiteTextFromBody(_ text: String) -> String? {
		let cleaned = text
			.replacingOccurrences(of: "\u{00A0}", with: " ")
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty else { return nil }

		let patterns = [
			// Standard label variants used across Modern Campus schools.
			"(?i)prerequisites?\\s*:\\s*([^\\.]+)",
			"(?i)prerequisites?\\s*-\\s*([^\\.]+)",
			// Abbreviated labels: "Prereq:", "Prereqs:"
			"(?i)prereqs?\\s*:\\s*([^\\.]+)",
			"(?i)prereqs?\\s*-\\s*([^\\.]+)",
			// Ultra-short form: "Pre:"
			"(?i)pre\\s*:\\s*([^\\.]+)",
			// Hyphenated form: "Pre-requisite:"
			"(?i)pre-requisites?\\s*:\\s*([^\\.]+)",
			// Sentence form: "Completion of X required."
			"(?i)completion of\\s+([^\\.]+?)\\s+(?:is\\s+)?required",
			// Sentence form: "Requires X."
			"(?i)requires?\\s*:\\s*([^\\.]+)"
		]
		for p in patterns {
			guard let re = cachedRegex(p) else { continue }
			let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
			guard let m = re.firstMatch(in: cleaned, range: nsRange), m.numberOfRanges >= 2,
				  let r1 = Range(m.range(at: 1), in: cleaned) else { continue }
			let value = cleaned[r1].trimmingCharacters(in: .whitespacesAndNewlines)
			if !value.isEmpty { return value }
		}
		return nil
	}

	nonisolated private static func parseCourseDetailFromPreviewHTML(_ html: String, fallback: CourseLinkStub) -> CatalogCourse? {
		// Bad URL joins / stale links can produce a ModernCampus 404-like page. Don't treat that as a description.
		if isModernCampusResourceNotFoundPage(html) { return nil }

		// autoreleasepool ensures the SwiftSoup DOM tree is released immediately after parsing,
		// preventing memory from ballooning when thousands of concurrent tasks call this function.
		return autoreleasepool {
		guard let doc = try? SwiftSoup.parse(html) else { return nil }
		let content = (try? doc.select("#acalog-content").first()) ?? doc

		// Uses the statically compiled \s+ regex from normalizedCatalogText() — no per-call overhead.
		func normalized(_ value: String) -> String {
			decodeHTMLEntities(value).normalizedCatalogText()
		}

		func stripTrailingMetadata(_ text: String) -> String {
			let trimmed = normalized(text)
			guard !trimmed.isEmpty else { return "" }

			let stopTokens = [
				"prerequisite:", "prerequisites:",
				"corequisite:", "corequisites:",
				"restriction:", "restrictions:",
				"typically offered:", "typicallyoffered:",
				"grading:",
				"note:",
				"credit:", "credits:"
			]

			let lowered = trimmed.lowercased()
			var cutIndex: String.Index? = nil
			for token in stopTokens {
				if let r = lowered.range(of: token) {
					if cutIndex == nil || r.lowerBound < cutIndex! {
						cutIndex = r.lowerBound
					}
				}
			}

			if let idx = cutIndex {
				let prefix = trimmed[..<idx]
				return normalized(String(prefix))
			}
			return trimmed
		}

		func extractCourseBodyText(titleLine: String) -> String {
			// Many ModernCampus preview pages (including UB) render course details in a single container
			// around a title element with id=course_preview_title.
			if let titleEl = (try? content.select("#course_preview_title").first()) {
				let container = titleEl.parent() ?? titleEl
				let containerText = normalized((try? container.text()) ?? "")
				if !containerText.isEmpty {
					if !titleLine.isEmpty, containerText.hasPrefix(titleLine) {
						let dropped = containerText.dropFirst(titleLine.count)
						let v = normalized(String(dropped))
						if !v.isEmpty { return v }
					}
					return containerText
				}
			}

			// 1) Common ModernCampus markup
			let selectors = [
				".courseblockdesc",
				".courseblockdesc p",
				".courseblockextra",
				".courseblockextra p",
				"#course_preview .courseblockdesc",
				"#course_preview .courseblockextra",
				"#course_preview"
			]
			for sel in selectors {
				if let raw = (try? content.select(sel).first()?.text()), !raw.isEmpty {
					let v = normalized(raw)
					if !v.isEmpty { return v }
				}
			}

			// 2) Fallback: take the course block body (without title line)
			if let block = (try? content.select(".courseblock").first()) {
				let blockText = normalized((try? block.text()) ?? "")
				if !blockText.isEmpty {
					if !titleLine.isEmpty, blockText.hasPrefix(titleLine) {
						let dropped = blockText.dropFirst(titleLine.count)
						let v = normalized(String(dropped))
						if !v.isEmpty { return v }
					}
					return blockText
				}
			}

			// 3) Last resort: use all text under content (still better than empty)
			let v = normalized((try? content.text()) ?? "")
			return v
		}

		func stripLeadingModernCampusBoilerplate(_ text: String, courseCode: String) -> String {
			let t = normalized(text)
			guard !t.isEmpty else { return "" }
			let lower = t.lowercased()
			// UB preview pages can include a leading "HELP ... Print-Friendly Page (opens a new window)" banner.
			// Only apply aggressive stripping when that banner is present.
			let shouldStrip = lower.contains("print-friendly page") || lower.hasPrefix("help ")
			guard shouldStrip else { return t }

			// Prefer stripping based on the expected course code (e.g., "MTH 114LEC").
			if !courseCode.isEmpty, let codeRange = t.range(of: courseCode, options: [.caseInsensitive]) {
				var after = t[codeRange.upperBound...]
				// Drop through the first dash after the code, preserving the title and description.
				if let dash = after.range(of: "[-–—]", options: .regularExpression) {
					after = after[dash.upperBound...]
				}
				return normalized(String(after))
			}

			// Fallback: drop through the first "DEPT 123SUF -" pattern if present.
			if let re = cachedRegex("\\b[A-Z]{2,6}\\s*[0-9]{2,4}[A-Z]*\\s*[\\u2013\\u2014-]\\s*") {
				let nsRange = NSRange(t.startIndex..<t.endIndex, in: t)
				if let m = re.firstMatch(in: t, range: nsRange), m.numberOfRanges >= 1,
				   let r0 = Range(m.range(at: 0), in: t) {
					return normalized(String(t[r0.upperBound...]))
				}
			}
			return t
		}

		let rawTitleLine = (try? content.select(".courseblocktitle").first()?.text()) ??
			(try? content.select("h1,h2,h3").first()?.text()) ?? ""
		let titleLine = normalized(rawTitleLine)

		var courseCode = fallback.courseCode
		var dept = fallback.department
		var title = fallback.title
		var credits = 0

		if !titleLine.isEmpty {
			// cachedRegex: compiled once, reused on every call — not per-course.
			if let re = cachedRegex("\\b([A-Z]{2,6})\\s*([0-9]{2,4}[A-Z]*)\\s*-\\s*(.+)$") {
				let nsRange = NSRange(titleLine.startIndex..<titleLine.endIndex, in: titleLine)
				if let m = re.firstMatch(in: titleLine, range: nsRange), m.numberOfRanges >= 4,
				   let rDept = Range(m.range(at: 1), in: titleLine),
				   let rNum = Range(m.range(at: 2), in: titleLine),
				   let rTitle = Range(m.range(at: 3), in: titleLine) {
					let parsedDept = String(titleLine[rDept]).uppercased()
					let parsedNum = String(titleLine[rNum]).uppercased()
					var parsedTitle = String(titleLine[rTitle])
					// Remove parenthetical suffixes e.g. "(lec)" using cached regex.
					if let parenRe = cachedRegex("\\(.*?\\)") {
						parsedTitle = parenRe.stringByReplacingMatches(
							in: parsedTitle,
							range: NSRange(parsedTitle.startIndex..., in: parsedTitle),
							withTemplate: ""
						).trimmingCharacters(in: .whitespacesAndNewlines)
					} else {
						parsedTitle = parsedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
					}

					courseCode = "\(parsedDept) \(parsedNum)"
					dept = parsedDept
					if !parsedTitle.isEmpty { title = parsedTitle }
				}
			}
			credits = parseCreditsFromText(titleLine)
		}

		let bodyText = extractCourseBodyText(titleLine: titleLine)
		let cleanedBodyText = stripLeadingModernCampusBoilerplate(bodyText, courseCode: courseCode)

		// IMPORTANT: Some catalogs place credits in the body after a "Credits:" label.
		// Our description cleaner may strip that segment, so parse credits *before* stripping metadata.
		if credits <= 0 {
			credits = parseCreditsFromText(cleanedBodyText)
		}

		let prereqText = parsePrerequisiteTextFromBody(cleanedBodyText)
		let desc = stripTrailingMetadata(cleanedBodyText)

		if credits <= 0 {
			credits = parseCreditsFromText(desc)
		}

		return CatalogCourse(
			courseCode: courseCode,
			title: title,
			description: desc.isEmpty ? nil : desc,
			credits: credits,
			department: dept,
			prerequisites: nil,
			prerequisiteText: prereqText,
			corequisites: nil,
			typicallyOffered: nil
		)
		} // end autoreleasepool
	}

	private static func dedupeCatalogCourses(_ courses: [CatalogCourse]) -> [CatalogCourse] {
		func score(_ c: CatalogCourse) -> Int {
			var s = 0
			if c.credits > 0 { s += 3 }
			let title = c.title.trimmingCharacters(in: .whitespacesAndNewlines)
			let code = c.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
			if !title.isEmpty, title.caseInsensitiveCompare(code) != .orderedSame { s += 2 }
			if let d = c.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { s += 1 }
			return s
		}

		var bestByCode: [String: CatalogCourse] = [:]
		for c in courses {
			let key = c.courseCode
			if let existing = bestByCode[key] {
				if score(c) > score(existing) {
					bestByCode[key] = c
				}
			} else {
				bestByCode[key] = c
			}
		}
		return Array(bestByCode.values).sorted { $0.courseCode < $1.courseCode }
	}

	/// Parse course links from a Course Descriptions HTML page.
	///
	/// Handles anchors like:
	/// - preview_course.php?...
	/// - preview_course_nopop.php?...
	/// Text shapes:
	/// - "AAP 101SEM - Introduction to ..."
	/// - "CSE 115LR - ..."
	private static func parseCoursesFromCourseDescriptionsHTML(_ html: String) -> [CatalogCourse] {
		parseCourseLinkStubsFromCourseDescriptionsHTML(html)
			.map { $0.asCatalogCourse() }
	}

	private static func parseCollegesAndSchoolsHTML(_ html: String) -> [String] {
		do {
			let doc = try SwiftSoup.parse(html)
			let content = try doc.select("#acalog-content").first() ?? doc
			let headings = try content.select("h2, h3, h4")

			var results: [String] = []
			for h in headings.array() {
				let cleaned = decodeHTMLEntities(try h.text())
					.replacingOccurrences(of: "\u{00A0}", with: " ")
					.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
					.trimmingCharacters(in: .whitespacesAndNewlines)
				let lower = cleaned.lowercased()
				if cleaned.count < 4 { continue }
				if lower == "additional links" { continue }
				if lower.contains("select a catalog") { continue }
				if lower.contains("catalog search") { continue }
				if lower == "back to top" { continue }
				if lower.contains("print") && lower.contains("friendly") { continue }
				if lower.contains("college") || lower.contains("school") {
					results.append(cleaned)
				}
			}
			return Array(Set(results)).sorted()
		} catch {
			return []
		}
	}

	// MARK: - HTML Entity Decoding

	nonisolated private static func decodeHTMLEntities(_ text: String) -> String {
		var s = text
		s = s.replacingOccurrences(of: "&amp;", with: "&")
		s = s.replacingOccurrences(of: "&nbsp;", with: " ")
		s = s.replacingOccurrences(of: "&quot;", with: "\"")
		s = s.replacingOccurrences(of: "&apos;", with: "'")
		s = s.replacingOccurrences(of: "&lt;", with: "<")
		s = s.replacingOccurrences(of: "&gt;", with: ">")
		s = decodeNumericHTMLEntities(s)
		return s
	}

	static func decodeHTMLEntitiesPublic(_ text: String) -> String {
		decodeHTMLEntities(text)
	}

	nonisolated private static func decodeNumericHTMLEntities(_ text: String) -> String {
		if !text.contains("&#") { return text }

		var out = ""
		out.reserveCapacity(text.count)
		var i = text.startIndex

		while i < text.endIndex {
			// Match: &#<digits>;
			if text[i] == "&" {
				let next1 = text.index(after: i)
				if next1 < text.endIndex, text[next1] == "#" {
					var j = text.index(after: next1)
					let digitsStart = j
					while j < text.endIndex, let scalar = text[j].unicodeScalars.first, CharacterSet.decimalDigits.contains(scalar) {
						j = text.index(after: j)
					}
					let hasDigits = digitsStart != j
					if hasDigits, j < text.endIndex, text[j] == ";" {
						let numStr = String(text[digitsStart..<j])
						if let codePoint = Int(numStr), let scalar = UnicodeScalar(codePoint) {
							out.append(Character(scalar))
							i = text.index(after: j)
							continue
						}
					}
				}
			}

			out.append(text[i])
			i = text.index(after: i)
		}

		return out
	}

	// MARK: - Text Normalization (for matching)

	private static func normalizeOrgUnitKey(_ value: String) -> String {
		value
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
			.replacingOccurrences(of: "&", with: "and")
			.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func stripOrgUnitPrefixes(_ value: String) -> String {
		let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines)
		let patterns = [
			"^department of\\s+",
			"^dept\\.?\\s+of\\s+",
			"^school of\\s+",
			"^college of\\s+",
			"^the\\s+"
		]
		var result = lowered
		for p in patterns {
			result = result.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
		}
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - robust Discovery

	/// Discover a list of active (non-archived) catalogs for a ModernCampus host.
	///
	/// Parses `misc/catalog_list.php` when present (DSU, UB gateway, etc.) and returns the **latest**
	/// catalog per normalized label (Undergraduate, Graduate, Law School, …). Falls back to a single
	/// current `catoid` when no list page exists.
	static func discoverActiveCatalogs(baseURL: String) async throws -> [ModernCampusCatalogDescriptor] {
		let listCandidates = try await discoverAcalogCatalogListCandidates(baseURL: baseURL)
		let posted = ModernCampusCatalogLabels.filterPostedCatalogs(from: listCandidates)
		if !posted.isEmpty {
			let latestPerLabel = ModernCampusCatalogLabels.latestCatalogsPerNormalizedLabel(from: posted)
			return latestPerLabel.sorted {
				$0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
			}
		}

		let catoid = try await discoverCurrentCatalogID(baseURL: baseURL)
		DebugLogger.shared.log(
			"⚠️ No posted catalogs found at \(baseURL); falling back to single inferred catoid=\(catoid)",
			category: .scraper,
			level: .error
		)
		return [ModernCampusCatalogDescriptor(catoid: catoid, title: "Catalog")]
	}

	/// Raw catalog rows from `misc/catalog_list.php` (all non-archived links, preserving list order).
	private static func discoverAcalogCatalogListCandidates(baseURL: String) async throws -> [ModernCampusCatalogDescriptor] {
		let host = URL(string: baseURL)?.host?.lowercased() ?? ""
		let listURL = "\(baseURL)/misc/catalog_list.php"
		let html: String
		do {
			html = try await fetchHTML(listURL)
		} catch {
			recordDiscoveryTelemetry("discover.catalog_list.fetch_failed")
			DebugLogger.shared.log(
				"⚠️ Catalog list fetch failed (\(listURL)): \(error.localizedDescription) — falling back to single-catalog discovery",
				category: .scraper,
				level: .error
			)
			return []
		}
		guard let doc = try? SwiftSoup.parse(html) else {
			recordDiscoveryTelemetry("discover.catalog_list.parse_failed")
			return []
		}

		return parseCatalogListPage(doc: doc, host: host)
	}

	/// Parses `misc/catalog_list.php` anchors, including trailing sibling text (UB puts `[ARCHIVED CATALOG]` after the link).
	static func parseCatalogListPage(doc: Document, host: String = "") -> [ModernCampusCatalogDescriptor] {
		let anchors = (try? doc.select("a[href*='index.php?catoid=']").array()) ?? []
		var out: [ModernCampusCatalogDescriptor] = []
		var seenCatoids = Set<String>()
		out.reserveCapacity(anchors.count)

		for a in anchors {
			let rawHref = (try? a.attr("href")) ?? ""
			let href = rawHref.replacingOccurrences(of: "&amp;", with: "&")
			let lineLabel = catalogListLineLabel(for: a)
			if ModernCampusCatalogLabels.shouldExcludeCatalogListTitle(lineLabel) { continue }

			let title = ModernCampusCatalogLabels.postedDisplayTitle(from: (try? a.text()) ?? "")
			if title.isEmpty { continue }

			let comps = URLComponents(string: href.starts(with: "http") ? href : "https://x/" + href.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
			guard let catoid = comps?.queryItems?.first(where: { $0.name.lowercased() == "catoid" })?.value,
			      !catoid.isEmpty else {
				continue
			}
			// UB gateway landing page — not a degree catalog.
			if host.contains("buffalo.edu"), catoid == "3" { continue }
			guard seenCatoids.insert(catoid).inserted else { continue }

			out.append(ModernCampusCatalogDescriptor(catoid: catoid, title: title))
		}

		return out
	}

	/// Anchor text plus trailing siblings until the next `<br>` or catalog link (captures `[ARCHIVED CATALOG]` markers).
	private static func catalogListLineLabel(for anchor: Element) -> String {
		var parts: [String] = []
		if let anchorText = try? anchor.text() {
			let trimmed = anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
			if !trimmed.isEmpty { parts.append(trimmed) }
		}

		var node: Node? = anchor.nextSibling()
		while let current = node {
			if let element = current as? Element {
				let tag = element.tagName().lowercased()
				if tag == "br" || tag == "a" { break }
				if let text = try? element.text() {
					let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
					if !trimmed.isEmpty { parts.append(trimmed) }
				}
			} else if let textNode = current as? TextNode {
				let trimmed = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
				if !trimmed.isEmpty { parts.append(trimmed) }
			}
			node = current.nextSibling()
		}

		return parts.joined(separator: " ")
			.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	static func discoverCurrentCatalogID(baseURL: String) async throws -> String {
		// `"1"` is Acalog's conventional first catalog id, used only as a last-resort guess.
		// Each fallback path is recorded so a wrong-catalog selection is diagnosable.
		let html = (try? await fetchHTML(baseURL)) ?? ""
		guard !html.isEmpty else {
			recordDiscoveryTelemetry("discover.catoid.fallback.empty_html")
			return "1"
		}
		do {
			let doc = try SwiftSoup.parse(html)
			let anchors = try doc.select("a[href*='catoid=']")
			var counts: [String: Int] = [:]
			for a in anchors.array() {
				let hrefRaw = try a.attr("href").replacingOccurrences(of: "&amp;", with: "&")
				let comps = URLComponents(string: hrefRaw.starts(with: "http") ? hrefRaw : "https://x/" + hrefRaw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
				if let id = comps?.queryItems?.first(where: { $0.name.lowercased() == "catoid" })?.value, !id.isEmpty {
					counts[id, default: 0] += 1
				}
			}
			if let best = counts.sorted(by: { $0.value > $1.value }).first?.key {
				return best
			}
			recordDiscoveryTelemetry("discover.catoid.fallback.no_links")
			return "1"
		} catch {
			recordDiscoveryTelemetry("discover.catoid.fallback.parse_failed")
			return "1"
		}
	}

	static func discoverSearchLocations(baseURL: String, catoid: String) async throws -> [SearchTarget: String] {
		guard allowRobotsDisallowedEndpoints else {
			DebugLogger.shared.log("🤖 Robots: refusing to use /search_advanced.php for search location discovery")
			return [:]
		}
		let urlString = "\(baseURL)/search_advanced.php?cur_cat_oid=\(catoid)"
		let html = (try? await fetchHTML(urlString)) ?? ""
		guard !html.isEmpty else { return [:] }

		var mapping: [SearchTarget: String] = [:]
		do {
			let doc = try SwiftSoup.parse(html)
			let options = try doc.select("select[name=location] option")
			for opt in options.array() {
				let id = try opt.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
				if id.isEmpty { continue }
				let label = try opt.text().lowercased()
				if label.contains("program") || label.contains("major") || label.contains("degree") {
					mapping[.programs] = id
				} else if label.contains("course") {
					mapping[.courses] = id
				} else if label.contains("hierarchy") || label.contains("school") || label.contains("department") {
					mapping[.hierarchy] = id
				}
			}
		} catch {
			return [:]
		}

		DebugLogger.shared.log("🗺️  Discovered Search Map: \(mapping)")
		return mapping
	}

	// MARK: - Program Scraping

	static func fetchPrograms(baseURL: String, catoid: String, locationID: String) async throws -> [ScrapedProgram] {
		// Robots-compliant default: DO NOT use /search_advanced.php.
		// Instead, discover program links by crawling index-linked content.php pages
		// (typically "Majors", "Minors", "Programs", etc) and extracting preview_program anchors.
		return try await fetchProgramsFromIndexContentPages(baseURL: baseURL, catoid: catoid)
	}

	/// Robots-compliant program discovery: scan index.php for content.php nav pages and parse preview_program links.
	private static func fetchProgramsFromIndexContentPages(baseURL: String, catoid: String) async throws -> [ScrapedProgram] {
		let logger = DebugLogger.shared
		let pairs = try await discoverIndexNavoids(baseURL: baseURL, catoid: catoid)
		if pairs.isEmpty {
			logger.log("⚠️ Programs(content): index scan returned 0 content.php links")
			return []
		}

		let wantedKeywords: [String] = [
			"majors",
			"minors",
			"programs",
			"degrees",
			"certificates",
			"micro-credentials",
			"micro credentials"
		]

		struct Candidate {
			let navoid: String
			let label: String
			let score: Int
		}

		var candidates: [Candidate] = []
		for (navoid, label) in pairs {
			let lower = label.lowercased()
			guard wantedKeywords.contains(where: { lower.contains($0) }) else { continue }

			var score = 0
			if lower.contains("majors") { score += 10 }
			if lower.contains("combined") { score += 4 }
			if lower.contains("minors") { score += 8 }
			if lower.contains("certificates") { score += 6 }
			if lower.contains("micro-credential") || lower.contains("micro credential") { score += 5 }
			if lower.contains("programs") { score += 4 }
			if lower.contains("degrees") { score += 3 }

			candidates.append(Candidate(navoid: navoid, label: label, score: score))
		}

		let ordered = candidates.sorted {
			if $0.score != $1.score { return $0.score > $1.score }
			return $0.label.count > $1.label.count
		}

		if ordered.isEmpty {
			logger.log("⚠️ Programs(content): no program-like content.php pages found on index")
			return []
		}

		// Bound concurrency: keep per-host request count under control.
		// We intentionally keep this small because catalogs often sit behind shared infrastructure.
		let semaphore = AsyncSemaphore(value: 16)
		var allPrograms: Set<ScrapedProgram> = []
		var allErrors: [Error] = []
		let indices = Array(ordered.indices)
		
		await withTaskGroup(of: (Int, [ScrapedProgram], Error?).self) { group in
			for i in indices {
				let c = ordered[i]
				group.addTask {
					await semaphore.acquire()
					defer { semaphore.release() }
					let urlString = "\(baseURL)/content.php?catoid=\(catoid)&navoid=\(c.navoid)"
					let html: String
					do {
						html = try await fetchHTML(urlString)
					} catch {
						return (i, [], error)
					}
					let found = parseProgramHTML(html, baseURL: baseURL)
					return (i, found, nil)
				}
			}
			
			var resultsByIndex: [Int: [ScrapedProgram]] = [:]
			for await (i, programs, error) in group {
				if let error {
					allErrors.append(error)
					continue
				}
				resultsByIndex[i] = programs
			}
			
			// Deterministic logging + merge.
			for i in indices {
				let c = ordered[i]
				let urlString = "\(baseURL)/content.php?catoid=\(catoid)&navoid=\(c.navoid)"
				logger.log("📄 Programs(content): loaded \(c.label) -> \(urlString)")
				for p in (resultsByIndex[i] ?? []) {
					allPrograms.insert(p)
				}
			}
		}
		
		if !allErrors.isEmpty {
			logger.log("⚠️ Programs(content): \(allErrors.count) content pages failed to load")
		}
		
		return Array(allPrograms).sorted { $0.name < $1.name }
	}

	nonisolated private static func parseProgramHTML(_ html: String, baseURL: String) -> [ScrapedProgram] {
		do {
			let doc = try SwiftSoup.parse(html)
			let content = programListContentRoot(in: doc)
			var currentSectionDegree: String? = nil
			var programs: [ScrapedProgram] = []

			for el in try content.select("*").array() {
				let tag = el.tagName().lowercased()
				if tag == "p" || tag == "h2" || tag == "h3" || tag == "h4" {
					if let strong = try el.select("strong").first() {
						let heading = decodeHTMLEntities(try strong.text())
							.trimmingCharacters(in: .whitespacesAndNewlines)
						if let sectionToken = degreeTokenFromCatalogSectionHeading(heading) {
							currentSectionDegree = sectionToken
						}
					}
				}

				guard tag == "a" else { continue }
				let href = try el.attr("href").replacingOccurrences(of: "&amp;", with: "&")
				guard href.contains("preview_program.php") || href.contains("preview_program_nopop.php") else { continue }

				let name = decodeHTMLEntities(try el.text()).trimmingCharacters(in: .whitespacesAndNewlines)
				if name.isEmpty { continue }
				if name.lowercased().contains("back to") { continue }
				guard let absoluteURL = makeAbsoluteURLString(baseURL: baseURL, href: href) else { continue }

				let degreeType = inferDegreeTypeToken(fromProgramName: name, sectionDegree: currentSectionDegree)
				let type = inferProgramListType(fromProgramName: name, degreeType: degreeType)

				programs.append(
					ScrapedProgram(
						name: name,
						type: type,
						url: absoluteURL,
						degreeType: degreeType
					)
				)
			}
			return programs
		} catch {
			return []
		}
	}

	/// Acalog often uses `<h1 id="acalog-content">`; include following sibling lists by widening to the parent block.
	nonisolated private static func programListContentRoot(in doc: Document) -> Element {
		if let anchor = try? doc.select("#acalog-content").first() {
			if anchor.tagName().lowercased() == "h1", let parent = anchor.parent() {
				return parent
			}
			return anchor
		}
		return doc
	}

	nonisolated private static func degreeTokenFromCatalogSectionHeading(_ heading: String) -> String? {
		let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		if trimmed.compare("Certificate", options: .caseInsensitive) == .orderedSame {
			return "Certificate"
		}
		return DegreeTypeNormalizer.normalize(trimmed)?.storageToken
	}

	nonisolated private static func inferDegreeTypeToken(fromProgramName name: String, sectionDegree: String?) -> String? {
		if let suffix = CatalogDegreeTypeFilter.suffixToken(fromDisplayName: name),
		   let normalized = DegreeTypeNormalizer.normalize(suffix)?.storageToken {
			return normalized
		}
		return sectionDegree
	}

	nonisolated private static func inferProgramListType(fromProgramName name: String, degreeType: String?) -> String {
		let lower = name.lowercased()
		if lower.contains("minor") { return "Minor" }
		if lower.contains("certificate") || degreeType?.compare("Certificate", options: .caseInsensitive) == .orderedSame {
			return "Certificate"
		}
		if lower.contains("ph.d") || lower.contains("doctor") { return "Doctorate" }
		if lower.contains("master") || lower.contains("m.s.") || lower.contains("m.a.") || lower.contains("mba") {
			return "Master's"
		}
		if let degreeType,
		   let entry = DegreeTokenRegistry.entry(forNormalizedToken: degreeType),
		   entry.degreeLevel == DegreeConfiguration.undergraduate {
			return "Major"
		}
		if lower.contains("b.s.") || lower.contains("b.a.") || lower.contains("bachelor") { return "Major" }
		return "Program"
	}

	nonisolated private static func parseProgramCatalogRequirementSheetFromHTML(_ html: String) -> ProgramCatalogRequirementSheet {
		guard let doc = try? SwiftSoup.parse(html) else {
			return ProgramCatalogRequirementSheet()
		}
		let content = programListContentRoot(in: doc)

		var programName = ""
		if let h1 = try? content.select("h1#acalog-content, h1").first() {
			programName = decodeHTMLEntities((try? h1.text()) ?? "")
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		var totalCreditsRequired: Int? = nil
		let bodyText = (try? content.text()) ?? ""
		if let match = bodyText.firstMatch(of: /Total Credits Required for Graduation:\s*(\d+)/) {
			totalCreditsRequired = Int(match.1)
		}

		var requirementGroups: [ProgramCatalogRequirementSheet.RequirementGroup] = []
		var courseCoidMap: [String: String] = [:]

		let h3s = (try? content.select("h3").array()) ?? []
		for h3 in h3s {
			let groupName = decodeHTMLEntities((try? h3.text()) ?? "")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !groupName.isEmpty else { continue }

			var chooseCount: Int? = nil
			var courseOptions: [String] = []
			var sibling = try? h3.nextElementSibling()
			while let sib = sibling {
				if sib.tagName().lowercased() == "h3" { break }
				if sib.tagName().lowercased() == "p" {
					let pText = decodeHTMLEntities((try? sib.text()) ?? "")
					if let match = pText.firstMatch(of: /(?i)choose\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+of/) {
						let token = String(match.1).lowercased()
						let spelled: [String: Int] = [
							"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
							"six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
						]
						chooseCount = Int(token) ?? spelled[token]
					}
				}
				if sib.tagName().lowercased() == "ul" {
					for li in (try? sib.select("li").array()) ?? [] {
						let line = decodeHTMLEntities((try? li.text()) ?? "")
							.trimmingCharacters(in: .whitespacesAndNewlines)
						if !line.isEmpty { courseOptions.append(line) }
						if let anchor = try? li.select("a[href*=preview_course]").first() {
							let href = ((try? anchor.attr("href")) ?? "").replacingOccurrences(of: "&amp;", with: "&")
							let label = decodeHTMLEntities((try? anchor.text()) ?? "")
								.trimmingCharacters(in: .whitespacesAndNewlines)
							if let coid = extractQueryParameter("coid", from: href), !label.isEmpty {
								courseCoidMap[label] = coid
							}
						}
					}
				}
				sibling = try? sib.nextElementSibling()
			}

			requirementGroups.append(
				ProgramCatalogRequirementSheet.RequirementGroup(
					groupName: groupName,
					courseOptions: courseOptions,
					chooseCount: chooseCount
				)
			)
		}

		return ProgramCatalogRequirementSheet(
			programName: programName,
			totalCreditsRequired: totalCreditsRequired,
			requirementGroups: requirementGroups,
			courseCoidMap: courseCoidMap
		)
	}

	// MARK: - Departments (Hybrid Strategy)

	static func fetchDepartments(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
		// For some catalogs (notably UB), the search dropdown may not contain the
		// "Departments & Programs" entry reliably. Prefer a homepage scan.
		let discoveredDepartmentsNavoid = try? await discoverDepartmentsNavoid(baseURL: baseURL, catoid: catoid)
		if let discoveredDepartmentsNavoid {
			DebugLogger.shared.log("🏫 Discovered Departments navoid: \(discoveredDepartmentsNavoid)")
			let depts = try await fetchDepartmentsFromContentPage(baseURL: baseURL, catoid: catoid, navoid: discoveredDepartmentsNavoid)
			if !depts.isEmpty {
				return depts
			}
			DebugLogger.shared.log("⚠️ Discovered Departments navoid returned 0; falling back to search/sidebar")
		}

		let searchDepts = try await fetchDepartmentsFromSearch(baseURL: baseURL, catoid: catoid)
		if !searchDepts.isEmpty {
			return searchDepts
		}

		DebugLogger.shared.log("⚠️ Search dropdown empty. Falling back to Sidebar scraping...")
		return try await fetchDepartmentsFromSidebar(baseURL: baseURL, catoid: catoid)
	}

	private static func fetchDepartmentsFromContentPage(baseURL: String, catoid: String, navoid: String) async throws -> [ScrapedDepartment] {
		let logger = DebugLogger.shared
		let urlString = "\(baseURL)/content.php?catoid=\(catoid)&navoid=\(navoid)"
		logger.log("🏫 Loading Departments content page: \(urlString)")

		let html = try await fetchHTML(urlString)
		if html.isEmpty { return [] }

		do {
			let doc = try SwiftSoup.parse(html)
			let content = try doc.select("#acalog-content").first() ?? doc
			let anchors = try content.select("a[href]")
			var items: [ScrapedDepartment] = []
			for a in anchors.array() {
				let href = try a.attr("href").replacingOccurrences(of: "&amp;", with: "&")
				let name = decodeHTMLEntities(try a.text()).trimmingCharacters(in: .whitespacesAndNewlines)
				let lower = name.lowercased()

				// UB: The "Departments & Programs" page contains hundreds of subject/program links
				// (preview_entity.php). For the department picker we want ONLY the top-level
				// bucket/org-unit entries.
				let looksLikeOrgUnit =
					name.hasPrefix("College of ") ||
					name.hasPrefix("School of ") ||
					name.hasPrefix("Graduate School") ||
					name.hasPrefix("Jacobs School") ||
					name == "Other Departments" ||
					lower == "other departments"

				if name.count < 3 { continue }
				if lower.contains("back to top") { continue }
				if lower.contains("print") { continue }
				if lower.contains("help") { continue }
				if lower.contains("catalog home") { continue }
				if lower.contains("skip to") { continue }
				if lower == "departments & programs" || lower == "departments and programs" { continue }
				if lower == "courses" || lower == "majors and combined degrees" { continue }
				if lower == "minors, certificates and micro-credentials" { continue }
				if href.lowercased().contains("help.php") { continue }

				if href.lowercased().contains("preview_entity.php") {
					continue
				}
				if !looksLikeOrgUnit {
					continue
				}

				items.append(ScrapedDepartment(name: name, code: nil))
			}
			return Array(Set(items)).sorted { $0.name < $1.name }
		} catch {
			return []
		}
	}

	static func fetchDepartmentsFromSearch(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
		guard allowRobotsDisallowedEndpoints else {
			DebugLogger.shared.log("🤖 Robots: refusing to use /search_advanced.php for department discovery")
			return []
		}
		let urlString = "\(baseURL)/search_advanced.php?cur_cat_oid=\(catoid)"
		let html = (try? await fetchHTML(urlString)) ?? ""
		guard !html.isEmpty else { return [] }

		do {
			let doc = try SwiftSoup.parse(html)
			var depts: [ScrapedDepartment] = []

			if let locationSelect = try doc.select("select[name=location]").first() {
				let options = try locationSelect.select("option[value]")
				for opt in options.array() {
					let code = try opt.attr("value")
					let name = decodeHTMLEntities(try opt.text()).trimmingCharacters(in: .whitespacesAndNewlines)
					let lower = name.lowercased()
					if lower.contains("select") || lower.contains("entire catalog") || lower.contains("courses") || lower.contains("programs") || lower.contains("policies") {
						continue
					}
					if name.count > 2 {
						depts.append(ScrapedDepartment(name: name, code: code))
					}
				}
			}

			if !depts.isEmpty {
				return Array(Set(depts))
			}

			if let keywordSelect = try doc.select("select[name='filter[keyword]']").first() {
				let options = try keywordSelect.select("option[value]")
				for opt in options.array() {
					let code = try opt.attr("value")
					let name = decodeHTMLEntities(try opt.text()).trimmingCharacters(in: .whitespacesAndNewlines)
					let lower = name.lowercased()
					if !lower.contains("select") && !lower.contains("all") {
						depts.append(ScrapedDepartment(name: name, code: code))
					}
				}
			}

			return Array(Set(depts))
		} catch {
			return []
		}
	}

	static func fetchDepartmentsFromSidebar(baseURL: String, catoid: String) async throws -> [ScrapedDepartment] {
		let indexURL = "\(baseURL)/index.php?catoid=\(catoid)"
		guard let html = try? await fetchHTML(indexURL) else { return [] }

		guard let navoid = bestNavoidFromIndex(html: html, catoid: catoid, intent: .orgUnits)?.navoid else { return [] }

		let contentURL = "\(baseURL)/content.php?catoid=\(catoid)&navoid=\(navoid)"
		guard let cHtml = try? await fetchHTML(contentURL) else { return [] }

		do {
			let doc = try SwiftSoup.parse(cHtml)
			let content = try doc.select("#acalog-content").first() ?? doc
			let anchors = try content.select("a[href*='content.php?']")
			var depts: [ScrapedDepartment] = []
			for a in anchors.array() {
				let name = decodeHTMLEntities(try a.text()).trimmingCharacters(in: .whitespacesAndNewlines)
				if name.count > 3 && !name.lowercased().contains("back to top") {
					depts.append(ScrapedDepartment(name: name, code: nil))
				}
			}
			return Array(Set(depts))
		} catch {
			return []
		}
	}

	// MARK: - Sidebar / Navigation Discovery

	private enum NavDiscoveryIntent {
		case orgUnits
		case programs
	}

	private struct NavCandidate {
		let navoid: String
		let label: String
		let score: Int
	}

	private static func bestNavoidFromIndex(html: String, catoid: String, intent: NavDiscoveryIntent) -> NavCandidate? {
		guard let doc = try? SwiftSoup.parse(html) else { return nil }
		guard let anchors = try? doc.select("a[href*='content.php?catoid=\(catoid)&navoid=']") else { return nil }

		var candidates: [NavCandidate] = []
		for a in anchors.array() {
			let href = (try? a.attr("href")) ?? ""
			let rawLabel = (try? a.text()) ?? ""
			let label = decodeHTMLEntities(rawLabel).trimmingCharacters(in: .whitespacesAndNewlines)
			if label.isEmpty { continue }
			guard let navoid = extractQueryParameter("navoid", from: href) else { continue }
			let score = scoreNavLabel(label, intent: intent)
			if score > 0 {
				candidates.append(NavCandidate(navoid: navoid, label: label, score: score))
			}
		}

		if candidates.isEmpty { return nil }
		return candidates.sorted { $0.score > $1.score }.first
	}

	private static func scoreNavLabel(_ label: String, intent: NavDiscoveryIntent) -> Int {
		let l = label.lowercased()

		// A few generic negatives to avoid picking index-y or irrelevant links.
		if l.contains("print") || l.contains("pdf") { return 0 }
		if l.contains("home") || l == "index" { return 0 }

		switch intent {
		case .orgUnits:
			var score = 0
			if l.contains("department") { score += 8 }
			if l.contains("colleges") || l.contains("college") { score += 6 }
			if l.contains("schools") || l.contains("school") { score += 6 }
			if l.contains("academic units") { score += 6 }
			if l.contains("departments & programs") || l.contains("departments and programs") { score += 7 }

			// penalize purely program-centric pages
			if l.contains("majors") || l.contains("minors") { score -= 3 }
			if l.contains("degrees") || l.contains("programs") { score -= 1 }
			return max(0, score)

		case .programs:
			var score = 0
			if l.contains("majors") { score += 9 }
			if l.contains("minors") { score += 8 }
			if l.contains("programs") { score += 7 }
			if l.contains("degrees") { score += 6 }
			if l.contains("certificates") { score += 5 }
			return score
		}
	}
}

