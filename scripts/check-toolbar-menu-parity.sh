#!/usr/bin/env bash
# M30-083 / E-3 — fail CI when a toolbar action lacks a menu or command-palette entry.
set -euo pipefail
cd "$(dirname "$0")/.."

MANIFEST="scripts/toolbar-menu-parity.tsv"
MENU_SOURCES=(
  "College/App/AppCompatibility.swift"
  "College/Core/Platform/Commands/AppCommandPalette.swift"
  "College/App/CollegeApp.swift"
)

missing=0
checked=0

while IFS=$'\t' read -r domain action patterns || [[ -n "${domain:-}" ]]; do
  [[ -z "${domain:-}" || "$domain" == \#* ]] && continue
  checked=$((checked + 1))

  if [[ "$patterns" == exempt:* ]]; then
    continue
  fi

  found=false
  for file in "${MENU_SOURCES[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "ERROR: missing menu source $file"
      exit 1
    fi
    content=$(<"$file")
    IFS='|' read -ra parts <<< "$patterns"
    for part in "${parts[@]}"; do
      trimmed=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$trimmed" ]] && continue
      if echo "$content" | grep -qi "$trimmed"; then
        found=true
        break
      fi
    done
    $found && break
  done

  if ! $found; then
    echo "ERROR: toolbar action ${domain}.${action} missing menu/palette match for: $patterns"
    missing=$((missing + 1))
  fi
done < "$MANIFEST"

if (( missing > 0 )); then
  echo "FAIL: $missing toolbar action(s) lack menu/palette parity ($checked checked)"
  exit 1
fi

echo "OK: toolbar→menu parity ($checked actions, manifest $MANIFEST)"
