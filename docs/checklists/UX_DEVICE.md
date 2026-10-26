# Phase 4U on-device checklist (UX overhaul)

Device: iPhone 16 Pro / Pro Max, iOS 26 or later; Apple Watch for the watch rows. Install the build from the stage branch
(`bash scripts/xtool-dev.sh`, or TestFlight when available). Every row: tick, or note what you saw (a screenshot helps).
Settings used below: **Larger Text** (Settings › Accessibility › Display & Text Size › Larger Text, slider to the
right end = AX-XXXL), **Increase Contrast**, **Reduce Motion**, **Reduce Transparency**, **Dark Mode**, per-app
language (Settings › Apps › Tabula › Language), **24-Hour Time** (Settings › General › Date & Time).

Specs: `docs/specs/UX_OVERHAUL_PLAN.md` (decisions D1, D4, D12), `docs/ux-review/design_ui_ux_fix_OPUS.md`.

## U1 — design foundation

The debug screen `debug.design` (DEBUG builds: launch argument `-TabulaScreen debug.design`, or the CI screenshot
`debug.design@secondary`) shows the tokens, the NowMarker, the type scale and every app symbol on one page.

### U1.1 Ink tint and tokens (D1)
- [ ] Light mode: buttons, links, toggles that are on, selected tabs and selection checkmarks are **royal blue ink**
      (#2541B2), not the bright system blue. Same in sheets (editors, lesson detail).
- [ ] Dark mode: the ink is a soft periwinkle (#8EA2FF), readable on black and dark-grey cards.
- [ ] Increase Contrast on: the ink gets darker in light mode (#1A2F85) and lighter in dark mode; `debug.design` shows
      "Increase Contrast" in the Environment row and the new hex values.
- [ ] Widgets (Home Screen, all sizes) and the Lock Screen Live Activity use the ink for tinted elements.
- [ ] `debug.design` › Tokens: each swatch matches its name; the contrast figures read ≥ 4.5 for ink, correction and
      pencil on the card of the current appearance.

### U1.2 App symbols (M8, H5)
- [ ] `debug.design` › AppSymbol: "Missing symbols: 0", every row has a green check and a visible glyph. **If any row
      shows a red octagon, note its name**: the name is wrong on this iOS version.
- [ ] Today / Timetable list rows: the room uses the **map pin** (same as Exams), not a door.
- [ ] A lesson with only a room change shows the "arrow into a square" badge; only a time change the clock with "!";
      a substitute teacher the two people with a gear; cancelled a filled ×; an extra lesson a filled +.
      The ↻ arrows no longer appear on change badges (they stay for "Repeats" only).
- [ ] Next exam widget uses the graduation cap (was a clipboard).

### U1.3 Prominent buttons in dark mode (RISKS #86)
- [ ] Dark mode, onboarding: the **Next** / **Get Started** button label is black on the light ink and easy to read.
- [ ] Dark mode, Tasks: the selected filter chip has black text on ink; unselected chips have white (primary) text.
- [ ] Note whether other prominent buttons (not yet converted by later stages) show white text on the light ink
      (expected to be hard to read; report where).

### U1.4 12/24-hour clock (D4 / H1)
- [ ] Settings › Calendar & time › Time format shows **System** on a fresh install (onboarding does not change it).
- [ ] iOS 24-Hour Time **off**, app setting System: lesson editor, exam editor, bell editor and reminder-rule time
      pickers show AM/PM, and so does the app's text ("8:00 AM").
- [ ] iOS 24-Hour Time **on**, app setting System: all of the above show 24-hour times, pickers included.
- [ ] App setting **24-hour** with iOS set to 12-hour (US region): every DatePicker wheel/compact picker shows 24-hour
      values (no AM/PM column), matching the text. The reminder-rule screen no longer mixes "at 17:00" with
      "7:00 AM".
- [ ] App setting **12-hour** with a Slovak region: pickers show AM/PM.
- [ ] Changing the setting while an editor is closed, then opening the editor: the picker follows immediately.

### U1.5 Language still correct with the injected locale (RISKS #87)
- [ ] Device language Slovak: all app text is Slovak (spot-check Today, Settings, an editor).
- [ ] Per-app language German (device English): app text is German, dates are German.
- [ ] Device language not supported by the app (e.g. Swedish): app text falls back to English, as before U1.
- [ ] Japanese or Simplified Chinese: the NowMarker reads 今 / 现在 and fits; time pickers follow the setting.

### U1.6 Contrast fixes in shared components (C2)
- [ ] Settings › Appearance: the **Pro** marker next to Pro palettes is ink text in a light-ink capsule, clearly
      readable even though the row is disabled (was pale blue). Dark mode: readable too.
- [ ] Onboarding: option cards and the language card are **white on a light-grey page** (dark mode: dark-grey cards
      on black); the option description text is clearly readable; "Open language settings" is readable.
- [ ] Onboarding: the **Back** button has a visible thin outline in light and dark mode.
- [ ] Tasks: open checkboxes are **neutral grey rings** for every subject (no red/green/yellow rings); a checked task
      shows an ink disc with a tick. Yellow-subject tasks have a visible ring.
- [ ] Tasks filter chips: unselected chip text is black (white in dark mode); the Overdue chip only has a red icon.
- [ ] Timetable grid: empty slots have a thin solid grey outline with a small grey +, visible on white and black.

### U1.7 Standard close button (M7)
- [ ] Lesson detail, task detail, exam detail (opened as sheets, e.g. from Today or a notification): the leading button
      is the system **×** close button (no "Done" text); Edit stays on the trailing side. VoiceOver reads "Close".
- [ ] "Nothing to show" sheets (e.g. an editor opened without a timetable) also use the ×.

### U1.8 Labels not repeated (M1)
- [ ] Timetable settings › Rotation, Lesson editor › Applies, Task editor › Due, Reminder rule › Follow-up, Day change ›
      What changes, Appearance › Mode: the word appears **once** (as the section header), the control shows only its
      value / options. VoiceOver still announces the control with that name.
- [ ] Larger Text AX-XXXL: those rows do not leave an empty label area.

### U1.9 Title fields and validation (M5, M6)
- [ ] New exam / new task / new subject / new timetable: the first text field is a large, left-aligned field with a
      grey hint ("Exam title", "Task title", "Subject name", "Timetable name"); it looks like a field you can type in.
- [ ] Opening a new editor shows **no** red or grey validation message. After typing a letter and deleting it, the hint
      ("Enter a title to save …" / "Enter a name.") appears directly under the title field.
- [ ] Day change editor: "Enter at least one change." is not shown on open; it appears after changing anything, or
      after tapping Save.
- [ ] Tapping **Save** on an incomplete form does not close the sheet; the messages appear next to the fields and
      VoiceOver announces "Some fields need a look before you can save."
- [ ] A complete form saves and closes as before.
- [ ] German and Slovak: the hint text and messages wrap, no truncation; AX-XXXL: the title field grows, the hint sits
      under it.

### U1.10 Times, rooms and type (M9, §9 type)
- [ ] Timetable list fallback (AX sizes) and other lesson rows: time and room are in the primary text colour (black /
      white), not grey; field icons are grey.
- [ ] Times on lesson tiles and rows use the rounded digits (SF Pro Rounded) and do not jiggle.
- [ ] Onboarding steppers show their value (e.g. "45 min") in rounded digits, readable grey.

### U1.11 Adaptive layout at large text (H13, F01)
- [ ] Larger Text AX-XXXL, onboarding profile step: each option shows its icon **above** the title, the title uses the
      full width (no "Elemen-tary" hyphenation), the checkmark stays visible. Slovak too.
- [ ] Larger Text AX-XXXL, timetable list rows: the subject badge sits above the subject name.
- [ ] Default text size: the same rows are side by side as before.
- [ ] `debug.design` › AdaptiveStack: "stacked yes" at AX sizes, "no" below; the icon never grows beyond ~40 pt.

### U1.12 NowMarker (signature element)
- [ ] `debug.design`: the small and regular **NOW** markers are black text on a yellow highlighter stroke with soft,
      slightly slanted ends, in light, dark and Increase Contrast; the word is never cut off at AX-XXXL.
- [ ] VoiceOver on the marker reads "Now" (not "N-O-W").
- [ ] Reduce Motion on: nothing changes (the marker never animates).
- [ ] (Watch, when the watch app adopts it) the marker renders the same.

### U1.13 Dates (L1)
- Screens adopt `contextualDate` in their own stages; nothing visible changes in U1. Linux tests cover the year
  boundary (`ContextualDateTests`).

### Not verifiable without a device
Actual resolved colours of the dynamic tokens (trait resolution in sheets, widgets and Live Activities), whether
`Button(role: .close)` renders the system ×, whether DatePickers honour the locale's hour-cycle keyword, string lookup
under the injected locale, whether a disabled row dims the ProBadge, the AX layouts, VoiceOver wording, and the SF
Symbol names that were not confirmed from an external list (`pencil.circle`, `exclamationmark.circle`, `circle`,
`list.bullet.indent`).
