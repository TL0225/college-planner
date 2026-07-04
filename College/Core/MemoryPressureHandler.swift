// MemoryPressureHandler.swift
// Feature: Core
// Purpose: Core module — MemoryPressureHandler.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Dispatch

/// Observes system memory and thermal pressure and runs cleanup hooks.
@MainActor
final class MemoryPressureHandler {
    static let shared = MemoryPressureHandler()

    private var observers: [NSObjectProtocol] = []
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var didInstall = false

    private(set) var lastMemoryPressureEventAt: Date?
    private(set) var lastMemoryPressureEventKind: String?

    private init() {}

    func startIfNeeded() {
        guard !didInstall else { return }
        didInstall = true

        let center = NotificationCenter.default
        let processInfo = ProcessInfo.processInfo

        observers.append(
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: processInfo,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleThermalChange()
                }
            }
        )

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let data = source.data
            if data.contains(.critical) {
                Task { @MainActor in
                    self?.handleCriticalMemoryPressure()
                }
            } else if data.contains(.warning) {
                Task { @MainActor in
                    self?.handleWarningMemoryPressure()
                }
            }
        }
        source.resume()
        memoryPressureSource = source

        handleThermalChange()
    }

    private func handleThermalChange() {
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal == .critical || thermal == .serious else { return }
        recordMemoryPressureEvent("thermal(\(thermal.rawValue))")
        clearCatalogCaches(reason: "thermal(\(thermal.rawValue))")
        if thermal == .serious {
            CatalogEmbedMemoryLifecycle.shared.releaseNow()
        }
        if thermal == .critical {
            LLMMemoryLifecycle.shared.releaseNow()
            CatalogEmbedMemoryLifecycle.shared.releaseNow()
            AppDataStore.shared.releaseActiveCatalogContainerForMemoryPressure()
        }
    }

    private func handleWarningMemoryPressure() {
        recordMemoryPressureEvent("memoryPressure.warning")
        clearCatalogCaches(reason: "memoryPressure.warning")
        CatalogEmbedMemoryLifecycle.shared.releaseNow()
    }

    private func handleCriticalMemoryPressure() {
        recordMemoryPressureEvent("memoryPressure.critical")
        clearCatalogCaches(reason: "memoryPressure.critical")
        LLMMemoryLifecycle.shared.releaseNow()
        CatalogEmbedMemoryLifecycle.shared.releaseNow()
        AppDataStore.shared.releaseActiveCatalogContainerForMemoryPressure()
    }

    private func recordMemoryPressureEvent(_ kind: String) {
        lastMemoryPressureEventAt = Date()
        lastMemoryPressureEventKind = kind
        DiagnosticsEvent.emit(
            subsystem: .memory,
            severity: .warning,
            code: "MEMORY_PRESSURE_WARNING",
            message: "Memory pressure event: \(kind)."
        )
    }

    private func clearCatalogCaches(reason: String) {
        ModernCampusEngine.clearAllCourseCachesForMemoryPressure()
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        // Unload every background shortcut page (keeps the active one); their DOM/JS heaps
        // are reclaimed and the pages reload from their last URL when revisited.
        WebShortcutCoordinatorPool.sleepInactiveForMemoryPressure()
        // Free reclaimable HTTP/disk/memory caches while preserving cookies (LMS logins).
        WebShortcutCoordinatorPool.purgeTransientWebCaches()
        CatalogRenderedHTMLFetcher.shared.releaseWebViewForMemoryPressure()
        WebScraperService.releaseAllWebViewsForMemoryPressure()
        Task { await AssistantWebPageCache.shared.evictAllForMemoryPressure() }
        TranslationCache.shared.evictAll()
        VaultThumbnailCache.shared.evictAll()
        FaviconStore.shared.evictMemoryCache()
        DebugLogger.shared.log(
            "MemoryPressureHandler: cleared catalog course caches (\(reason))",
            category: .system,
            level: .info
        )
    }
}
