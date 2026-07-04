#!/bin/zsh
# Xcode Cloud: trust mlx-swift-lm macro fingerprints and skip interactive validation.
set -euo pipefail

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
"${ROOT}/scripts/install-swiftpm-trust.sh"
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
