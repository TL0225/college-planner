// RuntimeTelemetryMonitor.swift
// Feature: Debug
// Purpose: Debug module — RuntimeTelemetryMonitor.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Darwin.Mach

/// Runtime diagnostics stream for deep pre-crash and pre-hang visibility.
///
/// Emits periodic heartbeat entries into `AppLogger` and tracks basic service
/// state transitions so log timelines show what was running right before a
/// freeze or abrupt termination.
actor RuntimeTelemetryMonitor {
    static let shared = RuntimeTelemetryMonitor()

    static let enabledKey = "diagnostics.runtimeTelemetryEnabled"
    static let heartbeatIntervalKey = "diagnostics.runtimeHeartbeatIntervalSeconds"
    static let stallThresholdKey = "diagnostics.mainThreadStallThresholdSeconds"

    private static let timerQueue = DispatchQueue(label: "com.college.runtime-telemetry", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var sequence: UInt64 = 0
    private var lastMainThreadAckUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var currentlyStalled: Bool = false
    private var serviceStates: [String: String] = [:]

    private init() {}

    nonisolated func startIfNeeded() {
        Task { self.reconfigure() }
    }

    nonisolated func reconfigure() {
        Task { await self._reconfigure() }
    }

    nonisolated func markServiceState(_ name: String, state: String) {
        Task { await self._markServiceState(name: name, state: state) }
    }

    private func _reconfigure() {
        let enabled = Self.isEnabled
        if enabled {
            startTimerIfNeeded()
            AppLogger.shared.info(
                "runtime.telemetry.enabled",
                category: .runtime,
                metadata: [
                    "heartbeat_interval_s": "\(Self.heartbeatIntervalSeconds)",
                    "stall_threshold_s": "\(Self.stallThresholdSeconds)"
                ]
            )
        } else {
            stopTimer()
            AppLogger.shared.info("runtime.telemetry.disabled", category: .runtime)
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: Self.timerQueue)
        source.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.handleTick() }
        }
        source.activate()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        currentlyStalled = false
    }

    private func _markServiceState(name: String, state: String) {
        let key = sanitizeServiceName(name)
        serviceStates[key] = state
        AppLogger.shared.info(
            "runtime.service_state",
            category: .runtime,
            metadata: [
                "service": key,
                "state": state
            ]
        )
    }

    private func handleTick() async {
        guard Self.isEnabled else {
            stopTimer()
            return
        }

        // Ask the main thread to acknowledge liveness. If it stops acking,
        // the background timer still runs and records a stall.
        DispatchQueue.main.async {
            Task { await RuntimeTelemetryMonitor.shared.recordMainThreadAck() }
        }

        let nowUptime = ProcessInfo.processInfo.systemUptime
        let lagSeconds = max(0, nowUptime - lastMainThreadAckUptime)
        let stallThreshold = Double(Self.stallThresholdSeconds)

        if lagSeconds >= stallThreshold {
            let rounded = Int(lagSeconds.rounded())
            if !currentlyStalled {
                currentlyStalled = true
                AppLogger.shared.fault(
                    "runtime.main_thread_stall_detected",
                    category: .runtime,
                    metadata: [
                        "lag_s": "\(rounded)",
                        "threshold_s": "\(Self.stallThresholdSeconds)"
                    ]
                )
                DiagnosticsEvent.emit(
                    subsystem: .runtime,
                    severity: .warning,
                    code: "HANG_DETECTED",
                    message: "Main thread was unresponsive for about \(rounded) seconds."
                )
            } else {
                AppLogger.shared.warn(
                    "runtime.main_thread_stall_continues",
                    category: .runtime,
                    metadata: [
                        "lag_s": "\(rounded)",
                        "threshold_s": "\(Self.stallThresholdSeconds)"
                    ]
                )
            }
        } else if currentlyStalled {
            currentlyStalled = false
            AppLogger.shared.info(
                "runtime.main_thread_recovered",
                category: .runtime,
                metadata: [
                    "lag_s": String(format: "%.2f", lagSeconds)
                ]
            )
        }

        sequence &+= 1
        let every = max(1, Self.heartbeatIntervalSeconds)
        guard sequence % UInt64(every) == 0 else { return }

        var metadata: [String: String] = [
            "seq": "\(sequence)",
            "uptime_s": String(format: "%.1f", nowUptime),
            "cpu_pct": String(format: "%.1f", Self.currentProcessCPUPercent()),
            "memory_mb": String(format: "%.1f", Self.currentProcessMemoryMB()),
            "main_lag_s": String(format: "%.2f", lagSeconds)
        ]

        let serviceSnapshot = await MainActor.run { Self.captureMainActorServiceSnapshot() }
        for (k, v) in serviceSnapshot {
            metadata[k] = v
        }
        for (name, state) in serviceStates {
            metadata["service.\(name)"] = state
        }

        AppLogger.shared.info(
            "runtime.heartbeat",
            category: .runtime,
            metadata: metadata
        )
    }

    private func recordMainThreadAck() {
        lastMainThreadAckUptime = ProcessInfo.processInfo.systemUptime
    }

    /// Seconds since the main thread last acknowledged the telemetry heartbeat.
    func mainThreadLagSeconds() -> Double {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        return max(0, nowUptime - lastMainThreadAckUptime)
    }

    /// Stall threshold in milliseconds (matches `stallThresholdKey` defaults).
    static var mainThreadStallThresholdMs: Int {
        stallThresholdSeconds * 1000
    }

    private static var isEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: enabledKey) as? Bool {
            return value
        }
        return true
    }

    private static var heartbeatIntervalSeconds: Int {
        let value = UserDefaults.standard.integer(forKey: heartbeatIntervalKey)
        if value == 0 {
            #if DEBUG
            return 1
            #else
            return 10
            #endif
        }
        return max(1, value)
    }

    private static var stallThresholdSeconds: Int {
        let value = UserDefaults.standard.integer(forKey: stallThresholdKey)
        return max(2, value == 0 ? 3 : value)
    }

    @MainActor
    private static func captureMainActorServiceSnapshot() -> [String: String] {
        [
            "app.is_active": AppActivityCoordinator.shared.isAppActive ? "true" : "false",
            "app.is_throttled": AppActivityCoordinator.shared.isResourceThrottled ? "true" : "false",
            "service.fs_watchdog": FSWatchdogService.shared.isWatching ? "running" : "stopped",
            "service.stale_file_monitor": StaleFileMonitor.shared.isMonitoring ? "running" : "stopped",
            "service.screenshot_triage": VaultScreenshotTriage.shared.isDailyScanScheduled ? "running" : "stopped"
        ]
    }

    private func sanitizeServiceName(_ raw: String) -> String {
        let lower = raw.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(lower.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private static func currentProcessMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    private static func currentProcessCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let task = mach_task_self_
        let kerr = task_threads(task, &threadList, &threadCount)
        guard kerr == KERN_SUCCESS, let threadList else { return 0 }
        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(task, vm_address_t(bitPattern: threadList), size)
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

            let kerr2: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { intPtr in
                    thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &infoCount)
                }
            }
            guard kerr2 == KERN_SUCCESS else { continue }
            if (info.flags & TH_FLAGS_IDLE) != 0 { continue }

            totalUsage += (Double(info.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
        }

        return totalUsage
    }
}