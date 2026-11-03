# Handoff — Tabula App Preview (EN, iPhone)

**Not uploaded, not submitted.** App Store Connect needs the paid Apple Developer account (deferred).

## Files
| File | What |
|---|---|
| `tabula-app-preview-en-iphone-29s.mp4` | The master: 886×1920, 29.000 s, 870 frames, CFR 30, H.264 High@4.0 at about 11 Mbps, AAC-LC 256 kbps, 48 kHz stereo, BT.709 SDR, fast start, 40.7 MB |
| `poster.png` | Poster = frame **75 (2.50 s)** of the master, 886×1920 |
| `composition/` | Editable Hyperframes project (source of truth) |
| `storyboard.md` · `capture-manifest.md` · `feature-evidence.md` · `qa-report.md` · `licenses.md` · `brag-plan.md` · `composition-brief.md` | Production record |
| `look-test-0-3s.mp4` | The single-workflow look test (draft) |

## Intended upload slot
App Store Connect → the app → the iOS version → **App Previews and Screenshots** → localization **English (U.K.)**, because the footage uses en_GB formats: 24-hour clock, "Tue 10 Nov", "Colours". **English (U.S.)** works too if you accept UK date formats → **iPhone 6.9" Display** (the "iPhone with Dynamic Island, large display" family; accepted size 886×1920). It covers iPhone 16 Pro Max; the medium Dynamic Island family accepts the same 886×1920. Poster frame: pick **00:02.50** in the uploader (the PNG doesn't set it; Apple's default is 5 s). Apple: changing the poster of an approved preview needs a new preview submission. There is no separate watchOS preview slot, and none is needed.

## Repeatable build
```bash
python3 video/tools/make_import_photo.py          # import prop (already in video/assets/)
python3 video/tools/prep_clips.py                 # clips from video/captures/ (git-ignored raw recordings)
cd video/app-preview-2026-11-04/composition && npx hyperframes check && npx hyperframes render --quality delivery -o renders/tabula-preview-v3.mp4
cd .. && python3 ../tools/conform.py composition/renders/tabula-preview-v3.mp4 tabula-app-preview-en-iphone-29s.mp4
bash ../tools/encoding_evidence.sh tabula-app-preview-en-iphone-29s.mp4 > qa/encoding-evidence.txt
ffmpeg -i tabula-app-preview-en-iphone-29s.mp4 -vf "select='eq(n\,75)'" -frames:v 1 poster.png
```
Re-capture: push to branch `video/app-preview` (workflow `app-preview-capture.yml`, shots `S1…S8`), then download the artifacts into `video/captures/run-<id>/` and update the run paths in `prep_clips.py`.

## Tools and modes used
- `/brag --full`, BRAG 0.5.0 (full, Hyperframes path; Slim not used). BRAG's frame-0 poster bake was deliberately not applied (brief).
- Hyperframes CLI 0.9.9 (local render). The HeyGen Hyperframes MCP connector was reachable but read-only from Claude Code (compose/render disabled for CLI clients): no hosted project, no job IDs.
- ElevenLabs connector: flow `mM2SxE9irFJvT8fUTrq0`, 4 music generations (1,740 credits, Free plan), no SFX. WaveSpeed: not used.
- Capture: GitHub Actions `xcode-27`, Xcode 27.0, iOS 27.0, iPhone 18 Pro Max simulator, runs 41748424916 / 41756161098 / 41761857082.
- FFmpeg 9.0.2, Python 3.14 + Pillow.

## Look-test findings (single workflow)
1. The raw S1 tap exposed about 3 s of CI-simulator tab lag → dissolve Today → week.
2. The 3-line "Reminders. Notifications. Alarms." at 62 px was crowded → 56 px list.
3. Raw `recordVideo` files mis-time in ffmpeg (DTS about 93 s behind PTS) → `-fflags +igndts` everywhere.
4. x264 ABR undershot to about 2 Mbps on static UI → CBR 11 Mbps with HRD filler to meet Apple's 10–12 Mbps target.

QA fixes after v1 (see `qa-report.md`): picker shot removed (stock photos), plain-text mention instead of chips, "Week, day or tiles." now over day → tiles, reading shot recut so its steps visibly advance.

## Owner steps remaining
1. **Music rights:** upgrade ElevenLabs to Creator before publishing (terms §1.5 moves existing output to the new plan). Otherwise credit "Created in collaboration with ElevenLabs" (Free-plan requirement), e.g. in the App Store description.
2. Paid Apple Developer account → app record → upload with the slot and poster above. Watch App Store Connect's processing result for the file.
3. Decide on the capture branch `video/app-preview` (seed + UI-test target + workflow): merge after QA, or keep it as a capture-only branch.
4. Resolve the spec drift: `docs/specs/MONETIZATION.md` still has prices and a paywall plan, against the P9-3 "no paywall" decision.
5. Before release, verify on device what the video shows or names: import from a real photo, reminders and alarms delivery, and that widgets, Live Activities and the Watch app ship in the build you submit (they're named in the video).
6. **Apple Intelligence footer (QA Q1):** the import footage shows the app's own line "Uses Apple Intelligence on this iPhone. Nothing is uploaded." The captions don't claim AI, but nobody verified that the FM normaliser actually ran in the capture. Accept it, or ask for a re-capture where Apple Intelligence is unavailable.
7. Before merging `video/app-preview`: run `scripts/validate.sh`, the xtool build and `ios.yml` on it; decide on the workflow's push trigger and the 5.1 MB `video/assets/import-source.png`.
8. App Review can't be guaranteed by any export. If a reviewer objects to the text mention of widgets / Live Activities / Apple Watch, drop scene 6b (`compositions/s6b.html`) and extend 6a.
