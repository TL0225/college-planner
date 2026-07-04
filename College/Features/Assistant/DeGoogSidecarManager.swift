// DeGoogSidecarManager.swift
// Feature: Assistant
// Purpose: Start, health-check, and stop the bundled local DeGoog runtime.

import Darwin
import Foundation

enum DeGoogSidecarError: LocalizedError, Equatable {
  case bundleMissing
  case portUnavailable
  case startupTimedOut(String)
  case processLaunchFailed(String)
  case processExited(Int32, String)

  var errorDescription: String? {
    switch self {
    case .bundleMissing:
      return "Built-in web search runtime is missing from the app bundle. Quit College, rebuild in Xcode (Product → Build), then try again. When building from source, run scripts/fetch-degoog-sidecar.sh once if needed."
    case .portUnavailable:
      return "Web search could not bind a local port on 127.0.0.1."
    case .startupTimedOut(let detail):
      if detail.isEmpty {
        return "Web search did not become ready in time."
      }
      return "Web search did not become ready in time. \(detail)"
    case .processLaunchFailed(let message):
      return "Web search could not start: \(message)"
    case .processExited(let code, let stderr):
      if stderr.isEmpty {
        return "Web search process exited unexpectedly (status \(code))."
      }
      return "Web search process exited (status \(code)): \(stderr)"
    }
  }

  static func == (lhs: DeGoogSidecarError, rhs: DeGoogSidecarError) -> Bool {
    switch (lhs, rhs) {
    case (.bundleMissing, .bundleMissing),
      (.portUnavailable, .portUnavailable):
      return true
    case (.startupTimedOut(let a), .startupTimedOut(let b)):
      return a == b
    case (.processLaunchFailed(let a), .processLaunchFailed(let b)):
      return a == b
    case (.processExited(let c1, let s1), .processExited(let c2, let s2)):
      return c1 == c2 && s1 == s2
    default:
      return false
    }
  }
}

