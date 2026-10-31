# Phase 7 plan: Sharing

Status: started 2026-10-31 under the human's /goal. Follow `ponytail` (token reduction) and `apple-design` (HIG: sharing, QR / camera, alerts).

**Specs:**
- SHARING.md: inline link `#payload` when the compressed payload is ≤ 2 KB, otherwise a short code `/c/<code>`, plus manual code entry. Worker + KV: `POST/GET /v1/share`, 30-day TTL, per-IP rate limit, no logs. The importer previews before importing and never overwrites silently.
- SHARE_FORMAT.md: v1 codec. It is complete and tested in `TimetableCore/Share/` (13 files).

Free tier (PRODUCT/MONETIZATION).

## Decisions
1. **Domain** stays the placeholder `tabula.simondev.sk` in one constant and one config file. The real domain, DNS, the Cloudflare account and `wrangler deploy` are **human steps**, listed in `docs/SHARING_DEPLOY.md`. The Cloudflare free tier is not a paid service.
2. **Universal links need the paid account** (Associated Domains). Until then:
   - a custom scheme `tabula://import#…` plus the manual code entry screen;
   - the AASA file is served by the Worker and ready for when the account exists.
3. **QR:** generate with CoreImage `CIQRCodeGenerator`. Scan with VisionKit `DataScannerViewController`, falling back to the photo picker and Vision barcode detection when the scanner is unavailable. Verify the APIs. The camera usage string goes in `InfoPlist.xcstrings`.
4. **Import:**
   - A preview screen showing timetable name, subjects, lesson count and conflicts.
   - Choice: "Add as new timetable" (default) or "Replace …", with confirmation and an automatic backup through Phase 6 S2.
   - All of it goes through the existing `ShareImport`, then `model.apply`.
5. **Worker:**
   - TypeScript Cloudflare Worker + KV.
   - Size cap equal to SHARE_FORMAT §5.1, envelope validation, an unguessable short code.
   - Rate limiting, no logging of payloads, CORS closed.
   - Tests with `node:test`, so there are no test-framework dependencies. `wrangler` is a dev-only tool (Apache/MIT); check its licence.
6. **Landing page:** a static page from the Worker. "Open in Tabula" plus a store placeholder. No trackers.

## Stages
| Stage | Agent | Scope |
|---|---|---|
| H1 App sharing (export sheet, QR, scan, import preview, scheme, code entry) | `swiftui-engineer` (**Opus**, data import) | App + TimetableUI |
| H2 Worker, AASA, landing page, deploy doc | `backend-engineer` (**Opus**, security) | `worker/`, `docs/SHARING_DEPLOY.md` |
| QA | `qa-reviewer` (**Opus**) | read-only |
