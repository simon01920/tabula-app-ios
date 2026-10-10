# Phase 2 gate report — App shell, onboarding, views, editors, settings, 12 languages

Status: **DRAFT — integration + translations running** · Plan: `docs/specs/PHASE2_PLAN.md` · Device checklist: `docs/checklists/PHASE2_DEVICE.md`

## Stages and model tier (CLAUDE.md "Model routing")
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| A Foundation | swiftui-engineer · **Opus 5.5 high** | AppModel/AppEnvironment, FileRepository in the App Group (with fallback), debounced serial saves, tab shell, route registry, TimetableUI components, seed/clock plumbing, DEBUG gating | validate ✓, both builds ✓; Release binary has 0 debug symbols |
| A QA | qa-reviewer · **Opus 5.5 high** | Approved with conditions. It found an onboarding data-wipe path, a lost save on a failed write, an unprotected background flush, and a test clock reaching real data | — |
| A fixes | swiftui-engineer · **Opus 5.5 high** | All conditions fixed (`4d1e635`) | 64 UI tests ✓ |
| B1 Onboarding | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | 7 steps; safe finish (replaces only an empty DB, otherwise adds); fresh-ID sample data | tests for both finish paths |
| B2 Today + Timetable | swiftui-engineer · **Opus 5.5 high** | Now & Next; grid / week blocks / day / tiles; week strip; A/B; quick add; lesson detail | 117 UI tests after merge |
| B3 Editors | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | Lesson, subject(s), bell, timetable, terms, day change, timetables manager; last-timetable guard | 162 UI tests after merge |
| B4 Settings + themes | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | Profile, calendar/time, appearance + palettes, reminders explainer, language, Pro tier display, about, Developer (DEBUG) | tests ✓ |
| Integration glue + screenshot list | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | _running_ | |
| C1 12 languages | localization-engineer-sonnet · **Sonnet 5.5 medium** | _running_ | |
| C3 final QA | qa-reviewer · **Opus 5.5 high** | _pending_ | |

Orchestrator-verified after all B merges (`10ea1e7`): `validate.sh` ALL CHECKS PASSED. That covers **502 core + 162 TimetableUI tests**, an xtool iOS build (17 s) and the watch type-check.

## Runtime evidence so far
CI simulator (iOS 27, run 37968712889, foundation only): the shell, Liquid Glass tab bar and seed data render. Slovak dates are formatted correctly. **Untranslated keys show as raw keys in Slovak.** iOS does not fall back to English per key, so C1 adds a completeness check and no partially translated language can ship.

### Full-app screenshot review (orchestrator, CI run 38010477525: 17 screens × light/dark/AX = 51 PNGs, no crash)
**Works as designed:**
- **Today:** Now & Next card with a progress bar, colour tiles, break separators, Liquid Glass tab bar.
- **Grid:** Week B label, change badges (time changed / cancelled struck through / added), double period, tap-to-add slots, the today marker, and a dot on the day with changes. It matches the reference patterns.
- **Week time-blocks:** proportional layout, with the short Thursday visible.
- **Lesson detail:** "Time changed — usually 08:00–08:45".
- **Onboarding:** profile step.
- **Subject editor:** live preview with the contrast ratio, named palette swatches, custom colour.
- **Settings.**
- **Largest text:** the grid switches to a readable list.
- **Dark mode** works everywhere.

**Bugs found (fix pass):**
1. **Frozen countdown is wrong.** Today shows "45:00" at 10:20 for a 10:00–10:45 lesson (should be 25:00). `Text(timerInterval:pauseTime:)` reference.
2. **Week view "now" line is drawn over tile text** (Tue SJL).
3. **Lesson editor's Subject picker** shows only the emoji, not the name.
4. **Settings → "I am in" shows the raw key `settings.profile.secondary`.** The key is built at runtime and missing from the catalog, invisible to the static key check. Needs a test that enumerates all dynamic keys.
5. **Subject editor's "close to the background → outline" hint fires for yellow in dark mode.** It should compare against the current scheme's background.
6. Polish: on Today tiles the "done" check overlaps the period-number circle.

## Decisions taken (reviewable)
- Real app code uses `@Observable`, `@State` and `@Entry`, all proven in Phase 0. SwiftData is banned.
- Tabs: Today · Timetable · Settings. Tasks and Exams arrive in Phase 3.
- "Replace data with sample" was removed from the Developer screen, because it would put foreign IDs and future timestamps into the real store.
- `-TabulaNow` and `-TabulaTimeZone` work only with `-TabulaSeed` (in-memory store).
- Onboarding replaces the database only when it is empty; otherwise it adds the timetable. Preset reminder rules are added only if none exist.
- The last timetable cannot be deleted; "Reset timetable" clears its lessons instead.
- Adding a timetable makes it the active one.
- Rotation editing: with lessons present, a timetable cannot switch between day cycle and weekdays, and a cycle cannot be shortened below what its lessons use.
- Bell-schedule variants made with "copy from" reuse period IDs, so lessons stay mapped.

## Decisions needed from you (collected so far)
- **Subject order:** the frozen schema has no subject order field, so the subjects list is alphabetical. Adding a `sortIndex` to `Subject` is a **schema change that needs your approval** (it would be additive and optional).
- Time pickers follow the device's 12/24 h setting, not the app's override. Acceptable for now, or force it?
- Wallpaper themes are deferred (they need photo storage).
