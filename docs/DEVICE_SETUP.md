# Device setup runbook: iPhone 16 Pro Max over USB into WSL2, xtool dev install

Goal: install and launch the xtool **dev build** (base variant) on the iPhone from this Windows 11 PC, then run the
priority device checks. Free Apple ID, 7-day provisioning (no paid account: `docs/PAID_ACCOUNT_SWITCHOVER.md`).

Legend: **[Human]** = you, **[Orch]** = the orchestrator (Claude) runs it. Facts are tagged **VERIFIED** (run on this
PC, see `docs/ENVIRONMENT.md` §9 and §27) or **RESEARCH-ONLY** (vendor docs, not yet run here). Anything tagged
RESEARCH-ONLY may need adjusting at first contact; record what actually happened in ENVIRONMENT.md.

Shell notes: the orchestrator calls WSL from Windows with `wsl.exe -d Ubuntu --exec bash ...` (not `--`, see ENVIRONMENT §22).
Repo path in WSL: `/mnt/c/Users/simon/Documents/Claude Code/school_timetable`.

Never type or paste an Apple ID password, 2FA code or app-specific password into the chat (CLAUDE.md rule 7).

> **VERIFIED 2026-10-16 (ENVIRONMENT §29): install through the relay route, not USB/IP.**
> - USB/IP (sections 1–2) pairs and provisions, but the app upload hangs at `[Connecting] 100%` (usbmuxd reports "message was too large"; xtool #341).
> - **Working route (phone: iPhone 16 Pro, iOS 27.0.1):**
>   1. Detach the phone from WSL: `usbipd detach --busid <BUSID>`.
>   2. Open the **Apple Devices** app on Windows, with the phone plugged in and trusted.
>   3. On Windows (no admin): `py -3 scripts/win-usbmuxd-relay.py 172.19.96.1`. Use the IP of the `vEthernet (WSL…)` adapter.
>   4. In WSL: `export USBMUXD_SOCKET_ADDRESS=172.19.96.1:27015 && cd /root/.cache/tabula/work && xtool dev run`.
>
>   Run `bash scripts/xtool-dev.sh build` first, so the work dir is current.
> - Use xtool **1.22.2+**; 1.20.1 cannot log in (error -80045).
> - The human opens a root shell without the first-run prompt using `wsl -d Ubuntu -u root --exec bash -l`.

## 0. Preflight (before the phone is plugged in)

**[Orch]** run the doctor; it is read-only and always exits 0:

```
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu --exec bash -lc 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && bash scripts/device-doctor.sh'
```

State on 2026-10-16 (VERIFIED): usbmuxd 1.1.1, libimobiledevice-utils 1.4.0 (`idevice_id`, `ideviceinfo`, `idevicepair`,
`idevicesyslog`, `idevicecrashreport`), xtool 1.20.1 and the Darwin SDK are installed; `ideviceinstaller` and `lsusb`
(`usbutils`) are not (optional). **xtool is logged out** (section 3). WSL kernel 6.18.33.2 has `vhci_hcd` as a module,
which is what `usbipd attach` needs. Windows: `usbipd` is **not installed yet**; Apple Mobile Device Service is not present.

If the doctor ever reports tools missing, **[Orch, needs sudo, tell the human first]**:

```
sudo apt-get update && sudo apt-get install -y usbmuxd libimobiledevice-utils libimobiledevice6 ideviceinstaller usbutils
```

## 1. Windows side (usbipd-win)

All of this is **[Human]** except the check commands.

1. Install (once). Needs no admin to start, but the installer asks for elevation:
   ```
   winget install --interactive --exact dorssel.usbipd-win
   ```
   (`winget install usbipd` also resolves; the exact id is `dorssel.usbipd-win`.) Then **open a new PowerShell**
   (the PATH is updated only for new shells) and check:
   ```
   usbipd --version
   ```
   Expected: a `5.x` version (latest known 5.3.0, GPL-3.0, host tool only, not shipped with the app).
2. Plug the iPhone in with a **data cable**, unlock it, and when asked **Trust This Computer** may already appear
   (on Windows if iTunes/Apple devices driver is present). Tapping Trust here is harmless.
3. Find the device:
   ```
   usbipd list
   ```
   The row with `05ac:` (Apple) and a name like "Apple iPhone" / "Apple Mobile Device USB Composite Device" is the phone.
   Note its `BUSID` (e.g. `2-3`). The BUSID can change if you use another USB port; always re-read it.
4. **Bind once** (admin PowerShell: right-click Start, Terminal (Admin)):
   ```
   usbipd bind --busid <BUSID>
   ```
   Persists across reboots. If it refuses because a driver holds the device, `usbipd bind --busid <BUSID> --force`
   (RESEARCH-ONLY). `usbipd list` should now show `Shared`.
5. **Attach** to WSL (normal PowerShell is enough after the bind; keep a WSL window open so the VM stays running):
   ```
   usbipd attach --wsl --busid <BUSID>
   ```
   Optional auto-reattach whenever the phone is replugged (leave this terminal open): `usbipd attach --wsl --busid <BUSID> --auto-attach`.
6. **Re-attach** is needed after: unplugging, a phone reboot, the phone re-enumerating (after Trust, after Developer Mode
   restart, sometimes on first install), `wsl --shutdown` and a Windows reboot. Bind survives; attach does not.
   Same command, same BUSID (check `usbipd list`: state should read `Attached`).

### Apple Mobile Device Support / iTunes / Apple Devices app (conflict?)

RESEARCH-ONLY. While the phone is **attached to WSL, Windows cannot use it**: iTunes / the Apple Devices app / Windows
Explorer will not see it. They do not otherwise block `usbipd bind`. usbipd-win's docs list no known conflict with the
Apple USB driver. Practical rules: do not run iTunes while attached; if bind fails, close iTunes/Apple Devices and retry
(`--force` as a last resort); and do not run both Windows' `AppleMobileDeviceService` and WSL's usbmuxd against the same
phone (only one side owns the device at a time). If attach cannot be made to work at all, use the iTunes relay (section 6).

### Windows firewall

RESEARCH-ONLY. `usbipd attach --wsl` talks to the Windows host over TCP 3240 from the WSL virtual NIC. If attach fails
with a connection error/timeouts, allow inbound TCP 3240 for the WSL network (admin PowerShell):
```
New-NetFirewallRule -DisplayName "usbipd (WSL)" -Direction Inbound -Protocol TCP -LocalPort 3240 -Action Allow
```
Remove it afterwards if you like (`Remove-NetFirewallRule -DisplayName "usbipd (WSL)"`). Admin rights are needed for
**install, `bind`, and the firewall rule**; `attach` and `list` are not.

## 2. WSL side: usbmuxd, pairing, Trust, Developer Mode

1. **[Orch]** confirm the phone is visible and pairing works:
   ```
   bash scripts/device-doctor.sh
   ```
   Expected after attach: `OK Apple USB device visible inside WSL`.
2. usbmuxd: the package ships udev rule `39-usbmuxd.rules` which starts it on attach (`usbmuxd.service` is *static*,
   VERIFIED 2026-10-06). WSL2 has no systemd-udevd in some setups; if `pgrep -x usbmuxd` shows nothing after attach,
   **[Orch]** start it by hand: `sudo usbmuxd -f -v &` (or `sudo usbmuxd -U root`). Note `idevice_id -l` prints
   `ERROR: Unable to retrieve device list!` (exit 255) while usbmuxd is not running (VERIFIED 2026-10-16).
3. **[Human]** unlock the phone and keep it unlocked. **[Orch]** run `idevicepair pair`. The phone shows
   **Trust This Computer?** -> tap **Trust**, enter the **phone passcode**. (Passcode is typed on the phone only.)
   Then **[Orch]**: `idevicepair validate` -> `SUCCESS: Validated pairing`, `idevice_id -l` -> prints the UDID,
   `ideviceinfo -k ProductVersion` -> iOS version. Pairing reconnects the device: re-run `usbipd attach` if the UDID vanishes.
4. **Developer Mode.** The switch appears on the phone only **after the first dev install attempt** (it is hidden before):
   Settings -> Privacy & Security -> scroll to the bottom -> **Developer Mode** -> On -> **Restart**, confirm after
   restart ("Turn On", passcode). The phone reboots, so **re-attach** (section 1.6). Readable from WSL (best-effort):
   `ideviceinfo -q com.apple.security.mac.amfi -k DeveloperModeStatus` -> `true`/`false` (RESEARCH-ONLY; doctor prints it).

## 3. xtool sign-in (free Apple ID)

Verified CLI (xtool 1.20.1, `xtool auth --help`): `xtool auth login [-u <apple id>] [-p <password>] [-m key|password]`,
`xtool auth status`, `xtool auth logout`. Today `xtool auth status` prints `Logged out` (VERIFIED). Building needs no login;
only the device install does (ENVIRONMENT §2).

**[Human]** in your own interactive WSL terminal (Windows Terminal -> Ubuntu), *not* through the orchestrator:

```
xtool auth login --mode password
```

- Do **not** pass `--password` on the command line (it lands in shell history). Let xtool prompt for it.
- Enter the Apple ID e-mail and password when prompted. Use a throwaway/secondary Apple ID if you prefer
  (ENVIRONMENT H3). A free account is enough; the paid-only `--mode key` (App Store Connect API key) is for later.
- Apple then sends a **2FA code to your trusted devices**: type it at the xtool prompt. Not in chat.
- xtool does not need an app-specific password for this flow as far as its docs/source show (RESEARCH-ONLY). If xtool
  asks for one, generate it yourself at appleid.apple.com -> Sign-In and Security -> App-Specific Passwords, and
  paste it only into that terminal prompt.
- Credentials are stored by xtool on this machine (not in the repo). The orchestrator only runs `xtool auth status`
  (and the doctor prints just logged in/out, never the account).

Free-team limits (Apple rules for personal teams; RESEARCH-ONLY unless noted):
- Provisioning profiles **expire after 7 days**: re-run `bash scripts/xtool-dev.sh` weekly (reinstall refreshes it; user
  data is kept). After expiry the app refuses to launch until reinstalled.
- At most **3 apps** with development profiles per device on a free team, and a weekly cap on new App IDs
  (the app and the widget extension each use an App ID).
- **App Groups are filtered out for free teams by xtool** (ENVIRONMENT §7, RISKS #47; upstream PR #284 open). The app
  falls back to Application Support (Settings -> Developer -> Store shows "Application Support (fallback)"), and the
  **widget cannot read the app's data**. This is expected, not a bug. Data created now is stranded in the fallback when
  an App Group appears later (RISKS #47).
- No Time Sensitive, CloudKit, Push or In-App Purchase on a free team; those rows need the paid account.
- xtool re-signs under `XTL-<ID>.sk.simondev.tabula`, so the on-device identity differs from CI/TestFlight (RISKS #20).

## 4. Build, install, launch

**[Orch]** (after sections 1 to 3 are green: doctor shows device, `xtool auth status` is not `Logged out`):

```
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu --exec bash -lc 'cd "/mnt/c/Users/simon/Documents/Claude Code/school_timetable" && TABULA_WORKDIR=/root/.cache/tabula/work TABULA_SCRATCH=/root/.cache/tabula/device bash scripts/xtool-dev.sh'
```

(`TABULA_WORKDIR` defaults to `~/.cache/tabula/work`; `xtool-dev.sh` syncs the repo to that ext4 dir, compiles the
String Catalog, then runs `xtool dev run`, i.e. build + install + launch. `TABULA_SCRATCH` is read by the other scripts
such as `validate.sh`; harmless here.) Useful variants: `... xtool-dev.sh build` (no device needed), `--macro-probes`
(macro variant). To pick a device when several exist: `xtool dev run --udid <udid> --usb` is what the script passes through;
list with `xtool devices --no-wait` (**always add `--no-wait`**: the default `--wait` blocks forever with no phone, VERIFIED).

Expected: `Build complete!`, an install progress, the app launches on the phone, `+ widget appex check: ... present`.
First attempt typically fails or the app will not open until the next two steps.

**[Human]** on the phone:
1. Developer Mode (section 2.4) if it is not on yet, then **[Orch]** re-run the command.
2. **Trust the developer certificate:** Settings -> General -> **VPN & Device Management** -> under "Developer App" tap your
   Apple ID -> **Trust**. (Needed once per account; after a 7-day refresh no re-trust.) Then open **Tabula** from the Home Screen.

**Launch without rebuilding / with arguments [Orch]:** `xtool launch sk.simondev.tabula.XTL...` is awkward because xtool
rewrites the bundle ID; easiest is the whole `xtool-dev.sh` again, or tap the icon. DEBUG-only launch arguments in the
checklists (`-TabulaSeed`, `-TabulaNow`) need Xcode/simctl; on the device use **Settings -> Developer** instead.

**Logs [Orch]** (idevicesyslog 1.4.0 has no process filter option, so filter with grep; VERIFIED options list):
```
idevicesyslog -x | grep -i -E 'TabulaApp|TabulaWidgets|sk\.simondev\.tabula'
```
Start it **before** reproducing a problem; stop after. Crash reports after a crash: `idevicecrashreport -e -k /tmp/tabula-crashes`
then read `*.ips` there (RESEARCH-ONLY; `-k` keeps them on the phone). Also on the phone: Settings -> Privacy & Security ->
Analytics & Improvements -> Analytics Data.

## 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `usbipd list` does not show the phone | cable is charge-only, phone locked, other port | different cable/port, unlock the phone, replug |
| Doctor: `no Apple USB device visible inside WSL` | not attached, or WSL VM restarted | `usbipd attach --wsl --busid <BUSID>` with a WSL window open; check `usbipd list` says `Attached` |
| `usbipd attach` error about connection/timeouts | Windows firewall blocks TCP 3240 | firewall rule in section 1; `wsl --update` if WSL kernel is old |
| `idevice_id -l` -> `ERROR: Unable to retrieve device list!` | usbmuxd not running | `sudo usbmuxd -f -v &`, then retry; attach first |
| `idevice_id -l` empty, `usbmuxd` running | not attached, phone locked/never trusted | unlock phone; `idevicepair pair`; re-attach |
| `Could not start com.apple.mobile.lockdown` / `ERROR: Could not connect to lockdownd` | phone locked or not trusted, or pairing record stale | unlock, `idevicepair unpair; idevicepair pair`, tap Trust, re-attach; if it persists reboot the phone, then re-attach |
| `idevicepair pair` -> `Please enter the passcode on the device` / `user denied` | Trust prompt unanswered | unlock the phone, tap Trust, passcode, rerun |
| `ERROR: Pairing dialog response pending` | waiting for the human | answer on the phone |
| `xtool dev run` hangs at `[Connecting]` or `AFCClient.Error.muxError` | usbmuxd/lockdown problem over USB-IP | re-attach and retry; if repeatable use the iTunes relay (section 6) |
| Install stops with auth error / `Logged out` | not signed in | section 3 (human, interactive) |
| Provisioning: "maximum number of apps/App IDs", "team has no ... capability", profile errors | free-team limits, or a paid-only entitlement slipped into `Config/*.entitlements` | delete old dev apps from the phone / wait a week; confirm `bash scripts/validate.sh` is green (it blocks paid entitlements); paid-only rows need the paid account |
| Install ok but icon greyed / "Untrusted Developer" | certificate not trusted | VPN & Device Management -> Trust |
| "Developer Mode required" on launch | not enabled / restart pending | section 2.4; **re-attach after the restart** |
| App launches then closes at once (crash on launch) | profile expired (7 days), entitlement mismatch, real crash | reinstall; run `idevicesyslog -x \| grep -i Tabula` while launching, then `idevicecrashreport`; report the log (redact nothing needed, no secrets are logged) |
| Widget missing / shows no data | expected on free team: no App Group | not a bug; see section 3 |
| Device disappears from WSL when the phone locks or sleeps | USB-IP drops if the phone re-enumerates (Trust, lock with cable power change, USB sleep) | keep the screen on during the session (Settings -> Display & Brightness -> Auto-Lock -> Never, restore afterwards); `--auto-attach`; Windows Power Options -> USB selective suspend off |
| `usbipd bind` "access denied" | not an admin shell | open Terminal (Admin) |
| iTunes/Apple Devices opens a pairing prompt on Windows | Windows still owns the device | detach (`usbipd detach --busid <BUSID>`), quit iTunes, attach again |

## 6. Fallback: iTunes relay (ENVIRONMENT §9)

Use only if USB-IP will not give stable lockdown/AFC access (`AFCClient.Error.muxError`, hang at `[Connecting]`).
RESEARCH-ONLY (xtool issue #19, comment 2898986718): install iTunes/Apple Devices on Windows so
Windows' own usbmuxd (port 27015) owns the phone, and let WSL talk to it over TCP.

1. **[Human, admin]** with the phone **not** attached via usbipd (`usbipd detach`), plug it in and trust it on Windows.
2. **[Human, admin]** allow the WSL network to reach port 27015: Windows Defender Firewall rule for the
   `vEthernet (WSL (Hyper-V firewall))` interface (inbound TCP 27015), and a port proxy from the WSL host address to
   loopback, where `<WSL-HOST-IP>` is the Windows-side address of the WSL NIC (`ipconfig`, adapter "vEthernet (WSL...)"):
   ```
   netsh interface portproxy set v4tov4 listenport=27015 connectaddress=127.0.0.1 connectport=27015 listenaddress=<WSL-HOST-IP>
   ```
3. **[Orch]** in WSL, per shell: `export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"`, then
   `idevice_id -l` should list the phone; the same variable must be set for `xtool-dev.sh`. Do not run WSL's own usbmuxd then.
4. Undo later: `netsh interface portproxy delete v4tov4 listenport=27015 listenaddress=<WSL-HOST-IP>` and remove the firewall rule.

## 7. What to test first (about 15 rows, highest value)

Free team, local xtool build: there is **no Time Sensitive and no App Group** (widget will not show data; Developer ->
Store reads "Application Support (fallback)"). Rows needing those are skipped here; do them on the paid build. Tick results
in the full checklists, `docs/checklists/PHASE2_DEVICE.md` and `PHASE3_DEVICE.md`. Run each in order; stop and report
on the first crash.

| # | Checklist row | Why first |
|---|---|---|
| 1 | P2 A1 First launch -> onboarding, A2 persistence across relaunch / force-quit | the app runs at all; data survives (every later check depends on it) |
| 2 | P3 A1.1 to A1.3 (no prompt at launch; request permission; test notification after 5 s, locked) | notifications are the product's core promise |
| 3 | P3 A1.4 long-press actions on a delivered reminder (Mark as Done, in 1 Hour, Tomorrow) | notification actions, untested path |
| 4 | P3 A1.5 / A1.6 turn notifications off/on in Settings, health row recovers | permission edge cases |
| 5 | P3 A4.1 + A4.2 AlarmKit test alarm (60 s) with Silent OFF, then Silent ON | loud alarms ring through Silent; biggest unknown (needs AlarmKit permission, A1.7) |
| 6 | P3 A4.3 / A4.5 alarm in Focus; after force-quit | alarms in Focus / after kill |
| 7 | P3 A4.9 + A4.10 Snooze countdown Live Activity, stop with a button | snooze path |
| 8 | P3 A7.1 / A7.3 background refresh request; BAR off health row | rolling planner depends on it |
| 9 | P3 A6 time zone / DST rows (change zone with app open and in background) | plan correctness |
| 10 | P2 A7 time zone, locale, 12/24 h | time display |
| 11 | P2 B2.1 Today "Now & Next" header + B2.4 Grid (Dynamic Type XXL) | core screens never seen |
| 12 | P2 B3.1 + B3.2 editor sheets: Cancel/Save, lesson editor | data entry path |
| 13 | P3 B3a/B3b attachments: add a photo / voice note, relaunch, delete (data-loss sensitive) | permissions + file handling |
| 14 | P3 Q1 permission asked in context, Q6 notification tap shows something | deep links and permission UX |
| 15 | P2 A4 store banners (corrupt / schema v99 recovery tests) | safety net for user data |

Always note, per row: Observed, pass/fail. Report anything surprising to the orchestrator, which records it in
`docs/ENVIRONMENT.md`.
