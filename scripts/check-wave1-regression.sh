#!/usr/bin/env bash
# M30-014 — Wave 1 shell unblock regression gate.
set -euo pipefail
cd "$(dirname "$0")/.."

checks=(
  College/PrivacyInfo.xcprivacy
  College/Core/Platform/AppErrorPresenter.swift
  College/Core/Platform/WKWebViewProcessRecovery.swift
  docs/adr/010-sync-local-first.md
)

for path in "${checks[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "error: missing Wave 1 artifact $path"
    exit 1
  fi
done

if rg -n 'fatalError\(' College/Core/Data/Persistence/CollegePersistence+Career.swift 2>/dev/null; then
  echo "error: prod fatalError still in CollegePersistence+Career"
  exit 1
fi

echo "ok: Wave 1 regression gate PASS"
