// AppleSiliconPlatform.swift
// Feature: Core
// Purpose: Core module — Report.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Metal

/// College targets **Apple Silicon Macs only** (arm64 + Apple GPU, unified memory).
enum AppleSiliconPlatform {
    /// MLX kernels used by mlx-swift embedders dispatch **16×64×1 = 1024** threads per threadgroup.
    static let mlxRequiredThreadsPerThreadgroup = 1024

    private static let mlxRuntimeDisabledKey = "platform.mlx.runtimeDisabled.v1"

    struct Report: Sendable, Equatable {
        /// arm64 Mac with an Apple GPU — the app shell can launch.
        let isSupported: Bool
        /// GPU can run MLX Metal kernels (1024-thread layouts used by mlx-swift).
        let isMLXCompatible: Bool
        let deviceName: String
        let maxThreadsPerThreadgroup: Int?
        let requirementMessage: String?
        let mlxRequirementMessage: String?
    }

    private nonisolated(unsafe) static var cachedReport: Report?

    static var report: Report {
        if let cachedReport { return cachedReport }
        let evaluated = evaluate()
        cachedReport = evaluated
        return evaluated
    }

    static var isSupported: Bool { report.isSupported }

    static var isMLXCompatible: Bool {
        guard !UserDefaults.standard.bool(forKey: mlxRuntimeDisabledKey) else { return false }
        return report.isMLXCompatible
    }

    static var requirementMessage: String {
        report.requirementMessage
            ?? "College requires a Mac with Apple Silicon (M-series or later)."
    }

    static var mlxRequirementMessage: String {
        report.mlxRequirementMessage
            ?? "This Mac's GPU cannot run College's on-device MLX models. Turn on Apple Intelligence or use a Mac with a higher Metal threadgroup limit."
    }

    /// Best-effort latch when MLX throws at runtime (Metal debug asserts cannot be caught).
    static func noteMLXRuntimeFailure() {
        UserDefaults.standard.set(true, forKey: mlxRuntimeDisabledKey)
        cachedReport = nil
    }

    static func evaluate() -> Report {
        #if !arch(arm64)
        return Report(
            isSupported: false,
            isMLXCompatible: false,
            deviceName: "unsupported-architecture",
            maxThreadsPerThreadgroup: nil,
            requirementMessage: "This build is for Apple Silicon Macs only.",
            mlxRequirementMessage: nil
        )
        #else
        guard let device = MTLCreateSystemDefaultDevice() else {
            return Report(
                isSupported: false,
                isMLXCompatible: false,
                deviceName: "none",
                maxThreadsPerThreadgroup: nil,
                requirementMessage: "No Metal GPU was found.",
                mlxRequirementMessage: nil
            )
        }

        let name = device.name
        guard device.supportsAnyAppleGPUFamily() else {
            return Report(
                isSupported: false,
                isMLXCompatible: false,
                deviceName: name,
                maxThreadsPerThreadgroup: nil,
                requirementMessage:
                    "College requires an Apple Silicon Mac. The active GPU (\(name)) is not supported.",
                mlxRequirementMessage: nil
            )
        }

        let maxThreads = measuredMaxThreadsPerThreadgroup(on: device)
        let mlxCompatible = maxThreads >= mlxRequiredThreadsPerThreadgroup
        let mlxMessage: String? = mlxCompatible
            ? nil
            : "The GPU (\(name)) reports a Metal threadgroup limit of \(maxThreads > 0 ? "\(maxThreads)" : "unknown") "
                + "but on-device MLX requires at least \(mlxRequiredThreadsPerThreadgroup). "
                + "Turn on Apple Intelligence in System Settings, or use deterministic assistant tools without the local Qwen model."

        return Report(
            isSupported: true,
            isMLXCompatible: mlxCompatible,
            deviceName: name,
            maxThreadsPerThreadgroup: maxThreads > 0 ? maxThreads : nil,
            requirementMessage: nil,
            mlxRequirementMessage: mlxMessage
        )
        #endif
    }

    #if arch(arm64)
    private static func measuredMaxThreadsPerThreadgroup(on device: MTLDevice) -> Int {
        let perDimension = device.maxThreadsPerThreadgroup
        guard mlxLayoutFitsPerDimensionLimits(perDimension) else { return 0 }

        var caps: [Int] = []
        if let trivial = pipelineThreadgroupCapacity(on: device, scratchFloats: 0) {
            caps.append(trivial)
        }
        for scratch in [256, 512, 768, 1024] {
            if let cap = pipelineThreadgroupCapacity(on: device, scratchFloats: scratch) {
                caps.append(cap)
            }
        }
        return caps.min() ?? 0
    }

    private static func mlxLayoutFitsPerDimensionLimits(_ limits: MTLSize) -> Bool {
        16 <= limits.width && 64 <= limits.height && 1 <= limits.depth
    }

    private static func pipelineThreadgroupCapacity(on device: MTLDevice, scratchFloats: Int) -> Int? {
        let scratchDecl: String
        let body: String
        if scratchFloats > 0 {
            scratchDecl = "threadgroup float scratch[\(scratchFloats)];"
            body = """
                uint idx = gid.x + gid.y * tptg.x;
                scratch[idx % \(scratchFloats)] = 0;
                threadgroup_barrier(mem_flags::mem_threadgroup);
                if (gid.x == 0 && gid.y == 0) { out[0] = scratch[0]; }
            """
        } else {
            scratchDecl = ""
            body = "(void)gid;"
        }

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void college_mlx_probe_kernel(
            device float* out [[buffer(0)]],
            uint2 gid [[thread_position_in_threadgroup]],
            uint2 tptg [[threads_per_threadgroup]]
        ) {
            \(scratchDecl)
            \(body)
        }
        """
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "college_mlx_probe_kernel") else {
                return nil
            }
            let pipeline = try device.makeComputePipelineState(function: function)
            return pipeline.maxTotalThreadsPerThreadgroup
        } catch {
            return nil
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
