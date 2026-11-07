# Phase 10 gate report: polish, bug fixes and performance

**Status:** READY FOR REVIEW, waiting for your approval (2026-11-06).
- Plan: `docs/specs/PHASE10_PLAN.md`
- Device checklist: `docs/checklists/PHASE10_DEVICE.md` (90 rows)
- PR: simon01920/tabula-app-ios#1 (`main-er1vxs` → `main`)

**Roadmap change (your decision, 2026-11-05).** Phase 10 is now polish, bug fixes and performance. Monetisation moves to Phase 11 and Release to Phase 12 (`ROADMAP.md`).

**How this phase was built.** It ran in a cloud session with no Swift toolchain, so the agents wrote every change without a compiler. CI on the PR is the build and test evidence (RISKS #100, ENVIRONMENT §41).

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| Audit: app/UI performance | qa-reviewer · **Opus** | P1–P18. Biggest: every edit re-rendered every tab; a 6-page PNG export was a ~108 MB bitmap built on main | read-only |
| Audit: core performance | qa-reviewer · **Opus** | C1–C10, K1. Biggest: iCloud sync re-encoded and hashed the whole store on every change | read-only |
| Audit: bug hunt | qa-reviewer · **Opus** | B1–B16, no blocking bug. Biggest: Week-view PDF clipped a normal day; a PDF render kept running after Cancel | read-only |
| Audit: polish and device range | qa-reviewer · **Opus** | U1–U19. Biggest: privacy manifest missing FileTimestamp; the privacy text claimed nothing leaves the device | read-only |
| WP1 App state and change fan-out | swiftui-engineer · **Opus** | Derived state rebuilt only when its inputs change; reminder state saved once per run, planner off main; foreground blip policy; launch hold removed when already loaded; launch re-plan delayed 1.5 s; Timetable week resolved once per pass; quiet-hours edits saved once; notice when a notification "Mark done" fails | `f1b17e4`, `bc4e59e`, merged `c688e86` |
| WP2 Widget, Live Activity and watch pipeline | widgets-watch-engineer · **Opus** | One snapshot build per change, shared with Live Activities; app resolvers reused; exact byte budget (≤ 2 encodes); timeline instants computed once; bundle created once; launch read off main; Japanese widget separator | `32b6a52`, merged `40ffdb5` |
| WP3 Export, share and import | swiftui-engineer · **Opus** | PNG pixel budget (12 MP) + ImageIO encode off main; Week/Day PDF fits the page; cancellable renders with temp cleanup; CSV/XLSX/ICS off main; QR rendered once; share code reused per payload; double-tap guards; photo downsampling; PDF read off main with locked/broken states; narrow-screen week falls back to the grid | `98639ca`, merged `cf42ebf` |
| WP4 Core fast paths and correctness | core-domain-engineer · **Opus** | DST resolve fast path, overrides sorted once, reasons index, regexes built once, ICS fold fast path, validation sort keys computed once; VTIMEZONE includes standard-offset changes; XLSX styles (real dates and times) | `058e470`…`b0c0828`, merged `139351d` |
| WP5 Sync, backup and attachments | sync-storage-engineer · **Opus** | Incremental CloudKit records with a byte-identical fast path; send batch builds only the records it sends; fetched batches merged together; state-save retry; restore result waits for the save; export Try Again; backup pruning; Cancel while an attachment copies; a clean launch no longer rewrites the store | `a3355d4`, `681a3ae`, `46e6e51`, merged `6ade335` |
| WP6 UI polish and small bugs | swiftui-engineer-sonnet · **Sonnet** | Segmented pickers become menus at AX sizes; weekday chips fit 375 pt; VoiceOver symbol names; no-timetable states with an action; ja/zh separators; scaled frames; `chevron.forward`; honest privacy text; confirmations (remove day change, re-record); pickers follow the week start; voice-note player race | `31a8ab4`, merged `2f81fc2` (widget separator part reverted in `1fc99d4`, redone in WP2) |
| WP7 Privacy manifest and screenshot coverage | env-ci-engineer-sonnet · **Sonnet** | FileTimestamp C617.1 (+ 3B52.1 in the app) in all manifests, enforced by validate; placeholder-domain warning; `sim_pick` finds a device on older runtimes; Increase Contrast and double-length screenshot inputs; `@hu` routes | `d9921c1`, merged `04b85e9` |
| CI fixes | orchestrator · Opus | A `@ScaledMetric` declared in the wrong struct (macOS build); `.onInkLabel()` on two new prominent buttons; review export | `2c7b8a6` |
| QA, merged state | qa-reviewer · **Opus** | **No code defect that loses data, shows stale widgets or misses a reminder** (all 10 focus areas traced). Majors: RISKS not updated, device checklist missing, backup pruning could delete the copy the app promised. Minors: locale-only changes, launch re-plan postponed if suspended within 1.5 s, B12 save failure, engine re-entrancy, picker label at AX | read-only |
| Docs | orchestrator · Opus | RISKS #100–#113, ENVIRONMENT §41, device checklist (90 rows), PHASE8_PLAN XLSX note, NOTIFICATIONS trigger table (WP1) | `11ee901`, `b7989ba` |
| QA fix pass | swiftui-engineer · **Opus** | Backup retention: newest 5 per label plus anything younger than 30 days (P10-6), footer in 12 languages; forced context/formatter rebuild on a locale change and a real foreground; a pending launch re-plan runs when the app goes to the background; "Mark done" whose save fails posts the notice; `ReminderEngine.run` coalesces concurrent calls; visible picker label at AX sizes | `dc739a3`, merged; 3 test files |
| Delta QA (fix pass) | qa-reviewer · **Opus** | **Ready, 0 blocking, 0 major.** Minors kept as notes: (1) every return from the background now rebuilds context and formatter (redraws views that read them; blips still skip it); (2) the launch re-plan could run twice on back-forward-back, fixed by the orchestrator; (3) when a "Mark done" save fails, the item is done in memory and a save-failed banner shows, while the notice says "Couldn't Mark as Done"; (4) the App-target parts of the fix pass are device rows H1–H6 | read-only |
| Fix: double launch re-plan | orchestrator · Opus | The background Task re-checks `launchReplanPending` | `d438306` |

**Tier split.** Opus did all four audits, WP1–WP5 (state, concurrency, sync, time zones, persistence) and the QA review. Sonnet did WP6 (UI polish on existing screens) and WP7 (config and CI wiring).

CI found the Sonnet work's only compile error, and I reverted one of its design choices (the widget separator followed the device language rather than the app language). None of the Opus packages failed CI.

## Runtime evidence
**iOS CI run 42311374105 on `0ba1e8e` (all seven work packages merged): every job green.**
- **Linux:** `validate.sh` **ALL CHECKS PASSED**.
  - **642 core + 743 TimetableUI tests** (611 + 686 at the Phase 9 gate).
  - 1,642 catalog keys complete in all 12 languages; review export current.
  - Privacy manifests checked for the exact reason sets.
- **macOS:**
  - TimetableCore tests with Apple Foundation and tz data.
  - XcodeGen unsigned iOS + watchOS build, with bundle layout verified (embedding, compiled catalogs, privacy manifests, arm64_32 watch).
  - The CloudKit variant compiles.
- **xtool/SwiftPM path:** the build passes. Bundle: app 13 `InfoPlist.strings`, widget 0; widget appex keeps `__text`/`__swift5_entry`.
- **Final head (`e2cae07`, with the QA fix pass and the double-launch fix): iOS CI run 42313737371, every job green.** Linux tests and validate, macOS core tests, XcodeGen iOS + watchOS build, CloudKit variant, xtool path. The test counts above are from `0ba1e8e`; the final head adds the QA fix tests, and all pass.
- **Local run in this session (Swift 6.4.0 installed through P10-7):** `validate.sh` on `c84370b` exited 0, **ALL CHECKS PASSED**. 642 core + **747 TimetableUI** tests, and the share Worker tests 12/12 (not run in CI).
- **First CI run (`0197a5e`, four packages):** failed on one compile error and one validate rule. Both were fixed in `2c7b8a6`.
- **Not measured:** the compiler warning count (the CI log tail does not show it). Phase 9 reported 0.

**Equivalence and performance tests added (Linux).** Each optimisation is compared with the old algorithm, kept in the tests as a reference:
- DST resolve, every 15 min around every transition 2020–2030 in 6 zones.
- Override order.
- Reasons index.
- Validation order.
- ICS folding (2,201 lines).
- VTIMEZONE (Caracas 2016, Volgograd 2020, Samoa 2011).
- Widget snapshot bytes (every seed, 1/2/4 timetables, worst case).
- Timeline planner.
- Lesson-work index (240 tasks, 40 exams).
- CloudKit records (every entity type).
- Incremental sync scan (5,000 tasks, 1 edit → 1 record).
- Backup pruning.
- Clean-launch save.

**Screenshots, run 42312145288 on `0ba1e8e`.** iPhone SE (3rd generation), iOS 27.2 simulator. 15 screens × light / dark / AX-XXXL / Increase Contrast, 60 PNGs, reviewed by the orchestrator. The environment change P10-7 made the artifact reachable.
- **Correct at 375 pt:**
  - Weekday chips (4 + 3, two columns at AX).
  - Subject editor in Hungarian.
  - Slovak exam card.
  - Export sheet (stacks at AX) and Grid export preview.
  - Onboarding week.
  - About › Privacy, with the corrected text.
  - Backup.
  - Reminders settings.
  - Share sheet (QR rendered once, off main).
  - Tasks.
  - Grid.
  - University week: 5 days keep readable time blocks.
  - Today.
  - Japanese widgets, which now use "・" (WP2).
- **One regression found and fixed (`1e87ea6`).** Exams in Slovak at AX-XXXL: the U7 menu fallback in that tight, background-less List row was clipped at the top ("Zobraziť") and bottom ("Nadchádzajúce"). At accessibility sizes the two choices are now full-width rows with a checkmark under the "Show" header; segmented as before at other sizes. The other menu fallbacks rendered correctly in their screenshots.
- **Rerun 42317047487 on `c84370b`** (iPhone SE, 5 screens × light/dark/AX-XXXL) confirms both fixes:
  - **Exams in Slovak at AX-XXXL:** "Zobraziť" header, then full-width "Nadchádzajúce ✓" and "História" rows; nothing clipped. Normal sizes still segmented.
  - **Import review at AX:** the visible "Show" label sits above the menu (QA fix #6).
  - **Backup:** unchanged. The seed has no automatic copies, so the new retention footer is not shown (device row H6).
- **The Increase Contrast variant looks almost identical to light.** Whether `simctl ui … increase_contrast` takes effect is still unverified (device row: Increase Contrast on the phone).

**Device:** nothing has run on a device. `PHASE10_DEVICE.md` is the list.

## What changes for the user
- **Faster on every phone, most of all on A13 iPhones:**
  - An edit no longer re-renders every tab.
  - Background work after an edit (reminders, widgets, Live Activities, sync) is lighter and mostly off the main thread.
  - Launch shows content as soon as it is loaded.
  - The Timetable tab resolves its week once instead of 4–5 times.
- **Export:**
  - PNG uses at most ~12 MP, about 48 MB instead of ~108 MB.
  - Exports never freeze the screen and can be cancelled.
  - The Week and Day PDF pages fit a normal school day.
  - Excel has real dates and times.
- **iCloud sync:** cost is proportional to what changed, not to the whole store.
- **Small screens and large text:** pickers, weekday chips, the week view and symbol cells adapt.
- **Fixes:**
  - The restore result is honest when the save fails.
  - "Mark done" failures are reported.
  - Attachments are not lost or orphaned on Cancel.
  - Double taps no longer duplicate imports.
  - Pickers follow the app's week start.
  - Japanese and Chinese separators.
  - The privacy text is accurate.

## Not done / known limits
- **Nothing seen on a device:** all 90 checklist rows are open.
- **Speed is not measured:** no Instruments numbers yet (rows A1, A2, A6 and section C).
- **Kept as is:**
  - P16 (off-screen `TimelineView`): device check A6.
  - P17 (TipKit configure): Apple requires it at launch.
  - B8 (undo of a repeating task keeps its successor): decision P10-1.
- **Translations:** every new string is machine-made `needs_review` (decision P10-5).
- **The pseudo-locale and Increase Contrast screenshot inputs are unverified** on the runner Xcode; they warn and skip if unsupported.

## Decisions needed from you
| # | Decision | Default used now |
|---|---|---|
| **P10-0** | **Approve Phase 10** | Approve after the device checklist, starting with sections A, C and E |
| P10-1 | **Undo of a completed repeating task keeps the next occurrence it created.** Remove it on undo? (The tombstone rule would block that occurrence forever.) | Keep it |
| P10-2 | **App Privacy label:** share codes keep a timetable copy on the share server for 30 days. Declare "User Content, not linked, App Functionality"? | In-app text corrected; label decided at Phase 12 |
| P10-3 | **A real domain** for share links, the privacy policy and the support email | validate warns until then; required before Phase 12 |
| P10-4 | **Week/Day PDF taller than the page** | Fit by shrinking the hour height (min 20 pt) |
| P10-5 | **Native translation review** of all 12 languages | Not in Phase 10 |
| P10-6 | **Backup retention** | Keep the newest 5 copies of each kind, and anything younger than 30 days |
| P10-7 | **Cloud environment `tabula-app-ios`.** Approved in this session: `download.swift.org` plus the GitHub Actions log and artifact hosts, and a setup script that installs Swift 6.4.0 (approved; unproven until the next fresh session). The artifact storage host changes per run (`productionresultssaNN.blob.core.windows.net`), so later runs may need their host added | Keep it, and start future cloud sessions for this repo on it |

## Risks
New rows #100–#113 in `docs/RISKS.md`. Three of them are decisions (P10-2, P10-3, P10-6). The main open risk is #100: Phase 10 has only been checked by CI, not on a device.

## Human steps
1. Open run 42312145288 on GitHub, download `ui-screenshots-57`, and look at the iPhone SE screens:
   - Today
   - Timetable grid and week
   - Subject editor in Hungarian
   - Exams in Slovak
   - Weekday chips
   - About › Privacy
   - Backup
   - Share
   - Export
   - Widgets in Japanese
2. Run `docs/checklists/PHASE10_DEVICE.md` on the iPhone 16 Pro Max:
   - Start with A (launch and edits), C (export and import) and E4–E9 (backup and attachments).
   - If you can borrow an A13 iPhone, do rows A1/A2 there.
3. Answer P10-0 to P10-7.
4. Merge PR #1 into `main` when you approve.
