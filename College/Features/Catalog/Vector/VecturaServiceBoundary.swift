// VecturaServiceBoundary.swift
// Feature: Catalog
// Purpose: Catalog module — VecturaMLXKitIsolationNotes.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Boundary for the isolated **`VecturaService`** Swift package at the repository root (`VecturaService/`).
///
/// That package defines `IsolatedSentenceEmbedding768` and `VecturaMLXSentenceAdapter`, wrapping `VecturaMLXKit`
/// so catalog code could depend on a single product. **College does not link it in Xcode yet:** SwiftPM cannot merge
/// the College `swift-transformers` graph with `VecturaMLXKit`’s `swift-tokenizers` graph (`swift-jinja` major mismatch).
/// Verify locally with `cd VecturaService && swift build`; see `VecturaIntegrationNotes` inside the package for details.
///
/// Production catalog embeddings remain on `CatalogMLXEmbedService` / `MLXEmbedders` from `mlx-swift-lm` +
/// `swift-transformers`.
enum VecturaMLXKitIsolationNotes {
    static let upstreamRepositoryURL = URL(string: "https://github.com/rryam/VecturaMLXKit")!
    static let isolatedPackageRelativePath = "VecturaService"
    /// Historical intent: separate linkage so the app target never imports `VecturaMLXKit` directly.
    static let isolationStrategy =
        "Standalone Swift package + adapter; Xcode link deferred until swift-jinja / tokenizer graphs converge or you ship an XCFramework."
}
