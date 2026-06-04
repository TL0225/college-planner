# IntentClassifier (Create ML) regeneration

The app ships [`College/Intelligence/IntentClassifier.mlmodel`](College/Intelligence/IntentClassifier.mlmodel) trained from [`College/Intelligence/Resources/IntentTrainingData.csv`](../College/Intelligence/Resources/IntentTrainingData.csv).

After editing the CSV (more labels or utterances), regenerate the model:

```bash
cd /path/to/College
swift Scripts/train_intent_text_classifier.swift College/Intelligence/Resources/IntentTrainingData.csv
```

Requires **macOS**, **Xcode**, and the **Create ML** toolchain (script `import Create ML`).

Commit the updated `IntentClassifier.mlmodel` with the CSV change.
