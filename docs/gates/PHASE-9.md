# Phase 9 gate: AI import (photo, scan or PDF to timetable)

Plan: `docs/specs/PHASE9_PLAN.md`. Merged to `main` at `8f35be8`. The same merge round also brought in the Grid layout option at `bce400e`.

## Done
| Stage | Agent / tier | What | Commits |
|---|---|---|---|
| I1 Parser, reconciliation, review model, eval | core-domain-engineer · **Opus** | `RecognizedTable` with `Bounds` input caps, `TimetableImportParser` (both orientations, 12-language days, times, spans, cell split, confidence reasons), `CellNormaliser` seam, `ImportReview`, `ImportPayloadBuilder` → `SharePayloadV1` | `bf4c753` … `6f49ed3` |
| I2 Capture, Vision, review UI, entry points, Tier A, model screen | swiftui-engineer · **Opus** | Document camera / Photos / Files / PDF pages, `VisionTableReader`, processing screen, review (image ↔ grid, questions, "Which week is A?", edit and apply to identical cells), Approve through `ShareImportPreview` (Add, or Replace with a backup), `FoundationModelsNormaliser`, Settings › Import | `wip/phase9-app` → `eedc207`, `8f35be8` |
| Grid layout option (human decision) | swiftui-engineer · **Opus** | `AppSettings.gridLayout`; Slovak days × periods by default; Settings switch; old layout kept; "Tabula Pro · Active" row | `bce400e` |
| QA | qa-reviewer · **Opus** ×3 | I1: blocked on input bounds, fixed. Grid: ready. I2: ready; 4 one-line follow-ups applied in `8f35be8` | — |

## Evidence
- validate.sh on `main` `8f35be8`: ALL CHECKS PASSED. 611 core and 686 TimetableUI tests; 1,605 catalog keys complete in all 12 languages.
- xtool build: 0 warnings.
- Eval (`docs/eval/IMPORT_EVAL.md`, 40 synthetic fixtures, 12 languages):
  - Structure exact on 40/40; 35/40 fixtures fully correct; subject 96.2%.
  - The human's aSc example parses exactly.
  - The 5 silent errors are all span guesses in the loose-line fallback.
- CI screenshots on the branch: runs 41659680319 and 41665404310 (fixes applied from them).

## Not done / limits
- **Never run on a device:**
  - Vision quality on real photos, the document camera, real PDFs.
  - Foundation Models output, time and memory per import.
- **The eval fixtures are synthetic,** and the same agent wrote them and the parser, so expect real-world accuracy to be lower.
- **Tier B local model is UI only:** a disabled Download and "Available in a later version". It needs a dependency approval, hosting, and likely the paid account (increased-memory-limit entitlement).
- **Foundation Models doesn't support Slovak, Czech, Polish, Hungarian, Romanian, Ukrainian or Serbian** (Apple's list), so for those languages import is deterministic only.
- **Not re-screenshotted after the last fixes:** `import.capture`, `onboarding`, `settings.import-model`, `import.review`.

## Decisions needed
| # | Decision | Recommendation |
|---|---|---|
| P9-1 | Approve Phase 9 | Approve after the device checklist rows P9.1–P9.29 |
| P9-2 | Tier B: llama.cpp (MIT, new dependency) plus model choice and hosting | Decide with the paid account; deterministic + Apple Intelligence covers clean aSc tables |
| P9-3 | Phase 10: the human declined a paywall ("most features are free") | Keep the "Tabula Pro · Active" row; StoreKit waits for the paid account |

## Device checklist
`docs/checklists/PHASE9_DEVICE.md` (P9.1–P9.29); grid rows in `docs/checklists/UX_DEVICE.md`.

## Human steps
Import a real photo of your aSc timetable on the iPhone. Report what came out wrong.
