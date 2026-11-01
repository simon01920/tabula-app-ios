# Share service: deploy (human steps)

The Worker in `worker/` serves `POST /v1/share`, `GET /v1/share/:code`, the landing pages `/t` and `/c/<CODE>`, and
`/.well-known/apple-app-site-association`. Spec: `docs/specs/SHARING.md`, `PHASE7_PLAN.md` decisions 1, 2, 5, 6.
Everything below is done by the human. Never paste a Cloudflare token or password into chat; nothing here is a
secret that belongs in the repo (CLAUDE.md rule 7).

Placeholder domain: `tabula.simondev.sk` (also in `ShareConfiguration.defaultDomain`, TimetableCore).

## 1. Account and tools
1. Create a free Cloudflare account at dash.cloudflare.com (Free plan).
2. Add the zone that will hold the share domain (for the placeholder: `simondev.sk`) and switch its nameservers at
   the registrar to the two Cloudflare nameservers shown. Wait until the zone is "Active".
3. Install Node.js ≥ 22.18 (Windows or WSL), then in `worker/`: `npm install` (installs `wrangler`, dev only).
4. `npx wrangler login` (opens a browser; the human signs in). `npx wrangler whoami` shows the account ID.

## 2. KV namespace and placeholders
1. `npx wrangler kv namespace create SHARES` → copy the printed `id` into `worker/wrangler.toml` (`<KV_NAMESPACE_ID>`).
2. If `whoami` lists several accounts, set `account_id` in `wrangler.toml` (or `CLOUDFLARE_ACCOUNT_ID` in your shell).
3. Real domain: replace `tabula.simondev.sk` in `routes` and `PUBLIC_ORIGIN`, in `ShareConfiguration.defaultDomain`
   and in `TABULA_SHARE_DOMAIN` (`Config/AppIdentity.xcconfig`).
4. `APPLE_TEAM_ID` stays `""` until the paid account exists (the AASA route answers 404 until then; see §6).

## 3. Deploy and DNS
1. `npm test` (12 tests, `node:test`) then `npx wrangler deploy`.
2. `routes = [{ pattern = "<domain>", custom_domain = true }]` makes Cloudflare create the DNS record and the
   certificate for the custom domain itself. No other DNS record is needed. `workers_dev = false`: no
   `*.workers.dev` URL.
3. Dashboard → Workers & Pages → `tabula-share` → Settings: check that Observability/Logs are **off** and that no
   Logpush job exists (no request or IP logging).

## 4. Verify with curl
```sh
D=https://tabula.simondev.sk
curl -si -X POST "$D/v1/share" -H 'content-type: application/json' -d '{"v":1,"payload":"1.AAAA"}'
#   201 {"code":"7KX2M9QH","url":"https://…/c/7KX2M9QH","expiresAt":"…"}   (30 days ahead)
curl -si "$D/v1/share/7KX2M9QH"      # 200 {"v":1,"payload":"1.AAAA"}
curl -si "$D/v1/share/22222222"      # 404
curl -si -X POST "$D/v1/share" -H 'content-type: text/plain' -d x     # 415
curl -si "$D/c/7KX2M9QH" | head -20  # 200 text/html, content-security-policy: default-src 'none' …
curl -si "$D/.well-known/apple-app-site-association"   # 404 until APPLE_TEAM_ID is set
for i in 1 2 3 4 5 6 7; do curl -s -o /dev/null -w '%{http_code}\n' -X POST "$D/v1/share" \
  -H 'content-type: application/json' -d '{"v":1,"payload":"1.AAAA"}'; done   # 201 ×5, then 429
```
(The rate limit is per Cloudflare location and approximate, so the 429 can arrive one or two requests late.)

## 5. Free-tier limits (verified 2026-10-31 in developers.cloudflare.com) and the usage alarm
| Limit (Free plan) | Value | What happens when exceeded |
|---|---|---|
| Worker requests | 100,000 / day, reset 00:00 UTC | Error 1027 (custom domain: no fallback) |
| Worker CPU | 10 ms / request; 128 MB memory | request fails |
| KV reads | 100,000 / day | KV calls fail → Worker answers 503 |
| **KV writes** | **1,000 / day** (different keys); 1 write/s per key | KV calls fail → `POST` answers 503 until 00:00 UTC |
| KV deletes / lists | 1,000 / day each (Worker uses none; TTL expiry is free) | — |
| KV storage | 1 GB; value ≤ 25 MiB; key ≤ 512 B; `expirationTtl` ≥ 60 s | — |
| Rate Limiting binding | periods 10 or 60 s; per location, eventually consistent; docs name **no plan restriction and no price** | — |
| Request body | 100 MB on a Free zone (the Worker caps at 65,792 B itself) | — |

Cost per short-code share: 1 KV write + 1 KV read (collision check) + 1 read per open. **The binding limit is KV
writes: at most ~1,000 short-code shares per day across all users.** Inline links (most school timetables, ≤ 2 KB
compressed) never touch the server.

**Usage alarm.** Cloudflare offers no Workers/KV usage notification on the Free plan (Notifications page: the only
usage alert, "Usage Based Billing", is Pro+/pay-as-you-go). So: check Dashboard → Storage & Databases → KV →
`SHARES` → Metrics weekly, and immediately if users report "try again later". If writes regularly pass ~700/day,
decide at a gate between Workers Paid (a paid service: ask the human; check the current price) and App Attest (RISKS #14).

## 6. When the paid Apple account exists (universal links)
1. Set `APPLE_TEAM_ID` in `wrangler.toml` to the 10-character Team ID (public, not a secret) and `npx wrangler deploy`.
   `curl $D/.well-known/apple-app-site-association` now returns `applinks` for `/t*` and `/c/*` with
   `appIDs: ["<TEAM>.sk.simondev.tabula"]`, `content-type: application/json`, no redirect.
2. The app's `com.apple.developer.associated-domains` (`Config/Entitlements/PaidAccount/Tabula.entitlements`,
   `applinks:$(TABULA_SHARE_DOMAIN)`) becomes active with `TABULA_PAID_ACCOUNT=1` (domain from `TABULA_SHARE_DOMAIN`).
3. Apple's CDN fetches the file within 24 h; devices check about weekly. Until then (and without the paid account)
   the landing page's "Open in Tabula" button uses `tabula://import#<envelope>` / `tabula://import?code=<CODE>`.
