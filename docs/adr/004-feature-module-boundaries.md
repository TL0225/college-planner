# ADR 004: Feature Module Boundaries

**Status:** Accepted (charter); enforcement deferred to Phase 2  
**Date:** 2026-06-05

## Context

Feature code lives under `College/Features/` with no compile-time import boundaries. `Features/Calendar` can import `Features/Academics` today without build failure. Engineering toolbar architecture can reach A/A+ while enterprise boundary enforcement remains B+ until modules and CI exist.

## Decision

Document a **Phase 2 Platform Initiative** charter now; enforce boundaries after the toolbar refactor ships.

### Phase 2 deliverables

| Deliverable | Description |
| --- | --- |
| `Packages/CollegeCalendar/` etc. | One Swift package per major feature |
| `Package.swift` dependency edges | Features depend on Core/Shared only—not other features |
| `Scripts/check-feature-imports.sh` | Fail on forbidden cross-feature `import` |
| `.github/workflows/feature-boundaries.yml` | PR gate after packages exist |
| Migration order | Calendar → Academics → Career (lowest coupling first) |

### Kickoff charter

| Field | Requirement |
| --- | --- |
| **Owner** | Timothy Leung (project maintainer) — recorded at toolbar refactor ship gate, 2026-06-05 |
| **Hard kickoff** | Whichever occurs first: (1) toolbar refactor PR merged to `main`, or (2) **14 calendar days** after that merge (deadline: **2026-06-19**) |
| **Soft triggers** | Health check reports new cross-feature import; second parallel feature team lands work in `Features/` |
| **Max debt window** | 14 days post-toolbar-merge—cross-feature import debt accumulates fastest in this gap |
| **Interim protection** | Ship `check-feature-imports.sh` as **warn-only** in toolbar-architecture CI during Phases 0–6; PR checklist bans *new* `Features/X` → `Features/Y` imports |

### Exit criteria

Phase 2 is **done** when:

1. `feature-boundaries.yml` fails CI on forbidden cross-feature imports.
2. `import CollegeAcademics` inside `CollegeCalendar` sources fails CI.
3. Calendar package is extracted first; remaining features follow migration order.

## Consequences

- **Positive:** "Ship toolbar first" is bounded by a 14-day clock, not open-ended deferral.
- **Positive:** Warn-only script runs during toolbar work to prevent new debt.
- **Negative:** Until Phase 2 completes, feature coupling remains a manual review concern.
- **Owner:** Timothy Leung — Phase 2 kickoff clock starts at toolbar refactor PR merge (14-day deadline 2026-06-19).
