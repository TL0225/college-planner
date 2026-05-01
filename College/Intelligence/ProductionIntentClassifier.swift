import Foundation
import NaturalLanguage
import CoreML

// MARK: - Settings

enum AssistantIntentNLModelSettings {
    static let enabledKey = "assistant.intent.nlmodel.enabled"
    static let probabilityThresholdKey = "assistant.intent.nlmodel.probabilityThreshold"

    /// Prefer Core ML intent classification when bundled model loads successfully.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) != nil
            ? UserDefaults.standard.bool(forKey: enabledKey)
            : true
    }

    /// Minimum softmax probability from ``NLModel.predictedLabelHypotheses`` to trust the label (tune via validation CSV / Create ML Testing).
    static var probabilityThreshold: Double {
        if UserDefaults.standard.object(forKey: probabilityThresholdKey) != nil {
            return UserDefaults.standard.double(forKey: probabilityThresholdKey)
        }
        return 0.35
    }
}

// MARK: - Classifier

/// On-device intent routing via Create ML ``IntentClassifier`` (text classification) + ``NLModel``.
enum ProductionIntentClassifier {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedNLModel: NLModel?
    nonisolated(unsafe) private static var loadFailed = false

    /// Returns best label and its probability when above ``AssistantIntentNLModelSettings.probabilityThreshold``.
    static func classify(message: String) -> (intentId: String, probability: Double)? {
        guard AssistantIntentNLModelSettings.isEnabled, !loadFailed else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let model = nlModel() else { return nil }
        let threshold = AssistantIntentNLModelSettings.probabilityThreshold
        let hypotheses = model.predictedLabelHypotheses(for: trimmed, maximumCount: 32)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        guard best.value >= threshold else { return nil }
        return (best.key, best.value)
    }

    private static func nlModel() -> NLModel? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedNLModel { return cachedNLModel }
        guard let mlModel = try? IntentClassifier(configuration: MLModelConfiguration()).model,
              let nl = try? NLModel(mlModel: mlModel) else {
            loadFailed = true
#if DEBUG
            DebugLogger.shared.log(
                "ProductionIntentClassifier: failed to load IntentClassifier.mlmodel (NLModel)",
                category: .intelligence,
                level: .warn
            )
#endif
            return nil
        }
        cachedNLModel = nl
        return nl
    }

    /// Call after changing UserDefaults that affect model selection (tests).
    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        cachedNLModel = nil
        loadFailed = false
    }
}
