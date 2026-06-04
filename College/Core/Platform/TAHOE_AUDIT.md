# macOS Tahoe (26) Calendar UX Audit — Phase 0

Completed checklist for College calendar surfaces (Xcode 26 / macOS 26 SDK).

## Layout

- [x] Sidebar inset + calendar grid alignment verified under `backgroundExtensionEffect`
- [x] Floating `CalendarModalHost` is canonical add/edit path (no calendar `.sheet`)
- [x] Toolbar search via `AppToolbarCoordinator` + results overlay on calendar page

## Chrome

- [x] `MonthCalendarCell` / `TimeEventBlock` use `DesignSystem` glass tokens
- [x] `EventDetailPopover` uses popover (not sheet) → Edit routes to modal host

## Settings

- [x] `SettingsPanels_Calendar` grouped sections (general, work hours, integrations)

## Known follow-ups (non-blocking)

- Scrollbar hover shift on dense week view — track separately from architecture PRs
- Liquid Glass tuning on connection bar — cosmetic

## Deployment / FFI

- Documented in `College/Platform/FFI/CALENDAR_FFI.md`
- `CollegePlatform` SPM boundary enforced via `scripts/check-platform-boundary.sh`

## Availability (Phase 8 gate)

- **Decision:** local-only HTTP stub (`AvailabilityLinkService`, no cloud v1)
