# AI IMPORT — from photo/screenshot/PDF to timetable (free, on-device)

## Goal
User photographs or uploads a timetable; the app builds the timetable, shows it beside the original for approval, highlights uncertain cells, asks targeted clarifying questions, and saves only after explicit approval. **Per-use cost to us: zero.** No network inference by default.

## Findings that shape the design
- Vision (iOS 26) `RecognizeDocumentsRequest` detects tables (rows/columns), but OCR language coverage for Slovak, Czech, Polish, Hungarian, Romanian, Serbian must be **measured**, not assumed (`supportedRecognitionLanguages` at runtime; diacritics accuracy on fixtures).
- Apple's Foundation Models (on-device ~3B) needs an Apple Intelligence-capable device **and a supported device language**. Forum reports say Polish, Czech, Hungarian, Romanian and others are unsupported and `SystemLanguageModel.isSupported` is false there; Slovak is very likely the same. It also excludes pre-iPhone-15-Pro hardware. Therefore it can only be a **bonus tier**, never the primary path. Check `SystemLanguageModel.supportedLanguages` at runtime.
- Hence: the primary LLM is a **bundled-on-demand open-weight model** running locally.

## Pipeline (each layer independently testable)
0. **Capture:** VisionKit document scanner / Photos / Files (images + PDF via PDFKit rendering). Perspective correction, contrast normalisation.
1. **Structure:** `RecognizeDocumentsRequest` → `RecognizedTable` (cells with text, row/col spans, bounding boxes, per-cell OCR confidence).
2. **Fallback structure:** `VNRecognizeTextRequest` + geometric clustering when no table found.
3. **Deterministic parser (TimetableCore):** detect header row/column (days in 12 languages incl. abbreviations; period numbers; time ranges in formats like 08:00–08:45, 8.00-8.45, "1. hod"); infer bell schedule; split cell text into subject / room / teacher / building / type using patterns and the user's enabled fields; merged-cell and multi-line handling; produce candidates + **per-cell confidence with reasons**.
4. **LLM normaliser (only for cells below threshold, and for bell-schedule/abbreviation inference):** input = OCR cell text + position JSON (not the image); output = JSON constrained by grammar/schema. Hard rules: never invent lessons absent from the OCR; copy text verbatim for subject names; return `unknown` + alternatives instead of guessing; temperature 0.
5. **Reconciliation:** merge deterministic + LLM results, recompute confidence, build the **review model**.
6. **Review UI:** original image beside parsed grid; low-confidence cells highlighted; targeted questions ("Is 'Bio' Biology? Room 204 or 2O4?"); inline editing; bulk "apply to all identical cells"; explicit Approve → save.

## LLM tiers
- **Tier A (bonus):** Apple Foundation Models with guided generation when available, language supported, and device eligible. The WWDC26 notes mention on-device image understanding arriving in a newer OS release; check actual availability on the target OS and report — do not depend on it.
- **Tier B (primary, universal):** open-weight small model, 4-bit quantised, run via **llama.cpp** (GBNF grammar-constrained JSON, GGUF) or **MLX Swift** (Apple, Metal) — pick by spike (build feasibility under xtool and CI, memory, speed, structured output). Candidates to evaluate with data: Qwen3 1.7B/4B (Apache-2.0, broad multilingual coverage), Phi-4-mini (MIT), Gemma 3 1B/4B (custom licence — read terms), Llama 3.2 3B (community licence). Verify each licence at selection time. Selection criteria: JSON-validity rate under constraints, per-field accuracy across the 12 languages, peak memory (budget ≲ 2 GB; consider the increased-memory-limit entitlement), latency (≲ 20 s per timetable), model size (≲ 2.5 GB).
- **Tier C (optional, OFF by default, decide at gate):** Cloudflare Workers AI free daily allocation as a server fallback for very weak devices. Only with consent, App Attest protection, and size/rate limits; images may contain personal data — document GDPR implications. If doubts remain, skip it.
- Tier D: deterministic-only result with more manual review prompts (always available).

## Model delivery
Not in the app binary. User-initiated, Wi-Fi-preferred download with progress, resume, SHA-256 verification, delete-from-settings, and clear size disclosure. Hosting candidates: Cloudflare R2 (as far as I know free egress and a free storage tier — verify) or Apple-hosted Background Assets (included with the Developer Program — verify limits/terms). Choose with cost evidence; record in docs/ENVIRONMENT.md.

## Evaluation harness (build first)
`Fixtures/import/`: ≥ 30 timetables (synthetic + real-style photos: skewed, low light, handwriting-lite, screenshots, PDFs, merged cells, uni 90-min blocks, A/B weeks), across all 12 languages, each with expected JSON. Metrics: structure accuracy, per-field exact/fuzzy match, confidence calibration (are low-confidence cells really the wrong ones?), time per import, memory peak. The report goes in `docs/localization/` or `docs/eval/` and informs the Phase 9 gate. Be honest about failures.

## Tests
Parser + reconciliation on Linux from `RecognizedTable` JSON fixtures; Vision adapter and model runner verified on the physical iPhone with a debug screen and a manual checklist.
