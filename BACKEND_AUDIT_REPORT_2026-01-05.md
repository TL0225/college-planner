# Backend Audit Report (College app)
Date: 2026-01-05

## Scope (what I reviewed)
This repo is a macOS SwiftUI app. “Backend” here means the non-UI layers that determine correctness/performance/scalability:
- Persistence: Core Data (`CoreDataManager.swift`)
- Catalog ingestion: ModernCampus scraping (`ModernCampusEngine.swift`, `UniversalCatalogScraper.swift`)
- Network services: GitHub data fetch (`GitHubDataService.swift`), AI catalog import (`CourseCatalogService.swift`)
- Intelligence/ML: prerequisite parsing (`IntelligenceService.swift`)
- Logging/diagnostics: `DebugLogger.swift`
- Dependency inventory via SwiftPM `Package.resolved`

I did not run a full profiling session (Instruments) in this pass; findings below are based on static inspection + known Core Data/Swift concurrency constraints.

## Executive summary
This is not production-ready yet for an App Store release, primarily due to:
- Threading and Core Data confinement risks (potential crashes/data corruption under load)
- Debug logging design that’s incompatible with sandboxed production environments
- Incomplete/placeholder “AI import” and “MLX model” paths that are currently unsafe to ship
- Excessive ungated `print()` logging in non-debug builds

The ModernCampus scraping engine has several solid performance practices already (URL cache, bounded connections, timeouts). With targeted fixes to Core Data usage and diagnostics/logging, the app can be made robust for large catalogs on-device.

If you mean “backend scalability” in the sense of *multi-user / cross-device / server-side scale*, this codebase currently has no server backend. You’ll need a real backend plan (CloudKit or your own API) to scale beyond a single device.

## Local-first security & privacy posture (priority)
You said this is intended to be **local-only**. In that world, the security/privacy bar is mostly about (a) minimizing data exposure *on device*, (b) preventing accidental exfiltration (logs/network), and (c) keeping the app resilient under concurrency.

### High-impact changes
1. **Remove/disable network features that aren’t required for local-only.**
  - `CourseCatalogService` calls a third-party AI API; this is incompatible with “local-only” unless explicitly enabled with clear consent.
  - Anything that sends catalog content off-device is a privacy risk and complicates App Review.
2. **Fix logging so it cannot leak data.**
  - Writing to Desktop and printing everything to stdout is a data-leak footgun.
  - Recommendation: debug-only logging + unified logging (see “Critical blockers”).
3. **Treat user-entered content and imported catalog content as sensitive.**
  - Avoid logging raw prerequisite strings, advisor emails, scraped HTML fragments, etc.
  - Make sure exported CSVs are explicitly user-initiated and clearly labeled.

### Data-at-rest expectations (macOS)
- Core Data stores are SQLite files in your container; macOS does not provide a built-in “encrypted Core Data store” toggle.
- Practical guidance for a local-first macOS app:
  - Keep secrets (tokens, API keys if ever reintroduced) in **Keychain**, not Core Data/UserDefaults.
  - Prefer storing documents in **Application Support** (you already do for Document Vault) rather than Desktop.
  - Assume disk encryption is provided by **FileVault** at the OS level; don’t invent your own crypto unless you must.

### Privacy checklist (local-first)
- Eliminate remote calls by default; if any remain, add:
  - explicit in-app toggle (“Enable online features”), default OFF
  - clear disclosure of what leaves device
- Ensure logs are opt-in and redact sensitive fields.
- Make sure there’s no analytics/telemetry unless explicitly enabled.

## Speed-ups for the current architecture (no new dependencies)
These are the biggest performance wins without adding packages:

### Core Data imports and large writes
- ~~Move heavy imports off the main thread using `newBackgroundContext()` **and** `context.perform { ... }`.~~
- ~~Use `NSBatchInsertRequest` for large catalog inserts when possible.~~
- ~~De-dupe upfront using in-memory maps (e.g., `[normalizedCourseCode: objectID]`) to avoid per-row fetches.~~
- ~~Save in chunks (e.g., every 250–1000 rows) and wrap chunks in `autoreleasepool {}` to reduce peak memory.~~
- ~~Add unique constraints in the `.xcdatamodeld` for `CourseCatalogEntity` (e.g., `university + normalizedCourseCode`) so duplicate imports don’t bloat the store.~~

### Queries and fetch performance
- ~~Use `fetchBatchSize` + `returnsObjectsAsFaults` for lists.~~
- ~~Use `propertiesToFetch` / dictionary fetches when you only need a few fields.~~
- ~~Avoid `first(where:)` loops over large arrays; build dictionaries/sets once.~~

### Regex performance
- Precompile your `NSRegularExpression` patterns once (static) instead of compiling on each call in `IntelligenceService`.

### Logging overhead
- Gate `print()` behind `#if DEBUG` or replace with `os.Logger` at appropriate log levels.
- Add signposts (via os.signpost) around imports/scrapes to make Instruments profiling actionable.

