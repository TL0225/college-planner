#!/usr/bin/env bash
# College test parallelism budget — source from any script that invokes `xcodebuild test`.
# Never exceed two concurrent test runner processes (local + CI).

XCODEBUILD_TEST_PARALLEL_ENABLED="${XCODEBUILD_TEST_PARALLEL_ENABLED:-YES}"
XCODEBUILD_TEST_MAX_PARALLEL_WORKERS="${XCODEBUILD_TEST_MAX_PARALLEL_WORKERS:-2}"

XCODEBUILD_TEST_PARALLEL_ARGS=(
  -parallel-testing-enabled "$XCODEBUILD_TEST_PARALLEL_ENABLED"
  -maximum-parallel-testing-workers "$XCODEBUILD_TEST_MAX_PARALLEL_WORKERS"
)

export XCODEBUILD_TEST_PARALLEL_ENABLED
export XCODEBUILD_TEST_MAX_PARALLEL_WORKERS
export XCODEBUILD_TEST_PARALLEL_ARGS
