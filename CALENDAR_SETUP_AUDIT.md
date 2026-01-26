# Calendar Setup Audit (UI/UX + Interactions + Animation + Recommendations)

**Scope of this audit (code-based):**
- `College/CalendarView.swift` (Month/Week/Day UI, interactions, keyboard shortcuts, event layout)
- `College/AddCalendarItemOverlay.swift` (Add/Edit modal UX + form state + persistence mapping)
- `College/CoreDataManager.swift` (calendar event CRUD + fetch)

> Note: This is a UX/product audit, but every claim about “what the app does today” is based on the code paths above.

---

## 1) What exists today (feature inventory)

### A. Navigation / entry points
- `CalendarView` shows `CalendarMainContent` with:
  - `selectedSemesterID` (default semester chosen on appear)
  - `displayedMonth` as the anchor date for month/week/day
  - `modalCoordinator.activeModal = .addCalendarItem(...)` as the create entry point

### B. Top bar (Month/Week/Day)
Implemented in `CalendarMainContent.calendarTopBar`:
- Title changes with view mode:
  - Month: `LLLL yyyy`
  - Week: formatted range string (e.g. “Jan 7 – Jan 13, 2026”)
  - Day: `EEEE, MMM d`
- Controls:
  - Month mode only: chevron left/right (changes `displayedMonth` by ±1 month)
  - “View today” button (Cmd+T)
  - View mode segmented control (Cmd+1/2/3)
  - “Create new” (Cmd+N)
- Global keyboard shortcuts:
  - Cmd+← / Cmd+→ navigates by:
    - month in Month mode
    - ±7 days in Week mode
    - ±1 day in Day mode

### C. Month view
- 6×7 grid (Sunday-start week headers)
- Each day cell:
  - Shows day number, “TODAY” styling, and a list of chips
  - “BREAK” styling exists (striped), but whether it’s used depends on upstream data
  - Tap empty day: creates event defaulting to 9–10am
  - Tap event chip: opens edit modal
  - Context menu on chips:
    - Events: Edit / Delete
    - Tasks: Delete
- Tasks appear as chips with “checklist” icon and a time prefix.

### D. Week view (schedule)
- 7 columns, 24-hour vertical timeline
- All-day row:
  - Up to 2 all-day chips per day, +overflow badge
  - Chips can be dragged horizontally to move by day
- Timed schedule grid:
  - Drag to select time range to create event (snaps to 15-minute increments; minimum 30 minutes)
  - Tap to create (snaps to 15 minutes; default duration 60 minutes)
  - Drag existing event block:
    - vertical drag moves time (snaps to 15)
    - horizontal drag moves between days
  - Resize handle at bottom of event block (vertical; snaps to 15)
- “Now” indicator line when the week contains “today” (TimelineView updates every 60s)

### E. Day view (single-day schedule)
- Same interaction model as Week view but with a single day column:
  - All-day row (up to 3 chips + overflow)
  - Drag-select create
  - Tap-create
  - Drag move and resize event blocks
  - “Now” indicator when viewing today

### F. Event visual design
- Timed events are rendered as blocks with:
  - tinted background (`color.opacity(0.12)`)
  - a left color bar
  - subtle border
  - title + optional location
  - resize affordance (tiny capsule handle)
- Color rules:
  - If event has a course → stable deterministic palette based on course code
  - Otherwise → `DesignSystem.Colors.primary`

### G. Overlap layout
- Overlapping timed events are laid out into columns (first-fit assignment) and each collision group gets a `columnCount`.
- This is a solid baseline for Week/Day views.

### H. Add/Edit modal (`AddCalendarItemOverlay`)
- Full-screen dim background (60% black); click outside closes the modal.
- Centered “card” with left content + right “settings” panel.
- Fields:
  - Title
  - Start and end date/time (custom popovers)
  - All-day toggle (checkbox)
  - Repeat menu (Daily/Weekly/Monthly/etc.)
  - Location
  - Description/notes
  - Guests (chips)
  - Event type cards (Class/Assignment/Personal/Meeting)
  - Course association
  - Notification toggles (email/push) + static “30 minutes before” text
- Actions:
  - Save/Update
  - Cancel
  - Delete (edit mode only) with confirmation dialog

### I. Persistence mapping (what actually saves)
Via `CoreDataManager.addCalendarEvent` / `updateCalendarEvent`:
- Saved:
  - title, startDate, endDate, allDay
  - notes (from Description)
  - location
  - semester (passed in)
  - course association
  - createdAt / lastUpdated
- **Not saved (currently UI-only):**
  - repeatOption
  - eventType
  - guests
  - emailReminder / pushNotification

---

## 2) UI/UX evaluation (what’s strong vs. what’s friction)

