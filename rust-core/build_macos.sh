#!/usr/bin/env bash
# build_macos.sh — Build college-core as a universal macOS static library.
#
# Output:  rust-core/build/libcollege_core.a   (universal: arm64 + x86_64)
#
# Usage:
#   ./rust-core/build_macos.sh            # release build (default)
#   ./rust-core/build_macos.sh --debug    # debug build
#
# Prerequisites:
#   • Rust toolchain  (https://rustup.rs)
#   • rustup target add aarch64-apple-darwin x86_64-apple-darwin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATE_DIR="$SCRIPT_DIR/college-core"
BUILD_DIR="$SCRIPT_DIR/build"

PROFILE="release"
CARGO_FLAG="--release"
if [[ "${1:-}" == "--debug" ]]; then
    PROFILE="debug"
    CARGO_FLAG=""
fi

echo "▶ Building college-core ($PROFILE)..."

# Ensure Rust targets are installed
rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

# Build for both architectures
(cd "$CRATE_DIR" && \
    cargo build $CARGO_FLAG --target aarch64-apple-darwin && \
    cargo build $CARGO_FLAG --target x86_64-apple-darwin)

ARM_LIB="$CRATE_DIR/target/aarch64-apple-darwin/$PROFILE/libcollege_core.a"
X86_LIB="$CRATE_DIR/target/x86_64-apple-darwin/$PROFILE/libcollege_core.a"

mkdir -p "$BUILD_DIR"

# Create a universal (fat) binary
lipo -create "$ARM_LIB" "$X86_LIB" -output "$BUILD_DIR/libcollege_core.a"

echo "✅ Built: $BUILD_DIR/libcollege_core.a"
echo ""
echo "Next steps:"
echo "  1. In Xcode → College target → Build Phases → Link Binary With Libraries"
echo "     Add: rust-core/build/libcollege_core.a"
echo "  2. In Build Settings → Header Search Paths, add: \$(SRCROOT)/../rust-core/include"
echo "  3. Create College/Rust/CollegeCore-Bridging-Header.h with:"
echo "       #include \"college_core.h\""
echo "  4. Set Objective-C Bridging Header to College/Rust/CollegeCore-Bridging-Header.h"
echo "     (or merge into existing bridging header if one already exists)"
