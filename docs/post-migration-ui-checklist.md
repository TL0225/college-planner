# Post-migration UI checklist (manual QA)

Use after app-database-only cutover and Profile UI re-wire. Run on a Debug or Release build with your real data (or a fresh install per the fresh-cutover checklist in docs).

## Profile & academics

- [ ] Open **Profile** → edit name, pronouns, photo; save and relaunch — values persist
- [ ] **Achievements**: add, edit, delete; order stable after relaunch
- [ ] **Experiences**: add current role, end date on past role; persist after relaunch
- [ ] **Per-degree tabs**: college, degree level/type, majors/minors; specialization picker updates Academics cards
- [ ] **Graduation timeline** sheet: edit term credit caps; save; audit reflects caps

## Catalog & settings

- [ ] **Settings → Catalog**: skeleton sync for active school; progress strings mention app database (not local store)
- [ ] **Degree requirements** refresh for a program on your degrees
- [ ] Switch primary university / school — catalog container switches; Academics still loads requirements

## Calendar & focus

- [ ] Create/edit calendar events; search finds new events
- [ ] **Focus blocks** (if exposed in UI): add block, relaunch — block still listed (local store + legacy UserDefaults import)

## Vault & career

- [ ] Vault: add document, favorite, open; watched folder still scans when enabled
- [ ] Career: add application, change status; list refreshes without stale rows

## Privacy & wipe

- [ ] **Privacy overview** lists local store (not local store)
- [ ] **Wipe local data** → relaunch shows onboarding / empty state; no crash on second launch

## Automated gates (before sign-off)

```bash
./scripts/check-neutral-persistence-labels.sh
./scripts/check-no-vision-llm.sh
./scripts/check-no-gemma4.sh
xcodebuild test -scheme College -destination 'platform=macOS' -only-testing:CollegeTests
```
