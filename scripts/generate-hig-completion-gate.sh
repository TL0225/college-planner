#!/usr/bin/env bash
# M30-089 — Part 27.15 program completion gate dashboard.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build

COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

score() {
  local name=$1
  local value=$2
  echo "$name=$value"
}

# Static gates — 100 when script/workflow exists and recent waves landed.
shell_hig=$([[ -f College/App/CollegeApp.swift ]] && echo 100 || echo 0)
motion=$([[ -f College/Core/DesignSystem/CollegeInteractiveSurface.swift ]] \
  && bash scripts/check-motion-tokens.sh >/dev/null 2>&1 \
  && echo 100 || echo 0)
spatial=$([[ -f scripts/check-spatial-surfaces.sh ]] \
  && bash scripts/check-spatial-surfaces.sh >/dev/null 2>&1 \
  && echo 100 || echo 0)
toolbar_parity=$(bash scripts/check-toolbar-menu-parity.sh >/dev/null 2>&1 && echo 100 || echo 0)
share_ext=$(bash scripts/check-share-extension-entitlements.sh >/dev/null 2>&1 && echo 100 || echo 0)
privacy_adr=$([[ -f docs/adr/008-encryption-ship-posture.md && -f docs/adr/010-sync-local-first.md ]] && echo 100 || echo 0)
release_ci=$([[ -f .github/workflows/release-hardening.yml && -f .github/workflows/release-notarization.yml ]] && echo 100 || echo 0)
phase4=$([[ -f College/Features/Calendar/CalendarTasksDeadlinesHub+App.swift ]] && echo 100 || echo 0)
analytics=$([[ -f College/Core/Services/ProductAnalytics.swift ]] && echo 100 || echo 0)
assistant_ai=$([[ -f College/Features/Assistant/AssistantInference/AssistantInferenceAvailability.swift ]] && echo 100 || echo 0)

a11y_depth=$(bash scripts/check-a11y-depth.sh >/dev/null 2>&1 && echo 100 || echo 0)
ftue_empty=$(bash scripts/check-ftue-empty-states.sh >/dev/null 2>&1 && echo 100 || echo 0)
perf_p95=$([[ -f CollegeTests/Performance/ShellP95BudgetContractTests.swift ]] && echo 100 || echo 0)

overall=$(( (shell_hig + motion + toolbar_parity + share_ext + privacy_adr + release_ci + phase4 + analytics + assistant_ai + spatial + a11y_depth + ftue_empty + perf_p95) / 13 ))

cat > build/hig-completion-gate.json <<EOF
{
  "gitCommit": "${COMMIT}",
  "generatedAt": "${GENERATED_AT}",
  "dimensions": {
    "shellHIG": ${shell_hig},
    "motionSystem": ${motion},
    "toolbarMenuParity": ${toolbar_parity},
    "shareExtension": ${share_ext},
    "privacySyncADR": ${privacy_adr},
    "releaseReadiness": ${release_ci},
    "phase4Domain": ${phase4},
    "productAnalytics": ${analytics},
    "assistantAIHIG": ${assistant_ai},
    "spatialSurfaces": ${spatial},
    "accessibilityDepth": ${a11y_depth},
    "ftueEmptyStates": ${ftue_empty},
    "performanceP95": ${perf_p95}
  },
  "overall": ${overall},
  "target": 100
}
EOF

cat > build/hig-completion-gate.md <<EOF
# HIG Program Completion Gate (Part 27.15)

- Commit: \`${COMMIT}\`
- Generated: ${GENERATED_AT}
- Overall: **${overall}/100** (target 100)

| Dimension | Score |
|-----------|-------|
| Shell / HIG | ${shell_hig} |
| Motion system | ${motion} |
| Toolbar→menu parity | ${toolbar_parity} |
| Share extension | ${share_ext} |
| Privacy + sync ADR | ${privacy_adr} |
| Release readiness | ${release_ci} |
| Phase 4 domain | ${phase4} |
| Product analytics | ${analytics} |
| Assistant AI HIG | ${assistant_ai} |
| Spatial surfaces | ${spatial} |
| Accessibility depth | ${a11y_depth} |
| FTUE + empty states | ${ftue_empty} |
| Performance p95 budgets | ${perf_p95} |
EOF

echo "Wrote build/hig-completion-gate.json (overall ${overall}/100)"
