# Phase 10B gate: bug-fix pass and adaptive layout (iPad, iPhone Duo)

**Status:** READY FOR REVIEW (2026-11-12). Human request of 2026-11-11: reliability, iPad and iPhone Duo support, then judge the next phase. Extends Phase 10; Phases 11 and 12 are unchanged.

## Done
| Work | Agent / tier | Result |
|---|---|---|
| Bug hunt (read-only) | qa-reviewer · **Opus** | 6 defects (2 major, 4 minor), no crash or data loss; persistence, recurrence core, deletes and task completion traced clean |
| Bug fixes | swiftui-engineer · **Opus** | All six fixed with regression tests: split-class lessons both visible in the Grid; "Change for This Day" on a cancelled lesson no longer un-cancels it; `today` rolls over at midnight in the timetable's zone; A/B weeks survive an edit under rotation None; "Shortened lessons" only on bell-schedule timetables; a backup with its own validation error can be restored |
| QA of the fixes | qa-reviewer · **Opus** | Ready, nothing blocking |
| Adaptive layout | swiftui-engineer · **Opus** | iPad enabled (device family 1,2); shared `LayoutWidth` breakpoints from container width; standard `TabView` with `.sidebarAdaptable`; Tasks and Exams list beside detail; Timetable lesson inspector at ≥ 960 pt; Today and Settings capped to a readable column; no split at accessibility text sizes; 22 strings "this iPhone" → "this device". Details: `docs/specs/ADAPTIVE_LAYOUT.md` |

## Evidence
- **No local builds:** WSL is down (virtualization disabled in firmware, ENVIRONMENT §42). All build and test evidence is GitHub CI.
- **iOS CI 43117958232** (bug fixes): all jobs green, 644 core and 753 TimetableUI tests.
- **iOS CI 43121775032** (adaptive layout head `7892bbb`): all jobs green.
- **Integration branch CI:** see the commit that merged this report.
- **Simulator screenshots read:**
  - iPhone 17 Pro Max (43117887986): no regressions.
  - iPad 11" and 13" portrait (43117879078, 43117870293), and the re-shot fixes (43121791072): split views, capped Settings, lesson inspector all as designed.
  - iPad 13" landscape (43118725126): rotation works; taken before the fixes.
  - iPhone Duo outer display (43117883532): Today, grid, Tasks and the task editor fit with no clipping.

## Not done / limits
- **Duo inner display:** screenshots are black (the simulated device was closed). Unverified.
- **Duo side bars:** the tab bar stayed at the bottom on the outer display in the simulator. The HIG says the system moves standard bars to the side; we keep the standard `TabView` and do not override placement. Needs a device or a newer SDK check.
- **iOS 27 Duo APIs** (`ReservedRegion`, `ArrangementView`, toolbar visibility priority) are not used: the deployment target is iOS 26 (RISKS #116).
- **Nothing was run on a real device.** Resizing or folding while an editor is open, the midnight rollover and the split-class tiles (about 23–30 pt, under the 44 pt target, RISKS #118) are unverified.
- **Performance:** no new measurements. Phase 10 holds the measured pass; this round changed no hot path except the grid lane assignment.

## Decisions needed
| # | Decision | Recommendation |
|---|---|---|
| P10B-1 | Approve this pass | Approve after the device rows in `docs/checklists/ADAPTIVE_DEVICE.md` and I1–I3 in `PHASE10_DEVICE.md` |
| P10B-2 | Raise the minimum OS to iOS 27 to adopt the Duo fold APIs | Not now; standard components already adapt |
| P10B-3 | Split-class tiles under 44 pt | Check on a device; if too small, open a chooser from one stacked cell |

## Next phase
Phase 11 (monetisation) and Phase 12 (release) both need the paid Apple Developer account, and the paywall was declined (P9-3). No further phase can start without that decision. Recommended next milestone: turn virtualization back on, install this build, and run the device checklists for Phases 4–10B.

## Human steps
1. Enable virtualization in the PC firmware so WSL, local validation and iPhone installs work again.
2. Run the device checklists; report what is wrong.
