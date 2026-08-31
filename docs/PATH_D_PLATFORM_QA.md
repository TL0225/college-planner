# Path D platform visual QA

Manual checklist for per-OS shell fidelity. Run after major UI changes.

## Setup

1. `npm run tauri:dev` (or platform build) on each target OS.
2. Confirm `document.documentElement.dataset.platform` is `macos`, `windows`, or `linux` (set by `PlatformProvider`).
3. Optional: toggle **Settings → App → Display density** through Auto / Compact / Default / Comfortable.

## macOS

- [ ] Window controls and title bar feel native (traffic lights, drag region).
- [ ] Sidebar: correct font weight, `⌘` shortcuts in palette and welcome copy.
- [ ] Hub pills, command palette (`⌘K`), assistant (`⌘J`) open without focus traps.
- [ ] Trailing inspectors resize and persist width per hub.
- [ ] Reduce motion: page transitions respect `ui.reduceMotion`.

## Windows

- [ ] Window border subtle/none setting applies (`ui.windowStroke`).
- [ ] `Ctrl` shortcuts shown in palette, settings, welcome.
- [ ] Life / School / Career toolbars and segmented pills align at 1280×800 and 960 min width.
- [ ] Finance charts and calendar grids readable at compact density.

## Linux

- [ ] `data-platform="linux"` styles apply (if any linux-specific CSS).
- [ ] File dialogs and vault paths work; Library import flow usable.
- [ ] No layout overflow on narrow sidebar collapse (&lt;1024px).

## Cross-hub smoke (all platforms)

| Hub | Check |
|-----|--------|
| Home | Quick launch tiles navigate to Life, Career, Library, School, Assistant |
| School | Plan, Discover toolbar, degree requirements |
| Career | Pipeline list/board, Growth tabs, pathing inspector |
| Life | Schedule/Money pills, account inspector |
| Library | Files / Portfolio / Identity pills |
| Settings | App density Auto, theme, backup export |

## Screenshots (optional)

Save under `docs/assets/overhaul/` with names `{platform}-{hub}-{width}.png` when capturing baselines.
