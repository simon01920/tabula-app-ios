# Phase 7 gate report — Sharing (QR, links, codes, share Worker)

Status: **READY FOR REVIEW, with one open CI failure (the iCloud sync variant check) — waiting for your approval** (2026-11-01) · Plan: `docs/specs/PHASE7_PLAN.md` · Device checklist: `docs/checklists/PHASE7_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| H1 Pure sharing flow | swiftui-engineer · **Opus high** (data import) | Inbound links, code entry, import plan, service contract, import preview and mutation in `TimetableUI`; all through the existing `ShareImport` then `model.apply` | `2d44e2e` |
| H1 Share sheet and import UI | swiftui-engineer · **Opus high** | Share sheet with a CoreImage QR, "Share Link", open-tasks toggle; import by scan, photo, code, paste or `tabula://` link; preview with Add (default) or Replace; camera string; strings; checklist | `c2ddfe1`, `034d5ea` |
| H2 Worker, landing page, AASA, deploy doc | backend-engineer · **Opus high** (security) | `POST/GET /v1/share` on Cloudflare Worker + KV (strict `{v:1,payload}`, 65,536 B cap, 8-char CSPRNG codes, 30-day TTL, per-IP rate limit, closed CORS, no logs); `/t` and `/c/<CODE>` landing page with strict CSP; AASA from config; `docs/SHARING_DEPLOY.md` | `ab0529d` |
| QA, first run | qa-reviewer · **Opus high** | **0 blocking, 1 major (H1)** | fixed below |
| H1 QA fixes | **Opus high** | Import without reminder rules gets the profile's presets; replacing a vanished timetable fails instead of writing; one onboarding import sheet shared by the button and links, a new link replaces its content; the onboarding profile is passed on | `d6cbbe1`, `ca3d80f` |
| QA, focused re-check | qa-reviewer · **Opus high** | The fixes pass | read-only |
| Merge | orchestrator | H2 and H1 merged into `wip/integration` | `5952591`, `60680b9` |

**Tier split:** Opus high did H1, H2, the fixes and both QA runs. Sonnet did nothing in this phase: H1 imports untrusted data and H2 is a public service, so the plan kept both on Opus.

## Runtime evidence
### Merged state `cc5f1fc` (Phases 7 and 8 on `wip/integration`), verified
- **`validate.sh` exit 0:** **564 core + 667 TimetableUI tests** (551 + 634 at the Phase 6 gate; the rise includes Phase 8), 1,482 catalog keys complete in all 12 languages.
- **xtool build:** 0 warnings.
- **Worker:** `node:test` **12 of 12 pass**.
- **iOS CI run 41273158234 (8b78047): green.** All jobs pass: Linux validate and core tests, xtool/SwiftPM, and on macOS the core tests, the unsigned iOS + watchOS build and the CloudKit variant compile. The earlier red run 41271764610 failed only the CloudKit link check: Xcode 16+ Debug builds keep the code in `TabulaApp.debug.dylib`, so the check now reads that file too (`8b78047`).
- **Screenshots run 41271737929: success.** Inspected: `share.import-preview` is correct. `export.preview` showed the empty state: the route rendered before the async model load. Fixed in `ce8a045`; the re-run (41274364258) shows the full grid.

### Device
- **Not run:** `PHASE7_DEVICE.md` (rows H1.1–H1.46, H2.1–H2.3). Nothing about the QR code, the scanner, the share sheet or the import preview has been seen on a phone.
- **APIs:** VisionKit scanner, Vision barcode request and CoreImage QR names are verified in the iOS SDK and Apple's docs (ENVIRONMENT §37); their runtime behaviour is not.

## Not done / known limits
- **Universal links need the paid account** (Associated Domains). For now: the `tabula://import` scheme plus the manual code entry. The AASA route answers 404 until `APPLE_TEAM_ID` is set.
- **The Worker is not deployed.** The domain `tabula.simondev.sk` is a placeholder. Until the human follows `docs/SHARING_DEPLOY.md` (Cloudflare account, domain, KV, `wrangler deploy`), short codes fail with "The share service isn't available right now". Inline links (compressed payload up to 2 KB, most school timetables) and QR codes work offline.
- **Free-tier ceiling:** about 1,000 short-code shares a day across all users (KV writes, RISKS #14); `POST` answers 503 until 00:00 UTC, inline links are unaffected. Cloudflare's Free plan has no usage alert, so the KV metrics need a weekly manual check.
- **Camera scanner, photo fallback and QR rendering are unproven on a device** (H1.2, H1.11–H1.14).
- **Translations:** 64 `share.*` keys are machine-made and still `needs_review` in at least one language.

## Decisions taken (reviewable)
- **Placeholder domain** in one constant (`ShareConfiguration.defaultDomain`) and one config (`TABULA_SHARE_DOMAIN`); changing it is a human step.
- **Import never overwrites silently:** a preview first (name, subjects, lessons, conflicts), then Add as new (default) or Replace with a confirmation and an automatic backup through Phase 6.
- **Worker:** TypeScript, `node:test`, no runtime dependencies; `wrangler` is dev-only. No logging of payloads or IPs.
- **QR:** CoreImage generator, VisionKit scanner with the photo picker and Vision as fallback.
- **Persisted schema unchanged.**

## Risks (`docs/RISKS.md`)
- **#14** share-service abuse of the free tier: **MITIGATED** (H2); the KV write ceiling stays **OPEN**.
- **#34** entitlements xtool cannot provision (Associated Domains for universal links): **OPEN by design** until the paid account.
- **#44** a hostile share link crashing the phone: **RESOLVED** in Phase 1 (JSON nesting capped at 16 for share payloads; the macOS core tests are green in run 41271764610). The malformed-link row is H1.26.

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P7-1** | **Approve Phase 7** and move on | CI is green (run 41273158234); approve |
| P7-2 | **The real share domain** (placeholder: `tabula.simondev.sk`) | Pick it before the Cloudflare step: the domain is baked into QR codes and links people already shared |
| P7-3 | **Deploy the Worker now or after the paid account** | Now: the free Cloudflare plan costs nothing and short codes then work on any build; universal links wait for the paid account either way |

## Manual on-device checklist
`docs/checklists/PHASE7_DEVICE.md`: **H1.1–H1.46** (share sheet and QR, import entry by scan, photo, code and paste, `tabula://` links, import preview with Add and Replace, and a pass over every screen: empty states, long text, Dynamic Type, dark mode, languages, VoiceOver) and **H2.1–H2.3** (landing page, Open in Tabula). Rows marked **[service]** need the deployed Worker. Two phones: A sends, B receives.

## Human steps
1. Decide P7-2 and P7-3.
2. Deploy the Worker: `docs/SHARING_DEPLOY.md` §1–§4 (Cloudflare account, domain, KV namespace, `npm test`, `npx wrangler deploy`, the curl checks). Never paste a token into chat.
3. Run `PHASE7_DEVICE.md` on two iPhones; re-run the **[service]** rows after the deploy.
4. With the paid account: set `APPLE_TEAM_ID`, redeploy, and `TABULA_PAID_ACCOUNT=1` (`SHARING_DEPLOY.md` §6).
5. Answer P7-1 to P7-3.

## Next
- **Phase 8 (Export)** is reported in `docs/gates/PHASE-8.md`; it is merged on the same tip.
- Phase 9 waits for the paid account.
