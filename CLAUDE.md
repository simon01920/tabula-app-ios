# CLAUDE.md — Tabula (working name)

iOS 26+ / watchOS 26+ school-and-university timetable app with homework, exam and reminder management. Swift only. Developed on **Windows 11 + WSL2** (no Mac, no Simulator, no Xcode locally). Physical test devices: iPhone 16 Pro Max, Apple Watch Series 7.

Specs live in `docs/specs/`. Read the relevant spec before touching a feature. If a spec and the code disagree, stop and tell the human — do not silently pick one.

## Operating mode: orchestrator + subagents
The main session is the **orchestrator**. It plans, delegates, reviews, integrates, and talks to the human. It does not write large amounts of feature code itself.
- Delegate to the subagents in `.claude/agents/` with a narrow brief: goal, files in scope, spec to follow, acceptance criteria, how to prove it (command + expected result).
- Every subagent report must contain **evidence** (test output, build log, diff summary). "Should work" is not evidence.
- Before merging a subagent's work, run `qa-reviewer` on it.
- Work in **phases** (`docs/specs/ROADMAP.md`). At the end of each phase write a gate report (done / not done / risks / decisions needed / manual on-device checklist) and **stop for human approval**.
- Keep `docs/RISKS.md` and `docs/ENVIRONMENT.md` current. Log every verified fact and every failed assumption.

### Model routing (human decision, 2026-10-09)
The orchestrator stays on **Opus 5.5**. For each delegated task it picks the agent tier:
- **Opus 5.5, high effort** (`<role>`, e.g. `swiftui-engineer`): architecture and foundations, complex or risky logic (time, sync, persistence, layout engines), anything touching the frozen schema, security- or data-loss-sensitive work, and **all `qa-reviewer` runs**.
- **Sonnet 5.5, medium effort** (`<role>-sonnet`, e.g. `swiftui-engineer-sonnet`): well-specified, lower-risk work such as forms and settings screens built on an existing foundation, translations, docs, CI and script wiring, checklists, and mechanical refactors.

When in doubt, use Opus. Each gate report lists which tier did each task, so the split can be reviewed.

### Save the limit (human decision, 2026-10-26)
- Hand quick, mechanical work to the `haiku-helper` subagent (user-level agent, Claude Haiku). That means finding files, grep searches, reading logs, listing folders, renames, one-line edits, and running a command to report its output.
- Batch several small lookups into one `haiku-helper` call.
- Keep planning, debugging, architecture and multi-file changes for yourself.

## Environment rules (hard)
1. Pure logic lives in `TimetableCore` (no Apple-only imports) so `swift test` runs on WSL/Linux.
2. Apple-framework code lives in thin targets: `TimetableUI`, `App`, `WidgetExtension`, `WatchApp`.
3. Two build paths must stay in sync: SwiftPM + `xtool.yml` (local) and XcodeGen `project.yml` (cloud macOS CI for release/TestFlight/watchOS if xtool cannot).
4. UI cannot be previewed or simulated. Never claim UI works because it compiles. Ship a manual on-device checklist per UI phase and debug screens where useful.
5. Do not assume macros (`@Observable`, SwiftData `@Model`, App Intents) compile under xtool until Phase 0 proves it. Default persistence: versioned Codable store in the App Group behind a `Repository` protocol.
6. Verify iOS 26 API names/availability in Apple's current docs (fetch them) before use. Do not rely on memory.
7. Never ask the human to paste secrets into chat. Secrets go in GitHub Actions secrets / local env files that are git-ignored.

## Code conventions
- Swift 6 language mode, strict concurrency, unless Phase 0 shows a blocker (document it).
- Small types, protocol seams at module boundaries, no singletons beyond a dependency container.
- All user-facing strings in String Catalogs; never concatenate translated fragments; plural rules via catalog variations.
- Dates: explicit `Calendar`/`TimeZone` everywhere; test DST, week-start differences, midnight rollover, time-zone changes.
- Every new dependency needs: one-line justification, licence check (permissive only), maintenance check. Prefer 50 lines of own code over a dependency.
- Accessibility from the start: Dynamic Type, VoiceOver labels, contrast-safe text on user-chosen colours, Reduce Motion.

## Commands (verified in Phase 0; run inside WSL `Ubuntu`, repo at `/mnt/c/Users/simon/Documents/Claude Code/school_timetable`)
- Validation (run before every commit): `bash scripts/validate.sh`
- Core tests: `bash scripts/core-test.sh` (= `swift test --package-path Packages/TimetableCore` with an ext4 scratch path)
- Local iOS build: `bash scripts/xtool-dev.sh build` · macro variant: `--macro-probes` · build+install+launch on a device: `bash scripts/xtool-dev.sh`
- Isolated probes: `bash scripts/probe-build.sh <MacroProbeSwiftData|XCStringsSwiftPM>`
- Xcode project (CI generates it): `TABULA_DEVELOPMENT_TEAM= xcodegen generate --spec project.yml`
- From Windows Git Bash (use `--exec`: with `--` the WSL login shell expands `$VARS`/`$?` first, so exit codes read as 0): `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu --exec bash -lc 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && bash scripts/validate.sh'`
- CI: `.github/workflows/ios.yml` (TestFlight: Actions → iOS CI → Run workflow; needs the paid account, deferred)
- Real iPhone (usbipd into WSL, xtool sign-in, install, first checks): `docs/DEVICE_SETUP.md`; preflight (read-only): `bash scripts/device-doctor.sh`
- Facts, failures and human steps: `docs/ENVIRONMENT.md`; risks: `docs/RISKS.md`; gate reports: `docs/gates/`

## Ask the human before
Adding paid services or dependencies with non-permissive licences; changing the persisted schema after Phase 1; changing minimum OS; changing the Free/Pro split; anything touching Apple Developer account, certificates, App Store Connect, or pricing.

## Definition of done (any task)
Builds on both paths · tests pass on WSL · localised strings added · accessibility checked · docs/specs updated · evidence attached · on-device checklist updated if UI changed.
