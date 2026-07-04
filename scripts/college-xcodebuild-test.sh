#!/usr/bin/env bash
# Canonical xcodebuild entry point for College tests (max 2 parallel runners).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/xcodebuild-test-parallel-flags.sh
source "$SCRIPT_DIR/xcodebuild-test-parallel-flags.sh"

is_test_invocation=0
for arg in "$@"; do
  case "$arg" in
    test|test-without-building) is_test_invocation=1 ;;
  esac
done

# CI runners must not block on untrusted SwiftPM build-tool plugins (e.g. mlx-swift CudaBuild).
PLUGIN_ARGS=(-skipPackagePluginValidation -skipMacroValidation)

if [[ "$is_test_invocation" -eq 1 ]]; then
  exec xcodebuild "${PLUGIN_ARGS[@]}" "${XCODEBUILD_TEST_PARALLEL_ARGS[@]}" "$@"
fi

exec xcodebuild "${PLUGIN_ARGS[@]}" "$@"