## Optional packages to consider (only if needed)
Given “security/privacy first,” the best packages are *fewer packages*. But if you need targeted gains:

1. **Swift Collections** (`OrderedSet`, better data structures)
  - Can simplify and speed up de-dupe/ordering logic in scrapers/imports.
2. **OSLog-based tooling (no extra package)**
  - Prefer `os.Logger` + signposts (built-in) rather than third-party logging.
3. **Encrypted local storage**
  - If you ever truly need encryption beyond FileVault, you’d be looking at SQLCipher-style solutions. This is a major tradeoff (complexity, perf, App Store review considerations). Only do this if you have a clear threat model requiring it.

## Dependency / package inventory (SwiftPM)
From `College.xcodeproj/.../Package.resolved`:
- `SwiftSoup` (used in `ModernCampusEngine.swift`, `UniversalCatalogScraper.swift`)
- `mlx-swift` (imported in `IntelligenceService.swift`, but model path is disabled/placeholder)
- `swift-atomics`, `swift-numerics` (transitive dependencies for MLX)
- `LRUCache` (pinned in `Package.resolved` but **not referenced anywhere in the code** and not present as an Xcode package reference in `project.pbxproj`)

### Recommendations
1. **Remove the unused `LRUCache` pin**.
   - It increases supply-chain surface area and can confuse reproducible builds.
   - If you previously used it, re-add intentionally when you reintroduce caching.
2. **Decide whether `mlx-swift` ships in beta**.
   - Right now the LLM path is disabled and `IntelligenceService` contains hard-coded local filesystem paths.
   - Options:
     - Remove MLX until it’s actually used, OR
     - Fully implement model loading in a sandbox-safe way (bundle model or user-selected folder) and add resource/memory safeguards.

## Critical blockers (must fix before “production ready”)

### 1) Debug logging is not sandbox/production safe
File: `College/DebugLogger.swift`

Observed:
- Writes logs directly to the user Desktop (`.desktopDirectory`) and clears the log on launch.
- No size cap; log can grow unbounded.
- Always prints to stdout (`print(logMessage, terminator: "")`) regardless of build configuration.
- Declares `@unchecked Sendable` while having mutable shared state (`didWriteSessionMarker`) accessed across threads without synchronization.

Why it matters:
- Sandboxed macOS apps generally cannot write arbitrary files to Desktop without user interaction/permissions.
- Unbounded file + console logging can become a real performance problem and can leak user data.
- `@unchecked Sendable` can hide real data races.

Recommendation:
- Make logging **build-gated** (`#if DEBUG`) or behind a runtime “Enable diagnostics” toggle.
- Store logs under Application Support or Caches (not Desktop), and implement log rotation / size cap.
- Replace with unified logging (`os.Logger`) for production builds.
- If you keep a custom logger: make it an `actor` or fully thread-safe; remove `@unchecked Sendable`.

### 2) Core Data thread confinement violations (crash risk)
Files: `College/CourseCatalogService.swift`, `College/CoreDataManager.swift`

Observed:
- `CourseCatalogService` uses `coreDataManager.viewContext` directly from async functions without guaranteeing MainActor access.
  - `viewContext` is main-queue constrained; touching it off-main can crash.
- `CoreDataManager.processComplexPrerequisitesInBackground` creates a background context but uses it without `context.perform { ... }`.
  - A background context is a private queue context; you must access it only inside `perform`/`performAndWait`.

Why it matters:
- Under load (big catalogs, user clicks around), these become intermittent crashes that are hard to reproduce.

Recommendation:
- Adopt a consistent Core Data pattern:
  - UI reads via `viewContext` on MainActor
  - Writes/imports in `newBackgroundContext()` with `context.perform { ... }`
  - Merge via `automaticallyMergesChangesFromParent` (you already set this)
- For imports of thousands of rows, use:
  - `NSBatchInsertRequest` (fastest)
  - Or chunked inserts with periodic saves + `autoreleasepool {}` to control memory
- Add unique constraints (in the model) + merge policies so re-import doesn’t create duplicates.

### 3) “AI catalog import” path is not shippable as-is
File: `College/CourseCatalogService.swift`

Observed:
- Sends up to 100,000 chars of catalog HTML to Anthropic per request.
- No retry/backoff, no HTTP status checking, no response validation.
- Stores courses by always creating new `CourseCatalogEntity` objects (no dedupe → duplicates each import).
- API key handling is a placeholder (`apiKey: String = ""`);
  real apps must not hardcode keys and must treat third-party API usage as privacy-sensitive.

Why it matters:
- Cost/perf: this will be slow and expensive; token limits may fail unpredictably.
- Privacy/App Review: sending potentially user-derived content or browsing results to a third party needs clear disclosure and user consent.
- Data integrity: duplicate courses will bloat the DB, slow searches/exports, and confuse users.

