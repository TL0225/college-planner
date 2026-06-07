#!/usr/bin/env swift
/// Run from repo root on macOS: `swift Scripts/train_intent_text_classifier.swift`
/// Outputs `College/Intelligence/IntentClassifier.mlmodel` using Create ML.
import CreateML
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: swift Scripts/train_intent_text_classifier.swift College/Intelligence/Resources/IntentTrainingData.csv\n", stderr)
    exit(1)
}
let csvURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: "/Users/timothy/Desktop/College/College/Intelligence/IntentClassifier.mlmodel")

let data = try MLDataTable(contentsOf: csvURL)
let classifier = try MLTextClassifier(
    trainingData: data,
    textColumn: "text",
    labelColumn: "label"
)
try classifier.write(to: outputURL)

print("Wrote \(outputURL.path)")
