#!/bin/sh
set -euo pipefail

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "$PLIST" ]; then
  exit 0
fi

HASH="unknown"
if command -v git >/dev/null 2>&1; then
  HASH="$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

/usr/libexec/PlistBuddy -c "Set :GitCommitHash ${HASH}" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${HASH}" "$PLIST"
