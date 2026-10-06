# SHARING (QR, link, short code)

## Payload
Versioned JSON schema (`v: 1`): timetable, subjects, grid, lessons, rotation settings; optional tasks (toggle "Include tasks"). Minified keys optional; deterministic field order. Pipeline: JSON → compress (zlib/deflate) → base64url.

## Three forms
1. **Inline link/QR** when compressed payload ≤ ~2 KB: `https://{{DOMAIN}}/t#<payload>` (fragment never reaches a server). QR limit is ~2.9 KB binary at low error correction; keep margin.
2. **Short code** when larger: upload to the Worker, receive 8-char code (alphabet without 0/O/1/I/L), shown with a copyable link `https://{{DOMAIN}}/c/<code>`.
3. **Manual code entry** screen in the app.

## Worker (Cloudflare Worker + KV, free tier first)
- `POST /v1/share` {payload, v} → {code, expiresAt}; `GET /v1/share/:code` → payload.
- TTL 30 days; max payload size enforced; strict schema validation; rate limit per IP; CORS minimal; no logging of payloads; no accounts; no analytics.
- Optional hardening (decide at gate): App Attest token to prevent abuse of the free tier.
- Verify and record current Cloudflare free-tier limits; add a usage alarm note to the README.
- Hosts the `apple-app-site-association` for universal links, and a tiny landing page for people without the app (App Store link).

## Receiving
Preview screen before import (name, subjects, lesson count, tasks yes/no); never overwrite silently; merge/duplicate handling; validate/sanitise every field; handle old/newer schema versions gracefully ("update the app"); handle camera permission denial; scanning with VisionKit/AVFoundation.

## Tests
Codec round-trip and fuzz tests (Linux), size-budget tests with large timetables, Worker tests (miniflare), malicious-payload tests.
