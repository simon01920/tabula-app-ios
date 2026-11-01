# Phase 6 gate report — Persistence hardening, backup and iCloud sync

Status: **READY FOR REVIEW, with one open CI failure — waiting for your approval** (2026-11-01) · Plan: `docs/specs/PHASE6_PLAN.md` · Device checklist: `docs/checklists/PHASE6_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| S1 Pure mapping, ledger, first sync | sync-storage-engineer · **Opus high** | One `CKRecord` per entity (type = entity type, name = entity id, `payload` = canonical JSON incl. meta and unknown keys). Tombstones are ordinary records, never a CKRecord delete. 900 KB size guard. Pending = payload hash differs from the server ledger (restart-safe, no outbox). First sync: Merge / Keep this device / Use iCloud. Tests drive a fake CloudKit zone with change tags and `serverRecordChanged` conflicts | `a97aac5` |
| S1 `CKSyncEngine` adapter | sync-storage-engineer · **Opus high** | Adapter behind `TABULA_CLOUDKIT` (private database, zone `Tabula`), Settings iCloud row, first-sync alert; incoming records go through `SyncMerge` and are saved before the engine state that acknowledges them | `b0bc93a` |
| S1 Wiring checks and docs | sync-storage-engineer · **Opus high** | `validate.sh` and CI check the xcconfig indirection, that CloudKit is imported only in whole-file `#if TABULA_CLOUDKIT` files, `remote-notification`, and the pbxproj conditions. ENVIRONMENT §36 (APIs checked in the iOS SDK and Apple's docs), RISKS #92–#96, checklist S1 | `e0fb159`, `d852f8f` |
| S1 QA → fixes | qa-reviewer · **Opus high** → Opus | Sends are acknowledged only after the store save; records from a newer app version (newer schema, unknown type) hold back the engine state and are not re-sent in a conflict loop; `userDeletedZone` is handled like a purge; RISKS #93, #97; tests for both orders | `8675cd0` |
| S2 Backup logic and stranded data | sync-storage-engineer · **Opus high** (data-loss risk) | `DatabaseMutation.restore`, `BackupImport` (plain-word problems), `BackupFolder` (never overwrites), `StrandedStoreMigration` (RISKS #47/#56: back up both stores, copy attachments, move in or `SyncMerge`, marker); 8 Linux tests | `65dffd5` |
| S2 Backup UI | sync-storage-engineer · **Opus high** | Settings › Backup: export a `.tabulabackup` through the share sheet, restore with Merge (default) or Replace (destructive alert, pre-restore copy first; no copy means no replace), automatic copies list; migration runs at launch; 24 strings in 12 languages (`needs_review`); screenshot route `settings.backup` | `df17524`, `d4eaf82` |
| S2 QA → fixes | qa-reviewer · **Opus high** → Opus | Restore keeps this device's `syncEnabled` (Merge and Replace); the pre-restore copy exists in both modes; the export is rebuilt after a restore; new tests (attachment copy skips existing folders, re-run after a crash is idempotent) | `0803ac6`, `1f7e83f` |
| Merge S1 + S2 | orchestrator | Docs conflicts resolved, review export regenerated | `2806474` |

**Tier split:** Opus high did S1, S2, both fix rounds and both QA runs. Sonnet did nothing in this phase. S1 and S2 touch data-loss and sync, so the plan kept both on Opus.

## Runtime evidence
### Merged state `16ac596` (Phase 6 and the 4U fix pass), verified
- **iOS CI run 41217701086:**
  - Linux job green: `validate.sh` ALL CHECKS PASSED, **551 core + 634 UI tests** (540 + 621 before Phase 6 and the fix pass), 1,389 keys and 5 InfoPlist keys complete in 12 languages.
  - xtool path green.
  - **XcodeGen job RED.** The macOS core-test compile fails with "the compiler is unable to type-check this expression in reasonable time" on the `#expect` sum at `Packages/TimetableCore/Tests/TimetableCoreTests/Sync/CloudSyncTests.swift:118-120`. Linux's compiler accepts it. The same step failed the same way on `81b9d50` (run 41216929532).
  - **Skipped because of it:** the XcodeGen iOS + watchOS build, the bundle-layout check, and the "Compile the iCloud sync variant (`TABULA_CLOUDKIT`)" step.
  - **Fixed after this report:** `1484f16` splits the sum. That uncovered a wrong CloudKit link check (Xcode 16+ Debug builds keep the code in `TabulaApp.debug.dylib`), fixed in `8b78047`. **iOS CI run 41273158234 is green on every job**, including the XcodeGen iOS + watchOS build and the `TABULA_CLOUDKIT` variant compile.
- **Local builds (ENVIRONMENT §36):** the base xtool build links no CloudKit (`linked=0`); `--cloudkit build` compiles the adapter (`linked=1`, compile check only, refuses install); both report 0 warnings.
- **Sync logic:** `CloudSyncTests` covers both merge directions, tombstones, idempotent re-apply and all three first-sync choices converging on a fake zone.
- **Backup and migration:** Linux tests for restore (Merge and Replace keep `syncEnabled`), attachment copy, crash re-run, and the stranded-store migration.

### Device
- **Not run:** `PHASE6_DEVICE.md`. Sync needs two iPhones and a paid-account TestFlight build; only the backup rows S2.1–S2.6 can run on a free dev build.

## Not done / known limits
- **The `CKSyncEngine` adapter is compiled but has never run** (RISKS #96). Every sync behaviour is unproven until two devices and a CloudKit container exist.
- **The Xcode-path compile of the sync variant is unproven in CI** until the test failure above is fixed.
- **Free and xtool builds compile sync out.** Settings shows "iCloud Sync · Not Available" with an honest footer. There is no fake toggle (`CKContainer` crashes without the entitlement; RISKS #34).
- **Attachment bytes do not sync** (RISKS #55): only the references do. `CKAsset` needs a second record type, upload-before-ref ordering, on-demand download, purge and quota handling.
- **`.tabulabackup` files contain no attachment files** (RISKS #56); a Replace restore tombstones tasks missing from the backup, so their files go after the 24 h grace. The confirmation warns. Adding files is a format-2 change.
- **The CloudKit schema is not deployed to Production** (RISKS #92).
- **Background push** without `registerForRemoteNotifications` follows Apple's sample but is unverified (RISKS #94).
- **Translations:** 17 S1 keys and 24 S2 keys are machine-made `needs_review`.

## Decisions taken (reviewable)
- **CloudKit only on paid builds:** `TABULA_CLOUDKIT` follows `TABULA_PAID_ACCOUNT=1`; CI compiles a flagged variant to prove it builds.
- **Layout:** private database, zone `Tabula`, one record per entity, built from the existing `SyncRecord` JSON; the pure mapping lives in TimetableCore, CloudKit types stay in App. The persisted schema is unchanged.
- **Sync is on by default** in paid builds. When both sides hold data, the first-sync alert offers Merge (default), Keep This iPhone, Use iCloud; nothing is dropped silently, and the alert returns after a relaunch (row S1.13).
- **Local-first on account events:** sign-out and account switch keep local data (Apple suggests deleting it); a zone purge or encrypted-data reset keeps local data, does not resend, and switches sync off with a notice.
- **Backup:** Merge is the default restore; Replace needs a confirmation and always writes a pre-restore copy first.
- **Stranded data (RISKS #47):** moved once and atomically when the App Group appears; non-empty group data is merged, never overwritten.

## Risks (`docs/RISKS.md`)
- **#10** sync complexity and conflicts: **MITIGATED** (logic) / **OPEN** (device, S1 rows).
- **#34** CloudKit and other entitlements cannot be provisioned by xtool: **OPEN by design** until the paid account.
- **#47** data stranded in the Application Support fallback: **MITIGATED**, device rows S2.7–S2.9. Residual: the marker is final.
- **#55** attachment bytes not synced: **OPEN**. **#56** attachments follow the store location: **MITIGATED** (backups without attachments are documented).
- **#92** schema not deployed to Production: **OPEN** (release step).
- **#93** account switch keeps the previous account's data: **ACCEPTED**. **#95** iCloud data purged or reset: **ACCEPTED**.
- **#94** silent pushes without `registerForRemoteNotifications`: **OPEN** (device), row S1.21.
- **#96** adapter compiled but never run: **OPEN** (paid account).
- **#97** records from a newer app version: **MITIGATED** (logic).

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P6-1** | **Approve Phase 6** and move on | Approve once CI is green on a tip with the `CloudSyncTests` fix (small, test-only) |
| P6-2 | **CloudKit needs the paid Apple Developer account.** Until then every sync row stays unrun and free builds compile sync out | Enrol before the device pass of Phases 5 and 6 (one TestFlight build serves both) |
| P6-3 | **Deploy the CloudKit schema Development → Production** in the CloudKit Console before the App Store release. A production build cannot create record types; without it sync fails for every user (RISKS #92) | Do it as a release-checklist step, after the S1 device rows pass |
| P6-4 | **Sync default on**, with the first-sync Merge dialog | Keep |
| P6-5 | **Attachments** stay device-local and are not in backups (RISKS #55, #56) | Accept for v1; schedule `CKAsset` and backup format 2 as one item |
| P6-6 | **Account switch keeps local data** (#93) and a **purge keeps it and turns sync off** (#95) | Accept; local-first matches the product |

## Manual on-device checklist
`docs/checklists/PHASE6_DEVICE.md`: **S1.0–S1.23** (iCloud sync on two iPhones: first sync, airplane-mode conflicts, deletes and resurrection, subtasks, first-sync alert, sign-out, different account, purge, storage full, background push, VoiceOver, Slovak) and **S2.1–S2.9** (backup export, Merge and Replace restore, damaged files, stranded-data migration). S2.1–S2.6 run on a free dev build today; S2.7–S2.9 need a build that newly gets the App Group.

## Human steps
1. Fix or approve the fix for the macOS test compile error, then check iOS CI is green.
2. Paid account: `docs/PAID_ACCOUNT_SWITCHOVER.md` steps 1–8. Step 8 sets `TABULA_PAID_ACCOUNT=1`, which compiles the sync code in.
3. Install the TestFlight build on two iPhones signed in to the same iCloud account; watch CloudKit Console (development), zone `Tabula`, while testing.
4. Run `PHASE6_DEVICE.md`; run S2.1–S2.6 on the free dev build first.
5. Before release: CloudKit Console → container `iCloud.sk.simondev.tabula` → Deploy Schema Changes to Production.
6. Answer P6-1 to P6-6.

## Next
- **Phase 7 (Sharing)** and **Phase 8 (Export)** plans are on `main`; work is on `wip/phase7-app` and `wip/phase8-app`.
- Phase 7 universal links need the host `tabula.simondev.sk` and the team ID (switchover runbook).
