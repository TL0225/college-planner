# MLX Swift Integration Guide

## Overview
This guide explains how to integrate MLX Swift (Apple's machine learning framework) into the College app for running Llama 3.2 3B locally for prerequisite parsing.

---

## Step 1: Add MLX Swift Dependency

### Option A: Using Xcode (Recommended)
1. Open `College.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select "College" target → "Package Dependencies" tab
4. Click "+" to add package
5. Enter repository URL: `https://github.com/ml-explore/mlx-swift`
6. Select version: "Up to Next Major" from `0.18.0`
7. Click "Add Package"
8. Select libraries to add:
   - ✅ MLX
   - ✅ MLXNN
   - ✅ MLXRandom
   - ✅ MLXOptimizers (optional)
9. Click "Add Package"

### Option B: Manual Package.swift (if using SPM)
Add to `dependencies`:
```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.18.0")
]
```

Add to target dependencies:
```swift
.target(
    name: "College",
    dependencies: [
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXRandom", package: "mlx-swift")
    ]
)
```

---

## Step 2: Download Llama 3.2 3B Model

### Model Requirements
- **Model:** Llama 3.2 3B (4-bit quantized)
- **Size:** ~2GB
- **Format:** MLX compatible (not PyTorch or GGUF)
- **Quantization:** 4-bit (Q4_K_M) for optimal size/quality balance

### Download Options

#### Option A: Use Hugging Face Hub
```bash
# Install Hugging Face CLI
pip install huggingface_hub

# Download model
huggingface-cli download \
    mlx-community/Llama-3.2-3B-Instruct-4bit \
    --local-dir ~/Desktop/College/Models/llama-3.2-3b-4bit
```

#### Option B: Convert Existing Model
If you have the model in another format:
```bash
# Install MLX conversion tools
pip install mlx-lm

# Convert to MLX format with 4-bit quantization
python -m mlx_lm.convert \
    --hf-path meta-llama/Llama-3.2-3B-Instruct \
    --quantize \
    --q-bits 4 \
    --mlx-path ~/Desktop/College/Models/llama-3.2-3b-4bit
```

### Model Directory Structure
```
College/
    Models/
        llama-3.2-3b-4bit/
            config.json
            weights.safetensors
            tokenizer.json
            tokenizer_config.json
            special_tokens_map.json
```

---

## Step 3: Add Model to Xcode Project

### Option A: Bundle with App (Not Recommended - 2GB app size!)
1. Drag `Models/` folder into Xcode navigator
2. **Uncheck** "Copy items if needed" (use reference)
3. Select "Create folder references"
4. Add to target: College

### Option B: Download on First Launch (Recommended ✅)
1. Create a model download service
2. Download model files on first scrape
3. Cache in app's Documents directory

**Implementation:**
```swift
class ModelDownloadService {
    static let modelURL = "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit/resolve/main/"
    
    static func downloadModel(progress: @escaping (Double) -> Void) async throws {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelDir = documentsDir.appendingPathComponent("Models/llama-3.2-3b-4bit")
        
        // Create directory
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        // Download files
        let files = ["config.json", "weights.safetensors", "tokenizer.json"]
        for (index, file) in files.enumerated() {
            let url = URL(string: modelURL + file)!
            let localURL = modelDir.appendingPathComponent(file)
            
            // Download
            let (data, _) = try await URLSession.shared.data(from: url)
            try data.write(to: localURL)
            
            progress(Double(index + 1) / Double(files.count))
        }
    }
}
```

---

## Step 4: Update IntelligenceService to Use MLX

### Current Implementation (Placeholder)
```swift
// IntelligenceService.swift - line ~180
private func loadModel() {
    guard mlxModel == nil else { return }
    print("[Intelligence] Loading MLX model...")
    // TODO: Implement MLX model loading
}
```

### Replace with MLX Implementation
```swift
import MLX
import MLXNN
import Foundation

class IntelligenceService {
    private var mlxModel: LanguageModel?
    private var tokenizer: Tokenizer?
    private let modelPath: URL
    
    init() {
        // Get model path from Documents directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelPath = documentsDir.appendingPathComponent("Models/llama-3.2-3b-4bit")
    }
    
    // MARK: - Model Loading
    
    private func loadModel() {
        guard mlxModel == nil else { return }
        
        print("[Intelligence] Loading MLX model from \(modelPath.path)...")
        
        do {
            // Load tokenizer
            tokenizer = try Tokenizer(modelPath: modelPath.path)
            
            // Load model
            mlxModel = try LanguageModel.load(path: modelPath.path)
            
            print("[Intelligence] Model loaded successfully")
        } catch {
            print("[Intelligence] Failed to load model: \(error)")
        }
    }
    
    // MARK: - LLM Inference
    
    private func parseSingleWithLLM(text: String, courseCode: String) -> (PrerequisiteRule?, ParsingConfidence) {
        loadModel() // Lazy load
        
        guard let model = mlxModel, let tokenizer = tokenizer else {
            return (nil, .low)
        }
        
        // Build prompt
        let prompt = buildPrompt(prerequisiteText: text, courseCode: courseCode)
        
        // Tokenize
        let inputTokens = tokenizer.encode(prompt)
        
        // Generate
        let maxTokens = 150
        var outputTokens: [Int] = []
        
        for _ in 0..<maxTokens {
            let output = model.forward(inputTokens + outputTokens)
            let nextToken = output.argmax()
            outputTokens.append(nextToken)
            
            // Stop at end of sequence
            if nextToken == tokenizer.eosToken {
                break
            }
        }
        
        // Decode
        let generatedText = tokenizer.decode(outputTokens)
        
        // Extract JSON
        return extractJSON(from: generatedText)
    }
}
```

---

## Step 5: Model Memory Management

### Best Practices

1. **Lazy Loading:**
   ```swift
   // Only load model when needed
   private func loadModel() {
       guard mlxModel == nil else { return }
       // Load model...
   }
   ```

2. **Unload After Batch:**
   ```swift
   func parseComplexPrerequisites(batch: [(String, String)], completion: @escaping ([ParseResult]) -> Void) {
       // Load model
       loadModel()
       
       // Process batch
       let results = batch.map { parseSingleWithLLM($0.0, $0.1) }
       
       // Unload model to free memory
       mlxModel = nil
       tokenizer = nil
       
       completion(results)
   }
   ```

3. **Memory Warnings:**
   ```swift
   NotificationCenter.default.addObserver(
       forName: UIApplication.didReceiveMemoryWarningNotification,
       object: nil,
       queue: nil
   ) { [weak self] _ in
       self?.mlxModel = nil // Unload model
       self?.tokenizer = nil
   }
   ```

---

## Step 6: Testing the Integration

### Test 1: Simple Prerequisite
```swift
let intelligenceService = IntelligenceService()
let (rule, needsLLM, confidence) = intelligenceService.parsePrerequisite(
    text: "Prerequisite: CS 1110",
    courseCode: "CS 2110"
)

assert(rule != nil, "Should parse with regex")
assert(!needsLLM, "Should not need LLM")
assert(confidence == .high, "Should have high confidence")
```

### Test 2: Complex Prerequisite (LLM)
```swift
let batch = [
    (courseCode: "CS 2110", prerequisiteText: "(CS 1110 or CS 1112) AND MATH 1920")
]

intelligenceService.parseComplexPrerequisites(
    batch: batch,
    progress: { parsed, total in
        print("Progress: \(parsed)/\(total)")
    },
    completion: { results in
        guard let result = results.first else { return }
        assert(result.rule != nil, "LLM should parse complex prerequisite")
        print("Parsed rule: \(result.rule!)")
    }
)
```

### Test 3: Model Memory Usage
```swift
// Before loading model
let memoryBefore = getMemoryUsage()

// Load model
intelligenceService.loadModel()

// After loading model
let memoryAfter = getMemoryUsage()
let modelSize = memoryAfter - memoryBefore

print("Model memory usage: \(modelSize / 1024 / 1024)MB")
// Expected: ~100-150MB (4-bit quantized)
```

---

## Step 7: Performance Optimization

### 1. Batch Processing
Process multiple prerequisites at once:
```swift
// Instead of:
for prereq in prerequisites {
    let result = parseSingleWithLLM(prereq)
}

// Use:
let results = parseComplexPrerequisites(batch: prerequisites)
// Saves model load/unload overhead
```

### 2. Caching
Cache parsed results:
```swift
private var parseCache: [String: PrerequisiteRule] = [:]

func parsePrerequisite(text: String, courseCode: String) -> (PrerequisiteRule?, Bool, ParsingConfidence) {
    // Check cache first
    if let cached = parseCache[text] {
        return (cached, false, .high)
    }
    
    // Parse...
    let (rule, needsLLM, confidence) = actualParsing(text)
    
    // Cache result
    if let rule = rule {
        parseCache[text] = rule
    }
    
    return (rule, needsLLM, confidence)
}
```

### 3. Early Exit
Stop generation when JSON is complete:
```swift
var outputTokens: [Int] = []
var braceCount = 0

for _ in 0..<maxTokens {
    let nextToken = model.forward(...)
    outputTokens.append(nextToken)
    
    // Track JSON braces
    if tokenizer.decode([nextToken]) == "{" { braceCount += 1 }
    if tokenizer.decode([nextToken]) == "}" { braceCount -= 1 }
    
    // Stop when JSON is complete
    if braceCount == 0 && outputTokens.count > 10 {
        break
    }
}
```

---

## Step 8: Fallback Strategy

If MLX Swift integration fails, use cloud API:

```swift
func parseWithFallback(text: String, courseCode: String) async -> PrerequisiteRule? {
    // Try local MLX first
    if let result = tryMLXParsing(text) {
        return result
    }
    
    // Fall back to OpenAI API
    if let result = try? await parseWithOpenAI(text, courseCode) {
        return result
    }
    
    // Fall back to regex
    if let result = tryRegexParsing(text, courseCode) {
        return result
    }
    
    return nil
}
```

---

## Troubleshooting

### Issue 1: "Module 'MLX' not found"
**Solution:** Make sure MLX Swift package is added to target dependencies
```
Xcode → Project → Target → Build Phases → Link Binary With Libraries → Add MLX
```

### Issue 2: Model files not found
**Solution:** Check model path
```swift
print("Model path: \(modelPath.path)")
print("Files: \(try? FileManager.default.contentsOfDirectory(atPath: modelPath.path))")
```

### Issue 3: Out of memory
**Solution:** Reduce batch size or use smaller quantization
```swift
// Reduce batch size
let batchSize = 10 // Instead of 50

// Or use 8-bit quantization instead of 4-bit
// (larger size but less memory during inference)
```

### Issue 4: Slow inference
**Solution:** Check if running on GPU
```swift
import MLX

// Force GPU execution
MLX.set_default_device(.gpu)

// Check current device
print("Using device: \(MLX.default_device())")
```

---

## Expected Performance

| Metric | Value | Notes |
|--------|-------|-------|
| **Model Load Time** | 2-5 seconds | First time only |
| **Inference (single)** | 300-800ms | Depends on complexity |
| **Inference (batch 20)** | 8-15 seconds | Amortized ~500ms each |
| **Memory Usage** | +100-150MB | 4-bit quantized |
| **Disk Space** | ~2GB | Model files |

---

## Next Steps

1. ✅ Add MLX Swift dependency
2. ✅ Download model (one-time)
3. ✅ Update `IntelligenceService.swift` with MLX code
4. ✅ Test with sample prerequisites
5. ✅ Optimize batch processing
6. ✅ Add progress indicators in UI
7. ✅ Test on device (not just simulator)

---

## Resources

- **MLX Swift GitHub:** https://github.com/ml-explore/mlx-swift
- **MLX Documentation:** https://ml-explore.github.io/mlx/
- **Llama 3.2 Models:** https://huggingface.co/meta-llama
- **MLX Community Models:** https://huggingface.co/mlx-community

---

## Alternative: Use Cloud API Instead

If MLX Swift integration is too complex, use OpenAI API:

```swift
func parseSingleWithOpenAI(text: String, courseCode: String) async throws -> PrerequisiteRule? {
    let prompt = buildPrompt(prerequisiteText: text, courseCode: courseCode)
    
    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = [
        "model": "gpt-4o-mini",
        "messages": [
            ["role": "user", "content": prompt]
        ],
        "temperature": 0.1,
        "max_tokens": 150
    ]
    
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    
    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
    
    return extractJSON(from: response.choices[0].message.content)
}
```

**Pros:**
- No 2GB model download
- No memory overhead
- Always up-to-date
- Better accuracy

**Cons:**
- Requires API key
- Costs money (~$0.01 per 100 prerequisites)
- Requires internet connection
- Privacy concerns (sending course data to OpenAI)
