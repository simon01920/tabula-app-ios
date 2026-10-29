# UX overhaul plan (Phase 4U): fixes from the two UI/UX reviews

Status: started 2026-10-23 at the human's request: "fix the UI/UX issues highlighted in the MDs … then continue to the next build phase following the design instructions and HIG".

## Sources
- **Opus review:** `docs/ux-review/design_ui_ux_fix_OPUS.md`. It covers all 185 screenshots and uses finding IDs C1–C3, H1–H15, M1–M31, L1–L10 and R1–R6; §9 is the visual identity.
- **Astra review:** `docs/ux-review/design_ui_ux_fix_ASTRA.md`. It covers 39 screenshots and uses finding IDs F01–F22; §5 is the editor control audit.
- Screenshots: `docs/ux-review/screens/` (local, regenerate with `scripts/ux-review-index.py`).
- **HIG:** the user-level `apple-design` skill (dickwu/apple-design-skill @ 914b6a3, 123 HIG pages). Every UX agent loads it and cites the HIG page it follows.
- Project skills: `liquid-glass-design`, `swiftui-patterns`, `accessibility`.

## 0. Decisions
Answers to the reviews' open questions, as checked in the code:
- **Q1:** quick add creates a **weekly** lesson slot.
- **Q2:** production onboarding defaults to "Start blank"; the sample preselection was the DEBUG route.
- **Q3:** widget checkboxes are interactive only with `TABULA_APP_INTENTS` (TestFlight builds).
- **Q6:** exam "Mark Done" sets `completedAt`, which moves the exam to History.

Defaults the orchestrator took (listed for the gate, the human can reverse them):

