# Phase 9 plan: AI import (photo, screenshot or PDF to timetable)

Status: started 2026-11-02 (human: "implement Phase 9 as far as possible without the paid account; full UI/UX for a showcase video"). Follow `ponytail` and `apple-design`. Spec: AI_IMPORT.md.

## Paid-account check (verified 2026-11-02 in Apple's docs)
- **Works with free provisioning:**
  - Vision `RecognizeDocumentsRequest` / `VNRecognizeTextRequest`.
  - VisionKit document camera, PhotosPicker, fileImporter and PDFKit.
  - The on-device Foundation Models `SystemLanguageModel`. The framework overview lists no entitlement for it, only "a device that supports Apple Intelligence"; iPhone 16 models qualify. Entitlements exist only for Private Cloud Compute (`com.apple.developer.private-cloud-compute`) and custom adapters.
- **Language limit:** Apple Intelligence languages are English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (simplified and traditional), Japanese and Korean. **Not** Slovak, Czech, Polish, Hungarian, Romanian, Ukrainian or Serbian. Prompts with unsupported-language text throw `LanguageModelError.unsupportedLanguageOrLocale`. So Foundation Models stays a bonus tier (AI_IMPORT Tier A).
- **Needs the paid account or other approvals, so deferred:**
  - Tier B local model: llama.cpp (a new dependency, needs approval) or a Core AI model. It needs the increased-memory-limit entitlement (assumed paid; xtool strips it, RISKS #29) and model hosting (Cloudflare R2 is a human step; Apple-hosted Background Assets needs the Developer Program).
  - Private Cloud Compute.

## Decisions
1. **Tiers in this phase:**
   - **D, deterministic, always available:** the primary path.
   - **A, Foundation Models:** only for low-confidence cells, and only when `availability == .available` and the text passes `supportsLocale`. Text JSON goes in, guided generation (`@Generable`) comes out, temperature 0, never invent lessons. Multimodal image prompting is a later option; verify the API first.
   - **B, local model:** UI only. A Settings › Import "Recognition model" screen with size disclosure and a disabled download, labelled as coming in a later version. No fake progress.
2. **Capture:** document camera, Photos, Files (images and PDF; render PDF pages with PDFKit).
3. **Structure:** `RecognizeDocumentsRequest` tables, falling back to `VNRecognizeTextRequest` plus geometric clustering. The adapter outputs `RecognizedTable` JSON (cells, row/column spans, boxes, OCR confidence). This is the seam to TimetableCore.
4. **Parser (TimetableCore, Linux-tested):**
   - Both orientations: days as rows (the Slovak aSc layout, e.g. Po/Ut/St/Št/Pi × periods 1–13 with start times) and days as columns.
   - Day names and abbreviations in all 12 languages.
   - Period numbers and time ranges (08:00–08:45, 8.00-8.45, "7.00", "1. hod"); infer the bell schedule.
   - Spans become multi-period lessons.
   - Split cell text into subject, room, teacher and type.
   - Per-cell confidence with reasons.
5. **Review UI:**
   - The original image beside the parsed grid; low-confidence cells highlighted; targeted questions.
   - Inline edits; "apply to all identical cells".
   - **Approve** creates a new timetable through the existing import path (Add as new by default; Replace only with confirmation and an automatic backup). Never save silently.
6. **Entry points:** onboarding ("Import from Photo or PDF"), the timetables manager, the Timetable ⋯ menu.
7. **Evaluation harness:** `Fixtures/import/` with ≥ 30 `RecognizedTable` JSON fixtures and expected output, across the 12 languages, including the human's aSc example. Report in `docs/eval/IMPORT_EVAL.md`; be honest about failures.
8. **Tier:** follow MONETIZATION.md for Free or Pro; the current tier is all-access.

## Stages
| Stage | Agent | Scope |
|---|---|---|
| I1 Parser, reconciliation, review model, eval harness | `core-domain-engineer` (**Opus**: parsing, time) | TimetableCore + TimetableUI pure + fixtures |
| I2 Capture, Vision adapter, review UI, entry points, Tier A adapter, model screen | `swiftui-engineer` (**Opus**: data import) | App + TimetableUI; uses I1's types |
| QA | `qa-reviewer` (**Opus**) | read-only |
