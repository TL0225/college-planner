// CatalogPlatformProbe.swift
// Feature: Catalog
// Purpose: Derive catalog_format from live HTML/HTTP evidence; route ingest when confident.

import Foundation

enum CatalogPlatformProbe {
    struct LegacyResult: Sendable, Equatable {
        let declaredFormat: String
        let sniffedFormat: String
        let mismatch: Bool
        let message: String
    }

    enum ProbeOutcome: Sendable, Equatable {
        case succeeded(CatalogManifestVerificationRecord)
        case failed(message: String, blockedByWAF: Bool)
        case conflicting(CatalogManifestVerificationRecord)
    }

    private struct CachedProbe: Codable {
        let record: CatalogManifestVerificationRecord
        let cachedAt: Date
    }

    private static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    private static let maxHTMLBytes = 256 * 1024

    private static var probeCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("College/catalog_platform_probes.json")
    }

    static func evaluate(manifest: SchoolManifest, catalogURL: String) -> LegacyResult {
        let declared = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sniffed = CatalogPlatformFingerprintStore.sniffURL(catalogURL).manifestFormat
        let mismatch = !declared.isEmpty && sniffed != "unknown" && declared != sniffed
            && CatalogDetectedPlatform.from(manifestFormat: declared) != CatalogDetectedPlatform.from(manifestFormat: sniffed)
        let message: String
        if mismatch {
            message = "Manifest declares '\(declared)' but catalog URL looks like '\(sniffed)'."
        } else {
            message = ""
        }
        return LegacyResult(
            declaredFormat: declared.isEmpty ? "unknown" : declared,
            sniffedFormat: sniffed,
            mismatch: mismatch,
            message: message
        )
    }

    static func detectInHTML(_ html: String, baseURL: URL?) -> CatalogDetectedPlatform {
        let urlSniff = baseURL.map { CatalogPlatformFingerprintStore.sniffURL($0.absoluteString) } ?? .unknown
        let scores = CatalogPlatformFingerprintStore.scoreHTML(html, baseURL: baseURL, urlSniff: urlSniff)
        return CatalogPlatformFingerprintStore.decide(from: scores)?.winner ?? .unknown
    }

    static func probe(catalogURL: String, manifest: SchoolManifest, forceRefresh: Bool = false) async -> ProbeOutcome {
        let schoolID = manifest.id
        if !forceRefresh, let cached = loadCached(schoolID: schoolID), !isStale(cached) {
            return cached.record.blockedByWAF
                ? .failed(message: "Catalog verification blocked", blockedByWAF: true)
                : .succeeded(cached.record)
        }

        let trimmed = catalogURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failed(message: "Invalid catalog URL", blockedByWAF: false)
        }

        let declared = manifest.catalogFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // HEAD — PDF detection
        if let pdfRecord = await probePDFHead(url: url, schoolID: schoolID, declared: declared) {
            cache(record: pdfRecord)
            return .succeeded(pdfRecord)
        }

        // GET landing HTML
        do {
            await CatalogOriginRobotsThrottle.applyPoliteDelayBeforeFetch(url: url, politeness: .interactiveBackground)
            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            let finalURL = (response as? HTTPURLResponse)?.url?.absoluteString ?? trimmed

            if let http = response as? HTTPURLResponse,
               http.mimeType?.lowercased().contains("pdf") == true || finalURL.lowercased().hasSuffix(".pdf") {
                let record = CatalogManifestVerificationRecord(
                    schoolID: schoolID,
                    declaredFormat: declared,
                    detectedFormat: CatalogDetectedPlatform.pdf.manifestFormat,
                    confidence: 2.0,
                    margin: 2.0,
                    evidence: ["head:application/pdf"],
                    finalURL: finalURL,
                    probedAt: Date(),
                    blockedByWAF: false,
                    notACatalogHost: false
                )
                cache(record: record)
                return .succeeded(record)
            }

            let capped = Data(data.prefix(maxHTMLBytes))
            guard let html = String(data: capped, encoding: .utf8), !html.isEmpty else {
                return .failed(message: "Empty catalog page response", blockedByWAF: true)
            }

            if ModernCampusEngine.htmlLooksLikeWAFOrJSChallenge(html) {
                return .failed(message: "Catalog verification blocked by WAF", blockedByWAF: true)
            }

            let urlSniff = CatalogPlatformFingerprintStore.sniffURL(finalURL)
            var scores = CatalogPlatformFingerprintStore.scoreHTML(html, baseURL: URL(string: finalURL), urlSniff: urlSniff)

            // Secondary probes when ambiguous
            if let top = scores.first, top.score < 2.0, let origin = URL(string: finalURL)?.originURL {
                scores = await applySecondaryProbes(
                    scores: scores,
                    origin: origin,
                    urlSniff: urlSniff,
                    leading: scores.first?.platform
                )
            }

            guard let decision = CatalogPlatformFingerprintStore.decide(from: scores) else {
                let record = CatalogManifestVerificationRecord(
                    schoolID: schoolID,
                    declaredFormat: declared,
                    detectedFormat: CatalogDetectedPlatform.unknown.manifestFormat,
                    confidence: 0,
                    margin: 0,
                    evidence: ["no_fingerprint"],
                    finalURL: finalURL,
                    probedAt: Date(),
                    blockedByWAF: false,
                    notACatalogHost: true
                )
                cache(record: record)
                return .failed(message: "Could not verify catalog platform", blockedByWAF: false)
            }

            // Conflicting strong signals
            let strong = scores.filter { $0.score >= 2.0 }
            if strong.count >= 2 {
                let record = CatalogManifestVerificationRecord(
                    schoolID: schoolID,
                    declaredFormat: declared,
                    detectedFormat: decision.winner.manifestFormat,
                    confidence: decision.confidence,
                    margin: decision.margin,
                    evidence: strong.flatMap(\.evidence),
                    finalURL: finalURL,
                    probedAt: Date(),
                    blockedByWAF: false,
                    notACatalogHost: false
                )
                cache(record: record)
                return .conflicting(record)
            }

            let record = CatalogManifestVerificationRecord(
                schoolID: schoolID,
                declaredFormat: declared,
                detectedFormat: decision.winner.manifestFormat,
                confidence: decision.confidence,
                margin: decision.margin,
                evidence: scores.first?.evidence ?? [],
                finalURL: finalURL,
                probedAt: Date(),
                blockedByWAF: false,
                notACatalogHost: decision.winner == .unknown
            )
            cache(record: record)

            if record.autoOverrideEligible {
                SchoolManifestLocalOverrideStore.save(
                    SchoolManifestFormatOverride(
                        schoolID: schoolID,
                        catalogFormat: record.detectedFormat,
                        detectedAt: record.probedAt,
                        confidence: record.confidence,
                        evidence: record.evidence
                    )
                )
            }

            return .succeeded(record)
        } catch {
            return .failed(message: error.localizedDescription, blockedByWAF: false)
        }
    }

    /// Returns effective manifest with local override applied; probes when cache stale.
    static func resolveEffectiveManifest(
        _ manifest: SchoolManifest,
        forceRefresh: Bool = false
    ) async -> SchoolManifest {
        let base = SchoolManifestCatalog.effectiveManifest(manifest)
        guard let catalogURL = base.catalogURL?.trimmingCharacters(in: .whitespacesAndNewlines), !catalogURL.isEmpty else {
            return base
        }

        let outcome = await probe(catalogURL: catalogURL, manifest: base, forceRefresh: forceRefresh)
        switch outcome {
        case .succeeded(let record) where record.autoOverrideEligible:
            return base.withCatalogFormat(record.detectedFormat)
        case .succeeded, .conflicting:
            return SchoolManifestCatalog.effectiveManifest(manifest)
        case .failed:
            return base
        }
    }

    static func enqueueMismatchWarningIfNeeded(manifest: SchoolManifest, catalogURL: String) {
        let probe = evaluate(manifest: manifest, catalogURL: catalogURL)
        guard probe.mismatch else { return }
        CatalogReviewQueue.enqueue(
            schoolID: manifest.id,
            reason: "catalog_platform_mismatch: \(probe.message)",
            severity: .warning
        )
    }

  private static func probePDFHead(url: URL, schoolID: String, declared: String) async -> CatalogManifestVerificationRecord? {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (_, response) = try? await URLSession.shared.data(for: head),
              let http = response as? HTTPURLResponse else { return nil }
        let finalURL = http.url?.absoluteString ?? url.absoluteString
        let mime = http.mimeType?.lowercased() ?? ""
        if mime.contains("pdf") || finalURL.lowercased().hasSuffix(".pdf") {
            return CatalogManifestVerificationRecord(
                schoolID: schoolID,
                declaredFormat: declared,
                detectedFormat: CatalogDetectedPlatform.pdf.manifestFormat,
                confidence: 2.5,
                margin: 2.5,
                evidence: ["head:pdf"],
                finalURL: finalURL,
                probedAt: Date(),
                blockedByWAF: false,
                notACatalogHost: false
            )
        }
        return nil
    }

    private static func applySecondaryProbes(
        scores: [CatalogPlatformScoreResult],
        origin: URL,
        urlSniff: CatalogDetectedPlatform,
        leading: CatalogDetectedPlatform?
    ) async -> [CatalogPlatformScoreResult] {
        var merged = scores
        if leading == .moderncampus || leading == .unknown {
            if let listURL = URL(string: "\(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/misc/catalog_list.php"),
               let html = try? await fetchProbeHTML(listURL),
               html.lowercased().contains("catoid=") {
                merged.append(CatalogPlatformScoreResult(platform: .moderncampus, score: 1.0, evidence: ["secondary:catalog_list.php"]))
            }
        }
        if leading == .courseleaf || leading == .unknown {
            if let xmlURL = URL(string: "\(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/index.xml"),
               let html = try? await fetchProbeHTML(xmlURL),
               html.lowercased().contains("<urlset") || html.lowercased().contains("loc>") {
                merged.append(CatalogPlatformScoreResult(platform: .courseleaf, score: 1.0, evidence: ["secondary:index.xml"]))
            }
        }
        if leading == .coursedog || leading == .unknown {
            if let programsURL = URL(string: "\(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/programs"),
               let html = try? await fetchProbeHTML(programsURL),
               html.lowercased().contains("coursedog") {
                merged.append(CatalogPlatformScoreResult(platform: .coursedog, score: 1.5, evidence: ["secondary:/programs"]))
            }
        }
        // Re-aggregate by platform
        var totals: [CatalogDetectedPlatform: (score: Double, evidence: [String])] = [:]
        for item in merged {
            let existing = totals[item.platform, default: (0, [])]
            totals[item.platform] = (existing.score + item.score, existing.evidence + item.evidence)
        }
        return totals
            .map { CatalogPlatformScoreResult(platform: $0.key, score: $0.value.score, evidence: $0.value.evidence) }
            .sorted { $0.score > $1.score }
    }

    private static func fetchProbeHTML(_ url: URL) async throws -> String {
        await CatalogOriginRobotsThrottle.applyPoliteDelayBeforeFetch(url: url, politeness: .interactiveBackground)
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data.prefix(maxHTMLBytes), encoding: .utf8) ?? ""
    }

    /// Latest cached live probe for diagnostics (nil when never probed on this device).
    static func verificationRecord(schoolID: String) -> CatalogManifestVerificationRecord? {
        loadCached(schoolID: schoolID)?.record
    }

    private static func loadCached(schoolID: String) -> CachedProbe? {
        guard let data = try? Data(contentsOf: probeCacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let all = try? decoder.decode([String: CachedProbe].self, from: data) else { return nil }
        return all[schoolID]
    }

    private static func cache(record: CatalogManifestVerificationRecord) {
        var all: [String: CachedProbe] = (try? Data(contentsOf: probeCacheURL)).flatMap {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode([String: CachedProbe].self, from: $0)
        } ?? [:]
        all[record.schoolID] = CachedProbe(record: record, cachedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(all) {
            try? FileManager.default.createDirectory(at: probeCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: probeCacheURL, options: .atomic)
        }
    }

    private static func isStale(_ cached: CachedProbe) -> Bool {
        Date().timeIntervalSince(cached.cachedAt) > cacheTTL
    }
}

private extension URL {
    var originURL: URL? {
        guard let scheme, let host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url
    }
}
