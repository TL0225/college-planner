# CatalogEmbed (bundle-first MLX sentence model)

Place a complete **MLXEmbedders**-compatible directory here and name it `CatalogEmbed` (this folder is copied into the app as the **`CatalogEmbed`** bundle resource — ensure Xcode includes it under **Copy Bundle Resources** if you use a folder reference).

Required files (minimum):

- `config.json`
- Tokenizer assets (`tokenizer.json`, `tokenizer_config.json`, etc., per your model)
- `*.safetensors` (or the weight layout expected by your pinned `mlx-swift-lm` / model card)

**Resolution order** at runtime (see `CatalogMLXEmbedPaths.resolvedModelDirectoryURL()`):

1. `Bundle.main` → `CatalogEmbed` if `config.json` is present  
2. `Application Support/College/CatalogEmbed/` (staged updates / overrides)

Do not commit large weight files to git unless your distribution policy allows it; add `*.safetensors` to `.gitignore` if developers vendor locally.
