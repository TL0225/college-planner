// AcademicCalendarScrapeService.swift
// Feature: Calendar
// Purpose: Orchestrates academic calendar fetch, classify, extract, and reconcile.

import CollegeCalendar
import Foundation

enum AcademicCalendarScrapeReason: String {
  case manual
  case background
}

struct AcademicCalendarScrapeOutput: Sendable {
  var result: AcademicCalendarSyncResult
  var config: AcademicCalendarConfig
  var needsHubPicker: Bool
  var hubCandidates: [AcademicCalendarSubCalendarCandidate]
  var contentUnchanged: Bool
  var suggestedHubURL: String?
  var hubPickerNeutral: Bool
}

@MainActor
enum AcademicCalendarScrapeService {
  static let importTimeoutSeconds: TimeInterval = 45

  static func scrape(
    config: inout AcademicCalendarConfig,
    reason: AcademicCalendarScrapeReason,
    calendarManager: CalendarIntegrationManager? = nil,
    selectedSubCalendarURL: String? = nil,
    writeChanges: Bool = true,
    programProfile: AcademicCalendarProgramProfile? = nil,
    hubPickerNeutral: Bool = false,
    userConfirmedURL: Bool = false
  ) async -> AcademicCalendarScrapeOutput {
    let started = Date()
    let scrapeID = UUID()
    let profileSnapshot = programProfile
    let fingerprint = profileSnapshot.map {
      AcademicCalendarFingerprintCache.fingerprint(for: $0, schoolID: config.schoolID)
    }

    if AcademicCalendarCircuitBreaker.shouldSkip(configID: config.configID) {
      config.importStatus = .needsAttention
      config.lastError = String(
        localized: "calendar.circuit_breaker.open",
        defaultValue: "Import paused after repeated failures. Try again tomorrow or paste a direct calendar URL."
      )
      AcademicCalendarStore.upsertConfig(config)
      return AcademicCalendarScrapeOutput(
        result: .empty,
        config: config,
        needsHubPicker: false,
        hubCandidates: [],
        contentUnchanged: false,
        suggestedHubURL: nil,
        hubPickerNeutral: hubPickerNeutral
      )
    }

    config.lastAttemptedAt = Date()
    AcademicCalendarStore.upsertConfig(config)

    if let fingerprint,
       selectedSubCalendarURL == nil,
       config.chosenSubCalendarURL == nil,
       let cached = AcademicCalendarFingerprintCache.lookup(schoolID: config.schoolID, fingerprint: fingerprint) {
      config.chosenSubCalendarURL = cached.chosenSubCalendarURL
    }

    var targetURL = selectedSubCalendarURL
      ?? config.chosenSubCalendarURL
      ?? config.url

    if let chosen = config.chosenSubCalendarURL, selectedSubCalendarURL == nil {
      let valid = await AcademicCalendarFetchPort.shared.headValidate(urlString: chosen)
      if !valid {
        config.chosenSubCalendarURL = nil
        config.lastError = "Saved sub-calendar URL is no longer reachable."
        if fingerprint != nil {
          AcademicCalendarFingerprintCache.invalidate(schoolID: config.schoolID)
        }
      }
    }

    targetURL = selectedSubCalendarURL ?? config.chosenSubCalendarURL ?? config.url
    let deadline = Date().addingTimeInterval(importTimeoutSeconds)

    do {
      if selectedSubCalendarURL == nil,
         config.chosenSubCalendarURL == nil,
         let profileSnapshot,
         let termScope = termScope(from: config) {
        let navigator = AcademicCalendarHubNavigator(fetcher: AcademicCalendarFetchPort.shared)
        let navigation = await navigator.navigate(
          from: targetURL,
          profile: profileSnapshot,
          termScope: termScope,
          deadline: deadline
        )
        switch navigation {
        case .resolved(let url, _, _):
          targetURL = url
          config.chosenSubCalendarURL = url
        case .needsUserChoice(let candidates, _):
          AcademicCalendarFingerprintCache.storeHubCandidates(schoolID: config.schoolID, candidates: candidates)
          config.cachedHubCandidates = candidates
          config.hubCandidatesCachedAt = Date()
          config.importStatus = .needsChoice
          appendLog(config: config, reason: reason, path: .hub, result: .empty, error: "Hub picker required")
          let suggested = hubPickerNeutral
            ? nil
            : AcademicCalendarLinkResolver.bestMatch(
              candidates: candidates,
              profile: profileSnapshot,
              termScope: termScope
            )
          emitTelemetry(
            config: config,
            outcome: "needs_choice",
            margin: AcademicCalendarLinkResolver.confidenceMargin(
              candidates: candidates,
              profile: profileSnapshot,
              termScope: termScope
            ),
            hops: 0,
            started: started,
            source: config.discoverySource?.rawValue ?? "unknown"
          )
          return AcademicCalendarScrapeOutput(
            result: .empty,
            config: config,
            needsHubPicker: true,
            hubCandidates: candidates,
            contentUnchanged: false,
            suggestedHubURL: suggested,
            hubPickerNeutral: hubPickerNeutral
          )
        case .timedOut(let lastURL, _):
          targetURL = lastURL
          config.importStatus = .needsHelp
        case .failed(_, _):
          break
        }
      }

      let fetch = try await AcademicCalendarFetchPort.shared.fetch(
        urlString: targetURL,
        etag: config.etag
      )

      let newHash = fetch.content.isEmpty ? nil : AcademicCalendarFetcher.contentHash(fetch.content)
      if fetch.statusCode == 304 || (newHash != nil && newHash == config.lastContentHash) {
        let result = AcademicCalendarSyncResult.empty
        appendLog(config: config, reason: reason, path: .skippedUnchanged, result: result, error: nil)
        AcademicCalendarCircuitBreaker.recordSuccess(configID: config.configID)
        return AcademicCalendarScrapeOutput(
          result: result,
          config: config,
          needsHubPicker: false,
          hubCandidates: [],
          contentUnchanged: true,
          suggestedHubURL: nil,
          hubPickerNeutral: hubPickerNeutral
        )
      }

      if !fetch.content.isEmpty {
        config.etag = fetch.etag
        config.lastContentHash = AcademicCalendarFetcher.contentHash(fetch.content)
      }

      guard let baseURL = URL(string: targetURL) else {
        throw URLError(.badURL)
      }

      let classification = AcademicCalendarPageClassifier.classify(
        content: fetch.content,
        baseURL: baseURL,
        forcedMode: config.forcedMode
      )

      var parsed: [AcademicCalendarParsedEvent] = []
      var path: AcademicCalendarScrapePath = .scrape

      switch classification.kind {
      case .hasICSFeed:
        path = .ics
        if let feedURL = classification.icsFeedURL {
          parsed = try await importICS(feedURL: feedURL, config: config, subCalendarURL: targetURL)
        }
      case .indexHub:
        if selectedSubCalendarURL == nil && config.chosenSubCalendarURL == nil {
          let termScope = termScope(from: config)
          if AcademicCalendarLinkResolver.shouldAutoFollow(
            candidates: classification.subCalendars,
            profile: profileSnapshot,
            termScope: termScope
          ), let autoURL = AcademicCalendarLinkResolver.bestMatch(
            candidates: classification.subCalendars,
            profile: profileSnapshot,
            termScope: termScope
          ) {
            config.chosenSubCalendarURL = autoURL
            return await scrape(
              config: &config,
              reason: reason,
              calendarManager: calendarManager,
              selectedSubCalendarURL: autoURL,
              writeChanges: writeChanges,
              programProfile: profileSnapshot,
              hubPickerNeutral: hubPickerNeutral,
              userConfirmedURL: userConfirmedURL
            )
          }
          AcademicCalendarFingerprintCache.storeHubCandidates(schoolID: config.schoolID, candidates: classification.subCalendars)
          config.cachedHubCandidates = classification.subCalendars
          config.hubCandidatesCachedAt = Date()
          config.importStatus = .needsChoice
          appendLog(config: config, reason: reason, path: .hub, result: .empty, error: "Hub picker required")
          let suggested = hubPickerNeutral
            ? nil
            : AcademicCalendarLinkResolver.bestMatch(
              candidates: classification.subCalendars,
              profile: profileSnapshot,
              termScope: termScope
            )
          return AcademicCalendarScrapeOutput(
            result: .empty,
            config: config,
            needsHubPicker: true,
            hubCandidates: classification.subCalendars,
            contentUnchanged: false,
            suggestedHubURL: suggested,
            hubPickerNeutral: hubPickerNeutral
          )
        }
        path = .scrape
        parsed = await extractEvents(content: fetch.content, config: config, subCalendarURL: targetURL)
      case .calendar:
        path = .scrape
        parsed = await extractEvents(content: fetch.content, config: config, subCalendarURL: targetURL)
      }

      if shouldDiscardStaleSnapshot(config: config, fingerprint: fingerprint, profileSnapshot: profileSnapshot) {
        return AcademicCalendarScrapeOutput(
          result: .empty,
          config: config,
          needsHubPicker: false,
          hubCandidates: [],
          contentUnchanged: false,
          suggestedHubURL: nil,
          hubPickerNeutral: hubPickerNeutral
        )
      }

      if parsed.isEmpty {
        config.lastError = extractionFailureMessage(content: fetch.content)
      }

      parsed = AcademicCalendarEventParser.filterByImportedScopes(parsed, scopes: config.importedScopes)
      let activeScopes = Set(parsed.map(\.scopeKey))
      let extractionError = parsed.isEmpty ? config.lastError : nil

      if writeChanges,
         !userConfirmedURL,
         config.persistenceTier != .userConfirmed,
         shouldValidateBeforePersist(config: config, targetURL: targetURL),
         let profileSnapshot {
        let validation = await AcademicCalendarLinkValidator.validate(
          urlString: targetURL,
          config: config,
          profile: profileSnapshot,
          fetcher: AcademicCalendarFetchPort.shared
        )
        if !validation.isPassed {
          config.importStatus = .needsHelp
          config.lastError = validationFailureMessage(validation)
          AcademicCalendarCircuitBreaker.recordFailure(configID: config.configID)
          AcademicCalendarStore.upsertConfig(config)
          return AcademicCalendarScrapeOutput(
            result: AcademicCalendarSyncResult(
              scrapeID: scrapeID,
              added: 0,
              changed: 0,
              removed: 0,
              skipped: 0,
              moved: 0,
              changes: [],
              parsedEvents: parsed,
              path: path,
              error: config.lastError
            ),
            config: config,
            needsHubPicker: false,
            hubCandidates: [],
            contentUnchanged: false,
            suggestedHubURL: nil,
            hubPickerNeutral: hubPickerNeutral
          )
        }
        config.validatedAt = Date()
        config.persistenceTier = .validatedAuto
      }

      let result: AcademicCalendarSyncResult
      if writeChanges {
        result = await AcademicCalendarUpsertService.reconcile(
          config: config,
          incoming: parsed,
          scrapeID: scrapeID,
          activeScopeKeys: activeScopes
        )
      } else {
        result = AcademicCalendarSyncResult(
          scrapeID: scrapeID,
          added: 0,
          changed: 0,
          removed: 0,
          skipped: 0,
          moved: 0,
          changes: [],
          parsedEvents: parsed,
          path: path,
          error: extractionError
        )
      }

      var mutableResult = result
      mutableResult.path = path
      if let extractionError, parsed.isEmpty {
        mutableResult.error = extractionError
      }

      if !parsed.isEmpty {
        config.lastSuccessfulAt = Date()
        config.lastSuccessfulEventCount = parsed.count
        config.importStatus = .imported
        config.profileFingerprint = fingerprint
        if let chosen = config.chosenSubCalendarURL, let fingerprint {
          AcademicCalendarFingerprintCache.store(
            schoolID: config.schoolID,
            fingerprint: fingerprint,
            chosenSubCalendarURL: chosen,
            confidence: 1.0
          )
        }
        AcademicCalendarManifestExportQueue.enqueue(from: config)
        AcademicCalendarCircuitBreaker.recordSuccess(configID: config.configID)
      } else if mutableResult.error != nil {
        AcademicCalendarCircuitBreaker.recordFailure(configID: config.configID)
        config.importStatus = .needsAttention
      }

      config.lastError = mutableResult.error
      AcademicCalendarStore.upsertConfig(config)
      if let calendarManager {
        AcademicCalendarIntegration.registerCalendarIfNeeded(config: config, calendarManager: calendarManager)
      }
      AcademicCalendarIntegration.notifyConfigsDidChange()
      appendLog(config: config, reason: reason, path: path, result: mutableResult, error: mutableResult.error)
      emitTelemetry(
        config: config,
        outcome: mutableResult.error == nil ? "success" : "failed",
        margin: 0,
        hops: 0,
        started: started,
        source: config.discoverySource?.rawValue ?? "unknown"
      )

      return AcademicCalendarScrapeOutput(
        result: mutableResult,
        config: config,
        needsHubPicker: false,
        hubCandidates: [],
        contentUnchanged: false,
        suggestedHubURL: nil,
        hubPickerNeutral: hubPickerNeutral
      )
    } catch {
      config.lastError = error.localizedDescription
      config.importStatus = .needsAttention
      AcademicCalendarCircuitBreaker.recordFailure(configID: config.configID)
      AcademicCalendarStore.upsertConfig(config)
      let result = AcademicCalendarSyncResult(
        scrapeID: scrapeID,
        added: 0,
        changed: 0,
        removed: 0,
        skipped: 0,
        moved: 0,
        changes: [],
        parsedEvents: [],
        path: .scrape,
        error: error.localizedDescription
      )
      appendLog(config: config, reason: reason, path: .scrape, result: result, error: error.localizedDescription)
      emitTelemetry(
        config: config,
        outcome: "error",
        margin: 0,
        hops: 0,
        started: started,
        source: config.discoverySource?.rawValue ?? "unknown"
      )
      return AcademicCalendarScrapeOutput(
        result: result,
        config: config,
        needsHubPicker: false,
        hubCandidates: [],
        contentUnchanged: false,
        suggestedHubURL: nil,
        hubPickerNeutral: hubPickerNeutral
      )
    }
  }

