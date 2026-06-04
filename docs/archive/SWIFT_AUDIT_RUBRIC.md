# Swift Audit Rubric

Date: 2026-04-27

This rubric is used for the file-by-file legacy, performance, and deletion audit. It applies to all Swift files in `College`, `CollegeTests`, `CollegeUITests`, and `SourcePackages`.

## Severity

### High

Use `High` when a finding can affect user data, app startup, calendar/catalog correctness, security, privacy, or broad feature stability.

Examples:
- migration or compatibility logic that can affect persisted data,
- main-thread work likely to hitch common user flows,
- unsafe concurrency in shared services,
- god objects with high change blast radius,
- dependency pinning that can unexpectedly change runtime behavior.

### Medium

Use `Medium` when a finding is maintainability or performance debt with plausible user impact but lower immediate risk.

Examples:
- duplicated UI/service implementations,
- stale compatibility wrappers with narrow reach,
- repeated parsing or network setup outside the hottest paths,
- debug-only or low-fan-out code that may still be useful.

### Low

Use `Low` when a finding is cleanup debt, naming drift, minor style legacy, or dependency noise unlikely to affect users.

Examples:
- unused test scaffolding,
- upstream-only deprecation wrappers,
- minor outdated idioms without correctness or performance risk.

## Tags

- `legacy-api`: deprecated API, old framework style, compatibility wrapper.
- `legacy-data`: old persisted format, migration path, fallback model field.
- `god-object`: too many responsibilities in one type/file.
- `global-state`: singleton/shared mutable state with hidden dependencies.
- `dead-code-candidate`: no/near-zero references.
- `duplicate-implementation`: multiple implementations of the same responsibility.
- `main-thread-work`: heavy IO, CPU, parsing, or DB work on main actor/thread.
- `n-plus-one`: repeated fetch/network/parse work in loops.
- `recomposition-pressure`: large SwiftUI tree with broad state invalidation.
- `dependency-watch`: issue is primarily upstream/vendor-owned.
- `test-debt`: flaky, slow, template, or missing coverage issue.

## Action Classes

- `refactor`: keep behavior, reduce risk/complexity.
- `optimize`: improve performance or reduce resource use.
- `delete`: safe removal after verification.
- `monitor`: no immediate code change; revisit with evidence.
- `dependency-watch`: track upstream package/version state.
- `test-first`: add or stabilize tests before changing code.

## Deletion Confidence

- `High`: symbol/file has no Swift references and no known dynamic wiring.
- `Medium`: references are absent or minimal, but dynamic/debug/test use is plausible.
- `Low`: low fan-out, but current runtime or debug integration exists.

## Optimization Impact

- `Critical`: likely UI hitch, data stall, or startup blocker.
- `High`: visible latency, CPU, DB, memory, or battery impact in common flows.
- `Medium`: measurable overhead in less common or bounded flows.
- `Low`: cleanup-level efficiency improvement.

## Per-File Audit Entry Template

```text
Path:
Batch:
Track:
Lines:
Severity:
Tags:
Action:
Deletion confidence:
Optimization impact:
Evidence:
Finding:
Recommendation:
Validation:
```

