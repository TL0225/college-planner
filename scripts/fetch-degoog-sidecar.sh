#!/usr/bin/env bash
# fetch-degoog-sidecar.sh
# Downloads Bun + DeGoog prebuild into College/DegoogSidecar for app bundling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/College/DegoogSidecar"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DEGOOG_VERSION="${DEGOOG_VERSION:-0.21.0}"
BUN_VERSION="${BUN_VERSION:-bun-v1.3.14}"
ARCH="${DEGOOG_SIDECAR_ARCH:-aarch64}"

case "$ARCH" in
  aarch64|arm64) BUN_ASSET="bun-darwin-aarch64.zip" ;;
  x64|x86_64) BUN_ASSET="bun-darwin-x64.zip" ;;
  *) echo "Unsupported DEGOOG_SIDECAR_ARCH: $ARCH" >&2; exit 1 ;;
esac

echo "Fetching DeGoog ${DEGOOG_VERSION} prebuild..."
curl -fsSL \
  "https://github.com/degoog-org/degoog/releases/download/${DEGOOG_VERSION}/degoog_${DEGOOG_VERSION}_prebuild.tar.gz" \
  -o "$TMP/degoog.tgz"
tar -xzf "$TMP/degoog.tgz" -C "$TMP"

echo "Fetching Bun ${BUN_VERSION}..."
curl -fsSL \
  "https://github.com/oven-sh/bun/releases/download/${BUN_VERSION}/${BUN_ASSET}" \
  -o "$TMP/bun.zip"
unzip -q "$TMP/bun.zip" -d "$TMP"

mkdir -p "$DEST"
rm -rf "$DEST/runtime"
tar -czf "$DEST/college-degoog-runtime.tar.gz" -C "$TMP" degoog

BUN_BIN="$(find "$TMP" -type f -name bun -path '*/bun-darwin-*' | head -1)"
if [[ -z "$BUN_BIN" ]]; then
  echo "Could not locate bun binary in archive" >&2
  exit 1
fi
install -m 755 "$BUN_BIN" "$DEST/college-degoog-bun"
codesign -s - -f "$DEST/college-degoog-bun" >/dev/null 2>&1 || true
echo "$DEGOOG_VERSION" > "$DEST/college-degoog-VERSION"

# Remove legacy filenames from earlier script revisions.
rm -f "$DEST/bun" "$DEST/VERSION" "$DEST/degoog-runtime.tar.gz"

echo "Staged DeGoog sidecar at ${DEST}"
echo "  bun: $(file "$DEST/college-degoog-bun" | sed 's/^.*: //')"
echo "  archive: ${DEST}/college-degoog-runtime.tar.gz"
