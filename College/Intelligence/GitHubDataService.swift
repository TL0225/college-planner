import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Service for fetching data from GitHub repository (MANUAL ONLY - No background sync)
class GitHubDataService {
    /// Static data host (GitHub Raw). Keep this in sync with your data repo.
    private let repoOwner = "TL0225"
    private let repoName = "college-planner-data"
    private let branch = "main"

    private var fullBaseURL: String {
        "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/\(branch)"
    }

    /// Fallback that often works when `raw.githubusercontent.com` is blocked by DNS / filtering.
    /// Example: https://github.com/TL0225/college-planner-data/raw/main
    private var fallbackBaseURL: String {
        "https://github.com/\(repoOwner)/\(repoName)/raw/\(branch)"
    }
    
    // MARK: - Manual Fetch Methods (User-triggered only)

    private func makeGETRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // GitHub Raw can be picky in some contexts; send safe, explicit headers.
        request.setValue("CollegePlanner-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func fetchDataWithFallback(primaryURL: URL, fallbackURL: URL) async throws -> (Data, HTTPURLResponse, URL) {
        do {
            let (data, response) = try await URLSession.shared.data(for: makeGETRequest(url: primaryURL))
            guard let http = response as? HTTPURLResponse else {
                throw GitHubError.networkError
            }
            return (data, http, primaryURL)
        } catch {
            // If the primary host can't be resolved or is blocked, try the github.com/raw fallback.
            if let urlError = error as? URLError,
               urlError.code == .cannotFindHost || urlError.code == .cannotConnectToHost || urlError.code == .dnsLookupFailed {
                let (data, response) = try await URLSession.shared.data(for: makeGETRequest(url: fallbackURL))
                guard let http = response as? HTTPURLResponse else {
                    throw GitHubError.networkError
                }
                return (data, http, fallbackURL)
            }
            throw error
        }
    }
    
