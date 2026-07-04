// WebScraperService.swift
// Feature: Catalog
// Purpose: Catalog module — BasicCourse.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import WebKit

/// WKWebView-based fallback scraper for universities that block pure HTTP access.
///
/// ⚠️ DATA QUALITY WARNING: This service is a last-resort fallback only.
///
/// **Limitations to be aware of:**
/// - The Acalog JS scraper (`preview_course` link path) fetches no course detail pages:
///   credits are hardcoded to `3` and descriptions are `nil`. Real values require
///   per-course network round-trips that this scraper never makes.
/// - The Banner scraper starts at `credits: 3` and attempts to extract from description
///   text but relies on fragile regex and cannot guarantee correctness.
/// - The primary HTTP-based pipeline (`ModernCampusEngine` + `UniversalCatalogScraper`)
///   should always be tried first; this scraper is only reached on failure.
///
/// Any course imported via this path should be treated as incomplete and re-scraped
/// by the primary engine whenever possible.
@MainActor
class WebScraperService: NSObject {
    private var webView: WKWebView?
    private var completionHandler: ((Result<[CatalogCourse], ScraperError>) -> Void)?
    private var currentScraperScript: String?
    private static let courseCodeRegex = try? NSRegularExpression(
        pattern: "\\b[A-Z]{2,4}\\s*\\d{3,4}[A-Z]?\\b",
        options: []
    )
    
    override init() {
        super.init()
        Self.registerLiveInstance(self)
    }

    /// Drops the headless web view; recreated lazily on the next scrape (Phase 5 P0).
    func releaseWebViewForMemoryPressure() {
        completionHandler = nil
        currentScraperScript = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
    }

    static func releaseAllWebViewsForMemoryPressure() {
        for instance in liveInstances.allObjects {
            instance.releaseWebViewForMemoryPressure()
        }
    }

    private static let liveInstances = NSHashTable<WebScraperService>.weakObjects()

    private static func registerLiveInstance(_ instance: WebScraperService) {
        liveInstances.add(instance)
    }
    
    private func setupWebView() {
        guard webView == nil else { return }
        let configuration = WKWebViewConfiguration()
        // Privacy: avoid persistent cookies/cache for scraping.
        configuration.websiteDataStore = .nonPersistent()
        // Use WKWebpagePreferences for modern API
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // Create off-screen web view (headless)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
    }
    
    // MARK: - Main Scraping Method
    
