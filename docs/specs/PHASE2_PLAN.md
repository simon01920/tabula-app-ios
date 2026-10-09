# Phase 2 plan — App shell, onboarding, timetable views, editors, themes, settings, 12-language scaffold

Status: started 2026-10-09 (human: "start and finish Phase 2"). Owner: orchestrator (Opus 5.5).
Specs: PRODUCT.md (onboarding, timetable, views, themes), LOCALIZATION.md, `docs/design/REFERENCE_ANALYSIS.md` (patterns and anti-patterns), DOMAIN_MODEL.md (**frozen**: no persisted-schema changes without human approval).
Verification reality: there is no device; UI is verified through **iOS Simulator screenshots in CI** plus an on-device checklist for later. A compile proves nothing about UI (CLAUDE.md rule 4).

## 0. Decisions
1. **Macros in app code:** `@Observable`, `@State`, `@Entry` and `@Environment` are allowed in real app code. Phase 0 evidence: they compile on the xtool path (macro variant) and the Xcode path, and run in the iOS 27 Simulator. In the Xcode 27 SDK `@State` is itself a macro, so a macro-free SwiftUI app is impossible anyway. SwiftData and App Intents metadata stay unproven or unsupported on xtool: no SwiftData, and App Intents wait for Phase 4. `validate.sh`'s macro guard is narrowed to `App/Sources/Debug/**` plus a SwiftData ban.
2. **Debug screen** compiled only in `DEBUG` builds; reachable from Settings → Developer (DEBUG) and the `-TabulaScreen debug*` routes. Closes Phase 0 task §11.
3. **Tabs (iOS 26+ `TabView`, Liquid Glass via standard controls):** Today · Timetable · Settings. Tasks and Exams tabs arrive in Phase 3 (the shell is ready for them).
4. **State:**
   - One `@MainActor @Observable final class AppModel` per scene owns the `TabulaDatabase` snapshot.
   - All writes go through `AppModel.apply(_:)`, which stamps them via `MutationStamper` + `HybridLogicalClock`, validates, then saves through `TabulaRepository` (debounced, serial).
   - Derived engines (`ScheduleResolver`, layouts) are recomputed from the snapshot.
   - Views read small view-state structs, never mutate the database directly.
5. **Dependency container `AppEnvironment`** (no singletons):
   - repository: `FileRepository` in the App Group container resolved with `AppGroup.identifier(forBundleIdentifier:)`; falls back to Application Support when the group container is nil, as on free teams.
   - `now` provider, calendar-context provider (device time zone, locale first weekday, settings overrides), ID generator, HLC, `EntitlementsProvider` (`AllAccessEntitlements` until Phase 10).
   - Injected through the SwiftUI environment.
6. **Deterministic screenshot mode (launch arguments):**
   - `-TabulaScreen <route>`
   - `-TabulaSeed empty|elementary|secondary|university` (in-memory repository, fixed sample data)
   - `-TabulaNow <ISO-8601>` (fixed clock, so countdowns and "today" are stable)
   - `-AppleLanguages (sk)` etc.

   Release builds ignore `-TabulaSeed` and `-TabulaNow`.
7. **Colour and contrast:** subject colours from palette packs or custom; tile text colour always from `ColorValue.preferredTextColor` (WCAG). Colour is never the only carrier of meaning (status badges carry text and icons).
8. **Field rule** (PRODUCT.md): a disabled field is hidden everywhere, including editors; an enabled-but-empty field is absent (no placeholders, dashes or blank lines).
9. **Strings:** every user-facing string goes in `Resources/Localizable.xcstrings` with a context comment as it is written. At the end of the phase all 12 languages are scaffolded with machine translations, logged in `docs/localization/REVIEW.md` as "needs native review". Language list: en, sk, cs, pl, hu, ro, de, fr, uk, sr-Cyrl + sr-Latn, ja, zh-Hans.
10. **Not in Phase 2:**
    - Tasks/exams UI and real notification scheduling (Phase 3).
    - Widgets and Watch UI (Phases 4–5).
    - iCloud sync (Phase 6). The local store is real.
    - Share/QR UI (Phase 7) and export (Phase 8).
    - Wallpaper themes (they need photo storage, so they are deferred; noted for the gate).
    - Paywall (Phase 10). Gating calls go through `EntitlementsProvider` now, with all access granted.

## 1. Screens (routes in brackets)
- **Onboarding** (`onboarding.*`):
  - language note (system per-app language) → profile → rotation (none, A/B day, odd/even, N-week, per semester) with term dates → time structure (bell preset editor / free-form) → fields → reminders overview (explains the tiers; permissions not requested yet, Phase 3) → start (blank / sample / *import from photo* and *QR*, shown as "coming soon").
  - Ends in `OnboardingBuilder.makeInitialDatabase`.