    /// Fetch list of all available schools (Only when user clicks "Refresh Schools")
    func fetchSchoolsList() async throws -> [SchoolManifest] {
        guard let primaryURL = URL(string: "\(fullBaseURL)/manifests/schools.json"),
              let fallbackURL = URL(string: "\(fallbackBaseURL)/manifests/schools.json") else {
            throw GitHubError.invalidURL
        }
        let (data, httpResponse, usedURL) = try await fetchDataWithFallback(primaryURL: primaryURL, fallbackURL: fallbackURL)

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.fetchFailed(statusCode: httpResponse.statusCode, url: usedURL)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SchoolManifest].self, from: data)
    }
    
    /// Download specific school profile (Only when user clicks school name)
    func downloadSchoolProfile(schoolID: String) async throws -> SchoolProfile {
        guard let primaryURL = URL(string: "\(fullBaseURL)/profiles/\(schoolID).json"),
              let fallbackURL = URL(string: "\(fallbackBaseURL)/profiles/\(schoolID).json") else {
            throw GitHubError.invalidURL
        }
        let (data, httpResponse, usedURL) = try await fetchDataWithFallback(primaryURL: primaryURL, fallbackURL: fallbackURL)

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.fetchFailed(statusCode: httpResponse.statusCode, url: usedURL)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SchoolProfile.self, from: data)
    }
    
    /// Fetch scraper recipe for a specific format (Only when user manually scrapes)
    func fetchScraperRecipe(format: String) async throws -> ScraperRecipe {
        guard let primaryURL = URL(string: "\(fullBaseURL)/recipes/\(format)_scraper.json"),
              let fallbackURL = URL(string: "\(fallbackBaseURL)/recipes/\(format)_scraper.json") else {
            throw GitHubError.invalidURL
        }
        let (data, httpResponse, usedURL) = try await fetchDataWithFallback(primaryURL: primaryURL, fallbackURL: fallbackURL)

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.fetchFailed(statusCode: httpResponse.statusCode, url: usedURL)
        }
        
        return try JSONDecoder().decode(ScraperRecipe.self, from: data)
    }
    
    // MARK: - Community Contribution (Manual submission only)
    
    /// Submit policy correction (Only when user clicks "Submit to Community")
    /// Opens GitHub in browser with pre-filled issue (no API key needed)
    func submitCorrection(_ correction: PolicyCorrection) {
        let title = "Fix: \(correction.schoolID) - \(correction.policyName)"
        let body = """
        **School ID**: `\(correction.schoolID)`
        **Policy**: \(correction.policyName)
        **Current Value**: \(correction.currentValue)
        **Corrected Value**: \(correction.correctedValue)
        **Source**: \(correction.source ?? "Not provided")
        **Submitted**: \(correction.submittedDate.formatted())
        
        ---
        _Submitted via College Planner app_
        """
        
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let issueURL = "https://github.com/\(repoOwner)/\(repoName)/issues/new?title=\(encodedTitle)&body=\(encodedBody)&labels=data-fix,\(correction.schoolID)"
        
        if let url = URL(string: issueURL) {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Alternative: Submit via GitHub API (requires embedded token)
    /// Only use if you want in-app submission without opening browser
    func submitCorrectionViaAPI(_ correction: PolicyCorrection, apiToken: String) async throws {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/issues") else {
            throw GitHubError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let issueBody: [String: Any] = [
            "title": "Fix: \(correction.schoolID) - \(correction.policyName)",
            "body": """
                **School ID**: `\(correction.schoolID)`
                **Policy**: \(correction.policyName)
                **Current Value**: \(correction.currentValue)
                **Corrected Value**: \(correction.correctedValue)
                **Source**: \(correction.source ?? "Not provided")
                """,
            "labels": ["data-fix", correction.schoolID]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: issueBody)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GitHubError.submissionFailed
        }
    }
    
    // MARK: - Local Caching
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("GitHubCache")
    }()
    
    /// Cache schools list locally (7 day TTL)
    func cacheSchoolsList(_ schools: [SchoolManifest]) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(schools)
        
        let cacheFile = cacheDirectory.appendingPathComponent("schools.json")
        try data.write(to: cacheFile)
        
        // Save timestamp
        let timestampFile = cacheDirectory.appendingPathComponent("schools_timestamp.txt")
        try Date().timeIntervalSince1970.description.write(to: timestampFile, atomically: true, encoding: .utf8)
    }
    
    /// Load cached schools list (returns nil if expired or doesn't exist)
    func loadCachedSchoolsList() -> [SchoolManifest]? {
        let cacheFile = cacheDirectory.appendingPathComponent("schools.json")
        let timestampFile = cacheDirectory.appendingPathComponent("schools_timestamp.txt")
        
        guard FileManager.default.fileExists(atPath: cacheFile.path),
              FileManager.default.fileExists(atPath: timestampFile.path) else {
            return nil
        }
        
        // Check if cache is stale (7 days)
        if let timestampString = try? String(contentsOf: timestampFile, encoding: .utf8),
           let timestamp = TimeInterval(timestampString) {
            let cacheDate = Date(timeIntervalSince1970: timestamp)
            let daysSinceCache = Date().timeIntervalSince(cacheDate) / 86400
            
            if daysSinceCache > 7 {
                return nil // Cache expired
            }
        }
        
        // Load from cache
        guard let data = try? Data(contentsOf: cacheFile) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([SchoolManifest].self, from: data)
    }
}

// MARK: - Errors

enum GitHubError: LocalizedError {
    case fetchFailed(statusCode: Int? = nil, url: URL? = nil)
    case submissionFailed
    case invalidData
    case networkError
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed(let statusCode, let url):
            var message = "Failed to fetch data from GitHub."
            if let statusCode {
                message += " (HTTP \(statusCode))"
            }
            if let url {
                message += "\nURL: \(url.absoluteString)"
            }
            message += "\nCheck that the data repo is public and the URL is correct."
            return message
        case .submissionFailed:
            return "Failed to submit correction to GitHub. Please try again."
        case .invalidData:
            return "Received invalid data from GitHub repository."
        case .networkError:
            return "Network error occurred. Please check your connection."
        case .invalidURL:
            return "Invalid GitHub URL configuration."
        }
    }
}