| # | Decision |
|---|---|
| D1 | **Adopt the "Exercise book" identity** (Opus §9). Root tint `ink` (#2541B2 light / #8EA2FF dark; Increase Contrast #1A2F85). `correction` red is used only for overdue, cancelled and destructive. The `highlighter` "Now" marker is the single signature element. Times and countdowns use rounded monospaced digits. Everything else stays native. |
| D2 | **Base English is US English** (Color, Acknowledgments). Opus Q8 / L7. |
| D3 | **Remove the in-app Light/Dark override** (HIG dark-mode: "Avoid offering an app-specific appearance setting"). Palettes stay. |
| D4 | **Time format defaults to "System"** (follows iOS 24-Hour Time); the override stays. One `Locale` with the effective hour cycle is injected at the root, so every `DatePicker` matches the text (H1, F22). |
| D5 | **Keep the three task types** (Homework, Assignment, To-do): the data model is frozen. Add a one-line description of each in the type picker. |
| D6 | **Rename exam "Mark Done"** to "I've Taken This Exam", shown from the exam date on; before that, "Move to History" lives in the ⋯ menu. No grade recording: that would be a schema change, so it goes to the decision list. |
| D7 | **Hide "Time Sensitive"** wherever the build lacks the entitlement. The health check counts only user-fixable problems as warnings (H9). |
| D8 | **Onboarding goes from 7 steps to 4** (R5 / F08). Shown fields come from the profile. Reminder permission is asked in context (exists since Phase 3). Unavailable imports are hidden. "Just look around" creates sample data with a banner "This is sample data · Remove", which removes **only** the sample timetable and its children (tracked device-locally, no schema change) (F10). |
| D9 | **Week rotation in the lesson editor** is a segmented Every week / Week A / Week B; N-week cycles use a multi-select list with "Every week" first (H8). UI mapping only, with no model change. |
| D10 | **Field visibility controls summaries only.** Editors always offer every field under "More details" (Astra F06). |
| D11 | **Glossary** (Opus §10): Task (types Homework/Assignment/To-do); Break = gap between lessons; **Holidays** = days off; Week A/Week B; Change (Cancel/Move/Substitute/Room); **Custom times**; **School type**. Rotation labels come from localised full-phrase keys; no "Week " + label concatenation. |
| D12 | **Capitalisation:** Title Case for navigation titles, tab names, buttons and menu items; sentence case for section headers, row labels, footers, body text and empty states. English only; other languages follow their own rules. |

**Needs the human (not implemented):**
- **M30:** a reduced *free* Lock Screen widget. This changes the Free/Pro split, which CLAUDE.md says needs the human's approval.
- **Grade recording** for past exams (schema change).
- **Merging Assignment into Homework** (schema and reminder kinds).

## 1. Stages, tiers, ownership
| Stage | Agent (tier) | Findings |
|---|---|---|
| **U1 Foundation** | `swiftui-engineer` (**Opus high**) | D1 tokens (`DesignTokens`: ink, correction, highlighter; Increase Contrast variants) and the root tint; `AppSymbol` enum (one SF Symbol per concept, M8, H5 change symbols); a typography helper for times and countdowns (rounded + monospaced digits); the shared "Now" highlighter view; the **H1/D4** hour-cycle locale at the root; **C2** contrast fixes in shared components (Pro badge, tinted text on grey fills, chips, outlines); **M7** standard close/back buttons on detail sheets; **M1** duplicate header/label pattern in the shared form helpers; **M6** title-field style in the shared editor scaffold; **M5** validation only after interaction; **M9** primary colour for times and rooms; **L1** dates without the current year; a shared **AX layout helper** (H13/F01: stack the icon above the text at accessibility sizes, cap decorative icons). Builds the components the later stages use; it does not restructure screens |
| U2 Tasks + Exams | `swiftui-engineer-sonnet` (Sonnet medium) | **R2** grouped Tasks list + quick-entry sheet; C3, H6, H7, M10, M21, M22, M23, F15 (row tap vs completion, undo); Exams **H15/D6**, **M24**, **M25** ("When": during a lesson / custom / all day), F16 |
| U3 Today | `swiftui-engineer` (**Opus high**) | **R1** (one order for every profile, hero states before / break / lesson / after / holiday); **H2** "25 min left · ends 10:45" (minutes, no seconds in the app); H3, M10, F02, F14, F16 (exam below, title first), F17 |
| U4 Timetable | `swiftui-engineer` (**Opus high**) | **H4** toolbar (labelled view menu, Today button, Edit Timetable / Add Lesson); **H5** cell anatomy (room always visible, one badge slot, distinct change symbols, dimmed cancelled lessons, now highlight, TipKit legend); **H14** quick-add (opaque sheet, "Every Monday · Week B · Period 7"); M11 now line above cards with a time label (F19 contrast-safe on any subject colour); M12/F18 day-card time typography; M13 tiles (no ✓, dim past, "Now"); M14 quiet empty slots; M15 lesson-detail labels; F03 AX day agenda; F20, F21 (restrained subject fills option); L3, L5, L8; the "Week Párny" concatenation (D11) |
| U5a Settings IA + Reminders | `swiftui-engineer-sonnet` (Sonnet medium) | **R3** Settings IA (pushed navigation, Subjects / Bell schedule / Terms rows, no stacked sheets); **R4** Reminders (one row per kind, the toggle only in the detail); **H9/D7**, H10, H11, **D3**, M26 (palette picker + "Apply to all subjects" with Undo), M27, M28, L4 |
| U5b Editors | `swiftui-engineer` (**Opus high**) | **C1** bell toolbar + **R6** bell editor; **H8/D9** week picker; M16 weekday chips (week start respected); M17, M18, M19 (Holidays, swipe to delete), M20; **Astra F05 editor control audit** (every control in the subject, lesson, task, exam, bell, terms and day-change editors and their submenus: keep / disable with a reason / remove / informational; record the matrix in the stage report); **F06/D10** |
| U6 Onboarding | `swiftui-engineer` (**Opus high**) | **R5/D8** (4 steps), H12, H13 (onboarding), F01, F07 (repeat model with anchor and separate term dates), F09, F10, F11, F12, F13 |
| U7 Widgets & Live Activities | `widgets-watch-engineer-sonnet` (Sonnet medium) | M29 (time first, short names; circular `Gauge` instead of a spinner-like glyph), M31 (checkbox gap; remove circles on non-intent builds), L9, L10, H2 units ("25 min left", "in 1 h 30 min", no seconds before exams), the highlighter "Now" in the Today widget row and Live Activity, D1 tint in widgets |
| U8 Copy & terminology | `localization-engineer` (**Opus high**: rewrites meaning in 13 languages) | D2 US spelling, D11 glossary, D12 capitalisation, M2, M3, M4 developer language, Astra §4 copy table (en + sk given; re-translate the others), the Opus §10 string list. Runs **after** U2–U7 merge, so it sees the final strings |
| QA | `qa-reviewer` (**Opus high**) per stage; final UX QA with the `apple-design` skill against both reviews | — |

**Order:**
1. U1 first.
2. U2, U3, U4 in parallel.
3. U5a, U5b, U6, U7 in parallel.
4. U8.
5. Full screenshot set (`scripts/ux-review-index.py`) and a final UX re-review that checks every finding ID in both documents as fixed / deferred (with reason) / rejected (with reason).

## 2. Rules for every UX stage
- **Load the skills:** load `apple-design` and read the HIG reference pages for the components you touch (e.g. `references/components/toolbars.md`); cite the page in the report. Load `swiftui-patterns`, `accessibility` and `liquid-glass-design` as relevant.
- **Controls:** native SwiftUI controls only; no custom tab bar or navigation. Use U1's tokens, symbols and helpers; don't redefine them.
- **Every screen you change** must work at default size, an intermediate size and AX-XXXL, in light and dark, and with Increase Contrast and Reduce Transparency / Reduce Motion. It must also hold up in Slovak and German. No word-internal breaks in buttons.
- **Contrast:** text ≥ 4.5:1 (≥ 3:1 for large text); meaningful non-text indicators ≥ 3:1. Add pure contrast tests for any new token pair.
- **Data:** no schema change. Data written by older builds must keep its meaning.
- **Strings:** new or changed English strings go through `scripts/l10n-add.py` and `l10n-translate-missing.py` in WSL. Plural forms come from catalog variations; never concatenate fragments. Regenerate the review export.
- **Screenshots:** update the DEBUG screenshot routes and seeds when screens change. Add routes for new screens (e.g. the quick-entry sheet, the reminder kind detail) to `ui-screenshots.yml`.
- **Report:** the finding IDs fixed, deferred or rejected (with reasons), the HIG pages cited, the validate line, and a clean xtool build.

## 3. Status / resume point (paused by the human, 2026-10-26)
**Done and saved on GitHub** (none of it is merged into `main` yet):
- **`wip/ux-integration`** @ `5bafead`. U1 foundation + U1 QA fixes, U5b editors, U5a settings and U4 timetable are merged here and deduplicated: no local token, highlighter, symbol or touched-flag copies remain. validate: ALL CHECKS PASSED (540 core + 565 UI tests). xtool build: 0 warnings at `8047182`; `5bafead` has only had validate.
- **`wip/ux-u6-onboarding`** @ `6869aa1`. U6 is finished and validated **on its own** but **not yet merged** into the integration branch.
- **`wip/ux-u7-widgets`** @ `4b29fa4`. U7 is finished and validated **on its own** but **not yet merged**.

**Next steps, in order:**
1. Continue the integration on `wip/ux-integration`:
   - Merge U6: remove its duplicate `WeekdayChips`, `OnboardingColors` and local AnyLayout stacks, and take U1's choice-row structure.
   - Merge U7: `NowHighlighterTag` becomes `NowMarker` (needs a widget rendering-mode outline); delete `WidgetInkTokens`, `InkForeground` and `CorrectionForeground`.
   - Then: `grep "adopt U1"` must be empty; add an integration note here; regenerate the review export; run validate; run clean xtool builds (base and `--app-intents`).
2. Run one `qa-reviewer` (Opus) on the integrated branch, then merge it to `main` and push.
3. Run U2 (Tasks + Exams) and U3 (Today) **from the integrated `main`**, because they touch the files U1, U4 and U5b changed. Then U8 (copy and terminology). Then the full screenshot rerun (`scripts/ux-review-index.py`) and a check of every Opus and Astra finding ID. Then the Phase 4U gate report. Then Phase 5 (Watch).

**Integration decisions for the human to review:**
- A lesson with several change reasons shows the generic "changed" symbol, and the legend has a "Changed" row. U1's rule replaces U4's "most important reason" symbol.
- New tokens: `onCorrection` (the now-line time label) and `changed` (a moved time in lesson detail; 4.2:1 on the grey page, so it may only be used on cards).
- The now line stays correction-red. This bends D1's "red only for overdue, cancelled, destructive" rule; decide whether to keep it.
- D10: hiding a field affects summaries only, never the editors. PRODUCT.md was updated to match (it previously said "hidden everywhere").
- The "Other" school type now shows Room and Teacher by default (PRODUCT.md previously said all off).
- The "Lessons are called" setting is removed; it follows the school type.

**Session tooling:**
- The `ponytail` and `haiku-helper` skills are installed user-wide; follow them, and tell every subagent to load `ponytail`.
- The local agent worktrees under `.claude/worktrees/` hold the same commits as the `wip/*` branches and can be deleted after the merge.
