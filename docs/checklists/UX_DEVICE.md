# Phase 4U — UX overhaul: manual on-device checklist

One section per stage (`## U1` … `## U8`). Device: iPhone 16 Pro / Pro Max, iOS 26+. Seeds and screens through the DEBUG
launch arguments (`-TabulaSeed secondary|university|elementary`, `-TabulaScreen <route>`, `-TabulaNow` for a fixed
clock, see PHASE2_DEVICE.md). Every screen: default text, an intermediate size (xxLarge), AX-XXXL; light and dark;
Increase Contrast; Reduce Transparency; Reduce Motion; English, Slovak and German; VoiceOver.

## U4 — Timetable

Default clock: Tue 2026-10-13 10:20 Europe/Bratislava (period 3, SJL in the secondary seed). Secondary seed: this week
is "Week B" (the sample's own A/B labels); university seed: this week is "Even week", next week "Odd week".

### U4.1 Toolbar and title (H4, L2, L8, F20)
- [ ] `timetable.grid` (secondary): title "🏫 Gymnázium – 2.B"; the subtitle under it reads "12 Oct – 16 Oct · Week B".
      **Check the subtitle actually shows under an inline title on iOS 26** (API verified only in the SDK). If it does
      not appear, report it: the fallback is a principal toolbar item with title + subtitle.
- [ ] No "Week B" capsule and no date header in the content; the column headers start right under the bar.
- [ ] Trailing: ‹ › (one glass group), a gap, then ⋯. The ⋯ glyph never changes when switching views.
- [ ] ⋯ menu: View picker (Grid / Week / Day / Tiles with symbols, current one checked), then Edit Timetable, Add Lesson
      (+ "Change for This Day…" in Day/Tiles), then Density ›, Show Week › (secondary/university), Subjects.
- [ ] Edit Timetable opens Timetable Settings; Add Lesson opens the lesson editor prefilled with a free period of today
      (grid) or of the selected day (Day/Tiles); Subjects opens the subjects list.
- [ ] Tap › : the "Today" button appears on the leading side, subtitle shows "19 Oct – 23 Oct · Week A". Tap Today: back
      to this week, button gone. Day/Tiles: selecting another day of this week also shows Today; it returns to today.
- [ ] `timetable.grid-next-week`: starts on next week with "Today" visible (screenshot route).
- [ ] Long timetable name (rename to 40 characters): the title truncates with "…", buttons stay visible.
- [ ] `-TabulaSeed university` `timetable.week`: subtitle "12 Oct – 16 Oct · Even week"; next week "Odd week"; in Slovak
      "Párny týždeň" / "Nepárny týždeň"; never "Week Párny".
- [ ] VoiceOver: "Today, button, Shows the current week."; "Previous Week, button"; "Next Week, button";
      "View Options, button" (menu). Every menu item is read by its label.

### U4.2 Grid cells (H5, M14, L3)
- [ ] Every cell: short name on line 1, room on line 2 (also MAT Thu P2 and ANJ Wed P1, which have tasks); the task
      badge "☑ 1" sits in the bottom-right corner instead of replacing the room.
- [ ] Badge slot priority: DEJ Mon P5 (exam) shows the graduation cap; cells with tasks show ☑ + count; changed cells
      show their own symbol: FYZ Thu P1 / CHE Thu P3 clock (time changed), MAT Thu P2 → arrow-right-square (room) or
      person-gear (substitute) — compare with the lesson detail's "Changes on this day" symbols; INF Thu P7 ⊕ filled.
- [ ] Cancelled ANJ Thu P4: dimmed (clearly weaker than its neighbours), name and room struck through, red ⊗ badge at
      full strength. VoiceOver ends with "cancelled".
- [ ] Narrow cells (Dynamic Type xxLarge, or compact density): the emoji disappears before the name or room truncate.
- [ ] Current lesson (SJL Tue P3 at 10:20): black + yellow highlighter outline; the period number "3" in the gutter has
      a yellow highlighter background with black text. VoiceOver on the cell adds "in progress".
- [ ] Today's column header (TUE 13): tinted pill, day number in a filled ink-blue circle (not red). Dark mode: lighter
      ink with black number. Increase Contrast: darker ink.
- [ ] Thursday header: a small ⓘ-style exclamation symbol instead of the orange dot. VoiceOver on the header:
      "Thursday, 15 October, … lessons, … changes" (the change count, never colour alone).
- [ ] Empty slots (Mon P7, Wed P7, Fri P6–8, all P8): plain background, no dashes. Press and hold: dashed outline and
      "+" appear; release: quick add opens. VoiceOver: "…, period 7, 13:40 to 14:25, free, Adds a lesson in this period."
- [ ] Rows fill the screen down to the tab bar (no ~200 pt gap under period 8); with few periods the rows stop growing
      at twice their normal height.
- [ ] AX-XXXL: the grid becomes the day-by-day list (kept); the current lesson row shows the "NOW" tag; today's header
      tag is ink, not red.

### U4.3 Symbol legend (TipKit)
- [ ] Fresh install (delete and reinstall the app to reset TipKit):
      open the Timetable tab on the secondary seed WITHOUT `-TabulaNow` → an inline card "Symbols in the timetable"
      lists clock = Time changed, arrow = Room changed, people-gear = Substitute teacher, ⊕ = Extra lesson,
      ⊗ (red) = Cancelled, checklist = Open tasks, cap = Exam.
- [ ] Close (✕, 44 pt) hides it; it never returns after relaunch. VoiceOver: "Close, button".
- [ ] `timetable.grid-legend` (fixed clock) shows the card; plain `timetable.grid` with `-TabulaNow` never does.
- [ ] Weeks without changes (a holiday week) do not show the card.

### U4.4 Week and Day views (M11, M12, F18, F19, F03)
- [ ] `timetable.day` (secondary): the now line crosses the whole SJL card above it (2 pt red on a white/black halo),
      visible on the red card; "10:20" in a red capsule in the gutter; the "10:00" hour label is not covered (it hides
      only when the now label would overlap it).
- [ ] Repeat on a blue, grey, yellow and dark card (change `-TabulaNow` to 08:20, 11:20, 13:50): line always visible.
- [ ] Day cards: subject line, then "10:00–10:45" in semibold at the same size as the subject with the room next to it
      (map pin), teacher in footnote below. Card heights still match the lesson durations (compare 45 min vs a double).
- [ ] `timetable.week` (university): now line only in today's column, a faint hairline from the gutter label to it.
- [ ] Day view current card: highlighter outline. Cancelled block dimmed.
- [ ] AX-XXXL `timetable.day`: instead of five weekday columns a compact header ‹ [date picker] › (stacks when it does
      not fit); ‹ › move by school day (skipping weekends); the picker jumps to any date; the toolbar has no week arrows.
      Tiles: "Matematika" on its own full-width row (no "Mate-mati-ka"), symbol and period number above it, time and
      room below, badges on following lines.
- [ ] Subtitle still names the rotation week at AX sizes (cycle info preserved).

### U4.5 Tiles (M13, L5)
- [ ] `-TabulaSeed elementary` `timetable.tiles` at 10:20: past tiles dimmed, no ✓ anywhere; the current tile has the
      highlighter outline and a yellow "NOW" tag (German "JETZT", Slovak "TERAZ"); break separators unchanged.
- [ ] At rest the last tile ends above the floating tab bar after scrolling to the bottom (24 pt margin).
- [ ] Today tab (shares the tile): past lessons dimmed without ✓, current lesson with NOW — confirm this is acceptable
      to stage U3.

### U4.6 Quick add (H14)
- [ ] Tap Mon P7: the sheet is opaque grouped grey (no coloured grid behind the list), header
      "Every Monday · Week B · Period 7 (13:40–14:25)"; footer "The lesson is added to this week of the rotation only…".
- [ ] Elementary seed (no rotation): "Every Monday · Period 5 (…)", no footer.
- [ ] Slovak: "Každý pondelok · Týždeň B · Hodina 7 (13:40 – 14:25)"; German "Jeden Montag · Woche B · Stunde 7 (…)".
- [ ] Choose a subject: the cell fills for every Week-B Monday (check next Week-B week), not only this date.

### U4.7 Lesson detail (M15)
- [ ] `timetable.lesson-detail` (a changed lesson): section header "Changes on this day" (sentence case); each change
      row has its symbol (same as the grid badge).
- [ ] A time-changed lesson: the time row shows the new time in orange semibold with the clock-exclamation symbol and
      the usual time struck through in grey below. VoiceOver: "08:10 to 08:55, changed, usually 08:00 to 08:45".
- [ ] Room row uses the map pin. "Change for This Day" button text unchanged (U5b owns it).

### U4.8 Empty timetable (F22)
- [ ] Timetables manager › add a new timetable, make it active: banner "No lessons yet · Add your first lesson…" with a
      prominent "Add Lesson" button above the empty grid; the button opens the lesson editor.
- [ ] Add one lesson: the banner disappears.

### U4.9 States for every U4 screen
- [ ] Dark mode, Increase Contrast, Reduce Transparency (toolbar glass, legend card, quick-add sheet stay legible).
- [ ] German and Slovak: menu items, "Stundenplan bearbeiten", subtitle and quick-add header fit or wrap without
      word-internal breaks.
- [ ] Japanese / Chinese: subtitle "10月12日～16日 · B週" style fits; NOW tag "今" / "现在".
- [ ] Reduce Motion: nothing animates on its own (the now line jumps once a minute).

### Unverifiable without a device (U4)
- `navigationSubtitle` placement under an inline title; toolbar grouping with `ToolbarSpacer`; TipKit runtime display
  and persistence; press feedback of the quiet free slots; contrast of the backplate on every palette colour; the
  real height of the AX day header.
