// AppleSiliconPlatform.swift
// Feature: Core
// Purpose: Core module — Report.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Metal

/// College is built and supported for **Apple Silicon Macs only** (arm64 + Apple GPU).
///
/// MLX (Gemma + sentence embedders) dispatches some kernels with **16×64×1 = 1024** threads per
/// threadgroup. GPUs that cap below that (e.g. many AMD/Intel discrete GPUs at **832**) trip
/// `MTLDebugComputeCommandEncoder` assertions in Debug builds.
enum AppleSiliconPlatform {
    /// Must match MLX's largest known threadgroup layout used by mlx-swift kernels.
    static let mlxRequiredThreadsPerThreadgroup = 1024

    struct Report: Sendable, Equatable {
        let isSupported: Bool
        let deviceName: String
        let maxThreadsPerThreadgroup: Int?
        let requirementMessage: String?
    }

    private nonisolated(unsafe) static var cachedReport: Report?

    static var report: Report {
        if let cachedReport { return cachedReport }
        let evaluated = evaluate()
        cachedReport = evaluated
        return evaluated
    }

    static var isSupported: Bool { report.isSupported }

    static var requirementMessage: String {
        report.requirementMessage
            ?? "College requires a Mac with Apple Silicon (M-series or later)."
    }

    static func evaluate() -> Report {
        #if !arch(arm64)
        return Report(
            isSupported: false,
            deviceName: "unsupported-architecture",
            maxThreadsPerThreadgroup: nil,
            requirementMessage: "This build is for Apple Silicon Macs only."
        )
        #else
        guard let device = MTLCreateSystemDefaultDevice() else {
            return Report(
                isSupported: false,
                deviceName: "none",
                maxThreadsPerThreadgroup: nil,
                requirementMessage: "No Metal GPU was found."
            )
        }

        let name = device.name
        guard device.supportsAnyAppleGPUFamily() else {
            return Report(
                isSupported: false,
                deviceName: name,
                maxThreadsPerThreadgroup: nil,
                requirementMessage:
                    "College requires an Apple Silicon Mac. The active GPU (\(name)) is not supported."
            )
        }

        let maxThreads = Self.measuredMaxThreadsPerThreadgroup(on: device)
        guard maxThreads >= mlxRequiredThreadsPerThreadgroup else {
            return Report(
                isSupported: false,
                deviceName: name,
                maxThreadsPerThreadgroup: maxThreads > 0 ? maxThreads : nil,
                requirementMessage:
                    "College requires an Apple Silicon Mac with a GPU that supports on-device AI. "
                    + "The active GPU (\(name)) reports a threadgroup limit of \(maxThreads > 0 ? "\(maxThreads)" : "unknown") "
                    + "but at least \(mlxRequiredThreadsPerThreadgroup) is required."
            )
        }

        return Report(
            isSupported: true,
            deviceName: name,
            maxThreadsPerThreadgroup: maxThreads,
            requirementMessage: nil
        )
        #endif
    }

    #if arch(arm64)
    private static func measuredMaxThreadsPerThreadgroup(on device: MTLDevice) -> Int {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void college_mlx_probe_kernel(uint gid [[thread_position_in_grid]]) {
            (void)gid;
        }
        """
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "college_mlx_probe_kernel") else {
                return 0
            }
            let pipeline = try device.makeComputePipelineState(function: function)
            return pipeline.maxTotalThreadsPerThreadgroup
        } catch {
            return 0
        }
    }
    #endif
}

private extension MTLDevice {
    func supportsAnyAppleGPUFamily() -> Bool {
        var families: [MTLGPUFamily] = [
            .apple1, .apple2, .apple3, .apple4, .apple5, .apple6, .apple7,
        ]
        if #available(macOS 14.0, *) {
            families.append(.apple8)
        }
        if #available(macOS 15.0, *) {
            families.append(.apple9)
        }
        return families.contains { supportsFamily($0) }
    }
}
