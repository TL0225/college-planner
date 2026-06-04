// PerformanceMonitor.swift
// Feature: Debug
// Purpose: Debug module — PerformanceMonitor.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Combine
import Darwin.Mach
import Observation

/// Lightweight, live CPU + memory monitor for the current process.
///
/// Intended for in-app diagnostics UI (not persistent logging).
@Observable
@MainActor
final class PerformanceMonitor {
    private(set) var cpuPercent: Double = 0
    private(set) var memoryMB: Double = 0

    private var timerCancellable: AnyCancellable?

    func start(interval: TimeInterval = 1.0) {
        stop()
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.cpuPercent = Self.currentProcessCPUPercent()
                self.memoryMB = Self.currentProcessMemoryMB()
            }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
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
            // Deallocate thread list.
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
