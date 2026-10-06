# Phase 0 gate report — Environment & risk spikes

Date: 2026-10-04 · Orchestrator: Claude Code (Opus 5.5) · Status: **STOPPED AT GATE: awaiting human approval** (Phase 0 partially complete; remainder blocked on §3)

**Final evidence (orchestrator re-run after all fixes):** `bash scripts/validate.sh` → `EXIT=0`, 75 OK, 0 FAIL, 0 WARN, `ALL CHECKS PASSED`; core tests `✔ Test run with 9 tests in 2 suites passed`; macro scan clean (base app macro-free); no CRLF files. All Apple-platform Swift remains **UNCOMPILED** (no SDK yet). Nothing committed to git.

## Addendum: human response (2026-10-06) and what changed
- **D0 Phase 1 now:** yes ("go directly to phase 1 and finish it"). Plan: `docs/specs/PHASE1_PLAN.md`.
- **D1 Apple Developer Program:** **deferred** until the app has shape. Placeholders + a single switch are being prepared (`docs/PAID_ACCOUNT_SWITCHOVER.md`).
- **D2 GitHub:** repo `simon01920/tabula-app-ios` created, **private**, so macOS minutes are billed after the free allowance. Pushing needs one-time auth on this PC (`docs/GITHUB_SETUP.md`).
- **D3 xtool path:** not answered explicitly. The human supplied `Xcode_27.xip`, and the orchestrator proceeded on the xtool path. Recorded here so the decision stays visible.
- **H2/H3 SDK:** the `.xip` was copied to WSL `/root/` and `xtool sdk install` succeeded, with no Apple login needed for the SDK. The bundled Xcode is **27.0 (27A266a)**, matching OpenAppleMacros. *Correction:* the install log listed only iPhoneOS/iPhoneSimulator/macOS, but `WatchOS27.0.sdk` is also present, so watch sources are type-checked locally (`scripts/watch-typecheck.sh`).
- **H4/H5 device:** not possible for now (off-site). Interim UI verification goes through **iOS Simulator screenshots on GitHub Actions** (Windows can't run the iOS Simulator).
- Phase 0 work committed locally (`b2c0458`); CLAUDE.md `Commands` filled in.
- **First CI run** ([37449454629](https://github.com/simon01920/tabula-app-ios/actions/runs/37449454629), workflow_dispatch):
  - ✓ Linux core tests.
  - ✓ **XcodeGen path**: unsigned iOS app + widget + embedded watch app, with an `arm64_32` slice for the Series 7, en/sk `.strings` and `.stringsdict`, and privacy manifests.
  - ✗ **xtool path**: `xtool dev build` hung on macOS, probably an interactive prompt, until it was cancelled at ~40 min. Fix in progress (timeouts, non-interactive mode or SwiftPM fallback).
- Still open from §6: D4–D13. Their recommended options are used as defaults behind switches where code depends on them (D6 Time Sensitive ≤ 60 min, D7 alarms only from user rules).

## 1. Understanding of the project (≤ 10 lines)
1. **Tabula**: a local-first iOS 26+/watchOS 26+ SwiftUI app that unifies timetable, homework/assignments, exams and reminders, with widgets, Live Activity and an Apple Watch app.
2. Onboarding (elementary / secondary / university / other) pre-configures fields, rotation, time structure, views and reminders. Presets are data in `TimetableCore`, and everything stays editable.
3. Flexible timetables: multiple timetables, rotations (A/B, odd/even, N-week, semesters), bell schedules or free-form times, overrides, holidays, conflict warnings.
4. Reminders in three delivery tiers: Standard, Time Sensitive, and AlarmKit "loud alarm" (no Critical Alerts), planned inside the 64-pending-notification cap.
5. Sharing via QR, inline link or 8-char short code (Cloudflare Worker + KV); exports to image/PDF/CSV/XLSX/ICS; free on-device AI import from photo/PDF with a review UI.
6. iCloud sync on by default (CKSyncEngine, private DB), with a versioned Codable store in an App Group behind a `Repository` protocol.
7. 12 launch languages via String Catalogs. Accessibility is first-class.
8. Free + Pro (€1.99/mo, €11.99/yr, €24.99 lifetime) gated through an `Entitlements` protocol.
9. Built on Windows/WSL2 with xtool (SwiftPM) and released through XcodeGen + macOS CI. Pure logic in Linux-testable `TimetableCore`.
10. Delivery is phase-gated (0–11). Each gate requires evidence and an on-device checklist, because nothing UI-related can be previewed here.

## 2. Ambiguities, contradictions and risks found in the kit
_(see also `docs/RISKS.md` rows 16–27, added in this phase)_

**Platform/version**
- A. **iOS 26 minimum vs the current toolchain.** Today the shipping SDK is iOS 27 / Xcode 27, and xtool 1.20.x expects Xcode 27. The kit is silent on this. Proposal: deployment target iOS 26.0, built with the iOS 27 SDK, and every iOS 27 API `#available`-gated. *(Changing min OS is your decision; I'm not proposing a change.)*
- B. **watchOS 26 is now a hard ceiling for testing.** watchOS 27 (14 Sep 2026) dropped the Series 7, so your test Watch stays on 26.x. The watchOS deployment target must remain 26.0.
- C. The kit says "verify **iOS 26** API names". In practice we must verify against the iOS 27 SDK docs while targeting 26, so the availability annotations are what matter.

**Build paths**
- D. "CI builds both paths": the xtool path cannot run on a Linux CI runner without putting Xcode.xip there (Apple ID download, licence). Proposal: CI exercises the SwiftPM/xtool path on the **macOS** runner.
- E. `TimetableUI` is meant to be shared iOS + watchOS, but watchOS builds only in CI, so watchOS-specific breakage in `TimetableUI` surfaces late. Mitigation: a CI watchOS build on every push.
- F. Several Apple build steps may not exist under xtool on Linux: String Catalog compilation, asset catalogs, App Intents metadata. That affects localisation testing, configurable widgets, Siri/Shortcuts and the Focus filter in local builds. *(Probes written; device verification pending.)*
- G. xtool rewrites the bundle ID for device signing, so local builds and CI/TestFlight builds are different app identities (App Group / iCloud IDs, separate data).

**Product/monetisation (your decisions, flagged not changed)**
- H. **Loud alarms (your original "ring on silent" request) and the Watch app are both Pro.** Confirm this is intended, since they are headline features.
- I. **"Statistics"** is listed as Pro in PRODUCT.md, but no spec exists. It also appears in the reference screenshots.
- J. The reference screenshots include features not in the specs: live "Synchronization" of shared timetables, lock-screen wallpaper export, timetable generation. Not adopted; see `docs/design/REFERENCE_ANALYSIS.md` §4.
- K. **Children as users** (elementary): age rating, Kids Category (recommend not opting in), parental gate for the paywall, GDPR-K. Needs a decision before Phase 10.
- L. **Serbian is not an App Store Connect metadata language.** In-app sr-Cyrl/sr-Latn is fine; the store listing needs a fallback language. Chinese Traditional is still open.
- M. AI_IMPORT says the eval report goes in "docs/localization/ or docs/eval/". Proposal: `docs/eval/`.

**Process**
- N. The project subagents in `.claude/agents/` were not loaded by this session because they were copied in mid-session. For Phase 0 they ran as general-purpose agents with the role definition pasted verbatim. **Restart Claude Code in the repo** to load them natively.
- O. Phase 0 cannot fully complete without a paid Apple Developer account (RISKS #3). TestFlight upload, CloudKit, IAP and xtool API-key login all depend on it.

## 3. Manual steps only you can do (in this order)
Full copy-pasteable commands: `docs/ENVIRONMENT.md` §14. Nothing secret ever goes into chat.

| Step | What | Why it blocks | Effort |
|---|---|---|---|
| **H1** | Enrol in the **Apple Developer Program** (individual or organisation, see D1) | TestFlight, CloudKit, Time Sensitive, IAP, App Groups via xtool, xtool API-key login | 15 min + Apple review (individual often same day; org days–weeks) |
| **H2** | Download exactly **Xcode 27.0 (build 27A266a)** `.xip` from developer.apple.com/download/all (Apple ID; read D3 first), copy into WSL `~/`. *Exactly this build:* xtool's open-source SwiftUI macros track it, and in this SDK even `@State` is a macro | xtool needs it to build the iOS SDK; no iOS code can compile without it | download + 7 GB disk |
| **H3** | In your own WSL terminal: `xtool setup` (API key mode after H1+H7, or password mode) and point it at the `.xip` | interactive credentials, which I must never handle | 10–20 min |
| **H4** | Windows: install **usbipd-win**, bind and attach the iPhone to WSL, tap **Trust** | device install | 10 min |
| **H5** | `bash scripts/xtool-dev.sh`, enable **Developer Mode** on the iPhone, run the on-device checklist (§7) | the actual Phase 0 device verification | 30–60 min |
| **H6** | Create the **GitHub repo** (visibility = D2) and give me a way to push (install `gh` + `gh auth login`, or push yourself) | CI runs: watchOS build, both-path build check | 5 min |
| **H7** | App Store Connect API keys: **"CI"** (Admin) and **"xtool"** (App Manager) | CI signing/upload; xtool API-key login | 10 min |
| **H8** | GitHub secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` + variable `APPLE_TEAM_ID` | TestFlight job | 5 min |
| **H9** | App Store Connect **app record** for `sk.simondev.tabula`, then run the workflow manually | first TestFlight build → Watch install path | 15 min |
| **R** | **Restart Claude Code** in this folder | loads `.claude/agents/*` as native subagents (N) | 1 min |

## 4. Spike results (summary; evidence in the linked docs)

| Spike | Verdict | Key evidence | Doc |
|---|---|---|---|
| WSL toolchain | **VERIFIED** | Swift 6.4 on Ubuntu 26.04; `swift test` TimetableCore 6/6; repo path with a space works | ENVIRONMENT §1 |
| xtool install | **VERIFIED** | 1.20.1, SHA-256 matches release digest, runs under FUSE; `sdk status: Not installed`, `auth status: Logged out` | §2 |
| Hello-world + widget on iPhone | **BLOCKED** (H1–H5) | probe app + widget written (UNCOMPILED) | §2, §5 |
| Both build paths, same sources | **VERIFIED (static)** / compile BLOCKED | `scripts/validate.sh` → ALL CHECKS PASSED (25 checks), independently re-run by the orchestrator; XcodeGen 2.46.0 built on Linux, `xcodegen generate` OK, watch + widget embedded | §3 |
| Macros under xtool | **PARTIAL (source)** | SwiftUI + FoundationModels + Previews macro plugins shipped by xtool; `@Observable` from OSS toolchain; **SwiftData not provided** | §4 |
| watchOS under xtool | **RESEARCH-ONLY (expected fail)** | xtool 1.20.1 source: no watchOS triples, iPhoneOS-only packer → plan Watch as CI-only (~30–60 min per change) | §5 |
| String Catalogs under xtool | **FAILED on Linux host (executed)** / iOS cross-build expected to fail → **mitigated** | SwiftPM/SwiftBuild copy the catalog raw; own `l10n-compile.py` → `.lproj` (verified for `.strings`; plurals = device check) | §6 |
| App Intents metadata under xtool | **RESEARCH-ONLY (expected fail)** | PR #217 closed unmerged; no metadata processor in xtool's toolset → intents likely absent from Shortcuts locally; device checklist item 8 decides | §4 |
| Bundle-ID/App Group rewrite | **VERIFIED (source)** | `group.XTL-<ID>.…`; resolver `AppGroup.identifier(forBundleIdentifier:)` + Linux tests | §2.1 |
| Capability provisioning | **RESEARCH-ONLY** | xtool handles App Groups (paid) etc.; **not** CloudKit / Time Sensitive / IAP / increased memory → CI/TestFlight only | §7 |
| GitHub Actions → TestFlight | **BLOCKED** (H1, H6–H9) | workflow with 4 jobs written, YAML-validated; runner label `xcode-27`; altool upload; Admin key likely needed | §8 |
| On-device OCR + Foundation Models probe | **BLOCKED** (H5) | probe written (UNCOMPILED); API names verified in docs; Apple Intelligence covers only en/de/fr/ja/zh of our 12 | §17 |
| AlarmKit smoke test | **BLOCKED** (H5) | probe + Live Activity written (UNCOMPILED, syntax-checked); no entitlement; **limit undocumented/dynamic** | §18 |
| Local LLM runtime | **llama.cpp VERIFIED on Linux**, iOS BLOCKED; **MLX not viable on xtool path** | SwiftPM from-source build 50 s; grammar-constrained JSON walk works; XCFramework resolves | §17, `spikes/LLM_RUNTIME.md` |

## 4b. Independent QA (qa-reviewer, read-only)
**Verdict: PASS WITH FIXES → fixes applied.** QA re-ran `validate.sh` and `core-test.sh`. It checked the xtool / xtool.app / XcodeGen SHA-256 digests against the GitHub API, read the llama.cpp spike logs, and syntax-checked all 14 Apple-platform files (`swiftc -parse -swift-version 6`). It cross-checked the `AppGroup` mapping against xtool's source and key API signatures against Apple's docs JSON.

| QA item | Fix | Status |
|---|---|---|
| Blocking: "App Intents verified" claim; FAILED labels used for source-only conclusions | RISKS/ENVIRONMENT/gate relabelled; new status **EXPECTED** (source, not executed) | done |
| Macro probes compiled into the base app (one failing macro would block all device checks) | All macros behind `#if TABULA_MACRO_PROBES` (env var at manifest time); base app macro-free; device step A (base) / step B (macro variant); CI builds the macro variant | done (plus `ImportProbes` `@State` removal, see below) |
| `@State` is itself a macro in the Xcode 27 SDK (found during the fix) | `ImportProbes` moved to `ObservableObject`/`@StateObject`; RISKS #2 updated (stakes raised) | see §5 evidence |
| CI: push could cancel a TestFlight upload; l10n assertion was a no-op | `cancel-in-progress` off for `workflow_dispatch`; hard-fail checks for en/sk `.strings` + `.stringsdict` in app and widget | done |
| Series 7 needs an `arm64_32` watch slice | `ONLY_ACTIVE_ARCH=NO` + `lipo … grep -qw arm64_32`; swift-build `watchOSDevice.xcspec`: arm64_32 built for deployment targets up to 27 | done (unverified until CI runs) |
| TestFlight readiness | `ITSAppUsesNonExemptEncryption=false`; `PrivacyInfo.xcprivacy` for app + widget (UserDefaults CA92.1, 1C8F.1) wired into both paths | done |
| Should-fix batch | step-scoped release secrets; `TimetableCore` enum → `TimetableCoreInfo` (module/type clash); more `AppGroup` tests; `l10n-compile.py` `%%`/empty-string handling + self-test; Slovak plural probe uses the sk bundle explicitly; deeper two-path config comparison in `validate.sh`, now also run in the CI Linux job | done |
| Before a public repo: `examples/` (third-party screenshots, one with a real person's name) and `tabula-kit.zip` | git-ignored by default (nothing was committed) | done; reversible |
| Debug probes ship in Release archives | documented; Phase 2 task: gate behind `#if DEBUG` or a hidden toggle | open (Phase 2) |

## 5. Done / not done
**Done:** kit installed in repo; git initialised (nothing committed); WSL toolchain; xtool pinned; two-path project skeleton + probe app (UNCOMPILED) + widget + watch shell; CI workflow; Linux validation suite; String Catalog fallback compiler; llama.cpp feasibility on Linux; research matrices with citations; `docs/ENVIRONMENT.md`, `docs/RISKS.md` (34 rows), `docs/spikes/{LLM_RUNTIME,ALARMKIT}.md`, `docs/design/REFERENCE_ANALYSIS.md`, this report.

**Not done (all blocked on §3):** any iOS/watchOS compilation; install on iPhone; widget/Live Activity on device; macro confirmation on device; App Group provisioning; CI run; TestFlight upload; OCR language list; Foundation Models availability on your device; AlarmKit silent-switch test; llama.cpp on iOS.

**Honest status:** Phase 0 is **partially complete**. Everything that can be proven without Apple's SDK, your device, your account or a GitHub repo has been proven. The rest is prepared and waiting on §3.

## 6. Decisions needed from you
| # | Decision | My recommendation |
|---|---|---|
| **D0** | Start **Phase 1 (TimetableCore, pure Linux)** while you work through H1–H9? It doesn't need the SDK or device. | **Yes**: the plan comes first for your approval, and Phase 0 device checks are finished in parallel. |
| D1 | Apple Developer enrolment: individual or organisation | Individual unless you need a company as seller (org needs D-U-N-S; apps can be transferred later) |
| D2 | GitHub repo visibility | Public if you're comfortable (free macOS CI); otherwise private with a budget cap |
| D3 | Accept the xtool path given Xcode SDK Agreement §2.7 (non-Apple hardware) | Your call (not legal advice). The alternative is CI-only builds: much slower iteration, fully on Apple hardware |
| D4 | Approve **llama.cpp** (MIT) as the future AI-import runtime dependency (pinned XCFramework + checksum) | Approve in principle; final model choice comes from the Phase 9 eval |
| D5 | Keep **iOS 26.0 / watchOS 26.0** minimum, built with the iOS 27 SDK | Yes (watchOS 26 is required for your Series 7) |
| D6 | Time Sensitive only for reminders ≤ 60 min before; longer offsets fall back to Standard (Apple HIG) | Yes |
| D7 | Loud alarms only at a user-chosen time, never auto-generated "exam tomorrow" alarms (App Review risk) | Yes; also reword the AlarmKit usage string |
| D8 | Confirm Pro contains loud alarms + Watch app; specify or drop "Statistics" | Your call; I'd consider loud alarms for 1 rule free as a taster |
| D9 | Accept `AppGroup.identifier(forBundleIdentifier:)` in TimetableCore (small pure helper beyond "placeholder") | Accept |
| D10 | Serbian store-listing fallback language; Chinese Traditional at launch? | Fallback English; Traditional later |
| D11 | Kids Category / age rating approach (elementary users) | Don't opt into Kids Category; decide parental gate by Phase 10 |
| D12 | Make the initial git commit of Phase 0 work. Which name/email for commits? | Yes, after the QA fixes |
| D13 | Reference-screenshot extras (live share sync, wallpaper export, statistics) | Defer all; wallpaper export is a cheap Phase 8 add-on |

## 7. On-device checklist (after H5)
1. `docs/ENVIRONMENT.md` §15: 12 items (build path, bundle ID prefix, App Group, widget, localisation incl. Slovak plurals, @Observable, @Entry, AppIntent in Shortcuts, @Generable, icon, SwiftData/xcstrings probes).
2. Import probes (`docs/spikes/LLM_RUNTIME.md` §7–8): supported OCR languages (flag sk/cs/pl/hu/ro/sr/uk/de/fr/ja/zh/en), table recognition on a photographed timetable, Foundation Models availability + supported languages.
3. AlarmKit/notification matrix (`docs/spikes/ALARMKIT.md`): 60 rows: silent on/off × Focus × Low Power × force-quit × reboot × time zone × DST × Watch; alarm-limit and 64-cap probes.

Record results directly in those files (Observed column), or tell me and I'll record them.

## Addendum 2 (2026-10-06): CI + simulator evidence
- **iOS CI [37491895908](https://github.com/simon01920/tabula-app-ios/actions/runs/37491895908):** all green.
  - Linux core tests + validation: 3m08s.
  - Change detection: 5s.
  - **XcodeGen path:** 1m52s.
  - **xtool path:** 1m10s; the hang is fixed.
  - TestFlight job correctly not started.
- **UI screenshots [37491895960](https://github.com/simon01920/tabula-app-ios/actions/runs/37491895960):** 9m27s; the app launches in the iOS 27 Simulator (iPhone Pro Max).
  - The orchestrator inspected the screenshots. The launch route resolves.
  - `@Entry` ✓ and `@Generable` schema ✓ at runtime.
  - String Catalog en + sk ✓; **Slovak plurals render correctly** ("1 hodina · 3 hodiny · 5 hodín").
  - Dark mode ✓.
  - Artifacts: `ui-screenshots-1` (light / dark / AX-XXXL text for each probe screen).
- Still device-only: AlarmKit through the silent switch, Time Sensitive delivery, OCR on real photos, widget on the Home Screen, Watch install.