  private static func shouldValidateBeforePersist(config: AcademicCalendarConfig, targetURL: String) -> Bool {
    if config.validatedAt == nil { return true }
    let validatedURL = config.chosenSubCalendarURL ?? config.url
    return validatedURL != targetURL
  }

  private static func shouldDiscardStaleSnapshot(
    config: AcademicCalendarConfig,
    fingerprint: String?,
    profileSnapshot: AcademicCalendarProgramProfile?
  ) -> Bool {
    guard let fingerprint, let profileSnapshot else { return false }
    let current = AcademicCalendarFingerprintCache.fingerprint(for: profileSnapshot, schoolID: config.schoolID)
    return current != fingerprint
  }

  private static func validationFailureMessage(_ result: AcademicCalendarLinkValidationResult) -> String {
    if case .rejected(let failure, let detail) = result {
      return "\(failure.rawValue): \(detail)"
    }
    return "Validation failed"
  }

  private static func emitTelemetry(
    config: AcademicCalendarConfig,
    outcome: String,
    margin: Int,
    hops: Int,
    started: Date,
    source: String
  ) {
    AcademicCalendarDiscoveryTelemetry.emit(
      AcademicCalendarDiscoveryTelemetryPayload(
        resolvedTier: config.persistenceTier?.rawValue ?? "ephemeral",
        resolverConfidenceMargin: margin,
        isOverrideNeeded: config.importStatus == .needsChoice,
        discoverySource: source,
        hopCount: hops,
        elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
        schoolID: config.schoolID,
        departmentKey: config.departmentKey,
        outcome: outcome
      )
    )
  }

