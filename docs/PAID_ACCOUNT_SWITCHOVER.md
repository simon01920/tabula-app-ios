# Paid Apple Developer account: switchover runbook

Status: **deferred** (human decision 2026-10-06: enrol once the app has real shape). Owner: env-ci-engineer.
Everything that needs no paid account is built and tested now. The day the account exists, the steps below
switch the project over **without any code change**. Every step is done by the human in a browser or in
GitHub settings. Nothing secret is ever pasted into chat or committed.

## What is already in place (verified by `bash scripts/validate.sh`)

| Placeholder | Where | Today |
|---|---|---|
| Identity values (bundle ID `sk.simondev.tabula`, App Group `group.sk.simondev.tabula`, iCloud container `iCloud.sk.simondev.tabula`, share domain `tabula.simondev.sk`) | `Config/AppIdentity.xcconfig` (single source; project.yml uses `$(TABULA_*)`, xtool.yml/plists/TimetableCore are checked against it) | final values, no change needed |
| Team ID | `TABULA_DEVELOPMENT_TEAM =` (empty) in the xcconfig; CI passes GitHub variable `APPLE_TEAM_ID` | empty |
| Paid-only entitlements | `Config/Entitlements/PaidAccount/Tabula.entitlements` (App Group, CloudKit container + `icloud-services`, `aps-environment`, Time Sensitive, increased memory limit, `applinks:` associated domain) and `…/TabulaWidgets.entitlements` (App Group) | **not wired**: selected only when `TABULA_PAID_ACCOUNT = 1` |
| The switch | GitHub variable `TABULA_PAID_ACCOUNT` → release job passes it to `xcodebuild`; xcconfig picks `TABULA_APP_ENTITLEMENTS_$(TABULA_PAID_ACCOUNT)` | unset = 0 |
| Guard | `validate.sh`: switch committed OFF; with it off, no build input (xtool.yml, resolved project.yml, any Config plist/entitlements) contains a paid-only key; xtool never uses the PaidAccount files; with it on, the files resolve to the right container/domain/group. CI (`ios-xcodegen`) asserts the same resolution in real Xcode via `-showBuildSettings` | green |
| TestFlight job | `.github/workflows/ios.yml` → `release-testflight` (manual) skips with a notice until the secrets exist | skips |

## Steps on the day (in order)

