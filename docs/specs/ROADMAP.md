# ROADMAP — phases and gates
Stop at every gate. Each gate report: done / not done / evidence / risks / decisions needed / on-device checklist for the human.

**Phase 0 — Environment & risk spikes (before ANY feature code).**
Verify with evidence: WSL Swift + `xtool setup` + hello-world on iPhone; widget extension; macros (`@Observable`, SwiftData, App Intents) under xtool; watchOS feasibility; GitHub Actions macOS build via XcodeGen → archive → TestFlight with App Store Connect API key; capability provisioning (App Groups, CloudKit, Time Sensitive, AlarmKit, StoreKit); on-device debug screen running `RecognizeDocumentsRequest` and listing supported OCR languages and `SystemLanguageModel` availability/languages; AlarmKit smoke test (schedule an alarm, test with silent switch on); local-LLM runtime feasibility (llama.cpp vs MLX Swift) building under both paths. Deliver `docs/ENVIRONMENT.md`, `docs/RISKS.md`, and the list of manual human steps. **Blocker check:** paid Apple Developer account must exist before capability tests.

**Phase 1 — TimetableCore.** Models with sync metadata, rotation/override resolver, grid, conflicts, onboarding presets, reminder planner, share codec, `Entitlements` protocol; exhaustive Linux tests.

**Phase 2 — App shell & onboarding.** Onboarding flow, editors, subjects/colours, field toggles, all views, themes, settings, String Catalog setup with all 12 languages scaffolded.

**Phase 3 — Tasks, exams, notifications.** Attachments, subtasks, priorities, exams tab, rule model, planner, Time Sensitive, AlarmKit alarms, health check screen.

**Phase 4 — Widgets & Live Activity.**

**Phase 5 — Watch app & complication.**

**Phase 6 — Persistence hardening & iCloud sync (default on).** Backup/restore, migrations, CKSyncEngine, conflict rules, multi-device test matrix.

**Phase 7 — Sharing.** Codec in UI, QR scan/generate, universal links, Worker deploy (human steps), landing page.

**Phase 8 — Export.** Image/PDF/CSV/XLSX/ICS with view and type choice.

**Phase 9 — AI import.** Eval harness → model selection → pipeline → review UI → model download/hosting. Gate includes the accuracy report.

**Phase 10 — Monetisation.** `Entitlements`, StoreKit 2, paywall, gating, TestFlight sandbox plan.

**Phase 11 — Polish & release.** Accessibility audit, localisation review log, empty/error states, performance pass, privacy manifest, App Store assets/metadata drafts, final CI release run, TestFlight beta checklist.

Localisation and accessibility are continuous: strings go into catalogs as they are written, not at the end.
