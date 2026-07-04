#!/usr/bin/env bash
# When rust-typst/libcollege_typst.a is absent (typical on CI), clear the
# forced Typst link and COLLEGE_TYPST_LINKED so CollegeTypst uses the Swift
# fallback renderer. Local builds that ran rust-typst/build_macos.sh keep
# project settings unchanged.
#
# Usage: source this file with the same args you pass to xcodebuild, e.g.
#   source scripts/xcodebuild-typst-flags.sh "$@"
#   xcodebuild ... "${XCODEBUILD_TYPST_ARGS[@]}"

XCODEBUILD_TYPST_ARGS=()
_college_typst_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$_college_typst_root/rust-typst/libcollege_typst.a" ]]; then
  _college_typst_cfg=Debug
  _college_typst_prev=
  for _college_typst_arg in "$@"; do
    if [[ "$_college_typst_prev" == "-configuration" ]]; then
      _college_typst_cfg="$_college_typst_arg"
    fi
    _college_typst_prev="$_college_typst_arg"
  done
  XCODEBUILD_TYPST_ARGS+=(OTHER_LDFLAGS= LIBRARY_SEARCH_PATHS=)
  if [[ "$_college_typst_cfg" == "Release" ]]; then
    XCODEBUILD_TYPST_ARGS+=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=COLLEGE_TEST_HOOKS")
  else
    XCODEBUILD_TYPST_ARGS+=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG COLLEGE_TEST_HOOKS")
  fi
fi
unset _college_typst_root _college_typst_cfg _college_typst_prev _college_typst_arg
