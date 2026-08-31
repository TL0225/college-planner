# Bundled Typst binary (optional)

College can compile resume PDFs with [Typst](https://typst.app). The build does **not** download Typst automatically.

To ship Typst with the app, place the official CLI binary in this folder:

- **Windows:** `typst.exe`
- **macOS / Linux:** `typst`

Resolution order at runtime:

1. `TYPST_PATH` environment variable
2. This folder (`resources/typst/`)
3. `typst` on the system `PATH`

Download Typst from https://github.com/typst/typst/releases
