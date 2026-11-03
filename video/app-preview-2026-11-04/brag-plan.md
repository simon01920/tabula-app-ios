# Brag Plan: Tabula (App Store App Preview, English)

Run: `/brag --full` (full mode, Hyperframes; Slim not used), 2026-11-04. Brief: `video/01_Tabula_Main_Opus_Hyperframes.md` — it overrides BRAG defaults on duration (29 s), poster (no frame-0 bake), and authenticity (screen captures only).

## What is this app?
Tabula is an iPhone timetable app for school and university students: your week at a glance, set up from a photo, with homework and exams attached to the lessons they belong to.

## The angle
"Your school day, in order." Show the organised result first, then how little work it takes to get there. Clarity → easy setup → control over work → useful reminders → more ways to see the day. Every beat is a real screen recording of the current build; captions only explain what the footage is already doing.

## Hook (0–3 s)
A populated Today screen with the yellow Now marker on Mathematics (Room 204) and Biology next. The caption lands in the first second. No splash and no logo opener.

## Key moments
- A photo of a printed timetable goes through the real picker, the real review screen, and approval → a full week appears.
- Tap Mathematics → its homework "Finish algebra exercises" is right there → one real tick / quick add.
- "Biology quiz" with its countdown and its reminder.

## Outro
Back on the clearest timetable shot, with a small app icon and "Tabula" over it. "Ready for your next lesson." The app stays visible.

## User flow worth showing
Photo → review → approved timetable (centerpiece); lesson → its homework → done.

## Tone
- Preset: `app-store`, leaning `polished`.
- Creative direction: clean, energetic, friendly, confident; exercise-book identity.
- Interpretation: calm cuts and dissolves, stable holds, one caption per scene, no bounce or spin, nothing childish.

## Format: vertical — 886x1920 (App Store "iPhone with Dynamic Island, large display" accepted size)
## Duration: 29.0 s (870 frames at 30 fps)

## Visual identity (from `Packages/TimetableUI/Sources/TimetableUI/Theme/DesignTokens.swift`)
- Background: paper `#FBFAF7` (caption band); app page `#F2F2F7`.
- Accent: royal-blue ink `#2541B2`; highlighter `#FFE04A` (black text only, as in the NowMarker).
- Text: ink `#2541B2` for headlines, `#1C1C1E` for small text, pencil `#6C6C70` for secondary.
- Display font: Inter 700 (OFL, bundled with Hyperframes; close to the app's system face). Body: Inter 400.
- Strongest visual element: the yellow NowMarker on the current lesson; subject colours in the week grid.

## Share copy (draft)
Tabula: your school day, in order. Import your timetable from a photo, keep homework with each lesson, stay ahead of exams.

## Audio direction
- Role: warm bed.
- Music: **owner pick: take D, lo-fi bedroom pop**, 92 BPM (ElevenLabs Music v2.5, flow `mM2SxE9irFJvT8fUTrq0`, generation `M320qbvpgeY4DT9E3e27`). Batch 1 (A/B, "bright electronic pop") was rejected as generic elevator/tutorial music; take C (indie-electronic) was not chosen.
- Treatment: Rhodes and guitar from 0 s; drums enter at about 5.2 s (first detected beat 5.235 s), inside the import scene; soft resolved ending; 0.8 s fade-out so the end doesn't click. Normalise to about −16 LUFS in the conform (the raw file is −18.6 LUFS).
- Music cue guidance (`audio/beats-D.json`, `hyperframes beats`, 33 beats, period about 0.65 s): snap scene seams to the nearest beats 7.785 / 11.765 / 15.675 / 20.255 / 22.845 / 26.105 s (frames 234 / 353 / 470 / 608 / 685 / 783). Beat-lock the import result reveal to the drum entry (5.235 s) if the footage allows.
- Audio-reactive: none or very subtle. Over real UI, nothing should pulse.
- SFX posture: sparse. At most a soft paper swish on the 2–3 editorial transitions and a quiet accent on the import result. No alarm-like sounds, bells or ticking.
- Restraint rule: the edit must work fully muted; audio never implies an app sound or alarm delivery.

## Storyboard (master; frames end-exclusive at 30 fps)

### Scene 1 — Today — 0–3 s (0–90)
Today screen with Now = Mathematics, Next = Biology; natural tap to the week if the footage allows.
Caption: **Your school day, in order.** ("in order" on the highlighter)
Sequential/interaction: real tap recorded; its simulator lag is cut with a dissolve. Transition: dissolve → 2.

### Scene 2 — Photo import — 3–8 s (90–240)
Reading Timetable (own photo, live recognition steps) → Check Timetable review (held; "23 need checking") → imported week. The picker and Import screen are not shown (simulator stock photos; DEBUG row).
Caption: **Import your timetable from a photo.** No "AI" in our captions. The app's own footer "Uses Apple Intelligence on this iPhone" is visible, because the CI simulator reported Apple Intelligence available. Whether the FM normaliser actually ran is **not verified** (see feature-evidence.md).
Audio-coupled: quiet accent on the result. Transition: dissolve → 3.

### Scene 3 — Lesson → homework — 8–12 s (240–360)
Tap Mathematics → linked task → one real tick or quick add.
Caption: **Keep homework with each lesson.**

### Scene 4 — Exams — 12–16 s (360–480)
Exams list → "Biology quiz" countdown → its reminder section.
Caption: **Stay ahead of tasks and exams.**

### Scene 5 — Reminders — 16–20 s (480–600)
Exam reminder in Edit Exam → Settings › Reminders: the real per-kind notification rows and the "Allow loud alarms" option (in-app controls only; no Time Sensitive row: hidden without the paid entitlement).
Caption: **Reminders. Notifications. Alarms.**

### Scene 6 — More views — 20–26 s (600–780)
6a: real day → tiles views, **Week, day or tiles.** 6b: real week grid with a text-only mention **Also in Tabula: widgets, Live Activities and Apple Watch.** Owner decision: there's no footage of those surfaces (Apple: previews "must show only content within the app itself") and no marketing alternate.

### Scene 7 — Close — 26–29 s (780–870)
Strongest timetable shot. Small supplied AppIcon + **Tabula** / **Ready for your next lesson.** Held for at least 2 s; music resolves.

**Music mood for this video:** upbeat, quietly confident.
**Audio summary:** one friendly instrumental bed with a lift at the import, steady through the work scenes, and a clean resolve under the closing title.
