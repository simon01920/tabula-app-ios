# Phase 2 — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x). Until a device is available, run what is possible on the CI simulator
(`.github/workflows/ui-screenshots.yml`) and tick the rest later. Each stage appends its own section; keep the
format: **Setup → Steps → Expected**, plus the standard state matrix (empty, normal, long text, Dynamic Type XXL /
AX5, dark mode, German-length strings, CJK, VoiceOver).

Builds: local `bash scripts/xtool-dev.sh` (base variant, installs + launches) or a TestFlight/CI build. Launch
arguments (DEBUG builds only) via Xcode scheme / `xcrun simctl launch booted sk.simondev.tabula <args>`:
`-TabulaSeed empty|blank|elementary|secondary|university`, `-TabulaNow 2026-10-13T10:20:00+02:00` (or `live`; with a seed only),
`-TabulaTimeZone Europe/Bratislava`, `-TabulaScreen <route id>`, `-AppleLanguages "(de)"`. On a device without
Xcode, use **Settings → Developer** instead (onboarding reset, recovery tests; sample data only via `-TabulaSeed` or onboarding).

---

## A. Foundation (Stage A — app shell, state, persistence, routing)

### A1. First launch → onboarding
- Setup: delete the app (or simulator: `-TabulaSeed empty`).
- Steps: launch.
- Expected: a short "Loading…" at most, then the welcome screen ("Welcome to Tabula", one "Get Started" button);
  **no** tab bar. No banner.
- Steps: tap **Get Started**.
- Expected: the tab bar appears (Today · Timetable · Settings) without relaunch; Today shows "No lessons today" with
  today's full date in the device language (no subjects exist yet).

### A2. Persistence across relaunch
- Steps: Settings → Appearance → **Dark**; wait 1 s; force-quit (app switcher); relaunch.
- Expected: still dark, tab bar shown directly (onboarding not repeated). Repeat with **Light** and **System**.
- Steps: change appearance, then immediately press Home (background) and force-quit within 1 s.
- Expected: the change survived (save is flushed when the scene leaves `active`).
- Settings → Developer → Store: "Last save" shows `saved(generation: n)`; "Data source" shows **App Group: …/Tabula**
  (if it shows "Application Support (fallback)" the App Group is not provisioned — free team / xtool #284: note it,
  widgets will not see the data).

### A3. Appearance
- Expected for each of System / Light / Dark: whole app follows (tab bar, lists, sheets), including the Developer
  screen. System follows Control Centre dark-mode toggling live.
- Tab bar: standard iOS 26 Liquid Glass look (no custom background).

### A4. Store banners (recovery / read-only) — Settings → Developer → "Recovery tests"
- Restore: make two changes (e.g. appearance twice, 1 s apart) so a backup exists → **Corrupt tabula.json** →
  force-quit → relaunch.
  Expected: banner at the top "Data restored from a backup" + explanation, icon + text, ✕ button (44 pt) dismisses
  it; data is the state from before the last change. Developer → Store shows the banner list empty after dismissing.
- Without backup (fresh install, one change only) → corrupt → relaunch.
  Expected: full-screen "Your data can't be opened" (no onboarding offered, nothing deleted). Recover by deleting the
  app (Phase 6 adds restore).
- Read-only: **Mark tabula.json as schema v99** → force-quit → relaunch.
  Expected: non-dismissible banner "Update Tabula to make changes" (lock icon); Settings → Appearance picker is
  disabled; data visible. Then **Set back to schema v1** → relaunch → banner gone, picker enabled.
- Banner layout: long German text wraps (no truncation), works at AX5 (scrolls the content below, not cut off), dark
  mode legible, VoiceOver reads title + message as one element and the ✕ as "Dismiss".

### A5. Launch routes (simulator / Xcode)
- `-TabulaSeed secondary -TabulaScreen today` → Today tab with 7 lessons of Tue 13 Oct 2026 (ISO week 42 = week B: Matematika, Chémia,
  SJL, Biológia, Nemecký jazyk, Geografia, Etická výchova) with times "8:00 – 8:45" style (24 h, scenario setting).
- `-TabulaScreen timetable` / `settings` → that tab selected. `-TabulaScreen onboarding` → welcome screen even with data.
- `-TabulaScreen debug` (and `debug-platform`, `debug-localization`, `debug-macros`, `debug-import`, `debug-alarms`,
  `debug-developer`) → standalone debug screens; "Launch route" row shows `requested "<id>" → <id>`.
- `-TabulaScreen nonsense` → normal app; Developer screen shows `UNKNOWN "nonsense" → app shell`.
- Release/TestFlight build with `-TabulaSeed secondary`: **ignored** (real data shown); no Settings → Developer row.

### A6. Foundation primitives on the Today placeholder (`-TabulaSeed elementary`, B2 replaces the screen)
- Expected on Tue 13 Oct: 5 lessons; *Výtvarná výchova* has badge "Room changed" (icon + text) and room "Knižnica";
  *Hudobná výchova* is struck through with badge "Cancelled".
