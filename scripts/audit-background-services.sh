#!/usr/bin/env bash
# CI guard: background service lifecycle compliance.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN_DIR="$ROOT/College"
violations=0

fail() {
  echo "error: $1"
  violations=$((violations + 1))
}

# Allowlisted paths for lifecycle calls and scheduler usage.
LIFECYCLE_ALLOWLIST=(
  "College/Core/Platform/Services/BackgroundServiceManifest.swift"
  "College/Core/Platform/Services/BackgroundServiceRegistry.swift"
  "College/Core/Platform/Services/LaunchPreloadBridge.swift"
  "College/App/CollegeApp.swift"
  "College/Core/Platform/Services/BackgroundServiceTemplate.swift"
  "College/Features/Assistant/DeGoogSidecarManager.swift"
)

SCHEDULER_ALLOWLIST=(
  "College/Core/Platform/Services/BackgroundServiceScheduler.swift"
  "College/Core/Platform/Services/BackgroundServiceSchedulerIDs.swift"
  "College/Core/Platform/Services/BackgroundServiceDeprecatedShims.swift"
  "College/App/BackgroundTaskCompliance.swift"
)

DISPATCH_WAIT_ALLOWLIST=(
  "College/App/CollegeAppDelegate.swift"
)

is_allowlisted() {
  local rel="$1"
  shift
  local entry
  for entry in "$@"; do
    [[ "$rel" == "$entry" ]] && return 0
  done
  return 1
}

# 1. Stray lifecycle calls
LIFECYCLE_PATTERN='\.startIfNeeded\(|\.startWatching\(|\.startMonitoring\(|\.startObserving'
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

rg -n "$LIFECYCLE_PATTERN" "$SCAN_DIR" --glob '*.swift' > "$TMP" 2>/dev/null || true
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  if is_allowlisted "$rel" "${LIFECYCLE_ALLOWLIST[@]}"; then
    continue
  fi
  fail "stray lifecycle call outside manifest/registry — $line"
done < "$TMP"

# 2. NSBackgroundActivityScheduler outside wrapper
rg -n 'NSBackgroundActivityScheduler' "$SCAN_DIR" --glob '*.swift' > "$TMP" 2>/dev/null || true
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  if is_allowlisted "$rel" "${SCHEDULER_ALLOWLIST[@]}"; then
    continue
  fi
  fail "NSBackgroundActivityScheduler outside wrapper — $line"
done < "$TMP"

# 3. DispatchGroup.wait outside terminate hook
rg -n 'group\.wait\(|DispatchGroup\(\)' "$SCAN_DIR" --glob '*.swift' > "$TMP" 2>/dev/null || true
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  if [[ "$rel" == *"CollegeAppDelegate.swift"* ]] && [[ "$line" == *"group.wait"* ]]; then
    continue
  fi
  if [[ "$rel" == *"Debug/DebugLogger.swift"* ]] && [[ "$line" == *"group.wait"* ]]; then
    continue
  fi
  if [[ "$line" == *"DispatchGroup()"* ]] && [[ "$line" != *"wait"* ]]; then
    continue
  fi
  if [[ "$line" == *"group.wait"* ]]; then
    fail "DispatchGroup.wait sync bridge — $line"
  fi
done < "$TMP"

# 4. ProfileRepository+*Sync no-op stubs (real extensions like +PlannerSync are allowed)
STUB_SYNC_FILES="$(find "$ROOT/College" -name 'ProfileRepository+*Sync*.swift' ! -name 'ProfileRepository+PlannerSync.swift' 2>/dev/null || true)"
if [[ -n "$STUB_SYNC_FILES" ]]; then
  fail "ProfileRepository+*Sync stub files present: $STUB_SYNC_FILES"
fi

# 5. startTrackedServiceTask removed
if rg -q 'startTrackedServiceTask' "$ROOT/College" --glob '*.swift' \
  --glob '!College/Core/Platform/Services/BackgroundServiceDeprecatedShims.swift' 2>/dev/null; then
  fail "startTrackedServiceTask reintroduced"
fi

# 6. Manifest completeness heuristic — *RefreshService / *Monitor types
MANIFEST_IDS="$ROOT/College/Core/Platform/Services/BackgroundServiceManifest.swift"
EXCEPTIONS="$ROOT/scripts/background-service-manifest-exceptions.txt"
mkdir -p "$(dirname "$EXCEPTIONS")"
touch "$EXCEPTIONS"

rg -l 'class \w+(RefreshService|Monitor)\b' "$SCAN_DIR" --glob '*.swift' > "$TMP" 2>/dev/null || true
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  rel="${file#"$ROOT/"}"
  [[ "$rel" == *"BackgroundServiceTemplate.swift" ]] && continue
  basename="$(basename "$file" .swift)"
  snake="$(echo "$basename" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]' | sed 's/_service$//' | sed 's/_monitor$/_monitor/')"
  if rg -q "id: \"${snake}\"" "$MANIFEST_IDS" 2>/dev/null; then
    continue
  fi
  if rg -q "^${basename}$" "$EXCEPTIONS" 2>/dev/null; then
    continue
  fi
  # Soft warning only — many monitors use different id conventions.
  echo "warning: no manifest id heuristic match for $rel (add to manifest or $EXCEPTIONS)"
done < "$TMP"

# 7. MainActor network smell (heuristic)
rg -n 'URLSession|\.data\(for:|\.data\(from:' "$SCAN_DIR" --glob '*RefreshService.swift' --glob '*Sync*.swift' --glob '*Monitor.swift' > "$TMP" 2>/dev/null || true
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  if [[ "$rel" == *"BackgroundServiceTemplate.swift" ]]; then
    continue
  fi
  if rg -q '@MainActor' "$file" 2>/dev/null && ! rg -q 'fetchOffMain|BackgroundServiceExecutor' "$file" 2>/dev/null; then
    echo "warning: possible MainActor network I/O — $rel (verify fetchOffMain usage)"
  fi
done < "$TMP"

# 8. Debug-only failure paths in refresh/sync services (warning)
rg -l '#if DEBUG' "$SCAN_DIR" --glob '*RefreshService.swift' --glob '*Sync*.swift' > "$TMP" 2>/dev/null || true
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  rel="${file#"$ROOT/"}"
  if rg -q 'print\(' "$file" 2>/dev/null \
    && ! rg -q 'BackgroundActivityReporter\.finish|BackgroundServiceExecutor\.runWorkUnit|onFailure:' "$file" 2>/dev/null; then
    echo "warning: possible debug-only failure path — $rel (verify Release-visible reporting)"
  fi
done < "$TMP"

MANIFEST="$ROOT/College/Core/Platform/Services/BackgroundServiceManifest.swift"
if command -v rg >/dev/null 2>&1; then
  manifest_count="$(rg -c 'BackgroundServiceDescriptor\(' "$MANIFEST" 2>/dev/null || echo 0)"
else
  manifest_count="$(grep -c 'BackgroundServiceDescriptor(' "$MANIFEST" 2>/dev/null || echo 0)"
fi
if [[ "$manifest_count" -lt 25 ]]; then
  fail "manifest descriptor count unexpectedly low ($manifest_count)"
fi

echo "background-service audit: $violations violation(s)"
if [[ "$violations" -gt 0 ]]; then
  exit 1
fi
