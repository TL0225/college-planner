# UI overhaul audit (Phase 0)

## Completed

- [x] **5-hub IA** — `home`, `school`, `career`, `life`, `library` (`PILL_HUB_IDS` in `tokens.ts`; `MODULE_PILLS` in `App.tsx`)
- [x] **Career decomposition** — views split under `career/views/`, panels extracted
- [x] **Settings split** — per-domain pages under `settings/pages/`
- [x] **Typography migration (modules)** — semantic `text-caption` / `text-label` utilities; guardrail: `npm run check:typography`
- [x] **Design-system typography** — shared `text-body` / `text-meta` / `text-label` / `text-caption` in `styles.css`; DS components use semantic classes
- [x] **Density auto** — `ui.density` `auto` + `resolveDensity()` in `useShellLayout` / `App.tsx`
- [x] **`useCareerModule` hook** — state/logic extracted from `CareerModule.tsx`
- [x] **NotesEditor** — design-system primitive; wired in Profile + Career modals
- [x] **Density auto** — `ui.density=auto` resolves from window width
- [x] **Typography guardrail** — `npm run check:typography` (modules + design-system)
- [x] **Platform QA checklist** — [PATH_D_PLATFORM_QA.md](PATH_D_PLATFORM_QA.md)
- [x] **`NotesEditor`** — `design-system/components/NotesEditor.tsx` (e.g. profile notes)

## Dead code (cleanup status)

| Item | Status |
|------|--------|
| 7-hub `MODULE_PILLS` (college, finance, calendar, documents, assistant, profile) | **Removed** — 5 pills only |
| Old `ModuleId` values in `tokens.ts` | **Removed** — `HubId` + `settings` |
| `shellNavigate` custom events (after `navigate()` lands) | **Removed** — use `navigate({ hub, page })`; assistant tools remap via `migrateShellState` |
| Unused direct `@radix-ui/react-slot` dep | **Open** — transitive via Radix only |
| Standalone hub routing in `App.tsx` content switch | **Removed** — nested under School / Life / Library |
| `AssistantModule` as hub pill entry | **Removed** — sparkles / palette |
| `ProfileModule` as hub pill entry | **Removed** — settings / library |

## Click depth (top tasks — target ≤2 interactions)

| Task | Path |
|------|------|
| Add event | Home → Add event OR Life → Schedule → Add |
| Log expense | Home → Log expense OR Life → Money |
| Open planner | Home → School card OR School → Plan |
| Add application | Home → Career card OR Career → Pipeline |
| Upload document | Library → All → Import |
| Open settings | Avatar menu → Settings |
