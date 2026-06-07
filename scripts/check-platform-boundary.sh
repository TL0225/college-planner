#!/usr/bin/env bash
# CI guard: CollegePlatform must not import app feature modules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_SRC="$ROOT/CollegePlatform/Sources/CollegePlatform"
if grep -rE 'import (College|SwiftUI)' "$PLATFORM_SRC" 2>/dev/null; then
  echo "error: CollegePlatform must not import College app modules or SwiftUI"
  exit 1
fi
echo "ok: CollegePlatform boundary clean"