- **Today** (`today`): Now & Next header with a live countdown (`Text(timerInterval:)` with the fixed clock in screenshot mode), today's lessons as tiles (status badges for changes), next school day when today is free.
- **Timetable** (`timetable.grid|week|day|tiles`):
  - Week strip with the selected day and A/B or cycle label; previous/next week; "show week A/B" switcher.
  - Timetable switcher (`< School >`); view switcher remembered per timetable (`Timetable.defaultView`); density compact/comfortable.
  - Views: classic periods × days grid (`GridLayout`), proportional week time-blocks (`TimeBlockLayout`, current-time line), single day, big vertical tiles (elementary default).
  - Grid on iPhone portrait: 5/6/7 columns with short names; landscape allowed.
  - Tap an empty cell → quick subject picker → creates the lesson; tap a lesson → lesson detail/editor.
- **Editors** (sheets, `editor.*`):
  - **Lesson:** subject, day/cycle day, period(s) or times, cycle weeks (only if rotation), validity/terms, room/building/teacher/type/notes/bring list as allowed by field visibility; conflict warnings (warn, never block).
  - **Subject:** name, short name, colour (palette packs with names, plus custom), emoji or SF Symbol, default room/teacher/building, live contrast preview.
  - **Subjects list.**
  - **Bell schedule:** periods with kind, per-weekday variants, "copy from".
  - **Timetable settings:** name, emoji, days, rotation, time structure, fields, default view, density, palette.
  - **Terms & breaks.**
  - **"Change for this day"** (override): cancel lesson, room/teacher change, short day, follow another day, extra lesson.
  - **Timetables manager:** add, duplicate, delete with confirmation, reorder.
- **Settings** (`settings.*`):
  - Profile/terminology; week start; 12/24 h; time-zone mode; appearance (system/light/dark); palette pack; language (link to the iOS per-app language setting).
  - Reminders: placeholder page that explains the tiers, a Phase 3 hook.
  - About/privacy; Developer (DEBUG only).
- **Accessibility everywhere:**
  - Dynamic Type up to AX5, with the grid switching to a list layout at accessibility sizes.
  - VoiceOver labels: a lesson reads as "Matematika, 2. hodina, 8:55 až 9:40, učebňa 214, zmenené: iná učebňa".
  - Reduce Motion; 44 pt hit targets.

## 2. Stages, model tier, ownership (worktrees; orchestrator merges)
| Stage | Agent (tier) | Scope (exclusive folders) | Depends on |
|---|---|---|---|
| A Foundation | `swiftui-engineer` (Opus high) | `App/Sources/{AppShell,Environment,State,Routing}/`, `Packages/TimetableUI/Sources/TimetableUI/{Components,Theme,Formatting}/`, launch-arg seed/now plumbing, debug gating, validate.sh macro-policy update, screenshot route registry | main |
| B1 Onboarding | `swiftui-engineer-sonnet` (Sonnet medium) | `App/Sources/Onboarding/` | A |
| B2 Today + Timetable views | `swiftui-engineer` (Opus high) | `App/Sources/{Today,Timetable}/`, `TimetableUI/Components/Lesson*` additions | A |
| B3 Editors | `swiftui-engineer-sonnet` (Sonnet medium) | `App/Sources/Editors/` | A |
| B4 Settings + themes | `swiftui-engineer-sonnet` (Sonnet medium) | `App/Sources/Settings/` | A |
| C1 12-language scaffold | `localization-engineer-sonnet` (Sonnet medium) | `Resources/Localizable.xcstrings` translations, `scripts/l10n-compile.py` (all languages and plural categories), `docs/localization/REVIEW.md` | B merged |
| C2 Screenshot set + CI | `env-ci-engineer-sonnet` (Sonnet medium) | `.github/workflows/ui-screenshots.yml` route list (light/dark/AX, sk + de), artifact docs | B merged |
| C3 QA | `qa-reviewer` (Opus high) | read-only | C1, C2 |

Each UI agent runs `bash scripts/xtool-dev.sh build` with its **own** `TABULA_WORKDIR` and `TABULA_SCRATCH`, plus `bash scripts/validate.sh` and `bash scripts/watch-typecheck.sh`. Each delivers its screens' entries for `docs/checklists/PHASE2_DEVICE.md`.

## 3. Definition of done for Phase 2
- Both build paths green.
- Core and UI tests green (view-state logic in TimetableUI is unit-tested on Linux where it is pure).
- CI simulator screenshots of every route in light, dark and AX and in sk + de, inspected by the orchestrator.
- No English left in UI code outside the catalog.
- All 12 languages present (needs review).
- On-device checklist written.
- Gate report with the per-task model tier.
