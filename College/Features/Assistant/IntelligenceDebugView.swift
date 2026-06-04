// IntelligenceDebugView.swift
// Feature: Assistant
// Purpose: Assistant module — IntelligenceDebugView.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Debug view to test and monitor IntelligenceService
struct IntelligenceDebugView: View {
    @Environment(LaunchPreloadCoordinator.self) private var launchPreloadCoordinator
    @State private var prerequisiteText = "Prerequisite: (CS 1110 or CS 1112) AND MATH 1920"
    @State private var courseCode = "CS 2110"
    @State private var parseResult: String = ""
    @State private var isParsing = false
    @State private var modelStatus = "Not Loaded"
    
    private let intelligenceService = IntelligenceService()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Intelligence Service Debugger")
                .font(.title)
                .bold()
            
            // Model Status
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Model Status:")
                            .bold()
                        Spacer()
                        statusBadge
                    }
                    
                    Text("Model: Llama 3.2 3B (4-bit quantized)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Location: ~/Desktop/College/Models/llama-3.2-3b-4bit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !launchPreloadCoordinator.featureOutcomes.isEmpty {
                GroupBox("Launch Preload Outcomes") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(launchPreloadCoordinator.featureOutcomes.keys.sorted(), id: \.self) { key in
                            if let value = launchPreloadCoordinator.featureOutcomes[key] {
                                HStack {
                                    Text(key)
                                        .font(.caption)
                                    Spacer()
                                    Text(value.rawValue)
                                        .font(.caption)
                                        .foregroundColor(color(for: value))
                                }
                            }
                        }
                    }
                }
            }
            
            // Input
            GroupBox("Input") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Course Code", text: $courseCode)
                        .textFieldStyle(.roundedBorder)
                    
                    TextEditor(text: $prerequisiteText)
                        .frame(height: 80)
                        .border(Color.gray.opacity(0.3), width: 1)
                        .cornerRadius(4)
                }
            }
            
            // Parse Button
            Button(action: parsePrerequisite) {
                HStack {
                    if isParsing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isParsing ? "Parsing..." : "Parse Prerequisite")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(isParsing)
            
            // Result
            if !parseResult.isEmpty {
                GroupBox("Result") {
                    ScrollView {
                        Text(parseResult)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            }
            
            // Test Cases
            GroupBox("Quick Tests") {
                VStack(spacing: 8) {
                    testButton("Simple", text: "Prerequisite: CS 1110")
                    testButton("AND", text: "Prerequisites: CS 1110 and MATH 1920")
                    testButton("OR", text: "Prerequisite: CS 1110 or CS 1112")
                    testButton("Complex", text: "(CS 1110 or CS 1112) AND MATH 1920 with grade of B")
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: 800, maxHeight: 900)
        .onAppear {
            checkModelStatus()
        }
    }
    
    private var statusBadge: some View {
        Text(modelStatus)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(modelStatus == "Ready" ? Color.green : Color.orange)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    private func testButton(_ name: String, text: String) -> some View {
        Button(action: {
            prerequisiteText = text
            parsePrerequisite()
        }) {
            HStack {
                Text(name)
                Spacer()
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func checkModelStatus() {
        let modelPath = "/Users/timothy/Desktop/College/Models/llama-3.2-3b-4bit"
        
        if FileManager.default.fileExists(atPath: modelPath) {
            modelStatus = "Ready"
        } else {
            modelStatus = "Not Found"
        }
    }
    
    private func parsePrerequisite() {
        isParsing = true
        parseResult = ""
        
        let inputText = prerequisiteText
        let inputCode = courseCode

        // Parse on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let startTime = Date()
            
            let service = IntelligenceService()
            let (rule, needsLLM, confidence) = service.parsePrerequisite(
                inputText,
                courseCode: inputCode
            )
            
            let duration = Date().timeIntervalSince(startTime)
            
            DispatchQueue.main.async {
                var result = "⏱️ Parse Time: \(String(format: "%.3f", duration))s\n\n"
                
                if let rule = rule {
                    result += "✅ Success!\n\n"
                    result += "Method: \(needsLLM ? "LLM (Slow Lane)" : "Regex (Fast Lane)")\n"
                    result += "Confidence: \(confidence)\n\n"
                    result += "Parsed Rule:\n"
                    result += formatRule(rule, indent: 0)
                } else if needsLLM {
                    result += "⏳ Queued for LLM Processing\n\n"
                    result += "This prerequisite is too complex for regex.\n"
                    result += "It will be processed in the background using Llama 3.2 3B.\n\n"
                    result += "Confidence: \(confidence)"
                } else {
                    result += "❌ Failed to Parse\n\n"
                    result += "Could not parse this prerequisite with regex.\n"
                    result += "Confidence: \(confidence)"
                }
                
                parseResult = result
                isParsing = false
            }
        }
    }
    
    private func formatRule(_ rule: PrerequisiteRule, indent: Int) -> String {
        let indentStr = String(repeating: "  ", count: indent)
        
        switch rule {
        case .course(let req):
            var text = "\(indentStr)• Course: \(req.courseCode)"
            if let grade = req.minGrade {
                text += " (min grade: \(grade))"
            }
            return text + "\n"
            
        case .and(let rules):
            var text = "\(indentStr)AND:\n"
            for subRule in rules {
                text += formatRule(subRule, indent: indent + 1)
            }
            return text
            
        case .or(let rules):
            var text = "\(indentStr)OR:\n"
            for subRule in rules {
                text += formatRule(subRule, indent: indent + 1)
            }
            return text
        }
    }

    private func color(for outcome: LaunchPreloadCoordinator.FeatureOutcome) -> Color {
        switch outcome {
        case .completed:
            return .green
        case .timedOut, .skippedByBudget:
            return .orange
        case .failed:
            return .red
        }
    }
}

#Preview {
    IntelligenceDebugView()
}
