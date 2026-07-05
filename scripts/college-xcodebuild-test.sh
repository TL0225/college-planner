#!/usr/bin/env bash
# Canonical xcodebuild entry point for College tests (max 2 parallel runners).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/xcodebuild-test-parallel-flags.sh
source "$SCRIPT_DIR/xcodebuild-test-parallel-flags.sh"

is_test_invocation=0
configuration="Debug"
prev=""
for arg in "$@"; do
  case "$arg" in
    test|test-without-building) is_test_invocation=1 ;;
  esac
  if [[ "$prev" == "-configuration" ]]; then
    configuration="$arg"
  fi
  prev="$arg"
done

# CI runners must not block on untrusted SwiftPM build-tool plugins (e.g. mlx-swift CudaBuild).
PLUGIN_ARGS=(-skipPackagePluginValidation -skipMacroValidation)

# Hosted CI has no Mac Development certs / provisioning profiles.
# Bash 3.2 + set -u treats empty "${arr[@]}" as unbound; always pass a real argv slot.
EXTRA_ARGS=()
if [[ "${CI:-}" == "true" ]]; then
  if [[ "$is_test_invocation" -eq 0 ]]; then
    EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  elif [[ "$configuration" == "Release" ]]; then
    # Release XCTest hosts hang when unsigned on hosted macOS; ad-hoc sign without dev certs.
    EXTRA_ARGS+=(CODE_SIGN_IDENTITY=-)
  else
    EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  fi
fi

if [[ "$is_test_invocation" -eq 1 ]]; then
  exec xcodebuild "${PLUGIN_ARGS[@]}" "${XCODEBUILD_TEST_PARALLEL_ARGS[@]}" "$@" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
fi

exec xcodebuild "${PLUGIN_ARGS[@]}" "$@" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
