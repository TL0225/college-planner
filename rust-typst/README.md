# college-typst

Embedded Typst compiler static library for College resume PDF generation.

## Build (arm64 only)

```bash
./build_macos.sh
```

Produces `libcollege_typst.a`, `college_typst.h`, and `module.modulemap`.

## Xcode wiring

1. Run `./build_macos.sh` in this directory.
2. In the **College** target:
   - Add `$(PROJECT_DIR)/rust-typst` to **Library Search Paths**.
   - Add `-lcollege_typst` to **Other Linker Flags**.
   - Import `college_typst.h` via bridging header or the generated module map.
   - Add `-D COLLEGE_TYPST_LINKED` to **Other Swift Flags** (required for Release/production).

Without `COLLEGE_TYPST_LINKED`, the app uses the Swift fallback renderer (compatibility mode banner shown in the builder).

## API

- `college_typst_compile_pdf(source_utf8, out_len) -> uint8_t*`
- `college_typst_free(ptr, len)`
- `college_typst_last_error() -> const char*`

See `college_typst.h` for the full contract.
