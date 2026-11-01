# Phase 8 plan: Export

Status: started 2026-10-31. This is the final phase of the current /goal; Phase 9 waits for the paid account. Follow `ponytail` and `apple-design`.

**Spec (PRODUCT.md):**
- Export as an image (grid, week or day, themed), PDF, CSV, XLSX or `.ics`.
- The user chooses the type and the view.
- Exports are a Pro feature (MONETIZATION); the current tier is all-access, so the gate is the existing entitlements check.

## Decisions
1. **Pure exporters in TimetableCore (Linux-tested):** CSV, ICS and XLSX, built from the resolved schedule engine output for a chosen date range (default: the current term, or the next 4 weeks if there is no term).
   - **CSV:** RFC 4180, UTF-8 with BOM, one row per lesson occurrence. Header columns: date, start, end, subject, room, teacher, change. Column titles come from catalog keys passed in.
   - **ICS:** RFC 5545. Each occurrence becomes its own VEVENT: rotations, overrides and holidays make RRULE error-prone, and the date range bounds the size. Times use the timetable's zone (TZID with a VTIMEZONE from Foundation's rules for the range), or "floating" for follow-device timetables, documented. Stable UIDs come from the lesson id plus the date, so re-importing updates events instead of duplicating them.
   - **XLSX:** our own minimal writer (CLAUDE.md prefers our own code over a dependency). It writes the needed parts (`[Content_Types].xml`, workbook, one sheet with inline strings) and packs them with a small ZIP writer on the existing CZlib deflate. Tests check the archive structure and that the XML is well-formed. Opening it in Excel or Numbers goes on the device checklist.
   - **E1 as built** (`TimetableCore/Export/`): `ExportRows.build` → `CSVExport` / `ICSExport` / `XLSXExport` `.data(rows:labels:…)`. Cancelled occurrences stay in every format: CSV/XLSX via the change column, ICS as `STATUS:CANCELLED` (a re-import cancels the earlier event). CSV fields starting with `= + - @` TAB or CR get a leading `'` (formula injection from shared subjects). ICS: TZID + VTIMEZONE only when the caller passes a zone (`timeZoneMode == .fixed`), otherwise floating; DTSTAMP is injected. XLSX parts are deflated when smaller, else stored; fixed 1980 timestamps (deterministic).
2. **Image and PDF (App):** SwiftUI `ImageRenderer` of the existing grid, week and day views in a print layout (light theme, fixed width). PDF uses `ImageRenderer.render` into a PDF context, paginated per week. Verify the APIs.
3. **UI:**
   - An "Export…" item in the Timetable ⋯ menu opens a sheet: Type, View (image and PDF only), Range, then Export.
   - The file goes out through `ShareLink` or the share sheet with a sensible file name.
   - Pro gate through the entitlements helper.
   - Strings in 12 languages.

## Stages
| Stage | Agent | Scope |
|---|---|---|
| E1 CSV, ICS and XLSX writers | `core-domain-engineer` (**Opus**: time zones, formats) | TimetableCore + tests |
| E2 Export sheet, image and PDF rendering | `swiftui-engineer-sonnet` (Sonnet) | App + TimetableUI; calls E1 |
| QA | `qa-reviewer` (**Opus**) | read-only |
