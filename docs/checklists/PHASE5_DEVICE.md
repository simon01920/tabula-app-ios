# Phase 5 — manual on-device checklist (Apple Watch)

Devices: iPhone 16 Pro Max (iOS 26.x) + Apple Watch Series 7 (watchOS 26.x, arm64_32). Format as in
`PHASE4_DEVICE.md`: **Steps → Expected**, Observed, ✔ / ✘ / ? (unclear).

The watch app and its complications exist only in **TestFlight** builds (XcodeGen/CI path, paid account; RISKS #1, #37).
An xtool build has no watch app; its iPhone side still sends nothing harmful (W1.12). Nothing here can be previewed or
simulated locally; the CI watch-simulator screenshot (`ui-screenshots.yml`, input `watch: true`) only shows the empty
state.

watchOS version: ________ · iOS version: ________ · Build: TestFlight ____ · Tester: ________ · Date: ________

---

## W1 — Watch app, sync, complications

Setup: Pro tier (the current tier is all-access), a timetable with lessons today and tomorrow, iPhone and Watch paired.

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| W1.1 | **Pairing / install.** Install the TestFlight build on the iPhone. Watch app on iPhone → Available Apps → Tabula → Install (or automatic install) | Tabula appears on the watch Home Screen with the app icon; launching it shows no crash | | |
| W1.2 | Before opening Tabula on the iPhone (fresh install), open Tabula on the watch | "Open Tabula on your iPhone" with "Your timetable appears here after your iPhone sends it." No invented data | | |
| W1.3 | Open Tabula on the iPhone (finish onboarding or keep the existing timetable), wait ≤ 30 s, look at the watch app | The watch shows Now & Next (no iPhone-side diagnostics: the watch screen is the proof) | | |
| W1.4 | During a lesson: watch app | Top block: subject badge, **NOW** highlighter marker, subject name, room, **large** live countdown with "left" under it (mm:ss under 60 min, never a bare "25:00"), progress bar, "Next …" line. Then "Today · <date>" with the lessons still to come (current and past ones not listed), then "Tomorrow · <date>" | | |
| W1.5 | A lesson longer than 60 min (or edit one to 90 min): watch app at the start | Countdown shows minutes only ("1 hr, 29 min" style, no seconds) with "left"; switches to mm:ss below 60 min | | |
| W1.6 | Watch the screen across a lesson boundary (keep the app open, wrist up) | Within a minute the block flips to the break / next lesson ("Next", countdown "until start"); the Today list drops the ended lesson | | |
| W1.7 | **Offline.** Turn on Airplane Mode on the iPhone (or walk out of Bluetooth range), relaunch the watch app; then cross a lesson boundary | Same timetable from the cache; boundaries still advance (computed on the watch, not sent) | | |
| W1.8 | Edit a lesson's room on the iPhone (Bluetooth back on), lock the iPhone, wait 1 min | Watch app (and complications, W1.11) show the new room without opening anything on the watch | | |
| W1.9 | iPhone language Slovak (Tabula's in-app language), reopen both apps | Watch strings follow the snapshot's language (sk): "TERAZ", "zostáva", section headers; times follow the 12/24 h setting | | |
| W1.10 | **Complications.** Long-press a watch face → Edit → Complications: add Tabula to a corner, a circular slot (e.g. Modular Compact / Infograph), the rectangular slot (Modular) and the inline slot (Utility top) | Each family shows content: corner = short subject name + curved "25 min · MAT" label; circular = ring with short name + time left; rectangular = time-first line + next lesson; inline = "25 min · MAT". Tinted faces: outlined marks, legible | | |
| W1.11 | **Complication refresh.** Note a complication during a lesson, wait across the boundary without touching the watch | Updates at the boundary (timeline entry), live timer ticks without reloads; after W1.8 the room/subject updates after the watch app received data (reload on receive) | | |
| W1.12 | xtool build on the iPhone (no watch app installed) | iPhone app behaves as before; no error banner; no crash with a paired watch | | |
| W1.13 | **Smart Stack.** Turn the Digital Crown up from the watch face during a lesson; add Tabula to the Smart Stack if not suggested | The Now & Next widget appears (rectangular); during a lesson it tends to rise to the top (entry relevance) | | |
| W1.14 | **Background refresh.** Force-quit the watch app (side button, swipe), change a lesson on the iPhone, wait 2–5 min without opening the watch app, then look at a complication | Complication shows the change (watch app was woken by `.watchConnectivity`, cache written, timelines reloaded). If it only updates after opening the app, record ✘ (RISKS #89) | | |
| W1.15 | **Low Power Mode** on the watch (Control Center → battery %) during a lesson | Complications and the app still show the cached timetable; countdown may update less often; no crash. Turn Low Power Mode off: sync resumes (repeat W1.8) | | |
| W1.16 | **Always On** (wrist down, dimmed) with the watch app open | The countdown keeps showing time left (minute precision while dimmed is fine); no seconds-dependent layout jumps | | |
| W1.17 | **Free tier** (when StoreKit gating is live, or a DEBUG tier switch): open the watch app and look at complications | Watch app: "Available in Tabula Pro" with a lock; complications: Pro placeholder (lock + "Pro" on circular/corner) | | |
| W1.18 | **Day rollover.** Leave the iPhone off/away overnight; next morning open the watch app | Today = the new day from the cache (the snapshot covers today through the next school day); if it does not: "Open Tabula on your iPhone" + "Open the app to update your timetable." | | |
| W1.19 | Unpair / switch to another watch (if available) and back | Re-paired watch gets the snapshot after opening the iPhone app once (sender re-sends on activation / watch state change) | | |
| W1.20 | **VoiceOver** on the watch: swipe through the app | Now & Next read as one sentence (subject, time, ends at, next); each lesson row read as one sentence; empty state title + detail read | | |
| W1.21 | **Dynamic Type** (watch Settings → Display → Text Size, largest) | Text wraps or scales, nothing clipped in the Now & Next block and rows | | |
| W1.22 | **Time zone.** Change the iPhone/watch time zone (follow-device timetable) | 08:00 lessons still show at 08:00 local; complications re-plan within ≤ 6 h (RISKS #67) or immediately after opening the app | | |
