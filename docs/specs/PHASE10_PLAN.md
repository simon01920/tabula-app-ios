# Phase 10 plan — Polish, bug fixes & performance

Human request (2026-11-05): "finish the app with final polish and bug fixes and speed improvements, making the app good performing on any device." Monetisation moved to Phase 11, release to Phase 12 (`ROADMAP.md`).

## Target devices
- **Slowest iPhone on iOS 26:** A13 (iPhone 11, SE 2nd gen), 3–4 GB RAM. Every interaction stays fluid there.
- **Smallest screens:** 375 × 667 pt (SE, no Dynamic Island) and 375 × 812 pt (13 mini).
- **Largest screen:** 440 pt Pro Max.
- **Apple Watch:** Series 6/7-class.
- **Widget extensions:** about 30 MB memory.

## Inputs
Four read-only Opus audits (2026-11-05):
- **App/UI performance:** P1–P18.
- **Core performance:** C1–C10, K1.
- **Bug hunt:** B1–B16 and the known-open classification.
- **Polish / device range:** U1–U19.

Finding IDs below refer to those reports. Their essentials are copied into each work package.

## Environment constraint (new)
This phase runs in a cloud container with **no Swift toolchain** (download.swift.org is blocked by the network policy), so agents cannot build or test locally. Evidence comes from GitHub Actions on the PR:
- `ios.yml`: Linux `swift test` + `validate.sh`, and the macOS XcodeGen build.
- `ui-screenshots.yml`: dispatched on the branch.

Agents write code and tests by careful reading and must say "not compiled" in their report.

## Work packages
| WP | Agent · tier | Scope |
|---|---|---|
| WP1 App state & change fan-out | swiftui-engineer · **Opus** | P2 · P4 · P5 · P6 · P7 · P11 · P14 · P16 · P17 · B12 |
| WP2 Widget / Live Activity / watch pipeline | widgets-watch-engineer · **Opus** | P3/C2/P12 · C3 · P15 · P18 (snapshot part) |
| WP3 Export, share & import heavy operations | swiftui-engineer · **Opus** | P1/B13 · B1 (decision P8-3, default: fit to page) · B2 · B14 · C5 · P8/U12 · B9 · B4 · P9 · P10 · U11 · U9 |
| WP4 Core performance & correctness | core-domain-engineer · **Opus** | C4 · C6 · C7 · C8 · K1 · XLSX styles part · P13 · `DayResolution.reasons` dictionary |
| WP5 Sync, backup & attachments | sync-storage-engineer · **Opus** | C1 · C10 · B3 · B7 · B11 · B16 · U14 |
| WP6 UI polish & small bugs | swiftui-engineer-sonnet · **Sonnet** | U2 (text only) · U7 · U8 · U10 · U13 · U15 · U16 · U19 · B5 · B6 · B10 · B15 |
| WP7 Privacy manifest & screenshot coverage | env-ci-engineer-sonnet · **Sonnet** | U1 · U5 · U6 · U17 · `.invalid` URL warning (U3) |

Translations of the new keys go in each WP (catalog rule). A final localisation-engineer-sonnet pass runs only if gaps remain.

## Rules for every WP
- **Persisted schema: frozen.** No change to `TabulaDatabase` or entity Codable shapes. Ask the human first.
- **No new dependency. No change to the minimum OS or to Free/Pro.**
- **Behaviour stays identical unless the finding is a bug.** Performance changes need an equivalence test (old vs new output) where the code is Linux-testable.
- **Main-actor work moved off main** must move pure value-type computation only. UI state is still written on the main actor.
- **Debounce and coalescing changes keep every trigger:** launch, data change, foreground, time/zone/locale change, BG refresh. Write down which trigger maps to which work.
- **Files:** each WP edits only its own files. Shared files (`AppServices.swift`, `AppModel.swift`) get the smallest possible edits, and the report lists them.

## Decisions for the human (do not block the work)
| # | Decision | Default used in Phase 10 |
|---|---|---|
| P10-1 | **Undo of a completed repeating task (B8).** The next occurrence it created stays. Should it be removed? DOMAIN_MODEL §3.9's tombstone rule would block it forever. | Keep the current behaviour; document it |
| P10-2 | **App Privacy label (U2).** Share codes store a timetable on the worker for 30 days. Declare "User Content — not linked — App Functionality"? | The in-app privacy text is corrected to say so; the label is decided at Phase 12 |
| P10-3 | **Real domain (U3) for share links, privacy policy and support email.** All are placeholders. | validate warns (does not fail) while `.invalid` / `{{DOMAIN}}` remain; must be fixed before Phase 12 |
| P10-4 | **Week-view export taller than the page (P8-3, B1).** | Fit the day to the page by computing the hour height (no scaling, no extra pages) |
| P10-5 | **Native translation review (U4).** Every non-English string is `needs_review`. | Not in Phase 10; `REVIEW.md` counts updated |

## Gate evidence
- CI green on the PR: Linux core + UI tests, `validate.sh`, and the macOS build with 0 new warnings.
- Screenshots on the smallest available simulator (SE-class) plus the Pro Max for the changed screens.
- QA review of each WP and a final delta QA.
- `docs/checklists/PHASE10_DEVICE.md`, covering what only a device can show: launch time, scroll and hitches in Instruments on an A13 if available, the PNG/PDF export, landscape, Bold Text and Increase Contrast.