  private static func extractEvents(
    content: String,
    config: AcademicCalendarConfig,
    subCalendarURL: String?
  ) async -> [AcademicCalendarParsedEvent] {
    let deterministic = AcademicCalendarDeterministicParser.parse(
      content: content,
      config: config,
      subCalendarURL: subCalendarURL
    )
    if deterministic.count >= 3 {
      return deterministic
    }

    let llmEvents = await AcademicCalendarLLMExtractor.extract(
      content: content,
      config: config,
      subCalendarURL: subCalendarURL
    )
    if !llmEvents.isEmpty {
      return llmEvents
    }
    return deterministic
  }

  private static func extractionFailureMessage(content: String) -> String {
    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "The page returned no readable content. Try a more specific calendar URL or switch Import mode to ICS Feed."
    }
    if !AcademicCalendarLLMExtractor.isAvailable {
      return "No term dates could be parsed from this page, and on-device AI is unavailable to extract them. Install the Assistant model in Settings, or paste a direct .ics feed URL under ICS Feed Subscriptions."
    }
    return "No term dates could be extracted from this page. Try a more specific calendar URL, switch Import mode to ICS Feed if the school publishes one, or pick a sub-calendar when prompted."
  }

  private static func importICS(
    feedURL: String,
    config: AcademicCalendarConfig,
    subCalendarURL: String?
  ) async throws -> [AcademicCalendarParsedEvent] {
    guard let url = URL(string: feedURL) else { throw URLError(.badURL) }
    let (data, _) = try await URLSession.shared.data(from: url)
    let events = try CalendarFeedParser.parse(data: data, urlString: feedURL)
    return AcademicCalendarEventParser.fromICS(events: events, config: config, subCalendarURL: subCalendarURL)
  }

  private static func termScope(from config: AcademicCalendarConfig) -> AcademicCalendarTermScope.Resolved? {
    guard let scope = config.importedScopes.first else { return nil }
    return AcademicCalendarTermScope.Resolved(
      term: scope.term,
      year: scope.year,
      label: "\(scope.term) \(scope.year)",
      level: scope.level
    )
  }

  private static func appendLog(
    config: AcademicCalendarConfig,
    reason: AcademicCalendarScrapeReason,
    path: AcademicCalendarScrapePath,
    result: AcademicCalendarSyncResult,
    error: String?
  ) {
    AcademicCalendarStore.appendScrapeLog(
      configID: config.configID,
      entry: AcademicCalendarScrapeLogEntry(
        id: UUID(),
        timestamp: Date(),
        reason: reason.rawValue,
        path: path,
        added: result.added,
        changed: result.changed,
        removed: result.removed,
        skipped: result.skipped,
        error: error
      )
    )
  }
}
