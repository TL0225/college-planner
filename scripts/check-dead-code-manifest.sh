#!/usr/bin/env bash
# CI guard: Wave 2 dead-code manifest — listed files must not exist in the synced compile root.
# Update this manifest only after reference/target audit confirms deletion is safe.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DEAD_PATHS=(
  College/App/AppHeaderView.swift
  College/Core/DesignSystem/AppNavBar.swift
  College/Core/DesignSystem/LiquidGlassSidebarRow.swift
  College/Features/Degree/DegreeView.swift
  College/Features/Profile/AcademicIdentityView.swift
  College/Features/Calendar/NewEventModal.swift
)

REPORT_ONLY=0
if [[ "${1:-}" == "--report" ]] || [[ "${DEAD_CODE_REPORT_ONLY:-}" == "1" ]]; then
  REPORT_ONLY=1
fi

present=0
for rel in "${DEAD_PATHS[@]}"; do
  if [[ -f "$ROOT/$rel" ]]; then
    echo "dead-code manifest: still present — $rel"
    present=$((present + 1))
  fi
done

echo "dead-code manifest: ${present}/${#DEAD_PATHS[@]} listed paths still on disk"

if [[ "$REPORT_ONLY" -eq 1 ]]; then
  echo "note: report-only mode — gate not enforced"
  exit 0
fi

if [[ "$present" -gt 0 ]]; then
  echo "error: delete listed dead-code paths before ship (or remove from manifest after audit)"
  exit 1
fi

echo "ok: dead-code manifest clear"