- Subject badges: emoji on the subject colour; the yellow/pastel colours keep a visible edge in light mode,
  dark navy colours (ocean pack, once B3/B4 allow choosing it) keep an edge in dark mode.
- Field rule: elementary shows only room, teacher, bring-list lines; a lesson without bring list shows **no empty line
  or dash**. `-TabulaSeed university`: building, room, teacher, lesson type ("Lecture"/"Seminar"/"Lab"); no notes line
  where notes are empty.
- VoiceOver on a lesson row reads one sentence, e.g. "Výtvarná výchova, period 4, 10:55 to 11:40, room Knižnica,
  teacher Mgr. Novotná, bring vodové farby, štetce, and obrus, changed: Room changed" (wording in the device language
  once translated).

### A7. Time zone, locale, 12/24 h
- Device set to 12-hour (Settings → General → Date & Time → 24-Hour Time off) with a fresh install (onboarding
  default `hourCycle auto`): times show "8:00 AM" style in en-US; Slovak region keeps 24 h.
- Change the device time zone while the app is open → Developer → "Time zone" updates without relaunch; also after
  changing it while the app is in the background (refresh on becoming active, `NSTimeZone.resetSystemTimeZone()`).
- Leave the app open across midnight (or set the clock forward past midnight) → Today shows the new day
  (`significantTimeChangeNotification`).
- Make a change, then immediately go Home: Developer → "Last save" shows `saved` after returning (background task
  protected flush). With storage full, the "Couldn't save" banner appears and the change is retried on the next flush.
- Region with Sunday first (en-US) → Developer → "First weekday sunday"; Slovak → monday.
- `-TabulaSeed secondary` has `hourCycle h24`: always 24 h even on a 12 h device.

### A8. State matrix for the foundation screens (welcome, Today placeholder, Settings placeholder, banners, problem screen)
| State | How | Expected |
|---|---|---|
| Empty | `-TabulaSeed empty` / `blank` | welcome screen / "No lessons today" + date; no blank rows |
| Normal | `-TabulaSeed secondary` | list of lessons, badges |
| Long text | `-TabulaSeed secondary`, then (B3) rename a subject to 60+ chars | wraps, no truncation of the time line |
| Dynamic Type XXL / AX5 | Settings → Accessibility → Larger Text | every text scales; banner ✕ stays tappable; nothing clipped |
| Dark mode | Appearance Dark | all text legible; subject badge text black/white per contrast |
| German | `-AppleLanguages "(de)"` | strings fall back to English until stage C1 (expected now); layout holds long strings |
| CJK | `-AppleLanguages "(ja)"` | dates/times/weekday names in Japanese format (年月日, 時), list separator "、" after C1 |
| VoiceOver | VoiceOver on | tabs announced with names; lesson rows one element; banner text + Dismiss |

### A9. Not verifiable without a device / simulator run (open items)
- `@Observable` / macro-based `@State` runtime behaviour on the **xtool** build (OpenAppleMacros expansion at run time).
- Plural selection through `String(format:locale:arguments:)` with catalog plurals (`LocalizedTextRenderer`, Darwin path);
  Linux tests only cover positional substitution.
- `Locale.Components.hourCycle` forcing 12/24 h in `Date.FormatStyle` on iOS (verified only on Linux swift-foundation).
- `Locale.firstDayOfWeek` honouring the user's "First Day of Week" preference.
- App Group container availability on the xtool-signed build (free team → Application Support fallback).
- Liquid Glass tab bar appearance; `.bar` material banner under the status bar; sheet presentation for `.sheet` routes
  (no sheet route exists yet — B3).

## B4. Settings + themes (written without being able to see the UI; everything below is unverified until run on a device)
Routes: `settings`, `settings.calendar`, `settings.appearance`, `settings.reminders`, `settings.about` (`-TabulaScreen <id>`, seeds `secondary`/`university`/`elementary`).
Root sections: Profile, Calendar & time, Appearance, Timetables (only if B3 registers `editor.timetables`), Reminders, Language, Tabula Pro, About, Developer (DEBUG, last).

| Check | Expected |
|---|---|
| Profile | Picker: Primary school / Secondary school / University / Other; "Lessons are called" shows Lesson or Class; footer says existing data is untouched; existing lessons unchanged after switching |
| Week start | System / Monday / Sunday / Saturday; weekday names in the app language; week views follow after changing |
| Time format | System / 12-hour / 24-hour; the "Now" row changes immediately (13:05 vs 1:05 PM); persists after relaunch |
| Time zone | Follow shows the device zone; Fixed shows a row opening a searchable list (try "tokyo", "new york"), current zone first with checkmark, tap selects and returns; switching back works; Today times react |
| Appearance | System/Light/Dark applies instantly app-wide; all four packs selectable (all-access), Ocean/Sunset/Pastel carry a "Pro" marker; swatches wrap at AX5; Pastel swatches have a visible edge; colour list shows names; preview tile text legible in light and dark, outline on pale or navy tiles |
| Reminders | Three tiers, silent switch and Focus text, "later update" note; no permission prompt. Wording about Time Sensitive and the silent switch comes from documentation, verify on device |
| Language | Button opens iOS Settings for Tabula |
| Pro | "Current plan: Pro" and "All features are unlocked during development." |
| About | Version and build from the bundle; privacy and acknowledgements; a missing version/build row is absent, never a dash |
| Read-only store (Developer: schema 99) | Pickers disabled, pages still open |
| Stress | empty seed (onboarding), normal, AX5 (rows wrap, 44 pt, nothing clipped), dark, German (`-AppleLanguages "(de)"`, English fallback until C1), CJK (`ja`), VoiceOver (palette row reads "Ocean, Pro, Abyss, Navy, ...", selected trait, swatches not read separately) |

