#!/usr/bin/env bash
# Copy sandbox-calibrated Assistant fixtures into CollegeTests/Fixtures/Assistant/.
#
# Prerequisite: run export tests once (with .disabled removed or via college-xcodebuild-test):
#   bash scripts/college-xcodebuild-test.sh -scheme College -destination 'platform=macOS' \
#     -only-testing:CollegeTests/RoutingCorpusExportTests \
#     -only-testing:CollegeTests/EvalCorpusExportTests
#
# Usage (from anywhere):
#   ./scripts/copy-assistant-fixture-exports.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/CollegeTests/Fixtures/Assistant"
CONTAINER="${HOME}/Library/Containers/Timothy.College/Data/tmp"

mkdir -p "$DEST"

copy_one() {
  local name="$1"
  local src="$CONTAINER/${name}-calibrated.json"
  local dst="$DEST/${name}.json"
  if [[ ! -f "$src" ]]; then
    echo "error: missing export file: $src" >&2
    echo "Run export tests first (see script header)." >&2
    exit 1
  fi
  cp "$src" "$dst"
  echo "copied $src -> $dst"
}

copy_one "routing-corpus"
copy_one "eval-corpus"
copy_one "multi-turn-eval-corpus"

echo "Done. Fixture directory: $DEST"
