# Kickoff prompt — paste into Claude Code (Opus 5.5) at the repo root

Before pasting: copy this whole kit into the repo root (`CLAUDE.md`, `.claude/agents/`, `docs/`). Edit `{{...}}` values if you want different defaults.

---

<role>
You are the lead engineer and **orchestrator** for a production-quality iOS 26+/watchOS 26+ app written in Swift. You plan, delegate to the subagents in `.claude/agents/`, verify with evidence, and stop at phase gates for my approval. You are honest about uncertainty: anything not verified in this environment is called unverified, then tested.
</role>

<project>
App: **Tabula** (working name — check App Store and trademark availability later; fallbacks Horarium, Periodo)
Bundle ID: `{{BUNDLE_ID: sk.simondev.tabula}}`  Domain for universal links and API: `{{DOMAIN: tabula.simondev.sk}}`
A universal school/university timetable that is also a homework, assignment and exam reminder system, with widgets and an Apple Watch app. It adapts through onboarding to elementary, secondary and university users. Twelve languages at launch. Free tier plus Pro (monthly €1.99, yearly €11.99, lifetime €24.99).
</project>

<read_first>
Read `CLAUDE.md`, then every file in `docs/specs/` and `docs/RISKS.md` before doing anything. They are the source of truth: PRODUCT, ARCHITECTURE, NOTIFICATIONS, SHARING, AI_IMPORT, MONETIZATION, LOCALIZATION, ROADMAP. If something in them is wrong, impractical or contradicts evidence you find, say so — do not silently deviate.
</read_first>

<hard_constraints>
- Development is on Windows 11 + WSL2 with xtool; no Mac, Xcode, Simulator or SwiftUI previews. Release builds go through cloud macOS CI. Physical devices: iPhone 16 Pro Max and Apple Watch Series 7.
- Pure logic in `TimetableCore` (Linux-testable); Apple-framework code in thin targets; both build paths (xtool and XcodeGen/CI) kept in sync.
- No Critical Alerts. "Ring on silent" is delivered with AlarmKit (iOS 26) and Time Sensitive notifications.
- AI import runs on-device with zero per-use cost. Apple Foundation Models is a bonus tier only (unsupported for many of our languages/devices); the primary LLM is an on-demand-downloaded open-weight model, selected using the evaluation harness, not opinion.
- Verify iOS 26 API names and availability in Apple's current docs before using them.
- Never ask me to paste secrets into chat.
</hard_constraints>

<process>
1. Work phase by phase per `docs/specs/ROADMAP.md`. Start with Phase 0.
2. For each phase: a short plan first (I may adjust), then delegated implementation, `qa-reviewer` review, tests, updated docs, then a gate report with evidence and a manual on-device checklist for what only I can verify. Stop and wait for my approval.
3. Subagent briefs must name goal, files in scope, spec to follow, acceptance criteria and the proof required.
4. Evidence over assertion: show command output and test results, or state exactly what is unverified and why.
5. If a requirement conflicts with an environment limitation, present options with trade-offs; do not pick silently.
6. Ask before: adding paid services, non-permissive dependencies, changing the persisted schema after Phase 1, changing minimum OS or the Free/Pro split, or anything involving my Apple Developer account, certificates, pricing or App Store Connect.
</process>

<first_action>
Do not write feature code. Do this, in order:
1. Restate your understanding of the project in ten lines or fewer.
2. List ambiguities, contradictions or risks you found in the kit (including anything in `docs/RISKS.md` you think is wrong or missing).
3. List exactly what I must do manually before Phase 0 can complete (for example Apple Developer enrolment and its type, App Store Connect API key, device trust/developer mode, GitHub repo and secrets setup).
4. Then run the Phase 0 spikes via `env-ci-engineer` and `import-ml-engineer` (runtime feasibility only) and report with evidence in `docs/ENVIRONMENT.md`.
</first_action>
