# Phase 6 plan: persistence hardening and iCloud sync

Status: started 2026-10-30 under the human's /goal. Follow `ponytail` (token reduction) and `apple-design` for any UI.

ROADMAP covers backup/restore, migrations, CKSyncEngine, conflict rules and a multi-device test matrix. The specs are ARCHITECTURE.md "iCloud sync" and DOMAIN_MODEL §2 (merge, tombstones, clocks).

**Already built and tested in Phase 1:** `SyncMerge`, `SyncRecord`, the HLC clock, `MutationStamper`, `BackupArchive`, `FileRepository` (corruption recovery), `SchemaMigration`.

**Missing:** all CloudKit code, the backup UI, and stranded-data migration (RISKS #47).

## Decisions
1. **CloudKit only on paid builds.**
   - A compile-time flag `TABULA_CLOUDKIT` is set only when `TABULA_PAID_ACCOUNT=1` on the XcodeGen path. CI also compiles a variant with it on, to prove the code builds.
   - Without the flag, sync is compiled out, and Settings shows "iCloud sync is available in the App Store version" (honest, no fake toggle).
   - Reason: `CKContainer` crashes without the entitlement, and free and xtool builds can't get it (RISKS #34).
2. **Engine and data layout.**
   - `CKSyncEngine` (iOS 17+; verify the APIs) on the private database, one custom zone.
   - One `CKRecord` per entity, built from the existing `SyncRecord` JSON. Mapping is pure and lives in TimetableCore; the CloudKit types stay in App.
   - Incoming records go through `SyncMerge`. Outgoing changes come from the `MutationStamper` dirty set.
   - Tombstones follow DOMAIN_MODEL.
3. **First sync.** When both the device and iCloud hold data, show a merge dialog (ARCHITECTURE): Merge (default) / Keep this device / Use iCloud. Never drop data silently.
4. **Attachments** use `CKAsset`, deferred if the size budget runs out (RISKS #55).
5. **Backup and restore UI** (Settings › Backup):
   - Export a `.tabulabackup` file through the share sheet.
   - Import with two modes: Merge (default), or Replace with confirmation and an automatic pre-restore backup.
   - Reuses `BackupArchive`.
6. **Stranded data (RISKS #47).**
   - When an App Group container appears and the Application Support fallback holds data, move it once, atomically, keeping a backup.
   - Never overwrite non-empty group data: merge with `SyncMerge` instead.
7. **Multi-device test matrix:** `docs/checklists/PHASE6_DEVICE.md`, covering 2 iPhones, offline/online, conflicts, deletes, first sync and account sign-out. All rows need the paid account.

## Stages
| Stage | Agent | Scope |
|---|---|---|
| S1 CloudKit sync | `sync-storage-engineer` (**Opus**) | Decisions 1–4; pure mapping tests on Linux |
| S2 Backup UI + stranded data | `sync-storage-engineer` (**Opus**, data-loss risk) | Decisions 5–6 |
| QA | `qa-reviewer` (**Opus**) | read-only |