### Strong parts
- **Fast creation**: tap-to-create and drag-to-select are the two core “power calendar” interactions.
- **Direct manipulation**: dragging blocks to move/resize is the heart of week/day calendars, and you have it.
- **Snapping**: 15-minute snapping is a good default; 30-minute minimum on range-select prevents tiny events.
- **Localized time formatting**: hour labels use localized template `"j"`.
- **Now indicator**: periodic TimelineView update is a nice touch for Week/Day.
- **Overlap layout**: columns for conflicts are essential; baseline algorithm is correct.
- **Month chip context menus**: quick edit/delete is good; tasks are present in month view.

### UX friction points
- **Accidental dismissal risk**: clicking the dimmed background closes Add/Edit; easy to lose work (no “Discard changes?” guard).
- **Modal shows features that don’t persist**:
  - Repeat, guests, event type, reminders all look real, but none are saved.
  - This creates a trust gap (“I set a repeat/reminder but it didn’t stick”).
- **Inconsistent capabilities by view**:
  - Month view supports delete via context menu.
  - Week/Day event blocks do not expose delete/context menus; only tap-to-edit then delete.
- **Color semantics mismatch**:
  - Event “type” implies different colors, but the calendar uses course-based or primary color only.
- **Potential multi-day event rendering issues in Month view**:
  - Month chip generation iterates from `startDay` through `endDay` inclusive.
  - For all-day events stored as `[startDay, nextDay)` this can show the event on the day after it ends.
- **Semester filtering appears bypassed in calendar fetch**:
  - In `reloadCalendarData()`, the code sets `let semester: SemesterEntity? = nil` and fetches without the selected semester.
  - If the intent was per-semester calendar, the UI state and fetch are out of sync.
- **Popovers forced into light mode**:
  - Date and time pickers call `.environment(\.colorScheme, .light)` which will look wrong once you introduce dark mode.

### Visual hierarchy & density
- Month view chips are readable but can get dense quickly.
- Break styling is visually clear.
- Week/Day schedule event blocks are clean and modern.

---

## 3) Interactions & gesture design review

### Creation
- **Month**: tap empty cell creates an event at 9–10am.
  - Good: predictable default.
  - Missing: user-configurable default time (common in calendar apps).
- **Week/Day**:
  - Drag-select: creates event spanning selection; enforces minimum 30 min.
  - Tap: creates 60-min event.

### Move/resize
- Move:
  - Snaps to 15 minutes.
  - Week view also allows horizontal day shift.
- Resize:
  - Bottom handle only.
  - No constraints besides “at least one snap increment long.”

### Gesture conflicts / usability
- Using `DragGesture(minimumDistance: 0)` for tap-to-create is a standard workaround, but it can sometimes conflict with scroll intent.
- You have a guard for “moved < 6, predicted < 18” which helps.

### Discoverability
- Resize handle is subtle (good aesthetics, but low discoverability).
- Hover affordances are now present for macOS pointer users (Week/Day grid highlights the hovered 15‑min slot; event blocks lift on hover).

---

## 4) Animations & transitions (what exists vs. gaps)

### Exists
- Mode switcher highlight animates (`easeInOut 0.16`).
- View mode switching (Month ↔ Week ↔ Day ↔ Agenda) now crossfades with a subtle scale.
- Month navigation (previous/next month) now transitions with a direction-aware slide + fade.
- Overlays (command palette, quick add, editors/modals) now present/dismiss with subtle fade + scale.
- Week/Day timed blocks animate insert/remove (fade + subtle scale) when Reduce Motion is off.
- Week/Day dragging has rubber-banding at bounds and spring easing on release (when Reduce Motion is off).
- Week/Day dragging shows an in-drag placement “ghost” (dashed destination outline).
- Week/Day interactions respect Reduce Motion (animations/ghosts disabled or minimized).

### Implemented (details)
- **Month navigation (Month view)**
  - Uses a month-identity key so the grid is treated as “new content” each time you navigate.
  - Transition is direction-aware (previous month slides from left; next month slides from right) plus a subtle opacity fade.
  - Month changes triggered by keyboard navigation also animate when selection crosses the month boundary.
- **View mode switching (Month/Week/Day/Agenda)**
  - Container is keyed by `viewMode` so swapping modes is animated rather than an abrupt replace.
  - Transition is intentionally subtle (fade + tiny scale) to avoid “flashy” motion.
- **Hover affordances (Week/Day grids)**
  - Week/Day schedule grids highlight the hovered snap slot (15-minute cadence) via a mouse tracking bridge.
  - This improves discoverability of the “click to create” and “drag-select” interaction zones.
