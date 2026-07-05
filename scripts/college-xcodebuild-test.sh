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
  if [[ "$configuration" == "Release" ]]; then
    # Release test hosts need ad-hoc signing on hosted macOS; apply to build-for-testing too.
    EXTRA_ARGS+=(CODE_SIGN_IDENTITY=-)
  elif [[ "$is_test_invocation" -eq 0 ]]; then
    EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  else
    EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
  fi
fi

if [[ "$is_test_invocation" -eq 1 ]]; then
  exec xcodebuild "${PLUGIN_ARGS[@]}" "${XCODEBUILD_TEST_PARALLEL_ARGS[@]}" "$@" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
fi

exec xcodebuild "${PLUGIN_ARGS[@]}" "$@" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