actor DeGoogSidecarManager {
  static let shared = DeGoogSidecarManager()

  private var process: Process?
  private var activePort: Int = CollegeWebSearchDefaults.port
  private var launchTask: Task<Void, Error>?

  func resolvedBaseURL() async throws -> URL {
    if let custom = AssistantWebSearchSettings.normalizedCustomBaseURL() {
      return custom
    }
    guard AssistantWebSearchSettings.isWebSearchEnabled else {
      throw DeGoogSearchClientError.disabled
    }
    if CollegeTestRuntime.isUnitTestProcess, !UITestLaunchFlags.forcesMainUI {
      throw DeGoogSearchClientError.sidecarUnavailable
    }
    try await ensureRunning()
    return CollegeWebSearchDefaults.localBaseURL(port: activePort)
  }

  func ensureRunning() async throws {
    try await BackgroundServiceOnDemand.runThrowing(id: "degoog_sidecar") {
      try await DeGoogSidecarManager.shared.ensureRunningImpl()
    }
  }

  private func ensureRunningImpl() async throws {
    if let launchTask {
      try await launchTask.value
      return
    }
    if await isHealthy(port: activePort) {
      return
    }
    let task = Task {
      try await self.startIfNeeded()
    }
    launchTask = task
    defer { launchTask = nil }
    try await task.value
  }

  func stopIfRunning() {
    guard let process else { return }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    self.process = nil
  }

  // MARK: - Private

  private func startIfNeeded() async throws {
    if await isHealthy(port: activePort) { return }

    let runtimeRoot = Self.stagedRuntimeRoot()
    guard let bunExecutable = Self.bunExecutable() else {
      Self.log("bun helper missing from app bundle")
      throw DeGoogSidecarError.bundleMissing
    }

    try Self.stageRuntimeIfNeeded(to: runtimeRoot)

    let dataDir = Self.applicationSupportDataDirectory()
    try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

    var chosenPort: Int?
    for offset in 0...CollegeWebSearchDefaults.portFallbackSpan {
      let candidate = CollegeWebSearchDefaults.port + offset
      if await isHealthy(port: candidate) {
        activePort = candidate
        Self.log("reusing healthy DeGoog on port \(candidate)")
        return
      }
      if Self.isPortFree(candidate) {
        chosenPort = candidate
        break
      }
    }
    guard let port = chosenPort else { throw DeGoogSidecarError.portUnavailable }

    let scriptPath = runtimeRoot.appendingPathComponent("src/server/index.ts").path
    let launchCWD = Self.sidecarSupportRoot()
    let fm = FileManager.default
    Self.log(
      "launching DeGoog bun=\(bunExecutable.path) script=\(scriptPath) cwd=\(launchCWD.path) " +
      "cwdExists=\(fm.fileExists(atPath: launchCWD.path)) scriptExists=\(fm.fileExists(atPath: scriptPath)) port=\(port)"
    )

    let proc = Process()
    proc.executableURL = bunExecutable
    proc.arguments = ["run", scriptPath]
    proc.currentDirectoryURL = launchCWD

    var environment = ProcessInfo.processInfo.environment
    environment["DEGOOG_PORT"] = String(port)
    environment["DEGOOG_DATA_DIR"] = dataDir.path
    environment["DEGOOG_WIZARD"] = "false"
    environment["NO_COLOR"] = "1"
    environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    proc.environment = environment

    let stderrPipe = Pipe()
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = stderrPipe

    do {
      try proc.run()
    } catch {
      let message = error.localizedDescription
      Self.log("Process.run failed: \(message)")
      throw DeGoogSidecarError.processLaunchFailed(message)
    }
    process = proc
    activePort = port

    let deadline = Date().addingTimeInterval(90)
    while Date() < deadline {
      if !proc.isRunning {
        let status = proc.terminationStatus
        let errText = Self.drainPipe(stderrPipe)
        self.process = nil
        Self.log("DeGoog exited early status=\(status) stderr=\(errText)")
        throw DeGoogSidecarError.processExited(status, errText)
      }
      if await isHealthy(port: port) {
        Self.log("DeGoog ready on port \(port)")
        return
      }
      try await Task.sleep(nanoseconds: 500_000_000)
    }

    let tail = Self.drainPipe(stderrPipe)
    proc.terminate()
    self.process = nil
    Self.log("DeGoog startup timed out stderr=\(tail)")
    throw DeGoogSidecarError.startupTimedOut(tail)
  }

  private func isHealthy(port: Int) async -> Bool {
    let url = CollegeWebSearchDefaults.localBaseURL(port: port)
      .appendingPathComponent("readyz")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 2
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
      guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["ok"] as? Bool == true
      else { return false }
      return true
    } catch {
      return false
    }
  }

  private static func bunExecutable() -> URL? {
    let helper = Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/college-degoog-bun", isDirectory: false)
    if FileManager.default.isExecutableFile(atPath: helper.path) {
      return helper
    }
    let resourceCandidates: [URL?] = [
      Bundle.main.url(forResource: "college-degoog-bun", withExtension: nil),
      Bundle.main.resourceURL?.appendingPathComponent("college-degoog-bun", isDirectory: false),
    ]
    for url in resourceCandidates.compactMap({ $0 }) where FileManager.default.isExecutableFile(atPath: url.path) {
      return url
    }
    return nil
  }

  private static func bundledRuntimeArchive() -> URL? {
    let candidates: [URL?] = [
      Bundle.main.url(forResource: "college-degoog-runtime", withExtension: "tar.gz"),
      Bundle.main.resourceURL?.appendingPathComponent("college-degoog-runtime.tar.gz", isDirectory: false),
    ]
    for url in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
      return url
    }
    return nil
  }

  private static func bundledRuntimeVersion() -> String {
    let candidates: [URL?] = [
      Bundle.main.url(forResource: "college-degoog-VERSION", withExtension: nil),
      Bundle.main.resourceURL?.appendingPathComponent("college-degoog-VERSION", isDirectory: false),
    ]
    for url in candidates.compactMap({ $0 }) {
      if let raw = try? String(contentsOf: url, encoding: .utf8) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return "0"
  }

  private static func sidecarSupportRoot() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return support
      .appendingPathComponent("College", isDirectory: true)
      .appendingPathComponent("DegoogSidecar", isDirectory: true)
  }

  private static func stagedRuntimeRoot() -> URL {
    sidecarSupportRoot().appendingPathComponent("runtime", isDirectory: true)
  }

  private static func applicationSupportDataDirectory() -> URL {
    sidecarSupportRoot().appendingPathComponent("data", isDirectory: true)
  }

  private static func stageRuntimeIfNeeded(to runtimeRoot: URL) throws {
    let fm = FileManager.default
    let supportRoot = sidecarSupportRoot()
    let marker = runtimeRoot.appendingPathComponent(".staged-version")
    guard let archive = bundledRuntimeArchive() else {
      log("runtime archive missing from app bundle")
      throw DeGoogSidecarError.bundleMissing
    }

    let bundledVersion = bundledRuntimeVersion()
    let stagedVersion = (try? String(contentsOf: marker, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    try fm.createDirectory(at: supportRoot, withIntermediateDirectories: true)

    if stagedVersion == bundledVersion,
       fm.fileExists(atPath: runtimeRoot.appendingPathComponent("package.json").path) {
      return
    }

    log("extracting DeGoog runtime v\(bundledVersion) to \(runtimeRoot.path)")

    if fm.fileExists(atPath: runtimeRoot.path) {
      try fm.removeItem(at: runtimeRoot)
    }
    try fm.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

    let extract = Process()
    extract.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    extract.arguments = ["-xzf", archive.path, "-C", runtimeRoot.path, "--strip-components=1", "degoog"]
    let stderr = Pipe()
    extract.standardError = stderr
    try extract.run()
    extract.waitUntilExit()
    guard extract.terminationStatus == 0 else {
      let err = drainPipe(stderr)
      log("tar extract failed: \(err)")
      throw DeGoogSidecarError.processLaunchFailed(
        err.isEmpty ? "Could not unpack the DeGoog runtime." : err
      )
    }

    try bundledVersion.write(to: marker, atomically: true, encoding: .utf8)
  }

  private static func isPortFree(_ port: Int) -> Bool {
    let socket = socket(AF_INET, SOCK_STREAM, 0)
    guard socket >= 0 else { return false }
    defer { close(socket) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let bindResult = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return bindResult == 0
  }

  private static func drainPipe(_ pipe: Pipe) -> String {
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  private static func log(_ message: String) {
    DebugLogger.shared.log("[DeGoogSidecar] \(message)")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    let url = sidecarSupportRoot().appendingPathComponent("sidecar.log")
    try? FileManager.default.createDirectory(at: sidecarSupportRoot(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile()
      handle.write(line.data(using: .utf8) ?? Data())
      try? handle.close()
    } else {
      try? line.write(to: url, atomically: true, encoding: .utf8)
    }
  }
}
