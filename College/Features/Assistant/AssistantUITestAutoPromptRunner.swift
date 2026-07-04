// AssistantUITestAutoPromptRunner.swift
// Feature: Assistant
// Purpose: Auto-send scripted student prompts during UI-test / evaluation runs (no manual typing).

import Foundation

enum AssistantUITestAutoPromptRunner {
    private static let delimiter = "|||"
    private static let logFileName = "assistant-auto-prompt-log.json"

    static var isEnabled: Bool {
        guard UITestLaunchFlags.forcesMainUI else { return false }
        if ProcessInfo.processInfo.environment["COLLEGE_UITEST_ASSISTANT_AUTO_PROMPTS"] != nil { return true }
        return ProcessInfo.processInfo.arguments.contains("--uitest-assistant-auto-prompts")
            || ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--uitest-assistant-auto-prompts=") }
            || ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--uitest-assistant-auto-prompts-file=") }
    }

    static var prompts: [String] {
        if let env = ProcessInfo.processInfo.environment["COLLEGE_UITEST_ASSISTANT_AUTO_PROMPTS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return splitPrompts(env)
        }
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "--uitest-assistant-auto-prompts" {
                return defaultPrompts
            }
            if arg.hasPrefix("--uitest-assistant-auto-prompts=") {
                let raw = String(arg.dropFirst("--uitest-assistant-auto-prompts=".count))
                let parsed = splitPrompts(raw)
                return parsed.isEmpty ? defaultPrompts : parsed
            }
            if arg.hasPrefix("--uitest-assistant-auto-prompts-file=") {
                let path = String(arg.dropFirst("--uitest-assistant-auto-prompts-file=".count))
                if let loaded = loadPromptsFile(at: path), !loaded.isEmpty {
                    return loaded
                }
            }
        }
        return defaultPrompts
    }

    static var logFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(logFileName)
    }

    static var defaultPrompts: [String] {
        [
            "What is due?",
            "What's my major?",
            "What do I have this week?",
            "What's on my calendar tomorrow?",
            "What career does my major lead to?",
            "Can you create a semester-by-semester breakdown of my major?",
            "What's the residency requirement for my degree?",
            "Help me plan next semester",
            "Am I ready to register for classes?",
            "What model are you?"
        ]
    }

    struct LogEntry: Codable {
        let index: Int
        let prompt: String
        let reply: String
        let timestamp: String
        let intent: String?
        let routePath: String?
        let latencyMS: Int?
        let toolTrace: [String]?
        let flags: [String]?
    }

    struct LogFile: Codable {
        let completedAt: String
        let promptCount: Int
        let entries: [LogEntry]
    }

    static func writeLog(from messages: [AssistantMessage]) {
        var entries: [LogEntry] = []
        var pendingPrompt: String?
        var index = 0

        for message in messages {
            if message.isUser {
                pendingPrompt = message.text
            } else if let prompt = pendingPrompt {
                let intent = AssistantIntentSemantics.classify(message: prompt, role: .academicAdvisor)?.matchedIntent
                let routePath: String = {
                    switch AIAssistantToolRouter.routeDecision(
                        for: prompt,
                        role: .academicAdvisor,
                        snapshot: AssistantPlannerSnapshot(events: [], tasks: [], majors: [], minors: [], programs: []),
                        activePage: .assistant
                    ) {
                    case .deterministic: return "deterministic"
                    case .llmPreferred: return "llmPreferred"
                    case .none: return "planner"
                    }
                }()
                var flags: [String] = []
                if message.text.contains("Current programs:\n- Majors:") {
                    flags.append("robotic_program_dump")
                }
                let toolTrace = message.toolTrace.map(\.toolName)
                entries.append(
                    LogEntry(
                        index: index,
                        prompt: prompt,
                        reply: message.text,
                        timestamp: ISO8601DateFormatter().string(from: message.timestamp),
                        intent: intent,
                        routePath: routePath,
                        latencyMS: nil,
                        toolTrace: toolTrace.isEmpty ? nil : toolTrace,
                        flags: flags.isEmpty ? nil : flags
                    )
                )
                index += 1
                pendingPrompt = nil
            }
        }

        let payload = LogFile(
            completedAt: ISO8601DateFormatter().string(from: Date()),
            promptCount: entries.count,
            entries: entries
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: logFileURL, options: .atomic)

        let docsCopy = URL(fileURLWithPath: "/Users/timothy/Desktop/College/docs/assistant-auto-prompt-log.json")
        try? FileManager.default.createDirectory(at: docsCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: docsCopy, options: .atomic)

#if DEBUG
        DebugLogger.shared.log(
            "AssistantUITestAutoPromptRunner wrote \(entries.count) entries → \(logFileURL.path)",
            category: .intelligence,
            level: .info
        )
#endif
    }

    private static func splitPrompts(_ raw: String) -> [String] {
        raw
            .components(separatedBy: delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func loadPromptsFile(at path: String) -> [String]? {
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
