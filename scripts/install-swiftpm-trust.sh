#!/bin/zsh
# Installs checked-in SwiftPM package fingerprints so Xcode trusts mlx-swift-lm macros.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${HOME}/Library/org.swift.swiftpm/security/fingerprints"
SRC="${ROOT}/Config/SwiftPM/fingerprints"

if [[ ! -d "${SRC}" ]]; then
  echo "No fingerprints to install at ${SRC}" >&2
  exit 0
fi

mkdir -p "${DEST}"
cp -f "${SRC}/"*.json "${DEST}/" 2>/dev/null || true
echo "Installed SwiftPM fingerprints to ${DEST}"
