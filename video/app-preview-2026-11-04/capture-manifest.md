# Capture manifest — Tabula App Preview (EN, iPhone)

All footage is `xcrun simctl io <udid> recordVideo --codec=h264` of the real TabulaApp simulator binary, driven by real XCUITest taps (`PreviewCapture/Sources/PreviewCaptureTests.swift`) in `.github/workflows/app-preview-capture.yml` on branch `video/app-preview`. There are no debug fixture routes standing in for flows, no HTML rebuilds of UI and no synthetic system panels. Two views are started at real routes (`timetable.day`, `timetable.tiles`).

## Build and environment
| Field | Value |
|---|---|
| Source | `main` 727cb2a + `video/preview-seed` (ab305af `preview`, cf1110a `previewBlank`) + capture-only UI-test target/workflow. Capture SHAs: **a2c4739** (R3) and **dd4e854** (R5). Only seed files differ between them (QA-verified) |
| Runner | GitHub Actions `xcode-27`, Xcode 27.0 (27A266a), iOS 27.0 runtime, **iPhone 18 Pro Max** simulator (1320×2868), light mode, Large text |
| Build | XcodeGen Debug, ad-hoc "Sign to Run Locally" (App Group entitlement embedded), no Apple account |
| Data | In-memory seeds only (never the owner's data): `preview` (Class 11B) or `previewBlank` (empty Class 11B, for the import); `-AppleLanguages (en) -AppleLocale en_GB`; Europe/London |
| Clock | **Controlled**: seed reference instant Tue 2026-11-10 10:20 GMT; status bar overridden to 10:20. A visual fixture only: it proves no timed delivery |
| Reminders | `-TabulaReminders fake` (default): in-memory clients; nothing reached the notification centre or AlarmKit |
| Runs | R3 https://github.com/simon01920/tabula-app-ios/actions/runs/41748424916 (job concluded *failure* overall on the 60-min cap during S7; the shots used, S1/S4/S5/S8a/S8b, each passed, rc=0) · R4 …/41756161098 (*failure*: S2/S3/S6 failed, S7 partial; nothing from R4 is used) · R5 …/41761857082 (*success*: S2, S2b, S3, S6) |
| Raw files | `video/captures/run-<id>/app-preview-<n>/video-out/<shot>/<shot>.mp4` (git-ignored; VFR h264 1320×2868, with `manifest.json`, `xcodebuild.log`, `xcresult-summary.json`, keyframes). Known manifest quirk: the `seed` field says `preview` for S2/S2b; the `launch` field (used below) is correct (`previewBlank`) |

## Processing (all clips, `video/tools/prep_clips.py`)
- Raw recordings are VFR and their DTS lag PTS by about 93 s. Every read uses `ffmpeg -fflags +igndts` (presentation time). Default ffmpeg picks frames about 93 s early (verified: Home Screen instead of Today at 137 s).
- Trim → constant 30 fps → Lanczos 1320×2868 → 712×1548 (same aspect, 54 %; no crop, no zoom-in, no speed change, no retouch) → H.264 CRF 12. Composited 1:1 on the 886×1920 canvas; dissolves 0.25–0.3 s between clips.

## Clip map (generated from `prep_clips.CLIPS` + each shot's `manifest.json`; in/out = source PTS seconds)
| Clip | Scene | Shot | Run @ SHA | Launch args | In → out | Shows / edit note |
|---|---|---|---|---|---|---|
| c1a_today | 1 | S1 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 60 → 62 | Today (NOW Mathematics, Next Biology), Today tab selected |
| c1b_week | 1 | S1 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 70.3 → 72.3 | Week grid after the real Timetable tap. The ~3 s tap-to-render lag on the CI simulator (67.x-70.08) is cut with a dissolve, not shown |
| c2b_reading | 2 | S2 | 41761857082 @ `dd4e854` | `-TabulaSeed previewBlank -AppleLanguages (en) -AppleLocale en_GB` | 229.6 → 232.1 | Reading Timetable: the photo plus live steps (reading the image, finding the table) |
| c2c_review | 2 | S2 | 41761857082 @ `dd4e854` | `-TabulaSeed previewBlank -AppleLanguages (en) -AppleLocale en_GB` | 234.1 → 235.9 | Check Timetable review: 29 lessons, 9 subjects, 23 need checking, questions, Approve |
| c2d_week | 2 | S2 | 41761857082 @ `dd4e854` | `-TabulaSeed previewBlank -AppleLanguages (en) -AppleLocale en_GB` | 247.4 → 249.1 | The imported week after Approve -> Add as New Timetable (that sheet is skipped by a dissolve) |
| c3a_lesson | 3 | S3 | 41761857082 @ `dd4e854` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 101.3 → 102.9 | Lesson sheet (Wed P1 Mathematics, Room 204, Ms Carter) with its task Finish algebra exercises |
| c3b_task | 3 | S3 | 41761857082 @ `dd4e854` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 110.5 → 113.5 | Task Finish algebra exercises (for the lesson on Wed 11 Nov) -> real tick of Questions 1-10 at 111.82 |
| c4_exams | 4 | S4 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 105.4 → 109.6 | Exams list (Biology quiz in 3 days) -> real tap (107.2) -> exam detail |
| c5a_exam_reminder | 5 | S4 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 120.5 → 122.3 | Edit Exam, Reminders section: Remind me on, 1 day before at 18:00 (opened via Edit; later cancelled) |
| c5b_reminders | 5 | S5 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 143.2 → 146.6 | Settings -> real tap on Reminders (144.8) -> Reminders: per-kind rows, quiet hours, loud alarms |
| c6a_day | 6a | S8a | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB -TabulaScreen timetable.day` | 50 → 53.2 | Day view (time blocks), 10:20 now line on Mathematics |
| c6b_tiles | 6a | S8b | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB -TabulaScreen timetable.tiles` | 56.3 → 60.1 | Tiles view, Mathematics NOW |
| c6c_week | 6b | S1 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 72.4 → 75.9 | Week grid (static hold) under the text-only 'Also in Tabula' mention |
| c7_today | 7 | S1 | 41748424916 @ `a2c4739` | `-TabulaSeed preview -AppleLanguages (en) -AppleLocale en_GB` | 62.5 → 65.7 | Today (static hold) for the close |

## Edits that hide real steps (all dissolves, none implying a function the app lacks)
- **S1:** about 3 s of CI-simulator tab-switch lag (tab highlight about 67 s → grid at 70.08 s) is cut out (Today → week dissolve).
- **S2:** View Options → **Import screen (has the DEBUG row "Use Sample Picture (Debug)")** → PhotosPicker (shows the simulator's stock sample photos) are **not used**. The scene opens on Reading Timetable, with the owner's own photo visible. About 30 s of source (recognition about 6 s, the Approve tap, the "Add as New Timetable" sheet) plays in 4.8 s; the review screen and "23 need checking" stay visible.
- **S3:** the tap from lesson to task (104.8 s) is inside a dissolve; the subtask tick (111.82 s) plays in real time.
- **S4/S5:** the exam reminder is shown inside the real Edit Exam sheet (the test later taps Cancel, not shown).

## Not in the master
- S6 widgets (R5, real store, live clock): the real Home Screen widget with App Group data. Not used: outside the app; owner chose a text-only mention.
- S7 watch (R4): the real watch app in its empty state only; WatchConnectivity data never arrived (cause unverified). Not used.
- S2b (flat sheet image): also read by Vision. Not used.
