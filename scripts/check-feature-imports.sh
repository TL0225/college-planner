#!/usr/bin/env bash
# Cross-feature import boundary checker (ADR 004 Phase 2).
#
# Detects forbidden coupling between College/Features/* modules:
#   - import College<Feature> from a different feature target
#   - path references to College/Features/<OtherFeature>/ (or Features/<OtherFeature>/)
#   - explicit // cross-feature: debt markers
#
# Allowed shared modules (not counted as violations):
#   - CollegePlatform, CollegeCore
#
# Legacy allowlist (fail mode only — remove as packages land):
#   (none yet; Calendar → CollegePlatform imports are allowed shared deps)
#
# Usage:
#   bash scripts/check-feature-imports.sh [warn|fail]
#   warn (default): print warnings, exit 0
#   fail: exit 1 when non-allowlisted violations exist
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEATURES="$ROOT/College/Features"
MODE="${1:-warn}"

if [[ ! -d "$FEATURES" ]]; then
  echo "check-feature-imports: Features directory missing"
  exit 0
fi

ALLOWED_MODULES="CollegePlatform|CollegeCore"

feature_dirs=()
while IFS= read -r dir; do
  feature_dirs+=("$(basename "$dir")")
done < <(find "$FEATURES" -mindepth 1 -maxdepth 1 -type d | sort)

feature_for_path() {
  local rel="${1#"$ROOT"/}"
  rel="${rel#College/Features/}"
  echo "${rel%%/*}"
}

# Legacy violations exempt from fail mode. Format: "<relative-path>|<reason>"
LEGACY_ALLOWLIST=()

is_legacy_allowed() {
  local rel="$1"
  for entry in "${LEGACY_ALLOWLIST[@]}"; do
    local path="${entry%%|*}"
    if [[ "$rel" == "$path" ]]; then
      return 0
    fi
  done
  return 1
}

violations=()

# 1) Cross-feature College module imports
import_hits="$(grep -R -n -E "^[[:space:]]*import[[:space:]]+College" "$FEATURES" --include='*.swift' || true)"
if [[ -n "$import_hits" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line_no="${rest%%:*}"
    line="${rest#*:}"
    rel="${file#"$ROOT"/}"
    feature_dir="$(feature_for_path "$rel")"
    imported="$(sed -E 's/^[[:space:]]*import[[:space:]]+([A-Za-z0-9_]+).*/\1/' <<<"$line")"
    if [[ "$imported" =~ ^($ALLOWED_MODULES)$ ]]; then
      continue
    fi
    own_module="College${feature_dir}"
    if [[ "$imported" == "$own_module" ]]; then
      continue
    fi
    matched_feature=""
    for other in "${feature_dirs[@]}"; do
      if [[ "$imported" == "College${other}" ]]; then
        matched_feature="$other"
        break
      fi
    done
    if [[ -n "$matched_feature" && "$matched_feature" != "$feature_dir" ]]; then
      violations+=("$rel:$line_no imports $imported from Features/$feature_dir")
    elif [[ -z "$matched_feature" ]]; then
      violations+=("$rel:$line_no imports unknown College module $imported (feature=$feature_dir)")
    fi
  done <<<"$import_hits"
fi

# 2) Path references and cross-feature markers
for other in "${feature_dirs[@]}"; do
  path_hits="$(grep -R -n -E "(College/)?Features/${other}/|\\.\\./${other}/" "$FEATURES" --include='*.swift' || true)"
  if [[ -n "$path_hits" ]]; then
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      file="${hit%%:*}"
      rest="${hit#*:}"
      line_no="${rest%%:*}"
      rel="${file#"$ROOT"/}"
      feature_dir="$(feature_for_path "$rel")"
      if [[ "$other" == "$feature_dir" ]]; then
        continue
      fi
      violations+=("$rel:$line_no references Features/$other from Features/$feature_dir")
    done <<<"$path_hits"
  fi
done

marker_hits="$(grep -R -n -E "^[[:space:]]*//[[:space:]]*cross-feature:" "$FEATURES" --include='*.swift' || true)"
if [[ -n "$marker_hits" ]]; then
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line_no="${rest%%:*}"
    line="${rest#*:}"
    rel="${file#"$ROOT"/}"
    note="$(sed -E 's/^[[:space:]]*\/\/[[:space:]]*cross-feature:[[:space:]]*//' <<<"$line")"
    violations+=("$rel:$line_no marked cross-feature: $note")
  done <<<"$marker_hits"
fi

if ((${#violations[@]} == 0)); then
  echo "check-feature-imports: no flagged cross-feature imports"
  exit 0
fi

blocking=()
allowed=()
for violation in "${violations[@]}"; do
  rel="${violation%%:*}"
  if [[ "$MODE" == "fail" ]] && is_legacy_allowed "$rel" "$violation"; then
    allowed+=("$violation")
  else
    blocking+=("$violation")
  fi
done

if ((${#allowed[@]} > 0)); then
  echo "check-feature-imports: ${#allowed[@]} legacy allowlist match(es)"
  printf ' - %s (allowlisted)\n' "${allowed[@]}"
fi

if ((${#blocking[@]} == 0)); then
  echo "check-feature-imports: all violations allowlisted"
  exit 0
fi

if [[ "$MODE" == "fail" ]]; then
  echo "check-feature-imports: ${#blocking[@]} violation(s)"
else
  echo "check-feature-imports: ${#blocking[@]} warning(s)"
fi
printf ' - %s\n' "${blocking[@]}"

if [[ "$MODE" == "fail" ]]; then
  exit 1
fi

exit 0