- **Direct manipulation (Week/Day blocks)**
  - Dragging beyond valid day/time bounds now rubber-bands instead of going “infinite”, then springs back on release (motion disabled when Reduce Motion is on).
  - While dragging, a dashed “ghost” outline indicates the snapped placement destination.
  - Create/delete now have lightweight confirmation via insertion/removal transitions (fade + subtle scale) for timed blocks.
- **Overlay motion**
  - Global modals and calendar overlays now animate with fade + slight scale on present/dismiss.
  - Goal: reduce the feeling of “UI teleporting” while staying consistent with the app’s current design system.

### Not present (noticeable gaps)
- None of the previously noted Week/Day motion gaps remain; create feedback now includes a short “bloom” from the tap/selection region (disabled with Reduce Motion).

### Still missing (detailed checklist)
- [x] **Snap-back / rubber-banding** when dropping an event into an invalid spot (springs back rather than teleporting).
- [x] **In-drag “ghost” preview**: while dragging, show a lightweight preview of the new time/day placement.
- [x] **Creation confirmation animation**:
  - [x] Tap-to-create: subtle scale/opacity in for the new block.
  - [x] Drag-select create: blooms from the selection rectangle.
- [x] **Deletion feedback** (context-menu delete, keyboard delete): subtle shrink/fade to confirm removal.
- [x] **Drag end easing**: valid drops ease into the snapped slot.
- [x] **Reduce Motion support**: custom transitions respect `accessibilityReduceMotion`.
- [x] **Consistency across surfaces**: week/day blocks use consistent insert/remove semantics.

### Recommended baseline motion principles
- Motion should communicate:
  - spatial navigation (month/week/day)
  - confirmation of creation
  - snapping outcomes
- Keep it subtle (short, non-bouncy, no heavy parallax) to match the current design system.

---

## 5) Accessibility & macOS ergonomics

### Potential issues
- Calendar top bar icon-only buttons now have explicit accessibility labels/help; other icon-only controls elsewhere may still need a sweep.
- Custom components with `PlainButtonStyle()` can reduce discoverability for keyboard and VoiceOver users.
- Contrast: some light grays (`f8fafc`, `f1f5f9`, etc.) may be too subtle depending on display.

### Keyboard
- Great start with Cmd shortcuts.

### Keyboard coverage (implemented vs remaining)
- **Implemented**
  - Arrow keys move the Week/Day focus cursor.
  - Delete/backspace deletes at the focused slot (Week/Day).
  - Esc dismisses command palette / quick add.
- **Still missing / optional polish**
  - [ ] Esc should dismiss *all* overlays/modals consistently (where appropriate).
  - [ ] Enter/Return should open the focused event/task details (if a block exists at focus).
  - [ ] More “calendar-native” shortcuts (e.g., `T` for Today when calendar has focus, `J/K` time stepping) if desired.

---

## 6) Data / architecture notes (impact UX)

- **Refresh strategy**: `reloadCalendarData()` is called on:
  - onAppear, viewMode change, displayedMonth change, semester change, and `objectWillChange`.
  - This is simple and safe, but can become expensive as event volume grows.
- **Semester filtering**: currently bypassed in calendar data reload.
  - This affects UX (the user thinks they’re scoped to a semester, but results might not be).

---

## 7) Amie Calendar Replication Roadmap (The "Joyful Productivity" Spec)

To match the functional and aesthetic standard of Amie Calendar, the following features and architectural changes are required. Amie differentiates itself via **unified task/calendar blocking**, **keyboard-first navigation**, and **playful, polished interactions**.

### Phase 1: Unified Task & Calendar (The Core Loop)
Amie's defining feature is the sidebar of tasks that can be dragged immediately into the grid to "time block" them.
1.  **Integrate the Unused Sidebar**:
    - The `CalendarSidebar` struct exists but is unused.
    - **Action**: Implement a resizing split-view layout. Left pane: Sidebar (Tasks/Courses). Right pane: `CalendarMainContent`.
    - **Amie Parity**: Sidebar should have a clean, modern list of "Todo" items (Tasks) and "Done" items.
2.  **Drag-and-Drop Time Blocking**:
    - **Action**: Enable `onDrag` for Sidebar Task items. Enable `onDrop` for the `Month`/`Week`/`Day` grids.
    - **Logic**: Dropping a task on a time slot should:
        - Set the task’s `dueDate` (or specific `plannedDate`).
        - Visually represent it as an event block on the grid (distinct style, maybe a checkbox icon inside the block).
        - Allow dragging it *back* to the sidebar to "un-schedule" it.
3.  **Unified Entity Model**:
    - **Action**: Ensure `CalendarView` queries return both `CalendarEventEntity` (native events) and `TaskEntity` (scheduled tasks) and renders them interchangeably in the grid.
    - **Amie Parity**: Events are for "where I need to be". Tasks are for "what I need to do". Both live on the grid.

