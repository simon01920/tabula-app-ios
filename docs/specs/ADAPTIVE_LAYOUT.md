# Adaptive layout: iPhone, iPhone Duo, iPad (2026-11-11)

Human request: thoughtful support for iPhone Duo and iPad, existing iPhones unchanged. Layout follows the available
container width, the size classes and the safe areas. No device-name checks, no fixed screen sizes.
Device checklist: `docs/checklists/ADAPTIVE_DEVICE.md`. Risks: RISKS #114–#116. Environment: ENVIRONMENT §42.

## Platform

- `project.yml`: `TARGETED_DEVICE_FAMILY: "1,2"` for the app, the widget extension and the capture UI-test target;
  xtool already builds with its default `[1, 2]`.
- `Config/App-Info.plist` (both paths): `UISupportedInterfaceOrientations~ipad` = all four orientations, no
  `UIRequiresFullScreen`, so iPadOS can resize the app (Split View, Stage Manager, windowed apps).
  `validate_config.py` checks both.

## Breakpoints (`LayoutWidth`, TimetableUI, Linux-tested)

Measured per tab (`readsLayoutWidth()`, App/Sources/AppShell/LayoutWidthReader.swift): the tab's width minus the
leading and trailing safe area (where Duo puts its bars), plus both size classes.

| Class | Rule | Examples (points) | Used for |
|---|---|---|---|
| compact | horizontal OR vertical size class compact, or width < 600 | every iPhone portrait and landscape (Pro Max landscape is regular × compact), Duo outer display, Slide Over | today's phone layout, unchanged |
| medium | regular × regular, 600 ≤ width < 700 | narrow iPad windows | one column, readable cap |
| expanded | regular × regular, width ≥ 700 | iPad full screen, half Split View on 13-inch | list beside detail |

Content reasons: a list column needs ≥ 320 pt and a detail ≥ 380 pt (`listColumn` min 320 / ideal 360 / max 440);
the timetable grid keeps ≥ 600 pt beside a side panel (`fitsSidePanel`: width ≥ 960). One readable column is at most
672 pt (`readableMaximum`, UIKit's readable width at the default text size); at accessibility text sizes the cap is
off. A landscape iPhone never gets the tablet layout: its vertical size class is compact.

## Navigation

- One standard `TabView` with `.tabViewStyle(.sidebarAdaptable)` (iOS 18): a tab bar on iPhone, a tab bar that converts
  to a sidebar on iPad (HIG `tab-bars.md` › Tablet: "You can choose to have the tab bar appear as a fixed element, or
  with a button that converts it to a sidebar").
- iPhone Duo: no custom bar. The system moves standard tab bars and toolbars to the side on the outer display and on
  the inner display in landscape. HIG `designing-for-iphone-duo.md` › Vertical controls: "In general, don't override
  the default bar placement."; › Device poses: "A compact width layout for the outer display and a regular width layout
  for the inner display give you the fundamentals for every pose."
- Toolbars (Duo rules): every icon item already has a `Label` (title + symbol). Our own menus no longer use the
  ellipsis, which the HIG reserves for the system overflow ("Reserve the ellipsis symbol for overflow, and give other
  menus a distinct symbol"): Timetable "View Options" is `slider.horizontal.3`, the exam detail's "More" is
  `archivebox`. Not adopted: `ToolbarItemVisibilityPriority` / `ToolbarOverflowMenu` (iOS 27.0) and `ReservedRegion` /
  `ArrangementView` (iOS 27.1); the deployment target is iOS 26.0 and no screen needs them yet.

## Per screen

| Screen | Expanded | Compact (and iPhone) |
|---|---|---|
| Tasks | `NavigationSplitView`: grouped list (selected row highlighted) beside `TaskDetailView` in the detail column; placeholder "Select a Task" | unchanged: list, detail sheet |
| Exams | `NavigationSplitView`: list beside `ExamDetailContent`; the same `path` drives both layouts, so the open exam survives a resize | unchanged: list, pushed detail |
| Timetable | lesson detail in an `.inspector` column beside the grid when `fitsSidePanel` (≥ 960 pt), else the sheet | unchanged: sheet |
| Today | one column (UX decision R1, one order for every profile), rows capped at the readable width; no second column: the agenda beside the tasks did not earn its place | unchanged |
| Settings | every page (root and pushed) in one readable column (`readableWidth()` on the stack) | unchanged |
| Editors / forms | already sheets: iPadOS presents them as form sheets of limited width, so no cap is added | unchanged |

State on a resize: the selected tab and date live above the layout switch. Tasks: an open detail sheet stays open
(its editor may hold unsaved changes) and the same task is selected behind it; a selected task becomes the detail
sheet when the window narrows. Exams: the navigation path is shared. Timetable: the inspector lesson becomes the sheet
and back. Editors opened from a pane (Edit, Change for This Day, Add Homework, a task from the lesson) are presented by
the tab root, which survives the switch, so a resize never closes an editor.

Accessibility: VoiceOver reads the list column before the detail; the selected row carries `.isSelected`; text is never
capped (no readable cap at AX sizes); Reduce Motion: no custom transitions were added.

## Screenshots (CI)

`ui-screenshots.yml` inputs: `device` (an iPad or a multi-display iPhone is accepted when named explicitly; the default
pick and its Duo skip are unchanged), `displays` (Duo: `1 3`, see ENVIRONMENT §42), `orientation` (landscape:
`-TabulaOrientation` + Simulator's Device › Rotate Left). Routes for the split states: `tasks.selected`,
`exams.selected`, `timetable.grid-selected`. Simulator screenshots are simulation, not device verification.