Recommendation:
- Either disable this feature entirely for beta builds, or harden it:
  - Strict request timeouts + retries with exponential backoff
  - HTTP status code handling + structured errors
  - Stream/chunk parsing rather than shipping full HTML into one prompt
  - Dedupe by (universityID, normalized courseCode)
  - Provide a privacy notice + a per-feature consent gate

### 4) ML model path and behavior are not production safe
File: `College/IntelligenceService.swift`

Observed:
- Uses a hard-coded absolute local path: `/Users/timothy/Desktop/College/Models/...`
- LLM parsing function currently throws `modelNotLoaded` for every request.
- Yet other parts of the system queue items as `pending_llm`.

Why it matters:
- Hard-coded paths will break on every other machine.
- Features appear “implemented” but won’t work reliably.

Recommendation:
- If LLM parsing is not ready: remove `pending_llm` behavior or gate it behind a feature flag.
- If it is ready: implement model discovery and storage properly:
  - Bundle model (if allowed) or download into Application Support
  - Provide user-visible storage controls
  - Add memory/cpu budget safeguards and cancelation.

## High-priority performance issues

### A) Main-thread work during large imports
Files: `College/CoreDataManager.swift`, `College/CourseCatalogService.swift`

Risk:
- Large loops doing fetches/inserts and repeated `context.fetch` inside loops will block UI.

Recommendation:
- ~~Move imports to background contexts.~~
- ~~Avoid per-row fetches. Build dictionaries/sets once.~~
- ~~Save in batches (e.g., every 250–1000 rows).~~

### B) O(n^2) lookup patterns
File: `College/CoreDataManager.swift` (ghost course archiving section)

Observed:
- `existingCourses.first(where:)` repeated inside a loop over ghost codes.

Recommendation:
- ~~Build a `[String: CourseCatalogEntity]` dictionary keyed by course code to make this O(n).~~

### C) Ungated verbose logging
Files: multiple (`CoreDataManager.swift`, `IntelligenceService.swift`, `CourseCatalogService.swift`)

Recommendation:
- Replace `print()` with unified logging and gate debug-level logs.

## Things that are already good (keep them)

### ModernCampusEngine: sensible networking defaults
File: `College/ModernCampusEngine.swift`

Observed:
- Uses a tuned `URLSession` with cache, timeouts, bounded connections.
- Bounded concurrency via an async semaphore to avoid request storms.
- Adds a custom `User-Agent`.

Recommendation:
- Keep this approach.
- Consider adding per-host rate limiting / crawl delay if you see throttling.

### GitHubDataService: explicit fallback + local cache
File: `College/GitHubDataService.swift`

Observed:
- Uses fallback host when raw domain is blocked.
- Includes a basic 7-day TTL cache.

Recommendation:
- Consider adding ETag/If-None-Match support for better bandwidth efficiency.

## App Review / “Apple certified” readiness notes
No third-party app is “Apple certified” in the way you phrased it; Apple reviews submitted builds. Based on this code state, I would expect App Review / production readiness issues unless addressed:
- Desktop file writes for logging (sandbox)
- Third-party AI calls without privacy disclosures/consent controls
- Hard-coded local filesystem paths
- Potential crashes from Core Data thread confinement issues

If your goal is “something Apple/Google would ship,” the bar is:
- Predictable performance under large data
- No debug artifacts in release
- Clear privacy story, data minimization, and safe networking
- Strong correctness under concurrency

## Scalability: what this app can handle today

### On-device scalability (single user)
With fixes above, the architecture can handle:
- Universities with thousands to tens-of-thousands of courses
- Periodic scraping/import

The largest risks are DB bloat from duplicates, and UI freezes/crashes from Core Data threading.

### Multi-user / cross-device scalability
The app has no shared backend. If you want real “scalable backend”:
- Option 1: **CloudKit** (fastest path for Apple ecosystem; built-in auth and sync)
- Option 2: Your own API + DB (Postgres + a service layer), with:
  - Auth (Sign in with Apple)
  - Rate limiting
  - Background jobs for scraping
  - Caching/CDN for catalog content
  - Observability (metrics/tracing)

## Concrete next steps (recommended order)
1. Fix/replace `DebugLogger` for production safety.
2. Fix Core Data confinement everywhere (CourseCatalogService + CoreDataManager background context usage).
3. Add dedupe + unique constraints for catalog entities.
4. Gate/disable incomplete MLX + AI features for beta, or harden them fully.
5. Add Instruments profiling pass:
   - Time Profiler during import
   - Core Data fetches
   - Network requests during scraping
6. Add regression tests for:
   - No duplicate courses after repeated imports
   - Background import does not touch viewContext off-main

## Notes / minor cleanup
- ~~Swift 6 warning observed in `ModernCampusEngine.swift` about actor isolation for `parseProgramHTML(...)` calls. It should be resolved before switching to Swift 6 language mode.~~

