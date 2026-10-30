# Phase 5 plan: Watch app and complications

Status: started 2026-10-30, under the human's /goal to finish all phases. Orchestrator: Opus 5.5. Follow `ponytail` (token reduction) and `apple-design` (HIG: watchOS, complications, widgets).

Spec: PRODUCT.md "Watch":
- today and tomorrow;
- the current lesson's remaining time;
- the next lesson;
- complication and Smart Stack;
- an offline cache.

Watch is a Pro feature (MONETIZATION; the current tier is all-access).

## Decisions
1. **Data:**
   - The iPhone sends the existing `WidgetSnapshot` (hard cap 19,000 B) with WatchConnectivity `updateApplicationContext`, using latest-wins semantics.
   - It sends on every snapshot write; hook into `WidgetSnapshotWriter`.
   - The watch stores the last snapshot on disk, which is the offline cache, and renders only from it.
   - No database on the watch and no editing (v1 is read-only).
2. **Reuse:**
   - The pure presenters and planners in `TimetableUI/Widgets` (Now & Next, Today, Next exam), which are already watch-compatible and type-checked for watchOS.
   - `NowMarker` and the tokens.
   - No logic is forked.
3. **Watch app:** a NavigationStack with Now/Next at the top, then the rest of today, then tomorrow. Live time uses `Text(timerInterval:)` with units (the U7 rules). The Pro gate uses the snapshot tier.
4. **Complications:**
   - A new watchOS WidgetKit extension target in `project.yml` only, because xtool cannot build watchOS (RISKS #1).
   - Families: accessoryCircular, Rectangular, Inline and Corner.
   - It reads the snapshot that the watch app saved in its App Group, or a shared container if the free team lacks it. Verify this in the docs and choose the simplest working option.
   - Smart Stack relevance only if the API is cheap; verify it.
5. **Verification:**
   - Local `scripts/watch-typecheck.sh` must cover the new sources.
   - CI `ios.yml` builds and embeds them.
   - The screenshot workflow input `watch: true` provides simulator screenshots.
   - Install on the device needs TestFlight (paid; RISKS #37).

## Stages
| Stage | Agent (tier) | Scope |
|---|---|---|
| W1 Watch app, connectivity and complications | `widgets-watch-engineer` (**Opus high**) | All of the above in one stage (small and tightly coupled) |
| QA | `qa-reviewer` (**Opus high**) | read-only |

## Done when
- Validate is green, including the watch type-check.
- The CI XcodeGen build (iOS + watchOS + complication) is green.
- Watch simulator screenshots have been inspected.
- `docs/checklists/PHASE5_DEVICE.md` exists.
- The gate report lists the tier for each task.
