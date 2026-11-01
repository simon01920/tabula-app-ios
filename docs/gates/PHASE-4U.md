# Phase 4U gate report — UX overhaul (Exercise-book identity, HIG pass, verification and fix pass)

Status: **READY FOR REVIEW — waiting for your approval** (2026-11-01) · Plan: `docs/specs/UX_OVERHAUL_PLAN.md` · Verification: `docs/ux-review/VERIFICATION.md` · Device checklist: `docs/checklists/UX_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| U1 Foundation | swiftui-engineer · **Opus high** | D1 tokens (ink, correction, highlighter; Increase Contrast variants), `AppSymbol`, rounded-mono time type, `NowMarker`, hour-cycle locale (D4), contrast fixes in shared components, `AdaptiveStack` for AX sizes, validation visibility | `cf7cafd`, `a9c1f4b` |
| U1 QA → fixes | qa-reviewer · **Opus high** → Opus | **B1:** Save is disabled again while a draft is invalid. **B2:** `.onInkLabel()` on prominent buttons, enforced by `validate_config.py`. **M1:** the locale override is scoped to time pickers. RISKS #88 retired | `2fbb31a` |
| U4 Timetable | swiftui-engineer · **Opus high** | Toolbar and Today button, cell anatomy (room always visible, one badge slot), TipKit legend, now line, tiles, quick add, lesson detail; rotation phrases instead of "Week Párny" | `b0fdc40`, `6537e28`, `333a7d4` |
| U5a Settings IA + Reminders | swiftui-engineer-sonnet · **Sonnet medium** | Pushed Settings navigation, one row per reminder kind, Colors with Apply to All Subjects + Undo, Light/Dark override removed (D3) | `d3b28c9`, `6b05fa0` |
| U5b Editors | swiftui-engineer · **Opus high** | Bell editor, Every week / A / B picker (D9), weekday chips, editor control audit (`docs/ux-review/EDITOR_CONTROL_AUDIT.md`), D10 | `96721fb`, `5b708d1`, `a9612a8` |
| U6 Onboarding | swiftui-engineer · **Opus high** | 4 steps (D8), repeat model with anchor, removable sample data with a banner | `b2e0766`, `30b56c0`, `cafa9aa` |
| U7 Widgets and Live Activities | widgets-watch-engineer-sonnet · **Sonnet medium** | Units and short names, `Gauge` ring, highlighter NOW, checkbox gap | `d8d401f`, `c0c1380`, `4b29fa4` |
| Integration (U1, U4, U5a, U5b, U6, U7) | orchestrator · Opus; qa-reviewer · **Opus high** | Merged in order, then deduplicated onto U1 (plan §4). QA fixes: sample-removal count, pushed editors (no stacked sheets), tab bar hidden while an embedded editor is dirty, disabled `onInk` label, colour Undo scoped | `f3fa2d5`, `b911447`; CI run 40919273127 green; 540 core + 587 UI tests |
| U2 Tasks + Exams | swiftui-engineer-sonnet · **Sonnet medium** | Grouped Tasks list, quick-entry sheet, exam card, actions and "When" editor | `38d3a94`, `2939092`, `e46a8d0` |
| U3 Today | swiftui-engineer · **Opus high** | One section order for every profile, hero states, minute-precision "25 min left" | `0ca3280`, `eee4395` |
| U2/U3 QA → fixes | qa-reviewer · **Opus high** → Sonnet | Shared task undo toast (Today, VoiceOver), hero badge text, quick-entry and exam-editor fixes | `2755402`; merged `6689ffa`; CI 41064660625 green; 615 UI tests |
| U8 Copy and terminology | localization-engineer · **Opus high** | US English, glossary (D11), capitalisation (D12), developer-language fixes (M2–M4); 25 keys re-translated in 12 languages (`needs_review`) | `acad410`, `cc79e61`; merged `8d2bcaf`; CI 41120966686 green; 1,346 keys |
| Verification | qa-reviewer · **Opus high** (read-only, `apple-design` HIG) | 87 finding IDs against 182 CI screenshots and **24 new defects** (1 critical, 5 high, 9 medium, 9 low) | `dc06cc2` |
| Fix pass (23 of the 24 defects) | Opus (commit co-author) | Blank quick-entry sheet (D1), Today link tint and repeated hero (D5, D8), AX overflow and word breaks (D2, D7, D10, D12, D14, D24), now line behind cards, legible past tiles, badge keeps the room (D3, D4, D6), contextual dates (D15, L1), widget progress in ink, visible swatch edges (D19, D20), L6 maths glyph, screenshot routes for exam detail and the subject editor (H15, M18) | 7 commits `28fcccb` to `7f92328`; merged `16ac596` |

**Tier split:** Opus high did U1, U3, U4, U5b, U6, U8, the integration, the fix pass and all QA runs. Sonnet medium did U2, U5a and U7, plus the U2/U3 QA fix round. U4, U5a, U5b, U6 and U7 had no separate QA run; the integration QA covered them.

## Runtime evidence
### Verification of the overhaul (qa-reviewer, before the fix pass)
- **87 IDs:** Fixed 58 · Partial 24 · Not fixed 2 (L5 tab bar tint, L6 maths glyph) · Deferred by design 1 (M30) · Unverified 2 (H15, M18: no screenshot existed).
- **Method:** every screen as a light | dark | AX-XXXL montage, contrast pixel-sampled where flagged.
- The Watch image was not in the repo, so the Watch is unverified.

### Final merged state `16ac596`
- **iOS CI run 41217701086:**
  - Linux job green: `validate.sh` ALL CHECKS PASSED, **551 core + 634 UI tests** (includes Phase 6), 1,389 keys and 5 InfoPlist keys complete in 12 languages.
  - xtool path green.
  - **XcodeGen job red.** The macOS core-test compile fails in `CloudSyncTests.swift:118`, a Phase 6 test (see `PHASE-6.md`). It is not a 4U defect, but it hides the macOS check of this tip.
- **Screenshots:** run 41217701115 on `16ac596` is green. **Not yet reviewed.**
- **Earlier green iOS CI runs** with the XcodeGen iOS + watchOS build: `f3fa2d5`, `6689ffa`, `8d2bcaf`.

### Device
- **Not run:** `UX_DEVICE.md`. Nothing in this phase has been seen on the iPhone.

## Not done / known limits
- **The fix pass is not re-verified.**
  - There was no screenshot review and no qa-reviewer run after `16ac596`.
  - **D16 (Liquid Glass tab bar tinted by saturated tiles): closed, by design.** The suggested bottom margin has been in place since U4 (`TimetableRootView` `.contentMargins(.bottom, 24, for: .scrollContent)`, L5), so the last tile ends above the bar. The tint left over is content scrolling beneath the glass bar, which is what iOS 26 bars are designed to do (HIG: content scrolls under bars).
  - Partials that no fix-pass commit names:
    - H2 (widgets and Live Activities keep timer style);
    - M4, M6, M29, M31, L4, F15, F21.
  - Some may be fixed as a side effect; only a re-run tells.
- **Not verifiable from screenshots:** Increase Contrast, Reduce Motion, Reduce Transparency, VoiceOver wording, dark-mode label colour on ink buttons (RISKS #86), whether the tab bar really hides while an editor is dirty on iOS 26 (row IQ.3).
- **UX_DEVICE.md has no rows for the fix pass yet** (D1, D3, D4, D5, D6 and the AX layouts).
- **Widget checkboxes** show circles on non-intent builds; the interactive checkbox needs TestFlight (M31, P4-6).
- **P4-3 not built:** "Hide details on Lock Screen" for Live Activities.
- **Translations:** every changed or new string is machine-made `needs_review`. Use `docs/localization/review/`.

## Decisions taken (reviewable)
D1–D12 are in the plan §0. The ones that change behaviour most:
- **Identity:** "Exercise book"; ink is the tint, correction red only for overdue, cancelled, destructive and the now line, highlighter for "Now".
- **D3:** no in-app Light/Dark override. **D4:** time format follows iOS by default.
- **D6:** exam "Mark Done" became "I've Taken This Exam" (from the exam date; before that, "Move to History" in the ⋯ menu).
- **D8:** onboarding has 4 steps; sample data is removable and tracked device-locally (no schema change).
- **D10:** hiding a field affects summaries only; editors always offer every field. PRODUCT.md was updated.
- **Integration:** a lesson with several change reasons shows the generic "Changed" symbol; the "Other" school type shows Room and Teacher by default; "Lessons are called" is removed (follows the school type).
- **Schema:** unchanged. Old data keeps its meaning.

## Risks (`docs/RISKS.md`)
- **#86** white labels on the dark-mode ink: **OPEN**, device row U1.3. Prominent buttons use `.onInkLabel()`; the validator enforces it.
- **#87** hour-cycle locale and string lookup: **MITIGATED** (scoped to time pickers), device rows U1.4 and U1.5.
- **#88** Save tappable on invalid drafts: **RETIRED**.
- **Not in RISKS yet:** the unverified fix pass (see Not done).

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P4U-1** | **Approve Phase 4U** | Approve, after a screenshot look at run 41217701115 (the fix pass is unreviewed) |
| P4U-2 | **M30:** a reduced free Lock Screen widget. Changes the Free/Pro split | Decide with the paid-account and pricing work; not before |
| P4U-3 | **Grade recording** for past exams (schema change after Phase 1) | Defer to v1.1 |
| P4U-4 | **Merge Assignment into Homework** (schema and reminder kinds) | Keep three types (D5) |
| P4U-5 | **D1–D12 and the integration decisions** above | Accept; each is reversible in one stage |
| P4U-6 | Run a **re-verification** (screenshots + qa-reviewer) of the fix pass and the unnamed partials before Phase 11 | Yes, one short run |
| P4U-7 | **P4-3** Lock Screen privacy option (carried over from Phase 4) | Add it; small |

## Manual on-device checklist
`docs/checklists/UX_DEVICE.md`: sections U1 to U7, "Integration QA fixes" and U2, each with the state matrix (Dynamic Type to AX-XXXL, light and dark, Increase Contrast, Reduce Motion and Transparency, German and Slovak, CJK, VoiceOver, 44 pt targets). Start with U1.3, U1.4, U1.5 and IQ.3 (RISKS #86, #87).

## Human steps
1. Look through the screenshots of run 41217701115 (re-download the artifact; `docs/ux-review/screens/` is git-ignored).
2. Install the dev build on the iPhone (`docs/DEVICE_SETUP.md`) and run `UX_DEVICE.md`.
3. Review the Slovak strings (`docs/localization/review/`).
4. Answer P4U-1 to P4U-7.

## Next
- **Phase 5 (Watch) and Phase 6 (sync + backup)** are built; their gate reports follow in `PHASE-5.md` and `PHASE-6.md`.
- Phase 7 (Sharing) and Phase 8 (Export) have plans on `main` and work on `wip/phase7-app` and `wip/phase8-app`.