| # | Step (human) | Exactly what to do | Unblocks |
|---|---|---|---|
| 1 | **Enrol** | https://developer.apple.com/programs/enroll/ (individual vs organisation: decision D1; organisation needs a D-U-N-S number). Wait for the approval e-mail | everything below |
| 2 | **Team ID** | developer.apple.com → Account → Membership details → Team ID (10 characters, not secret). GitHub repo → Settings → Secrets and variables → Actions → **Variables** → New: `APPLE_TEAM_ID` = Team ID | signed CI builds (`TABULA_DEVELOPMENT_TEAM`) |
| 3 | **App Store Connect API key** | appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → **Team Keys** → +: name `CI`, access **Admin** (cloud signing with `-allowProvisioningUpdates` needs Admin, see ENVIRONMENT §8). Download `AuthKey_<KEYID>.p8` (**only possible once**), note Key ID and Issuer ID. Optional second key `xtool` with **App Manager** for local `xtool setup` | step 4 |
| 4 | **GitHub secrets** | Settings → Secrets and variables → Actions → **Secrets**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`. For the last one, without printing the key: PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8")) \| Set-Clipboard`, paste into the secret field, then `Set-Clipboard -Value ' '`. Move the `.p8` somewhere safe outside the repo (`.gitignore` blocks `*.p8` anyway) | `release-testflight` stops skipping |
| 5 | **Identifiers** (one-time, ~10 min) | Certificates, Identifiers & Profiles → Identifiers: App IDs `sk.simondev.tabula` (capabilities: App Groups, iCloud with CloudKit, Push Notifications, Time Sensitive Notifications, Associated Domains, Increased Memory Limit), `sk.simondev.tabula.TabulaWidgets` (App Groups), `sk.simondev.tabula.watchkitapp` (App Groups), `sk.simondev.tabula.watchkitapp.widgets` (App Groups; Phase 5 complications); App Group `group.sk.simondev.tabula` (assign to app + widget + both watch IDs, RISKS #90); iCloud Container `iCloud.sk.simondev.tabula` (assign to the app). Automatic signing with the Admin key may create App IDs/profiles itself; which capabilities it enables on its own is **RESEARCH-ONLY**, so doing this once by hand avoids a failed first archive | provisioning profiles for all paid entitlements |
| 6 | **App record** | App Store Connect → Apps → + → New App: iOS, name (must be unique on the store), primary language, bundle ID `sk.simondev.tabula`, SKU e.g. `tabula-ios` | TestFlight upload target |
| 7 | **First TestFlight, switch OFF** | GitHub → Actions → iOS CI → Run workflow (upload ✓). Expected: archive signed with the App Group only; build appears in App Store Connect → TestFlight after processing (5–30 min). Add yourself as internal tester, install via the TestFlight app | first real install on the iPhone **and the Apple Watch** (watch app arrives with the iPhone app); App Group on device; App Intents/Shortcuts listing on the Apple path |
| 8 | **Flip the switch** | Settings → Variables → New: `TABULA_PAID_ACCOUNT` = `1`. Run the workflow again | CloudKit (development environment), push for CKSyncEngine, Time Sensitive notifications, increased memory limit, universal links entitlement |
| 9 | **Local xtool with the paid team** (optional) | own WSL terminal: `xtool auth logout`, then `xtool setup` → mode `0: API Key` with the `xtool` key | App Groups work in xtool device installs (`group.XTL-<ID>.…`). CloudKit, Time Sensitive and the memory limit stay CI/TestFlight-only (xtool cannot provision them, ENVIRONMENT §2.1) |

Rollback at any time: set `TABULA_PAID_ACCOUNT` to `0` (or delete the variable). Nothing in git changes.

## Not part of the switchover (feature work, no account needed)

- **Phase 6 sync (S1 built):** `UIBackgroundModes` has `remote-notification` (done). Step 8 also turns on the iCloud sync code: `TABULA_PAID_ACCOUNT = 1` sets `TABULA_CLOUDKIT` (xcconfig `TABULA_CLOUDKIT_CONDITION`), so the switch-OFF build shows "iCloud Sync · Not Available" and the switch-ON build syncs (default on). After step 8 run `docs/checklists/PHASE6_DEVICE.md` S1 on two iPhones. **Before the App Store release:** CloudKit Console → Deploy Schema Changes from Development to Production (RISKS #92). Never flip `TABULA_PAID_ACCOUNT` locally for an xtool install: `CKContainer` traps without the entitlement (`xtool-dev.sh --cloudkit build` is a compile check only).
- **Data stranded in the Application Support fallback (RISKS #47) — needed before step 9 / any local build that newly gets the App Group.** Without a provisioned App Group (free team; xtool PR #284) the app stores its data in `<Application Support>/Tabula` (`AppEnvironment` → `StoreLocation`, Settings → Developer shows "Application Support (fallback)"). Once the group container exists, the app opens the (empty) group location and shows onboarding: the fallback data is not lost but no longer used. Before switching, add a one-time migration in the app: if the group store is missing and the fallback store exists, copy `tabula.json` + `tabula.backup.json` (+ the HLC from standard UserDefaults) into the group, verify by loading, then rename the fallback folder (keep it, never delete automatically). TestFlight/CI builds are a different app (canonical bundle ID) and are not affected.
- **Phase 7 universal links:** host `https://tabula.simondev.sk/.well-known/apple-app-site-association` listing `<TeamID>.sk.simondev.tabula` (backend phase).
- **Phase 10 StoreKit:** create the subscription group and products in App Store Connect; In-App Purchase needs no entitlement.

## Verification after step 8 (record in docs/ENVIRONMENT.md)

1. `release-testflight` log: `paid-account switch TABULA_PAID_ACCOUNT=1`, archive succeeds.
2. On the exported app: `codesign -d --entitlements - Payload/TabulaApp.app` lists the CloudKit container, `aps-environment = production`, time-sensitive, increased-memory-limit, `applinks:tabula.simondev.sk` (Time Sensitive key name is **RESEARCH-ONLY** until this check passes: Apple has no doc page for it).
3. TestFlight build on the iPhone: debug screen App Group row PASS; `os_proc_available_memory()` row higher than on the xtool build.
