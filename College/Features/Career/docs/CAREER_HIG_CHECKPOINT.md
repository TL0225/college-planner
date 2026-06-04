# Career workspace — macOS HIG / Tahoe checkpoint

Target: Xcode 26 / macOS Tahoe SDK. Use this as a manual pass after visual changes; forward findings to the career QA owner.

## Chrome & layout

- **Toolbar**: Career workspace relies on parent `NavigationStack` search where applicable; segmented Board / Resumes / Networking reads clearly and respects reduced motion (`CareerWorkspaceView` motion flags).
- **HSplitView**: Resume library and Networking use split panes with sensible `minWidth` (inspector/detail ≥ 300–340pt). Verify split autosave if enabled elsewhere in app does not fight Career local layout.
- **Lists vs grids**: Networking uses `LazyVGrid` cards with selection outline; focus ring visible when navigating by keyboard.

## Liquid Glass & materials

- Cards use system control background colors (`CareerResumeLibraryTheme.cardBackground`, `NSColor.controlBackgroundColor` in legacy panes). Confirm contrast in light and dark Aqua against window background (`DesignSystem.Colors.bgMain`).

## Typography & controls

- Primary actions: **Upload** uses `.borderedProminent` with black tint in resume header; verify legibility in Dark Mode (tint may need dynamic color follow-up).
- KPI tiles reuse `CareerKPIStatCard`; numeric content uses monospaced digits where applicable in resume ATS readout.

## Accessibility

- Resume cards: combined accessibility label on `ResumeLibraryCard`.
- Networking cards: ensure VoiceOver order is title → subtitle → state before shipping a full audit.
- Arrow keys: `onMoveCommand` on the networking grid scroll view; verify when split pane is narrow, two-column assumption still matches visual columns.

## References

- Apple HIG: window layouts, split views, and keyboard navigation.
- WWDC sessions on design updates (e.g. window controls, materials) as applicable to Tahoe.
