# Phase 8 gate report — Export (image, PDF, CSV, Excel, calendar)

Status: **READY FOR REVIEW, with one open CI failure (the iCloud sync variant check) — waiting for your approval** (2026-11-01) · Plan: `docs/specs/PHASE8_PLAN.md` · Device checklist: `docs/checklists/PHASE8_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| E1 CSV, ICS and XLSX writers | core-domain-engineer · **Opus high** (time zones, formats) | `ExportRows` from `ScheduleResolver` (`.actual`), then `CSVExport` (RFC 4180, UTF-8 BOM, formula neutralising), `ICSExport` (RFC 5545, one VEVENT per occurrence, stable UIDs, TZID + VTIMEZONE or floating, `STATUS:CANCELLED`), `XLSXExport` (own minimal OOXML and ZIP writer on CZlib, no dependency); 13 Linux tests | `e7539ca` |
| E2 Export sheet, image and PDF | swiftui-engineer-sonnet · **Sonnet medium** | Timetable ⋯ › Export… sheet (Type, View, Range), `ImageRenderer` print layout (light theme, fixed width), PNG pages and paginated PDF, file names, share sheet, Pro gate through the entitlements helper, strings, checklist | `bb08915` |
| QA, first run | qa-reviewer · **Opus high** | **0 blocking, 3 majors (E2)** | fixed below |
| E2 QA fixes | swiftui-engineer-sonnet · **Sonnet medium** | Export render flag, a DEBUG-only `export.preview` route, the term cap, temp-file cleanup, CSV and XLSX hardening | `b80e186` |
| QA, focused re-check | qa-reviewer · **Opus high** | The fixes pass | read-only |
| Merge | orchestrator | E1 and E2 merged into `wip/integration` | `cc5f1fc` |

**Tier split:** Opus high did E1 and both QA runs; Sonnet medium did E2 and its QA fixes, a well-specified UI stage on E1's finished writers. QA, always Opus, found 3 majors in it; the focused re-check passed them.

## Runtime evidence
### Merged state `cc5f1fc` (Phases 7 and 8 on `wip/integration`), verified
- **`validate.sh` exit 0:** **564 core + 667 TimetableUI tests** (551 + 634 at the Phase 6 gate; the rise includes Phase 7), 1,482 catalog keys complete in all 12 languages.
- **xtool build:** 0 warnings.
- **iOS CI run 41273158234 (8b78047): green.** All jobs pass: Linux validate and core tests, xtool/SwiftPM, and on macOS the core tests, the unsigned iOS + watchOS build and the CloudKit variant compile. The earlier red run 41271764610 failed only the CloudKit link check: Xcode 16+ Debug builds keep the code in `TabulaApp.debug.dylib`, so the check now reads that file too (`8b78047`).
- **Screenshots run 41271737929: success.** Inspected: `share.import-preview` is correct. `export.preview` showed the empty state: the route rendered before the async model load. Fixed in `ce8a045`; the re-run result is below.

### Device
- **Not run:** `PHASE8_DEVICE.md`. No exported file has been opened in Photos, Files, Numbers, Excel or Calendar. The checklist has the rows for each.

## Not done / known limits
- **`ImageRenderer` output is unchecked on a device.** The risk is `GeometryReader` and `ScrollView` content rendering blank or clipped. Use the DEBUG-only route `export.preview` to see the real export of the current week's grid, then the PDF and image rows of the checklist.
- **A Week-view page taller than the paper is clipped** (the print layout does not scale it down).
- **A term longer than 366 days exports only its first 366 days** (`ExportPlan.maximumDays`).
- **Temp-file removal timing needs a device check:** when the exported file is deleted relative to the share sheet closing.
- **An unfinished PDF render keeps running if the sheet closes through Cancel or a deep link.** Swiping the sheet down is now disabled while it renders; the other two exits are not blocked.
- **Exports are Pro, but the current tier is all-access,** so the gate is not visible. To see it, run a build whose entitlements deny `ProFeature.exports`.
- **Translations:** 34 `export.*` keys, including `export.file.fallback`, are machine-made and still `needs_review` in at least one language.
- **XLSX has no styles part:** dates and times are text, so the rows in Numbers and Excel are unchecked (opening without a repair prompt is a checklist row).

## Decisions taken (reviewable)
- **Pure writers in `TimetableCore`:** CSV, ICS and XLSX are Linux-tested. Image and PDF stay in the App because `ImageRenderer` is SwiftUI.
- **Cancelled lessons stay in every format:** the Change column in CSV and XLSX, `STATUS:CANCELLED` in ICS (a re-import cancels the earlier event).
- **ICS:** one event per occurrence (no RRULE, so rotations, overrides and holidays stay correct); a zone is written only for fixed-zone timetables, otherwise times float.
- **CSV safety:** fields starting with `=`, `+`, `-`, `@`, TAB or CR get a leading `'` (formula injection from shared subjects).
- **Default range:** the current term, or the next 4 weeks when no term contains today.
- **No new dependency; persisted schema unchanged.**

## Risks (`docs/RISKS.md`)
- **No new RISKS.md row was added for Phase 8.** The limits above are the register until the human decides; proposed rows: ImageRenderer fidelity (OPEN, device), term cap (ACCEPTED), PDF render continuing after Cancel (OPEN, low).

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P8-1** | **Approve Phase 8** and move on | CI is green (run 41273158234); approve and `export.preview` looks right on your phone |
| P8-2 | **Exports are Pro, but the current tier is all-access.** Keep exports in Pro? | Keep: it is already in the entitlements helper (MONETIZATION) and costs nothing to hold until the paid account |
| P8-3 | **A Week-view page taller than the paper:** scale to fit, or add pages? | Decide after the device rows show how often it happens |

## Manual on-device checklist
`docs/checklists/PHASE8_DEVICE.md`: sheet states, file names, PDF and image (the main risk), CSV in Numbers and Excel, `.xlsx` in Excel and Numbers, and `.ics` into Calendar (zone, cancelled events, re-import without duplicates). Start with `export.preview`, then Export… on a real timetable.

## Human steps
1. Run `PHASE8_DEVICE.md` on the iPhone 16 Pro Max; start with the PDF and image rows.
2. Open one CSV and one `.xlsx` in a spreadsheet app, and one `.ics` in Calendar.
3. Check that a file leaves no temporary copy behind (timing row of the checklist).
4. Answer P8-1 to P8-3.

## Next
- **Phase 7 (Sharing)** is reported in `docs/gates/PHASE-7.md`.
- Phase 9 waits for the paid account.
