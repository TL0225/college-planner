# Catalog embedding model evaluation (Phase 9)

## Current production

- **Runtime:** `CatalogEmbeddingRuntime` + bundled `CatalogEmbed` weights via Rust/MLX embed path.
- **Indexer:** Paged `CatalogVectorIndexer` (200-row fetch pages) with `CatalogEmbedMemoryLifecycle` idle release.

## Candidate: EmbeddingGemma 300M (MLX)

| Attribute | EmbeddingGemma 300M 4-bit | Current CatalogEmbed |
|-----------|---------------------------|----------------------|
| Disk (~4-bit) | ~173 MB ([mlx-community](https://huggingface.co/mlx-community/embeddinggemma-300m-4bit)) | Bundled in app |
| Dimensions | 768 (MRL truncatable) | Fixed by bundle |
| mlx-swift-lm | Supported (`qwen3_5` embed family in recent pins) | Custom FFI |

## Evaluation checklist (required before switch)

1. **Recall@k** on fixed catalog query set (`CatalogCourseSearchTests`, manual NYU/DSU fixtures).
2. **Index time** for 10k course rows (Instruments Allocations peak RSS).
3. **Reindex** after embedding version bump — migration path for existing vector SQLite.
4. **Idle RAM** after index complete — embedder `reset()` within 120s default.

## Decision

Keep CatalogEmbed until recall parity + reindex migration are proven on device. Spike branch: load `mlx-community/embeddinggemma-300m-4bit` in `CatalogEmbeddingRuntime` behind a feature flag.