Not verifiable without a device: Form/menu Picker look and Liquid Glass; target page of `UIApplication.openSettingsURLString`; searchable pushed list; sheet presentation of `editor.timetables` (the B3 view must bring its own NavigationStack).
## B1. Onboarding (`App/Sources/Onboarding`, logic in `TimetableUI/Onboarding`)
Nobody has seen this UI: it compiles (xtool build) and its logic is unit-tested on Linux, nothing more.
Routes: `onboarding` (welcome), `onboarding.profile|rotation|time|fields|reminders|start` (each pre-filled: secondary profile; rotation = odd/even + term; start = sample).

### B1.1 Flow (fresh install or `-TabulaSeed empty`)
- [ ] Welcome shows the language card; "Open language settings" opens this app's page in iOS Settings (Language row visible there).
- [ ] Next is disabled on Profile until a card is chosen; chosen card shows checkmark + outline.
- [ ] Profile presets: Elementary -> rotation offers only None / Odd-even / Day A-B, fields Room+Teacher+What to bring, 6 lessons; Secondary -> 5 rotation choices, 8 lessons from 08:00, fields Room+Teacher+Notes; University -> "Free times" selected (90 min), term switch already on, "class" wording (Class times, Class length, Before a class); Other -> all fields off, bell schedule 8 x 45.
- [ ] Changing profile on the way back resets answers to that preset; re-tapping the same profile keeps edits.
- [ ] Rotation: "Cycle" shows 2-6 stepper + note; "Different per semester" turns the term switch on; term end before start shows the error line (icon + text) and Next is disabled; switching the term off re-enables Next.
- [ ] Time: preview rows update live (first start, lesson length, count, breaks; long break after row 2). Start 22:00 with 14 lessons shows the "left out after midnight" note; 23:59 shows the error and disables Next.
- [ ] Fields: toggles match the preset; turn Building on and Room off, finish with sample data: Room is absent, Building shown (field rule).
- [ ] Reminders: toggles only for the preset's kinds; no permission prompt appears anywhere in onboarding; the three delivery texts match real behaviour (silent switch, Focus, alarms).
- [ ] Start: "Import from a photo" and "Import with a QR or share code" are dimmed, not selectable, VoiceOver says "Coming soon".
- [ ] Get started with Blank -> tabs appear with empty states; with Sample -> a filled timetable in the profile's style, dates relative to today (homework due next school day, exam next week).
- [ ] Kill and relaunch after finishing: no onboarding, data still there.

### B1.2 Existing data is never lost (important)
- [ ] With data present (`-TabulaSeed secondary`), delete the only timetable so the shell returns to onboarding, finish onboarding: old tasks and exams are still in the app (debug screen counts), the new timetable is active.
- [ ] `-TabulaScreen onboarding.start` on a seeded DB and "Get started": adds a second timetable, does not replace.

### B1.3 State matrix
| State | How | Expected |
|---|---|---|
| Dynamic Type AX5 | Settings -> Larger Text | every step scrolls; Back/Next keep 44 pt, labels wrap, steppers and date pickers usable |
| Dark mode | Appearance Dark | cards visible against background; outline of selected row visible; red error text legible |
| German | `-AppleLanguages "(de)"` | long labels wrap (English fallback / raw keys until C1 is expected) |
| Slovak plurals | `-AppleLanguages "(sk)"` | cycle value "2 týždne / 5 týždňov" (after C1) |
| CJK | `-AppleLanguages "(ja)"` | times and dates in Japanese format; no clipping |
| VoiceOver | on | step title is a header and is announced on step change; progress read "Step X of 7"; choice rows read title, detail, "selected"; preview rows read "Lesson 3, 10:00 to 10:45"; decorative icons silent |
| Reduce Motion | on | step change is an immediate swap, no fade |
| 12/24 h | Settings -> 12-hour | preview times and first-start picker follow it |
| Small phone / landscape | iPhone SE size | content scrolls above the fixed button bar |

### B1.4 Not verifiable without a device
- Visual quality of every step (spacing, bar material, Liquid Glass on `.borderedProminent`/`.bordered`).
- `UIApplication.openSettingsURLString` landing on the per-app language page; time-only `DatePicker` with a `\.timeZone` override; compact `DatePicker` popovers at AX sizes.
- Plural form of the cycle-length value through `String(format:)` + catalog (Darwin path).
