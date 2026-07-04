#!/usr/bin/env bash
# M30-066 — shell performance instrumentation present for CI ship gate.
set -euo pipefail
cd "$(dirname "$0")/.."

required=(
  College/Core/PerformanceDiagnostics.swift
  College/Debug/Diagnostics/ShellPerformanceTiming.swift
)

for path in "${required[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "error: missing performance artifact $path"
    exit 1
  fi
done

if ! rg -q 'ShellPerformanceTiming' College/App/ContentView.swift; then
  echo "error: ContentView missing ShellPerformanceTiming spans"
  exit 1
fi

if ! rg -q 'shellSidebarToggleWarnMsRelease = 100' College/Debug/LaunchPerformanceAcceptance.swift; then
  echo "error: release sidebar p95 budget must be 100ms"
  exit 1
fi

if ! rg -q 'academicsAuditWarnMsRelease = 2_000' College/Debug/LaunchPerformanceAcceptance.swift; then
  echo "error: release academics audit budget must be 2000ms"
  exit 1
fi

echo "ok: shell performance instrumentation PASS"
