import Foundation

/// Notes for linking ``VecturaService`` into the main College Xcode target.
public enum VecturaIntegrationNotes {
    /// The isolated package builds from the repo root with `swift build` inside `VecturaService/`.
    public static let standaloneBuildCommand = "cd VecturaService && swift build"

    /// SwiftPM merges **one** resolved graph for the whole Xcode project. Today this blocks simultaneous use of
    /// College’s `swift-transformers` pin and `VecturaMLXKit`’s `swift-tokenizers` pin because they disagree on `swift-jinja`.
    public static let packageGraphBlocker = """
    Xcode resolution fails: swift-tokenizers (via VecturaMLXKit) requires swift-jinja 0.2.x while swift-transformers (College LLM stack) requires swift-jinja 2.x.
    """

    /// Practical unblockers: fork/patch VecturaMLXKit to use Hugging Face `Tokenizers` from swift-transformers; ship this package as a prebuilt XCFramework; or drop swift-transformers from the app graph (large refactor).
    public static let unblockStrategies = """
    Fork VecturaMLXKit to replace swift-tokenizers with swift-transformers; OR build VecturaService to an XCFramework and link without SPM; OR converge mlx-swift-lm + transformers pins upstream.
    """
}
