#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET="aarch64-apple-darwin"
OUT_DIR="$SCRIPT_DIR/target/$TARGET/release"
LIB_NAME="libcollege_typst.a"
HEADER="$SCRIPT_DIR/college_typst.h"
MODULE_MAP="$SCRIPT_DIR/module.modulemap"

echo "Building college-typst for $TARGET (arm64-only; x86_64 is out of scope)..."

if ! rustup target list --installed | grep -q "$TARGET"; then
  rustup target add "$TARGET"
fi

MACOSX_DEPLOYMENT_TARGET=26.4 CARGO_TARGET_DIR="$SCRIPT_DIR/target" cargo build --release --target "$TARGET"

cp "$OUT_DIR/libcollege_typst.a" "$SCRIPT_DIR/$LIB_NAME"

cat > "$MODULE_MAP" <<'EOF'
module CollegeTypst {
    header "college_typst.h"
    export *
}
EOF

echo ""
echo "Built: $SCRIPT_DIR/$LIB_NAME"
echo ""
echo "Xcode wiring (College target):"
echo "  1. Add $LIB_NAME to Build Phases → Link Binary With Libraries (or LIBRARY_SEARCH_PATHS + OTHER_LDFLAGS)."
echo "  2. Set LIBRARY_SEARCH_PATHS to include: \$(PROJECT_DIR)/rust-typst"
echo "  3. Set OTHER_LDFLAGS = -lcollege_typst"
echo "  4. Add bridging header import or module map: $MODULE_MAP"
echo "  5. Add OTHER_SWIFT_FLAGS = -D COLLEGE_TYPST_LINKED (required for Release/production)."
echo ""

echo "Note: the Xcode project defaults to the Swift fallback renderer (CI-safe)."
echo "For production Typst PDFs, add the flags above to the College target, or set them"
echo "only in a local xcconfig that is not committed."
