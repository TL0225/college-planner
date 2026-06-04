# Career workspace — cross-surface QA handoff

Use this checklist when validating ingest, analytics, scheduler, and deep links against the Career visual overhaul.

## Resume library & vault

- Import the same PDF twice into Career resumes: second attempt should return the existing document (same filename under `Career · Resumes` folder) without duplicate blobs.
- Confirm `ensureCareerResumesVaultFolder()` creates a root folder named **Career · Resumes** in Documents / vault tree and new imports receive `parentFolderID`.
- Double-tap a resume card: Quick Look opens; drag-drop onto the grid still imports.
- Filters: **All** shows every resume; **General** / **Tailored** exclude archived; **Archived** only archived. Search matches display name, filename, tags, and target role.
- **Score**: ATS % persists in `careerResumeMetadataJSON` on `VaultDocumentEntity`; tier colors align to green ≥ 75, yellow ≥ 50, red below 50.

## Board & KPIs

- Kanban KPI strip counts match `careerPipelineMetrics()` / analytics popover definitions (applied pipeline, interview %, offer %).
- Cross-lane drag-and-drop, inspector selection, and VoiceOver labels on cards still behave as before.

## Networking hybrid grid

- Jobs (applied + interviewing) and **orphan** recruiter contacts (`application == nil`) appear in the two-column grid; row-major arrow keys move selection and scroll into view.
- Context menu on job tiles: Snooze and Follow-up Complete.
- Detail pane: job path uses networking notes + AI draft; contact path uses `lastInteractionSummary` and separate AI draft. Draft text is keyed by stable `NetworkingFollowUpItem.id` in `AppStorage` (`career.networking.outreachDrafts.v1`).
- KPI strip: contact count (all `RecruiterContactEntity`), follow-up queue count, coffee count (`CareerEventEntity` with `kindRaw == "coffee"`).

## Recruiter contact model

- New attributes migrate cleanly (lightweight): `roleTitle`, `companyName`, `contactKindRaw`, `isFavorite`, interaction fields.
- `displayCompanyName` prefers `application?.company` over orphan `companyName`. Linking a job clears orphan `companyName` via `applyNetworkingLinkWritePolicyForLinkedJob()`.

## Share extension & deep links

- Regression: share-extension save path (`upsertCareerApplication`) still lands on the board with expected status and keywords.
- `NotificationCenter` `.careerOpenBoardJob` from resume inspector still focuses the correct job when switching to Board.

## Scheduler & widgets

- Follow-up snooze / complete events still update `CareerEventEntity` and queue ordering.
- Widgets that reuse `careerNetworkingQueueFetchRequest()` remain consistent with queue definition (applied + interviewing only — hybrid grid adds orphan contacts separately).
