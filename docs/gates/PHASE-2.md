# Phase 2 gate report — App shell, onboarding, views, editors, settings, 12 languages

Status: **STOPPED AT GATE: awaiting human approval** (final screenshot results in §Runtime evidence) · Plan: `docs/specs/PHASE2_PLAN.md` · Device checklist: `docs/checklists/PHASE2_DEVICE.md`

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
| Integration glue + screenshot list | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | Editors now open the tapped lesson via `EditorContext`; "Edit timetable" menu reaches all editors; 17-screen default list | `fccf9e2` |
| C1 12 languages (2 passes) | localization-engineer-sonnet · **Sonnet 5.5 medium** | 802 keys × 12 languages (sr = Cyrillic + sr-Latn), CLDR plurals, all `needs_review`; completeness check FAILs on any gap; 13 `.lproj` on both build paths | `61b94d7`, `3dbc9b3` |
| Screenshot fix pass | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | 6 screenshot bugs fixed, plus **6 more dynamic-key bugs** of the same class found and fixed; `DynamicL10nKeys` test + validate guard | `76d79ca` |
| C3 final QA | qa-reviewer · **Opus 5.5 high** | **Approve with conditions.** No data-loss path, no schema change, the Stage A safety fixes held through the merges. One real bug: the timetable editor overwrote a bell variant made from inside it | — |
| QA fix pass 2 | swiftui-engineer-sonnet · **Sonnet 5.5 medium** | Stale-draft overwrite fixed (+ test), 44 pt tap targets, "Saved with warnings" alert, a11y separators, remaining dynamic keys, validity defaults relative to today, checklist updated | `18d021f` |

**Final orchestrator verification (`18d021f`):**
- `validate.sh` → ALL CHECKS PASSED: **502 core + 175 TimetableUI tests**, and **802 keys complete in all 12 languages**.
- xtool iOS build clean (0 errors, 0 warnings).
- Watch type-check OK.
- CI iOS + watch build green on every push.

**Model split:** Opus did 6 of the 13 tasks (foundation, its fixes, the timetable views, 3 QA reviews). Sonnet did 7 (onboarding, editors, settings, glue, 2 translation passes, 2 fix passes). Every bug in Sonnet's work was found by Opus QA or the screenshot review, and fixed by Sonnet.

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

**Bugs found (all fixed in `76d79ca`, verified in the next run's screenshots):** the countdown shows 25:00, Settings shows "Secondary school", the check sits beside the period number, and Slovak and German are fully translated.
1. **Frozen countdown is wrong.** Today shows "45:00" at 10:20 for a 10:00–10:45 lesson (should be 25:00). `Text(timerInterval:pauseTime:)` reference.
2. **Week view "now" line is drawn over tile text** (Tue SJL).
3. **Lesson editor's Subject picker** shows only the emoji, not the name.
4. **Settings → "I am in" shows the raw key `settings.profile.secondary`.** The key is built at runtime and missing from the catalog, invisible to the static key check. Needs a test that enumerates all dynamic keys.
5. **Subject editor's "close to the background → outline" hint fires for yellow in dark mode.** It should compare against the current scheme's background.
6. Polish: on Today tiles the "done" check overlaps the period-number circle.

### Final screenshot verification (orchestrator, `18d021f`)
- **Runs:**
  - [38059340329](https://github.com/simon01920/tabula-app-ios/actions/runs/38059340329): 18 screens not covered before, plus sk/de variants, 54 PNGs.
  - [38060174635](https://github.com/simon01920/tabula-app-ios/actions/runs/38060174635): core re-shoot after fix pass 2, 12 PNGs.
  - Earlier run 38014413425: the default 17 screens, 51 PNGs.
- **Coverage:** together these cover all 25 registered routes in light, dark and AX, with Slovak and German on 7 screens. **No crash in any run.**
- **Confirmed visually:**
  - countdown 25:00;
  - "now" line behind tiles;
  - subject name in the lesson picker;
  - "Secondary school" (no raw key);
  - inline done check;
  - full Slovak ("Dnes / Rozvrh / Nastavenia", "Kto ste?", "Prestávka · 10 min") and German ("Woche B", "Stunde bearbeiten");
  - timetable settings guard footer;
  - "Change for this day" with inline validation.
- **Curated set** in `docs/screenshots/phase2/` (16 PNGs).
- **Deviation from PHASE2_PLAN §3:** sk + de were captured on 7 key screens, not all 25 (to save macOS minutes on the private repo). All 12 languages are complete per the validator; the remaining layout checks per language are on the device checklist.

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

## Not done / known limits
- **No physical device yet.** Everything is verified only through compile, Linux tests and simulator screenshots. VoiceOver reading order, real gestures (swipe vs scroll), Liquid Glass rendering details, the background save on suspension, and the App Group on a free team all wait for the device checklist (`docs/checklists/PHASE2_DEVICE.md`).
- **Translations are machine-made.** All 9,000+ non-English strings are marked `needs_review`; see `docs/localization/REVIEW.md`. Info.plist usage strings and the display name are still English only (an `InfoPlist.xcstrings` is needed later).
- **Phase 3+ features are not here:** Tasks and Exams tabs, notifications/AlarmKit scheduling, import from photo/QR (shown as "coming soon"), wallpaper themes, widgets/watch UI, iCloud.
- **Small blocks in narrow time-block lanes** can be under 44 pt wide. Widening them would overlap neighbours; documented.
- **Performance:** each day is resolved 2–3× per render and conflict detection runs per keystroke. Fine at school sizes in tests, but not measured on a device.

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P2-1** | **Approve Phase 2** and move on to Phase 3 (tasks, exams, reminders/notifications, AlarmKit) | Approve |
| P2-2 | **Subject order:** add an optional `sortIndex` to `Subject` (additive schema change, needs your approval), or keep alphabetical | Add it in Phase 3 (small, additive, backward compatible) |
| P2-3 | Time pickers follow the device's 12/24 h, not the app's override | Accept for now |
| P2-4 | Wallpaper themes: deferred (photo storage, Pro feature) | Defer to the Phase 8/10 timeframe |
| P2-5 | Native review of translations: do you know native speakers for sk/cs/pl/hu/ro/de/fr/uk/sr/ja/zh? At least Slovak should be checked by you | You review Slovak; others before release (Phase 11) |
| P2-6 | `-TabulaScreen` routes still work in Release builds (harmless: onboarding then *adds* a timetable) | Restrict them to DEBUG in Phase 3 |

## Next: Phase 3 preview
- **Tasks & exams:** a Tasks tab (Today / Upcoming / Overdue / Completed, subtasks, attachments, priorities) and an Exams tab (countdown, history).
- **Reminders:** the iOS adapter for the Phase 1 planner (64-cap rolling window, Time Sensitive, AlarmKit loud alarms), permission explainer and health check.
- **Testing:** these features rely heavily on real-device testing (silent switch, Focus, lock screen). With no device, Phase 3's on-device checklist will be long. Simulator screenshots cover the UI, not delivery behaviour.
