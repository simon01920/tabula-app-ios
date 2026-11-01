# Phase 5 gate report — Watch app, WatchConnectivity sync, complications

Status: **READY FOR REVIEW — waiting for your approval** (2026-11-01) · Plan: `docs/specs/PHASE5_PLAN.md` · Device checklist: `docs/checklists/PHASE5_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| W1 Presentation and transfer format | widgets-watch-engineer · **Opus high** | `WatchSnapshotTransfer` (application-context format, validated decode), `WatchPresenter`/`WatchDisplay` (Now & Next, rest of today, tomorrow, "Open Tabula on your iPhone" and Pro states), `WatchHomeView` and the corner view in TimetableUI; `watch.open.*` strings in 12 languages (`needs_review`) | `2a9fe81` |
| W1 Watch app, sender, complications | widgets-watch-engineer · **Opus high** | The watch app renders only from its App Group cache (`WatchCache`). The iPhone sends each written `WidgetSnapshot` (cap 19,000 B) with `updateApplicationContext` and re-sends on activation. Complications (circular, rectangular, inline, corner) reuse the widget planner, presenters and views, with per-entry Smart Stack relevance. Live time uses `Text(timerInterval:)` with units | `848b0c3` |
| W1 Targets and checks | widgets-watch-engineer · **Opus high** | `TabulaWatchWidgets` extension embedded in the watch app (`project.yml` only), shared watch entitlements and privacy manifest, `watch-typecheck.sh` covers both targets, `validate_config.py` and `ios.yml` check bundle IDs, embedding, privacy manifests and arm64_32 | `8fd4359` |
| W1 Docs | widgets-watch-engineer · **Opus high** | Device checklist (W1.1–W1.22), ENVIRONMENT §35 (WatchConnectivity and WidgetKit APIs checked in the SDK and Apple's docs), RISKS #89–#91 | `ee1eb56` |
| QA → fixes | qa-reviewer · **Opus high** → widgets-watch-engineer · Opus | The background task waits for activation, pending content and an in-flight store (bounded to 10 s); the complication reload runs after the cache write; a failed iPhone send stays pending for retry; the watch screen sits in a `NavigationStack`; the receive side accepts payloads up to the 512 KB file limit by design (test) | `cf8cb88`; merged `e9ad235` |
| CI screenshot hardening | Sonnet (commit co-author) | Skips multi-display simulators, fails on missing PNGs, retries the watch screenshot | `550cb4a` |

**Tier split:** Opus high did the single W1 stage, its fix round and the QA run (the plan keeps it one stage: small and tightly coupled). Sonnet did only the CI screenshot script fix.

## Runtime evidence
### Merged state `e9ad235`, verified
- **iOS CI green** (run 41122190645). It covers:
  - the Linux core and UI tests: **540 core + 621 UI**, 1,348 keys complete in 12 languages;
  - the macOS core tests;
  - the XcodeGen iOS + watchOS build with the complication extension embedded;
  - "Verify bundle layout" (embedding, compiled catalogs, privacy manifests, watch arch);
  - the xtool path.
- **Local checks (2026-10-30):**
  - `validate.sh` ALL CHECKS PASSED, 190 OK, 0 WARN;
  - `watch-typecheck.sh` reports `watchOS type-check OK (arm64_32-apple-watchos26.0)` for both watch targets;
  - the xtool iOS build with the WatchConnectivity sender: `Build complete!`, 0 warnings.
- **Watch simulator screenshot:** the CI step succeeded (runs 41122957955, 41124975905). The image shows only the empty state and **has not been opened by us** (`VERIFICATION.md` §3: the file was not in the repo). The plan's "inspected" item is open.
- **Later tip `16ac596`:** the watch targets are unchanged. Its XcodeGen job is red because of a Phase 6 test compile error (see `PHASE-6.md`), so the watch build was not re-proven there.

### Device
- **Not run:** `PHASE5_DEVICE.md`. The watch app exists only in TestFlight builds.

## Not done / known limits
- **Nothing is verified at run time.** Linking, embedding and arm64_32 are CI-proven. WCSession activation order, `isWatchAppInstalled`, re-send after a watch switch, complication refresh and background wake are device-only (RISKS #91).
- **Needs the paid account:**
  - The watch app and complications ship only through TestFlight (XcodeGen path). An xtool build has no watch app (row W1.12).
  - The App Group must be enabled for `.watchkitapp` and `.watchkitapp.widgets`. Without it the watch shows "Open Tabula on your iPhone" forever (RISKS #90).
- **Read-only v1:** no editing and no Mark done on the watch (plan decision 1).
- **Complications lag when the watch app is not running** (RISKS #89). The wait for pending content is a bounded 10 s poll, a shortcut.
- **Pro gate:** the tier is all-access today, so the free-tier rows (W1.17) need a StoreKit or DEBUG switch.
- **Smart Stack:** only a per-entry relevance score; `RelevanceConfiguration` is not used.
- **Translations:** the `watch.open.*` strings are machine-made `needs_review`.

## Decisions taken (reviewable)
- **Data:** the iPhone sends the existing `WidgetSnapshot` by application context (latest wins); the watch has no database and renders only from its cache. The receive side is more tolerant than the send cap.
- **Cache location:** the App Group `group.sk.simondev.tabula`, because the complication extension must read what the watch app writes. Rejected: the app's own container (the extension cannot read it) and WCSession inside the extension.
- **Reuse:** no logic is forked; the watch uses the widget presenters, `NowMarker` and the tokens.
- **Complications** live in a new watchOS WidgetKit extension defined in `project.yml` only, because xtool cannot build watchOS (RISKS #1).

## Risks (`docs/RISKS.md`)
- **#1** xtool cannot build watchOS: **EXPECTED**; the CI watch build is verified, the type-check is local.
- **#89** complications lag when the watch app is not running: **OPEN** (device), rows W1.11 and W1.14.
- **#90** the watch needs the App Group: **OPEN** (paid account), row W1.3.
- **#91** watch UI and WatchConnectivity unverified at run time: **OPEN** (CI + device), rows W1.1–W1.22.
- **#67** time-zone change while the app is not running: **MITIGATED** (code), row W1.22.

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P5-1** | **Approve Phase 5** (Phase 6 is also ready for review) | Approve |
| P5-2 | v1 is **read-only** on the watch (no Mark done, no editing) | Accept; revisit after a week on the wrist |
| P5-3 | The Watch is a **Pro** feature (MONETIZATION), but the tier is all-access until StoreKit exists | Accept; free-tier rows wait for Phase 10 |
| P5-4 | Watch verification needs a TestFlight build, so the **paid account** (same blocker as P4-6) | Enrol before the device pass; Phases 5 and 6 share one build |
| P5-5 | Smart Stack uses a per-entry relevance score only | Accept |

## Manual on-device checklist
`docs/checklists/PHASE5_DEVICE.md` (W1.1–W1.22): pairing and install, offline cache, lesson-boundary refresh, complications in four families, Smart Stack, background refresh, Low Power Mode, Always On, free tier, day rollover, VoiceOver, Dynamic Type, time zone. Needs the iPhone 16 Pro Max and the Apple Watch Series 7. Start with W1.3, W1.11 and W1.14 (RISKS #89–#91).

## Human steps
1. Paid account: follow `docs/PAID_ACCOUNT_SWITCHOVER.md` steps 1–7. Step 5 lists the two watch App IDs and the App Group assignment (RISKS #90).
2. Run the iOS CI workflow with upload on (step 7) and install the TestFlight build on the iPhone. The watch app installs from the iPhone's Watch app.
3. Run `PHASE5_DEVICE.md` and note ✔ / ✘ per row.
4. Download the watch screenshot artifact from run 41124975905 and check it (the empty state only).
5. Answer P5-1 to P5-5.

## Next
- **Phase 6** (sync and backup) gate: `PHASE-6.md`.
- A Watch Mark done or a Watch Live Activity is outside this phase; add it only if the device pass asks for it.