### Phase 2: Speed & Intelligence (Keyboard First)
Amie is fast because you rarely touch the mouse.
4.  **Global Command Palette (Cmd+K)**:
    - **Action**: Implement a global overlay invoked by `Cmd+K`.
    - **Capabilities**: "Create Event", "Go to Today", "Switch View", "Search [Course]", "Email [Professor]".
5.  **Smart Natural Language Input (NLP)**:
    - **Action**: The current regex is a start, but Amie allows typing "Lunch with Sarah tomorrow 1pm" anywhere.
    - **UI**: A floating input bar (always available or invoked via `N`) that parses text live and animates the proposed slot on the grid *before* confirming.
6.  **Keyboard Grid Navigation**:
    - **Action**: Arrow keys should move a "focus cursor" around the grid slots. `Enter` to open details. `Backspace` to delete.

### Phase 3: "Joyful" Interactions (Polish & Motion)
Amie feels "alive" due to animation physics and confidence.
7.  **Rubber-banding & Snap-back**:
    - **Action**: When dragging an event, if you release in an invalid spot, it shouldn't just teleport back. It should *spring* back physically.
8.  **Direct Manipulation animations**:
    - **Action**: When creating an event (drag-select), the block should bloom/scale from the cursor.
    - **Action**: When completing a task, play a satisfying particle effect or checkmark animation.
9.  **Hover States (macOS)**:
    - **Action**: The grid should highlight the 15-min slot under the mouse.
    - **Action**: Events should lift (shadow depth) when hovered.

### Phase 4: Social & Context (The "Amie" Layer)
Amie focuses on "who".
10. **People-Centric Metadata**:
    - **Action**: Add a `Guests` or `People` relation to events.
    - **UI**: Show circular avatars in the event block on the grid.
11. **Spotify/Activity Integration** (College Context):
    - **Idea**: "Study Mode" toggle that logs time to a "Focus Stats" view.
    - **Amie Parity**: Amie tracks "What did I do?". This could track "What did I study?".

---

## 8) Progress Log (Completed Foundation)

### P0 — Trust & Correctness
- [x] **Semester Filtering**: Wired `selectedSemester()` into data fetch.
- [x] **Month Event Rendering**: Fixed all-day off-by-one errors.
- [x] **Modal Persistence**: Hidden non-persisted fields (Repeat, Guests) to avoid trust gaps.
- [x] **Discard Confirmation**: Added guard when checking out of Add/Edit modal.
- [x] **Event Duration**: Enforced minimum 15-min duration for timed events.

### P1 — Core Usability
- [x] **Context Menus**: Added Edit/Delete/Duplicate to grid blocks.
- [x] **Drag Feedback**: Added time tooltips and snap guidelines.
- [x] **Keyboard Navigation**: Implemented basic arrow key navigation and creation.
- [x] **Quick-Add NLP**: Implemented text parsing for "Title time date" inputs.
- [x] **Color Picker**: Replaced segmented control with 5-swatch palette + hex support.
- [x] **Search**: Added command-bar style search for events/tasks.
- [x] **Compact Layouts**: Reduced visual weight of Add/Edit overlays (~25%).

### P2 — UI/UX Polish (Motion + Hover + A11y)
- [x] **Month Navigation Transitions**: Added animated transitions for previous/next month.
- [x] **View Mode Transitions**: Added subtle transitions when switching Month/Week/Day/Agenda.
- [x] **Hover Slot Highlight**: Week/Day grids highlight the hovered 15-min slot.
- [x] **Overlay Motion + Labels**: Overlays animate in/out; key icon-only buttons have labels/help.
- [x] **Palette Ergonomics**: Esc dismisses command palette / quick add.
- [x] **Keyboard Delete**: Delete/backspace deletes at the focused Week/Day slot.

### P3 — Remaining Motion Polish (Completed)
- [x] **Snap-back physics**: spring back on invalid drops + easing on valid drops.
- [x] **In-drag ghost preview**: show placement preview while dragging.
- [x] **Create/delete confirmations**: subtle insertion/removal animation for blocks.
- [x] **Reduce Motion compliance**: respect `accessibilityReduceMotion`.

---

## 9) Final Open Questions for Amie-fication

1.  **Task persistence**: Do tasks become full calendar events when dragged, or do they stay "Tasks" with a `scheduledDate` property? (Recommended: Keep them as Tasks to allow "checking them off").
2.  **Sidebar behavior**: Should the sidebar be collapsible (Cmd+B)? (Amie allows this).
3.  **Mobile parity**: Amie is mobile-first. Is a companion iOS app planned?


