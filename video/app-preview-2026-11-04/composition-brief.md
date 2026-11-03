# Hyperframes Composition Brief: Tabula — App Store App Preview (EN)

## Objective
A 29-second App Store App Preview for Tabula built from real simulator screen recordings, with explanatory captions and an instrumental bed. Not a launch-film recreation: no HTML rebuild of the app.

## Output
- Composition: `video/app-preview-2026-11-04/composition/`
- Render: `composition/renders/tabula-preview-v3.mp4` (delivery) → `video/tools/conform.py` → master `../tabula-app-preview-en-iphone-29s.mp4`
- Format: vertical 886x1920, 30 fps CFR, 29.0 s (870 frames)

## Source material
- Footage: `assets/clips/*.mp4` = trimmed copies of `video/captures/run-<id>/` (provenance: `capture-manifest.md`). The native capture is 1320x2868, shown at 712x1547 (54%, same aspect, no crop).
- Product name: Tabula. Icon: `Resources/AppIcon.png` (supplied, unmodified).
- Copy (verbatim, each grounded in `feature-evidence.md`): "Your school day, in order." · "Import your timetable from a photo." · "Keep homework with each lesson." · "Stay ahead of tasks and exams." · "Reminders. Notifications. Alarms." · "Week, day or tiles." · "Also in Tabula: / widgets, Live Activities / and Apple Watch." (text-only mention, owner decision) · "Tabula" / "Ready for your next lesson."

## Creative direction
- Tone: app-store, leaning polished. Clean, friendly, confident; never childish.
- Hook: the populated Today screen with the yellow Now marker; caption in the first second.
- Avoid: generic SaaS language; abstract filler; device mockups, hands, floating phones; fake taps; zoom-ins that change how the UI looks; flashy transitions.

## Visual identity (DesignTokens.swift)
- Paper ground `#FBFAF7` with faint ink rules (`rgba(37,65,178,0.12)`, 48 px pitch), never over the screen.
- Ink `#2541B2` headlines, highlighter `#FFE04A` as a marker stroke under one phrase; small text `#1C1C1E`.
- Inter 700 (OFL, bundled): captions 62 px (s5 list and s6b at 56–58 / 44 px), 2 lines max (s5: a 3-item list), centred in the 332 px band above the screen.

## Storyboard
See `brag-plan.md` / `storyboard.md`. Scene slots: 0–3, 3–8, 8–12, 12–16, 16–20, 20–26, 26–29 s.

## Audio
- Role: warm bed. ElevenLabs Music v2.5 take D (lo-fi bedroom pop, 92 BPM, owner's pick); seams snapped to detected beats 7.785 / 11.765 / 15.675 / 20.255 / 22.845 / 26.105 s; import review beat-locked to the drum entry 5.235 s.
- Music file: `assets/music/tabula-bed.mp3` = generation `M320qbvpgeY4DT9E3e27` (git-ignored: Free-plan output). `data-volume` 0.85, fade-out 0.8 s.
- SFX: none by default. Add at most a soft paper swish on 1–2 seams after the picture is locked, and only if it helps muted-first viewing.
- Audio-reactive: none (real UI must not pulse).

## Hyperframes instructions
Root holds the paper, the screen frame with the timed `<video muted>` clips (0.3 s dissolves) and the music; one caption sub-composition per scene (`compositions/s1..s7.html`). Gate: `npx hyperframes check` with zero errors and real contrast coverage. Then snapshot every scene midpoint and seam. Render locally only; the hosted MCP compose/render is disabled for CLI clients.
