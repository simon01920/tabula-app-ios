# Phase 7 — manual on-device checklist (sharing)

Format as in `PHASE4_DEVICE.md`: **Steps → Expected**, Observed, ✔ / ✘ / ? (unclear). The UI cannot be simulated
locally; everything below is unverified until run on the iPhone 16 Pro Max. Two phones (A sends, B receives) where a
row says so; a second Tabula install is not needed for rows marked "A only".

Until the Worker is deployed (H2, `docs/SHARING_DEPLOY.md`), the share domain `tabula.simondev.sk` is a placeholder:
inline links, QR codes and `tabula://` links work offline, **short codes do not** (upload/fetch fail with "The share
service isn't available right now"). Rows that need the service are marked **[service]**.

Seeds: `-TabulaSeed secondary` (inline-sized), `-TabulaSeed university` (larger). Screenshot routes: `share.sheet`,
`share.import`, `share.import-preview` (all `@secondary`).

iOS version A/B: ________ · Build: xtool / TestFlight ____ · Tester: ________ · Date: ________

---

## H1 — sharing in the app

### Share sheet (Timetable ⋯ › Share Timetable…)

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| H1.1 | A only. Secondary seed → Timetable tab → ⋯ → **Share Timetable…** | Sheet "Share Timetable": QR code on a white card, "Share Link", the toggle "Include open tasks and exams" (off); no Code section (inline link); footer "Anyone with this link or QR code can import the timetable. Nothing is uploaded." | | |
| H1.2 | Zoom into the QR code (screenshot, pinch) | Square modules with sharp edges (no blur), white border around the code in light **and** dark mode | | |
| H1.3 | Point the **iOS Camera app** of B at A's QR | Banner for `https://tabula.simondev.sk/t#1.…`; until H2 is deployed Safari can't load it (expected) | | |
| H1.4 | Share Link → Messages to yourself | The message holds the link and "Here's my timetable in Tabula."; subject/preview uses the timetable name | | |
| H1.5 | Toggle **Include open tasks and exams** on, off | Sheet shows "Preparing the link…" briefly and rebuilds; with many tasks it may switch to the code path | | |
| H1.6 | **[service]** University seed (too big for inline) → Share Timetable… | "Preparing the link…", then the QR (short link), the code `XXXX-XXXX` in large monospaced type, footer "On the other phone, open Settings › Import Timetable…" | | |
| H1.7 | Before H2 is deployed, or Airplane mode: university seed → Share Timetable… | Section "Couldn't create a code" with a plain message ("You're offline…" in Airplane mode, "The share service isn't available right now…" without Airplane) and **Try Again**; no QR for a timetable this large (no fallback); no crash | | |
| H1.8 | Airplane mode on → Try Again → Airplane off → Try Again | Each attempt shows the progress row first; the last one succeeds **[service]** or shows the unavailable message | | |
| H1.9 | Long-press the code (H1.6) | Text can be selected/copied | | |

### Import entry (Settings › Import Timetable…)

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| H1.10 | B: Settings → **Import Timetable…** (below "Add Another Timetable…") | Sheet "Import Timetable": Scan QR Code, Choose Photo of QR Code, Code field, Paste button, Cancel | | |
| H1.11 | **Scan QR Code** (first time) | The iOS camera prompt shows the new purpose text "…a printed timetable or a shared timetable's QR code…" (in the device language) | | |
| H1.12 | Allow → point at A's QR (H1.1) | Scanner closes, "Opening the timetable…", then the import preview | | |
| H1.13 | Scan any non-Tabula QR code (e.g. a website) | Hint changes to "This QR code isn't from Tabula."; scanning continues | | |
| H1.14 | Deny the camera (or Settings › Privacy › Camera › Tabula off) → Scan QR Code | Alert "Camera Access Is Off" with Open Settings / Cancel; Open Settings opens Tabula's page in iOS Settings | | |
| H1.15 | Screenshot A's QR, send it to B → **Choose Photo of QR Code** → pick it | Preview opens. A photo without a code → "No Tabula QR code was found in this photo." | | |
| H1.16 | Code field: type `7kx2` | Hint "4 more characters" (plural correct in sk/cs/pl/uk: "Ešte 4 znaky"); keyboard shows capitals, no autocorrect | | |
| H1.17 | Type `O`, `0`, `1`, `I` or `L` | Red hint "Codes use only letters and digits, never 0, O, 1, I or L."; Find Timetable disabled | | |
| H1.18 | Type 9 characters | "A code has 8 characters." | | |
| H1.19 | **[service]** Type A's code (H1.6) with a dash or spaces → Find Timetable (or Return) | Preview opens | | |
| H1.20 | Valid-looking unknown code → Find Timetable | **[service]** "No timetable was found for this code. Codes expire after 30 days…"; before H2: "The share service isn't available right now." | | |
| H1.21 | Copy A's link (H1.4) → **Paste** | No paste-permission prompt (system PasteButton); preview opens | | |
| H1.22 | Copy any other text (e.g. `https://example.com`) → Paste | Alert "Can't Open This Timetable" — "This isn't a Tabula share link." | | |

### Links (`tabula://`)

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| H1.23 | In Notes on B, type `tabula://import#` + the part after `#` of A's link; tap it | Tabula opens on the import preview (from any tab; an open clean sheet closes first) | | |
| H1.24 | Same while an editor with unsaved changes is open | The editor stays; the preview appears right after Save/Cancel | | |
| H1.25 | **[service]** `tabula://import?code=<CODE>` | Preview of that code's timetable | | |
| H1.26 | `tabula://import?code=0000` and `tabula://import#` | Nothing happens (ignored), no crash | | |
| H1.27 | A widget tap still works (`tabula://open/…`) | Unchanged behaviour (Phase 4 A) | | |

### Import preview and import

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| H1.28 | Preview of A's secondary timetable (H1.12) | Title with emoji, the lesson count ("N lessons"), (tasks/exams rows only when included), subject list in A's order, one section per bell schedule with numbered times; no empty rows | | |
| H1.29 | A timetable with two lessons at the same time | Section "Before you import" with "2 lessons overlap other lessons." (warning icon) | | |
| H1.30 | **Pro / unlimited build:** Add as New Timetable | Sheet closes, Timetable tab shows the imported timetable (now active); the old one is in the title menu; nothing of the old one changed | | |
| H1.31 | **Free build (1 timetable):** preview | "Add as New Timetable" disabled; footnote "Tabula Free holds one timetable, so the shared one can only replace “…”." | | |
| H1.32 | Replace "…" → alert | Title "Replace “…”?", message names what is removed and that a copy goes to Settings › Backup; Replace is red, Cancel present | | |
| H1.33 | Confirm Replace | Imported timetable is active at the old position; old tasks/exams still in Tasks/Exams (unlinked); Settings › Backup › Automatic copies has a new entry (pre-import) | | |
| H1.34 | Restore that automatic copy (Settings › Backup) | The pre-import state comes back | | |
| H1.35 | Fresh install, onboarding step 2 → **Import a Shared Timetable…** → import A's QR | Onboarding ends, the tabs show the imported timetable; school type = the one chosen in step 1 | | |
| H1.36 | Fresh install, open a `tabula://import#…` link before finishing onboarding | The import sheet opens over onboarding; importing finishes onboarding; the sheet does not appear again afterwards | | |
| H1.37 | A link from a newer Tabula (`tabula://import#2.abc`) | "This timetable was shared from a newer version of Tabula. Update the app to open it." | | |
| H1.38 | A damaged link (delete characters in the middle) | "This shared timetable is damaged or incomplete." | | |

### Every screen (share sheet, import, preview, scanner)

| ID | Check | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| H1.39 | Empty states | Timetable with no lessons: share works ("This timetable has no lessons yet." in the preview) | | |
| H1.40 | Long text | A 100-character timetable name wraps in the preview title and alerts; buttons wrap, no truncation of "Replace “…”" | | |
| H1.41 | Dynamic Type AX5 | Code text shrinks to fit one line; QR stays square ≤ 280 pt; bottom buttons stack and stay tappable; the Form scrolls above them | | |
| H1.42 | Dark mode | QR keeps its white card; warning icons in correction red; text contrast fine | | |
| H1.43 | German / Slovak | "Als neuen Stundenplan hinzufügen", "Pridať ako nový rozvrh" fit (wrap, no word-internal breaks) | | |
| H1.44 | Japanese / Chinese | All share strings translated; code field still Latin capitals | | |
| H1.45 | VoiceOver | QR: "QR code for the timetable “…”, image"; code is spelled character by character; scanner hint is read; preview title is a header; Replace announces as a destructive button | | |
| H1.46 | Reduce Motion / Increase Contrast | No animation dependency; Increase Contrast ink/correction variants used | | |

## H2 — share service (Worker, landing page)

The Worker, the landing page and the AASA file are deployed by the human; follow **`docs/SHARING_DEPLOY.md`** (domain,
Cloudflare account, KV namespace, rate limits, `wrangler deploy`) and its checks. After deployment, re-run the rows
marked **[service]** above and add:

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| H2.1 | B without Tabula: open A's inline link in Safari | Landing page with "Open in Tabula" and the store placeholder; no trackers | | |
| H2.2 | B with Tabula: landing page → Open in Tabula | Tabula opens on the import preview (`tabula://import#…` / `?code=`) | | |
| H2.3 | Share 10+ codes within a minute | Eventually "Too many shares in a short time. Wait a minute, then try again." | | |

## QA re-check items (2026-11-01)
| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| H1.Q1 | Fresh install, onboarding: import a shared link | The import finishes onboarding; Settings > Reminders lists the profile's preset rules | | |
| H1.Q2 | During onboarding with the import sheet open, open a second `tabula://import` link | The open sheet swaps to the new timetable; no second sheet, nothing lost | | |
| H1.Q3 | After onboarding: delete every reminder rule, then import a link | No reminder rules come back | | |
