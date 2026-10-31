# ARCHITECTURE

## Targets
- `Packages/TimetableCore` — pure Swift (Linux-testable): models, rotation resolver, time grid, overrides, conflicts, onboarding presets, reminder planner, share codec, import parser/normaliser, export data-shaping, `Entitlements` protocol.
- `TimetableUI` — shared SwiftUI components (iOS + watchOS where possible).
- `App` — iPhone app. `WidgetExtension` — widgets + Live Activity. `WatchApp` — watchOS. Share/URL handling in App.
- `backend/` — Cloudflare Worker (TypeScript).
- App Group container shared by App, Widgets, Watch (via snapshot).

## Build paths
(a) SwiftPM + `xtool.yml` locally. (b) XcodeGen `project.yml` → xcodebuild in GitHub Actions macOS runner for release/TestFlight. CI builds both; either breaking fails the pipeline. Phase 0 documents what xtool cannot do.

## State & persistence
- Domain models are Codable value types with: stable `UUID`, `updatedAt` (hybrid logical clock preferred), `isDeleted` tombstone, `schemaVersion`.
- `Repository` protocol; default implementation = versioned Codable store in the App Group (atomic writes, migration chain, corruption recovery, full backup export/import). SwiftData only if Phase 0 proves macros work under the build path *and* it does not complicate CloudKit sync.
- Unidirectional data flow; small view models; no singletons beyond a dependency container.

## iCloud sync (default on)
Private CloudKit DB via `CKSyncEngine`; one record type per entity; field-level last-writer-wins for scalar fields, set-merge for subtasks/attachments; attachments as `CKAsset`; tombstones; first-sync merge dialog when both sides have data; sync status UI; schema deployed to Production before release. Fake transport for Linux tests. **Built (Phase 6 S1):** one zone `Tabula`, one record per entity (type = `EntityType` raw value, name = id, `payload` = canonical entity JSON, `schemaVersion`), tombstones as records, pending = payload hash ≠ server ledger (`cloudsync.json`), code compiled only with `TABULA_CLOUDKIT` (paid builds); attachments' `CKAsset` still deferred (RISKS #55).

## Time
Always explicit `Calendar`/`TimeZone`. Test: DST changes, week start (Mon/Sun/Sat), midnight rollover, time-zone travel, term boundaries, leap years, 53-week years for odd/even logic. Property tests for the resolver.

## Performance & resource budgets
Cold start < 1.0 s on iPhone 16 Pro Max for typical data; widgets timelines < 30 entries; Watch snapshot < 20 KB; on-device model memory < ~2 GB peak, loaded only during import and released after; no background CPU beyond system-scheduled refresh.

## Security & privacy
Local-first, no accounts, privacy manifest, accurate App Privacy answers. Share service stores opaque payload only. All imported/shared data is untrusted input: validate schema, bounds, string lengths; never execute or open links automatically.

## Dependencies
Minimal. Candidates to evaluate (justify each): llama.cpp or MLX Swift (local LLM), a small zip/XLSX writer (if XLSX chosen). Everything else uses system frameworks.