    /// Scrape course catalog from university website (User-triggered only)
    func scrapeCatalog(
        url: String,
        format: String,
        scraperScript: String
    ) async throws -> [CatalogCourse] {
        
        let logger = DebugLogger.shared
        logger.log("🌐 WebScraper.scrapeCatalog() called")
        logger.log("   URL string: \(url)")
        logger.log("   Format: \(format)")
        
        guard let catalogURL = URL(string: url) else {
            logger.log("❌ Failed to create URL from string")
            throw ScraperError.invalidURL
        }
        
        logger.log("✓ URL object created: \(catalogURL.absoluteString)")
        
        return try await withCheckedThrowingContinuation { continuation in
            if self.webView == nil {
                self.setupWebView()
            }
            guard let webView = self.webView else {
                continuation.resume(throwing: ScraperError.webViewNotAvailable)
                return
            }

            // Persist the script for execution after navigation completes.
            self.currentScraperScript = scraperScript

            // Store continuation for later
            self.completionHandler = { result in
                switch result {
                case .success(let courses):
                    continuation.resume(returning: courses)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            // Load the catalog page
            let request = URLRequest(url: catalogURL)
            webView.load(request)
        }
    }
    
    // MARK: - Built-in Scrapers
    
    /// Acalog scraper (used by ~300 universities including Stony Brook)
    func scrapeAcalog(url: String) async throws -> [CatalogCourse] {
        let logger = DebugLogger.shared

        // Prefer the robots-compliant ModernCampus engine (no WebView; crawls Course Descriptions
        // and then each preview_course(_nopop) page for details).
        do {
            let (normalizedCatalogURL, catoidHint) = ModernCampusEngine.normalizeCatalogEntryPointForCaller(url)
            let catalogID: String
            if let catoidHint {
                catalogID = catoidHint
            } else {
                catalogID = try await ModernCampusEngine.discoverCurrentCatalogID(baseURL: normalizedCatalogURL)
            }
            let courses = try await ModernCampusEngine.fetchAllCourses(baseURL: normalizedCatalogURL, catoid: catalogID)
            if !courses.isEmpty {
                logger.log("📚 ModernCampusEngine returned \(courses.count) courses")
                return courses
            }
            logger.log("⚠️ ModernCampusEngine returned 0 courses; falling back to WebView scraping")
        } catch {
            logger.log("⚠️ ModernCampusEngine failed: \(error.localizedDescription); falling back to WebView scraping")
        }
        
        // Fallback to WebView-based scraping for Acalog sites
        logger.log("⚠️ WebScraperService: using WKWebView fallback — credits will be hardcoded to 3 and descriptions will be nil for preview_course links (no detail pages visited)")
        logger.log("📝 Using WebView-based Acalog scraper for \(url)")
        
        // Modern Campus Catalog (Acalog) uses a search API
        // Convert base URL to search endpoint if needed
        let searchURL = url
        if url.contains("catalog.") && !url.contains("search_advanced") {
            // Try to extract domain and construct search URL
            if let domain = URL(string: url)?.host {
                // Robots compliance: ModernCampus robots.txt commonly disallows /search_advanced.php.
                // This WebView-based scraper doesn't require that endpoint; keep the existing URL.
                logger.log("🤖 Robots: not converting \(domain) to /search_advanced.php (disallowed); using WebView course link scraping")
            }
        }
        
        let script = """
        (function() {
            const courses = [];
            
            // Modern Campus Catalog uses table rows with course links
            const courseLinks = document.querySelectorAll('a[href*="preview_course"]');
            
            courseLinks.forEach(link => {
                const row = link.closest('tr');
                if (!row) return;
                
                const titleText = link.textContent.trim();
                // Match patterns like "CSE 101 - Introduction to Computer Science"
                const match = titleText.match(/^([A-Z]{2,4})\\s+(\\d{3}[A-Z]?)\\s*-\\s*(.+)$/i);
                
                if (match) {
                    const courseCode = match[1] + ' ' + match[2];
                    const title = match[3].trim();
                    
                    const course = {
                        courseCode: courseCode,
                        title: title,
                        credits: 3, // Default, would need to click through for actual
                        description: null,
                        department: match[1]
                    };
                    
                    courses.push(course);
                }
            });
            
            // Also try traditional courseblock format (some Acalog sites)
            const courseBlocks = document.querySelectorAll('.courseblock');
            courseBlocks.forEach(block => {
                const titleElement = block.querySelector('.courseblocktitle');
                const descElement = block.querySelector('.courseblockdesc');
                
                if (!titleElement) return;
                
                const titleText = titleElement.textContent.trim();
                const match = titleText.match(/^([A-Z]+\\s*\\d+[A-Z]?)\\s*-\\s*(.+?)\\s*\\((\\d+)\\s*credits?\\)/i);
                
                if (match) {
                    const course = {
                        courseCode: match[1].trim(),
                        title: match[2].trim(),
                        credits: parseInt(match[3]),
                        description: descElement ? descElement.textContent.trim() : null,
                        department: match[1].match(/[A-Z]+/)[0]
                    };
                    
                    // Extract prerequisites
                    const prereqMatch = descElement?.textContent.match(/Prerequisite[s]?:\\s*(.+?)(?=\\.|$)/i);
                    if (prereqMatch) {
                        course.prerequisites = prereqMatch[1].trim();
                    }
                    
                    courses.push(course);
                }
            });
            
            return JSON.stringify(courses);
        })();
        """
        
        return try await scrapeCatalog(url: searchURL, format: "acalog", scraperScript: script)
    }
    
    /// Banner scraper (used by ~200 universities)
    func scrapeBanner(url: String) async throws -> [CatalogCourse] {
        let script = """
        (function() {
            const courses = [];
            const courseRows = document.querySelectorAll('tr.ntdefault, td.ntdefault');
            
            let currentCourse = null;
            
            courseRows.forEach(row => {
                const text = row.textContent.trim();
                const codeMatch = text.match(/^([A-Z]{2,4}\\s*\\d{3,4}[A-Z]?)\\s*-\\s*(.+)/);
                
                if (codeMatch) {
                    if (currentCourse) {
                        courses.push(currentCourse);
                    }
                    
                    currentCourse = {
                        courseCode: codeMatch[1].replace(/\\s+/g, ' ').trim(),
                        title: codeMatch[2].trim(),
                        credits: 3,
                        description: '',
                        department: codeMatch[1].match(/[A-Z]+/)[0]
                    };
                } else if (currentCourse && text.length > 20) {
                    currentCourse.description += text + ' ';
                    
                    // Extract credits
                    const creditsMatch = text.match(/(\\d+)\\s*credit/i);
                    if (creditsMatch) {
                        currentCourse.credits = parseInt(creditsMatch[1]);
                    }
                    
                    // Extract prerequisites
                    const prereqMatch = text.match(/Prerequisite[s]?:\\s*(.+?)(?=\\.|Corequisite|$)/i);
                    if (prereqMatch) {
                        currentCourse.prerequisites = prereqMatch[1].trim();
                    }
                }
            });
            
            if (currentCourse) {
                courses.push(currentCourse);
            }
            
            return JSON.stringify(courses);
        })();
        """
        
        return try await scrapeCatalog(url: url, format: "banner", scraperScript: script)
    }
    
    // MARK: - Helper Methods
    
    private func executeScript(_ script: String) async throws -> String {
        guard let webView = webView else {
            throw ScraperError.webViewNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        continuation.resume(throwing: ScraperError.scriptExecutionFailed(error.localizedDescription))
                        return
                    }
                    
                    guard let jsonString = result as? String else {
                        continuation.resume(throwing: ScraperError.invalidResponse)
                        return
                    }
                    
                    continuation.resume(returning: jsonString)
                }
            }
        }
    }
    
    private func parseCourses(from jsonString: String) throws -> [CatalogCourse] {
        guard let data = jsonString.data(using: .utf8) else {
            throw ScraperError.parsingFailed
        }
        
        // Parse basic JSON structure from JavaScript
        let basicCourses = try JSONDecoder().decode([BasicCourse].self, from: data)
        
        // Convert to CatalogCourse with full structure
        return basicCourses.map { basic in
            CatalogCourse(
                id: UUID(),
                courseCode: basic.courseCode,
                title: basic.title,
                description: basic.description,
                credits: basic.credits,
                department: basic.department,
                prerequisites: parsePrerequisites(basic.prerequisites),
                corequisites: nil,
                typicallyOffered: nil
            )
        }
    }
    
    private func parsePrerequisites(_ prereqString: String?) -> PrerequisiteRule? {
        guard let prereqText = prereqString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prereqText.isEmpty else {
            return nil
        }
        
        // Simple parsing - extract course codes
        guard let regex = Self.courseCodeRegex else {
            return nil
        }
        
        let matches = regex.matches(in: prereqText, range: NSRange(prereqText.startIndex..., in: prereqText))
        let courseCodes = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: prereqText) else { return nil }
            return String(prereqText[range]).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        
        if courseCodes.isEmpty {
            return nil
        }
        
        // Determine if AND or OR logic
        let lowerText = prereqText.lowercased()
        
        if lowerText.contains(" or ") {
            let requirements = courseCodes.map { PrerequisiteRule.course(CourseRequirement(courseCode: $0, minGrade: nil)) }
            return .or(requirements)
        } else if courseCodes.count > 1 {
            let requirements = courseCodes.map { PrerequisiteRule.course(CourseRequirement(courseCode: $0, minGrade: nil)) }
            return .and(requirements)
        } else {
            return .course(CourseRequirement(courseCode: courseCodes[0], minGrade: nil))
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebScraperService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Page loaded, now execute scraper script
        Task {
            do {
                // Wait a bit for JavaScript to render content
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Execute the scraper script provided by the caller.
                guard let script = currentScraperScript, !script.isEmpty else {
                    completionHandler?(.failure(.scriptExecutionFailed("Missing scraper script")))
                    return
                }
                let jsonResult = try await executeScript(script)
                let courses = try parseCourses(from: jsonResult)
                
                completionHandler?(.success(courses))
            } catch {
                completionHandler?(.failure(.scriptExecutionFailed(error.localizedDescription)))
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completionHandler?(.failure(.navigationFailed(error.localizedDescription)))
    }
    
    private func getStoredScraperScript() -> String {
        // This would be loaded from the GitHub recipe or built-in
        return """
        (function() {
            return JSON.stringify([]);
        })();
        """
    }
}

// MARK: - Helper Structures

private struct BasicCourse: Codable {
    let courseCode: String
    let title: String
    let description: String?
    let credits: Int
    let department: String?
    let prerequisites: String?
}

// MARK: - Errors

enum ScraperError: LocalizedError {
    case invalidURL
    case webViewNotAvailable
    case navigationFailed(String)
    case scriptExecutionFailed(String)
    case invalidResponse
    case parsingFailed
    case ingestRejected(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid catalog URL"
        case .webViewNotAvailable:
            return "Web scraper not available"
        case .navigationFailed(let message):
            return "Failed to load catalog page: \(message)"
        case .scriptExecutionFailed(let message):
            return "Failed to extract course data: \(message)"
        case .invalidResponse:
            return "Received invalid response from catalog"
        case .parsingFailed:
            return "Failed to parse course data"
        case .ingestRejected(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Failed to parse course data" : detail
        case .timeout:
            return "Scraping timed out after 30 seconds"
        }
    }
}
