#!/usr/bin/env bash
# Verify main app and share extension declare the same app group (M30-075).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_GROUP="group.com.timothy.college"
ENTITLEMENTS=(
  "College/College.entitlements"
  "CollegeShareExtension/CollegeShareExtension.entitlements"
)

for file in "${ENTITLEMENTS[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: missing entitlements file: $file"
    exit 1
  fi
  if ! plutil -p "$file" | grep -q "\"$APP_GROUP\""; then
    echo "ERROR: $file missing application group $APP_GROUP"
    exit 1
  fi
done

echo "OK: app group $APP_GROUP present in main app and share extension"
