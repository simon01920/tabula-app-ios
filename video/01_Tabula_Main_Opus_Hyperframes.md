# Tabula App Preview — Recommended: Opus 5.5 + Hyperframes

Prepared 3 November 2026. This is a production prompt, not a claim that the app or video has already passed review.

**Recommended first choice: Opus 5.5 + full BRAG + Hyperframes.** This decision is made for this project. Claude should execute it, not run a workflow-selection exercise. Use **`/brag --full`** explicitly: ordinary `/brag` currently dispatches Opus 5.5 to Slim. [S5]

**Why this is the main prompt:** this job needs exact 29-second timing, authentic captured footage, readable captions, repeatable revisions and an inspectable export. Hyperframes supplies a defined composition/rendering workflow and a local editable project; its CLI includes timeline editing, frame inspection and validation. Slim leaves implementation to Opus and available tools. Both share BRAG's creative principles; the additional production structure is why I recommend Hyperframes here. This is a research-based fit assessment, not a measured visual-quality win. No controlled comparison on Tabula footage was performed. [S7, S9, S13, S22–S24]

| Decision factor | Main: Opus 5.5 + Hyperframes | Alternative: Opus 5.5 + BRAG Slim |
| --- | --- | --- |
| Composition and revision | Defined project, timeline and preview tools | Opus builds the editing implementation using available tools |
| Verification | Built-in project checks plus independent final-file inspection | Opus must implement equivalent checks in its chosen pipeline |
| Creative direction | BRAG story and Opus judgment | Same creative responsibility; greater implementation freedom |
| Fit for this brief | **Recommended:** more production structure for the precise deliverable | Viable standalone alternative when deliberately choosing fewer framework dependencies |

**How to use:** Put this file in the Tabula repository. In Claude Code with Opus 5.5, run:

```text
/brag --full Read Tabula_App_Preview_Claude_Prompt.md and execute its production brief. Use full BRAG with Hyperframes. Target 29 seconds, English captions, instrumental music, no voiceover, and authentic captures of the current Tabula build.
```

Use this file alone for the recommended run. `Tabula_App_Preview_Alternative_Opus_Only.md` is a separate replacement prompt for a deliberate Opus-only run; do not feed both execution briefs to the same run.

---

## Production brief — instructions to Claude

You are my creative director, editor, and engineering orchestrator. Create a polished **English App Store App Preview for Tabula**, using **Opus 5.5, full BRAG and Hyperframes**. This is the fixed production workflow. Use `/brag --full`; do not dispatch to Slim or compare engines. Produce the finished video and its reproducible production assets. Continue through capture, composition, render, and review; do not stop with a storyboard when execution is possible.

### 1. Confirmed creative decisions

- **Brand:** Tabula. Use the supplied blue-and-yellow `AppIcon.png`; this name and icon are confirmed for this brief. Locate the matching asset in the repository or supplied files. Do not redesign it.
- **Treatment:** clean, energetic, friendly, and confident. English captions and upbeat instrumental music. **No voiceover.**
- **Audio tools:** I will provide an ElevenLabs API key through a secure local setup. Prefer ElevenLabs for the instrumental soundtrack and restrained sound effects. I also have Suno; use it as an optional music alternative, not a required second service.
- **Length:** target **29.0 seconds**, leaving a margin below Apple's maximum. This explicitly overrides BRAG's shorter default.
- **Primary destination:** the iPhone App Store product page; portrait orientation. Match the intended screenshot orientation and display family.
- **Audience:** high school and university students, while remaining approachable for middle/primary school students. Use “For school and university” if an audience line is useful. Avoid a childish aesthetic.
- **Main promise:** a clear school day, less timetable setup, and assignments and exams that stay connected to lessons.
- **Priority:** timetable clarity and ease of use → photo import → lesson-linked homework/tasks → exams, reminders, notifications and alarms → widgets, Live Activities and Apple Watch.
- **Capture preference:** recover my previous **GitHub Actions macOS simulator + Python/script workflow**. I have used it with you before. Consult your available project memory and earlier working instructions, then verify them against the repository and successful workflow runs. Use existing GitHub authentication. Do not start by asking me to record everything manually.

### 2. Read the project and establish what actually ships

Read the current `CLAUDE.md` and applicable agent instructions. Use the repository's existing specialist agents and QA process where appropriate. You own the creative decisions and final integration. Keep each delegated task narrow and require evidence.

Start with:

- `docs/ENVIRONMENT.md`, `docs/RISKS.md`, relevant `docs/gates/`, `docs/checklists/`, and any current release notes.
- `docs/specs/PRODUCT.md`, `AI_IMPORT.md`, `NOTIFICATIONS.md`, `MONETIZATION.md`, `UX_OVERHAUL_PLAN.md`, and relevant Phase 4/5/9 plans when present.
- `.github/workflows/ui-screenshots.yml`, `.github/workflows/ios.yml`, `project.yml`, `xtool.yml`, `scripts/`, the app's route registry, seed fixtures, localization catalog, widget targets and watch targets.
- The supplied phase reports, `UX_DEVICE.md`, `PHASE9_DEVICE.md`, `TabulaApp.swift`, `Package.swift`, and `tabula-kit.zip` if the corresponding material is missing locally. The kit is an earlier specification snapshot, not the current implementation.

Record the source commit, working-tree state, build configuration, enabled capabilities and intended release feature set. Do not switch branches, overwrite work or revert changes to obtain an older prettier UI. If current code contradicts a spec, report the discrepancy and avoid the disputed claim until resolved.

Create a compact **feature evidence matrix** with: requested benefit; current implementation; actual runtime evidence; release availability/entitlement; planned shot; allowed caption; missing evidence. Distinguish planned, compiled, rendered, exercised, and physically verified behavior. A screenshot demonstrates appearance, not delivery or synchronization reliability.

The supplied reports establish these leads; verify their current status:

| Feature | Useful evidence from the supplied material | Production implication |
| --- | --- | --- |
| Timetable and Today | Color-coded lessons; grid, time-block/day/tile views; A/B rotations; room and change information; Now & Next; linked task/exam badges | Lead with a populated, readable current timetable and one natural interaction. |
| Tasks and exams | Lesson-linked homework, quick entry, subtasks, repeat rules, next-lesson due dates; upcoming exams and countdowns | Show a task connected to a lesson and a clear upcoming exam. Do not spend the scene filling a long form. |
| Reminders and alarms | Standard/Time Sensitive notifications and user-selected AlarmKit alarms; capabilities differ by build path | Show real supported settings and behavior. Never promise guaranteed delivery, “never miss an exam,” or universal Focus/silent-mode bypass. |
| Photo/PDF import | Vision recognition, deterministic parsing, editable review, approval and import; conditional Foundation Models normalization | Demonstrate picture → review → actual timetable. “AI-assisted” needs evidence that the AI path really ran. |
| Import limits | Phase 9 says the downloadable Tier B model is UI-only and disabled; Foundation Models has device/language limits | Do not advertise an available model download, perfect recognition or universal AI support. Prefer “Import your timetable from a photo” when AI is unavailable. |
| Watch | Now & Next, today's/tomorrow's lessons and complications; Phase 5 describes read-only v1 | No Watch task completion or editing unless later implemented. An old empty-state screenshot does not prove the populated app or sync. |
| Widgets / Live Activities | Shared schedule/task/exam presentation; some interactive controls depend on Xcode-generated App Intents metadata | Capture the actual shipped extension. Do not infer functionality from the local xtool build or a debug gallery. |
| Monetization | Older specs assign Pro features; Phase 9 records the owner's later decision that most features are free and paywall work is deferred | Resolve against current release intent. Neither a debug all-access tier nor the old price table settles the launch offer. |
| Additional breadth | Sharing, QR, export, backup and iCloud have implementation reports with their own limits | Secondary possibilities only. Do not cram every feature into this cut or advertise undeployed services. |

Use the attached UX direction: an exercise-book identity, royal blue ink (`#2541B2` in the supplied light-mode tokens), restrained yellow highlighting, clear subject colors, and the app's NowMarker. Inspect current tokens before using them. The icon's blue gradient is not automatically the UI tint.

### 3. Load the selected workflow: full BRAG + Hyperframes

Read the installed full BRAG skill and its composition, audio and delivery references. Invoke **`/brag --full`** and verify that full mode actually loaded. Read the applicable Hyperframes domain skills, especially composition/animation, CLI and media guidance. BRAG owns the creative brief; Hyperframes owns the composition and rendering implementation. Follow this brief over generic defaults: 29 seconds, authentic app recordings, no voiceover, no fabricated UI and no one-frame poster flash. Do not restart a generic creative interview. [S5–S8, S22–S24]

**Use a local editable Hyperframes project as the production source.** This provides the project files and direct debugging needed for precise edits. Verify installed commands and dependencies; the official local setup specifies Node.js 22+ and FFmpeg. Keep source footage as media layers; HTML/CSS is for composition and explanatory overlays, never a reimplementation of the native app. [S7–S9]

Inspect whether the owner's **Hyperframes MCP connector** is exposed and authenticated in this Claude Code session. A connection in Claude's web app does not establish CLI availability. The documented production endpoint is `https://mcp.heygen.com/mcp/hyperframes/`. Discover actual schemas, asset inputs, dimensions and export capabilities. Use it where it supports this brief and preserves the editable production source. If hosted source export or exact canvas control is unavailable, complete the composition/render locally with Hyperframes. That is the same selected engine, not a switch to Slim. Do not invent tool names or claim local checks were run on hosted output. [S9]

Send only approved media and the concise composition brief through any hosted handoff, not the whole repository. Verify asset loading, retain returned identifiers and download any output for inspection. Prefer local execution when a connector adds no useful capability.

Make one representative 3–5-second look test using actual timetable/import footage **within this selected workflow**. Inspect it at phone size for legibility, pacing and clean motion, fix defects, then extend the composition. Do not render two competing workflows or ask me to choose between them.

Use current documented lint/check, snapshot, preview and render commands. Inspect validation coverage as well as errors; zero sampled frames is not a passed visual check. Automated audits do not establish readability of text embedded in screen recordings, so manually inspect those. Final encoding and audio require independent file checks. [S23–S24]

If a real environment blocker remains, report the exact failed step and continue independent capture/storyboard/audio work. Do not silently switch to Slim; the separate alternative prompt is available if I later request that workflow.

**Higgsfield/Katana is research for later only.** No subscription is available for this job. Do not install, connect or generate with it. Use the separate future-tools research as background, not as an additional production dependency.

Use existing authorized resources without buying services, upgrading plans, incurring unapproved overages or changing account/certificate settings. Install only the relevant official production dependencies if needed and permitted by repository instructions. Ask a focused question only for a real missing authorization or capability.

### 4. Apply Apple's rules before stylistic defaults

Refresh the official sources below at execution time and record the date. Separate Apple's explicit requirements from conservative editorial choices.

**Content rules:** App Review §2.3.4 limits previews to video screen captures of the app, with explanatory overlays/narration allowed. Metadata must represent the actual product; featured purchases need disclosure. Use fictional personal information and licensed material. Metadata must suit all audiences; “For Kids”/“For Children” terminology is reserved for the Kids Category. [S1]

**Creative guidance:** keep the real UI prominent, use simple transitions, avoid misleading navigation, and make captions legible without audio. Apple recommends native-resolution capture rather than zoomed views. Avoid dated promotional copy and specific prices. Disclose applicable purchase, subscription or login requirements. [S2]

**Our editorial implementation:** no stock students, filming hands, device mockups, floating phone renders, AI-generated interface, fake tap results, awards, external URLs, download badges, lengthy logo opener or abstract feature cards replacing the app. Overlays explain the interaction underneath. Collect real screenshots for planning/posters, but build the finished preview primarily from actual screen recordings, not a slideshow animated to imply live interaction.

**Special review question:** Home/Lock Screen widgets, notifications, alarm surfaces, Live Activities and watchOS footage extend beyond the iPhone app window. The general sources do not expressly resolve every proposed composition. Do not claim blanket approval or invent a standalone watchOS video upload slot. Find current Apple guidance relevant to the actual shots and document your judgment. [S1, S4]

Attempt to capture all requested surfaces. If their inclusion in the App Store master remains uncertain, use genuine in-app controls/presentation where available and truthful, verified captions. Do not create a fake settings screen to make the footage qualify. Preserve the extra footage in a clearly labeled **optional marketing alternate**, with a shot-replacement map. Tell me exactly which requested features moved out of the master and why; do not quietly omit them. No export can guarantee Apple's review outcome.

### 5. Recover and extend the existing capture workflow

Known environment: Windows 11 + WSL2, local iOS builds via xtool, and cloud macOS/XcodeGen builds. No local Xcode or iOS Simulator. The repository location in the supplied instructions is `/mnt/c/Users/simon/Documents/Claude Code/school_timetable`; verify it. The supplied GitHub run links point to `simon01920/tabula-app-ios`; verify the actual remote.

**Recover before rebuilding:**

1. Inspect project memory, `docs/ENVIRONMENT.md`, workflows, scripts, git history and successful capture runs. Search for `simctl`, `recordVideo`, `screenshot`, `TabulaSeed`, `TabulaScreen`, `TabulaNow`, `TabulaTimeZone`, `ui-screenshots`, artifact handling and Python helpers. Read matching files; do not guess their names or arguments.
2. Historical evidence: Phase 3 names `ui-screenshots.yml`; Phase 5 names Watch screenshot runs `41122957955` and `41124975905`; Phase 9 names runs `41659680319` and `41665404310`. These are discovery leads, not current capture assets. Artifacts may have expired.
3. Find the scripts you previously used for downloading, inspecting and assembling simulator captures. Reuse them where sound. If memory is unavailable, say so and reconstruct the workflow from code and logs instead of claiming to remember it.
4. Confirm the target SHA is present on the runner. Discover installed Xcode versions, simulator runtimes, device IDs and schemes. Use a suitable current public runtime matching the intended release; do not choose a beta merely because an old report used it.
5. Start with one short smoke capture. Extend the existing workflow to record reproducible interactions where it currently produces only PNGs. Use the runner's documented simulator recording commands and the repo's automation/test harness; verify their help on that runner.
6. Await UI/data readiness, record, stop gracefully and verify a decodable non-empty video. A successful job with a blank or empty-state image is a failed capture. Download artifacts with the existing GitHub CLI/authentication and visually inspect them locally.

Batch shots into a small number of macOS runs, set timeouts, retain failure logs, and avoid repeatedly rebuilding unchanged code. Scope any new workflow to manual capture and least-required permissions; do not modify release deployment behavior. Do not print authentication tokens.

**Authenticity and demo data:**

- Capture the actual app binary built from the chosen code. Do not rebuild the UI in HTML, Figma, image generation or another framework.
- Reuse isolated seeded stores and launch arguments where supported. Current source determines their semantics. Never replace my live timetable to stage footage.
- The supplied UX checklist describes a Developer demo-data action that backs up and replaces data. Prefer a disposable simulator and isolated fixture instead of exercising this against personal data.
- Set UI language, subject names, tasks, room labels, notes and sample timetable image to **English**. Older screenshots used Slovak sample content under English UI; do not repeat that mismatch.
- Use one coherent fictional dataset: Mathematics, English, Biology and History; readable room names; “Finish algebra exercises”; “Biology quiz”; due times relative to the captured day. Match the same lesson across timetable, task, reminder and Watch.
- Keep dates/countdowns internally consistent. Frozen clocks may support visual fixtures but cannot prove real timed alarm delivery. Record any controlled-clock use in the evidence manifest.
- Debug launch routes may navigate or seed real production views. Exclude debug labels, synthetic system panels and test-only feature implementations from final footage.
- Preserve original captures with SHA, run URL, configuration, runtime, device, seed, locale, capture method and time. Record trims, speed changes and rescaling separately.

**Import shot:** create a clean fictional English timetable image, put it through the app's genuine picker and recognition/review pipeline, then approve and show the saved timetable. Simulator tooling may be able to supply the photo; discover the supported method. The `import.processing` and `import.review` routes in the supplied checklist are debug fixtures, so they alone do not prove recognition. Do not present precomputed results as a successful live AI import. If processing is trimmed, use an obvious edit; do not imply an instantaneous or error-free process. Keep a visible review step.

**Watch shot:** inspect the existing macOS watch build/capture path. Attempt a compatible paired iPhone/watchOS simulator setup and populate the real watch app. Verify its cache/WatchConnectivity behavior. If the simulator cannot sync, an isolated supported snapshot seed can demonstrate the real read-only UI, but label that method in production evidence and make no sync-speed claim. Never paste an iPhone view into a Watch silhouette. Do not assume xtool builds watchOS. If native watch video capture is unsupported, preserve authentic screenshots for the alternate/review and explain the limitation rather than inventing watch interactions.

**Widgets, Live Activities and alerts:** try the real installed extensions and actual scheduling APIs. A debug component gallery proves only rendering. Simulator inability to exercise hardware-dependent behavior should narrow the claim, not lead to a fabricated notification or alarm. Show notification and alarm controls separately if that is the truthful available proof. Do not add a fake alarm sound over a settings screen to suggest delivery.

Ask for footage only after inspecting and attempting the available automated route. If blocked, identify the exact shot, script/workflow tried, error, and smallest missing input while continuing independent editing work.

### 6. Creative concept and 29-second storyboard

**Concept: “Your school day, in order.”** Show the organized result first, then how little work it takes to get there. The emotional progression is clarity → easy setup → control over work → useful reminders → access at a glance.

The following is a starting edit, not permission to invent missing features. Preserve the duration and hierarchy while improving it around real captured material. Frame ranges are end-exclusive at 30 fps; total **870 frames**.

| Time / frames | Picture and action | English overlay | Purpose |
| --- | --- | --- | --- |
| 0–3 s / 0–90 | Open on a populated timetable/Today screen, with one clear Now/Next focus and a natural transition to the week if useful. | **Your school day, in order.** | Immediate product and benefit; no splash-screen delay. |
| 3–8 s / 90–240 | Select the timetable picture → genuine review → approved timetable. Preserve the connection between the source and result. | **Import your timetable from a photo.** | Distinctive ease-of-setup moment. Use “AI-assisted timetable import” only when verified. |
| 8–12 s / 240–360 | Open a lesson → its homework/tasks → one quick add or completion, using real interaction. | **Keep homework with each lesson.** | Show useful simplicity, not a list of capabilities. |
| 12–16 s / 360–480 | Upcoming exam card and its reminder configuration, or a genuine task/exam reminder surface if justified. | **Stay ahead of tasks and exams.** | Make dates, course and reminder connection understandable. |
| 16–20 s / 480–600 | Show the current app's notification/reminder options and user-selected alarm option; genuine delivery footage only if available and suitable. | **Reminders. Notifications. Alarms.** | Distinguish the three without promising unconditional delivery. |
| 20–23 s / 600–690 | One readable widget shot and one Live Activity shot, approximately 1.5 s each, subject to evidence/review checks. | **Widgets & Live Activities** | Brief supporting breadth; keep this label stable across both shots. |
| 23–26 s / 690–780 | Populated real watchOS Now/Next or today's lessons, subject to evidence/review checks. | **Your timetable. On Apple Watch.** | Show the companion app's actual read-only value. |
| 26–29 s / 780–870 | Return to the strongest timetable/Today shot. Small supplied icon/name overlay; keep the app visible. | **Tabula** / **Ready for your next lesson.** | Memorable product close; no web-style button. |

For a conservative iPhone-only master, replace an unresolved ecosystem shot with a real university time-block view, a useful schedule change, or an accessible elementary-style view. Use “For school and university” where truthful. Put the authentic ecosystem sequence in the alternate, not a pretend compliant composition. If a fallback needs more reading time, simplify the overlay or reallocate seconds; do not add time past the ceiling.

Additional features such as QR sharing or export may replace a weaker secondary shot only when demonstrated and readable. The main cut does not need every implemented capability. Do not flash five tiny feature names just to claim coverage.

### 7. Editing, design and sound

Apply BRAG's product-specific storytelling and readable pacing, plus the general scripting/product-video guidance in [S6, S10–S12]. Apple's constraints govern the master whenever a generic promotional technique conflicts.

- Let the viewer identify Tabula's purpose in the opening seconds. Tie every caption to visible evidence; turn feature names into student benefits where possible.
- Keep the timetable large enough to read on a phone. Preserve subject names, room details and the controls needed to understand the action. Do not blur or cover evidence with captions.
- Use one restrained overlay system inspired by the actual app: ink-blue typography and a small yellow highlight, with a clean neutral backing only when contrast needs it. Maintain a clear separation between editorial captions and app controls.
- Start with roughly 48–64 px headline text on the proposed portrait canvas, then judge the actual phone-size render. Use one short thought per scene, generally no more than two lines. These are editorial starting values, not Apple requirements.
- Short captions should settle long enough to read comfortably; aim for at least 1.5–2 seconds, longer for a sentence. Use quick entries and stable holds. Never accelerate reading to fit another feature.
- Favor clean cuts and restrained dissolves. Use real app transitions where possible. Avoid camera spins, bounce-heavy movement, ornamental 3D, strobe effects and magnification that makes the interface look different.
- Show a small tap indicator only when it explains a recorded action. Never use it to suggest a control worked when it did not.
- Use a single unobtrusive, upbeat instrumental bed. The edit must work fully muted. No vocal samples, school-bell gimmicks or exaggerated alarm SFX.
- Verify soundtrack, font and sound-effect rights for worldwide promotional distribution. BRAG's README credits bundled music under CC BY 4.0; a permissive code license does not remove a track's attribution conditions. Prefer an appropriately licensed no-attribution track if a clean valid credit placement is unavailable. Keep the license evidence. [S5]
- As an internal mix target, aim around −16 LUFS integrated with peaks at or below −1 dBTP; this is an editorial target, not an Apple specification. Fade naturally and prevent abrupt end clicks.

#### ElevenLabs-first audio workflow

Use an existing `ELEVENLABS_API_KEY` environment variable or the project's approved secret mechanism. Verify presence without printing the value. Never place it in the prompt, HTML composition, repository, render metadata, public asset URL or Hyperframes brief. If absent, ask me to configure it locally; continue work on the silent edit meanwhile.

Inspect the current ElevenLabs API and account capabilities before generating. The documented endpoints are `/v1/music` for composition and `/v1/sound-generation` for effects. Choose an explicitly supported current model and permitted high-quality output format, rather than relying on an old default. For prompt-based music, use the documented instrumental-only control and approximately 29,000 ms duration; composition-plan requests use their own supported schema. [S14–S16]

Check existing credits, applicable commercial/advertising rights and any API-specific or model-specific terms. An API key alone does not establish those rights. Confirm that this particular soundtrack can accompany an App Store promotional video; if official summaries conflict, use the controlling terms or request clarification. Use included/authorized credits for a small initial batch: at most two music candidates and three short effects. Ask before exceeding that batch or incurring overages. Save successful outputs and generation IDs; avoid duplicate charges from blind retries. [S17–S19]

**Starting music direction — adapt to the actual edit:**

> An original 29-second instrumental for Tabula, a clean and friendly student timetable app. Bright, focused, quietly confident electronic pop, approximately 116–122 BPM. Soft rounded percussion, warm bass, a light plucked motif, restrained keyboard texture. An immediate clean opening, gentle lift during the photo-import reveal, steady momentum under homework and reminders, and a satisfying resolved ending by 29 seconds. Spacious enough for readable app demonstrations. No vocals, spoken words, famous melodies, artist imitation, oversized cinematic impacts, ticking clocks or school bells.

Generate only effects that improve the edit: a soft paper-like swish for an editorial transition, a restrained tonal accent for the import result, or a gentle closing accent. Keep them sparse and quiet. Clearly editorial accents must not sound like features the app does not have. Prefer authentic recorded UI audio when demonstrating an actual app sound. Do not synthesize an alarm to imply successful AlarmKit delivery.

Audition the available candidates against the real footage before choosing. Align useful cuts to the music where practical, but preserve readable holds and natural interactions. Measure generated audio duration, trim/fade musically, and conform the final mix to the export contract. Supply only rendered audio files to the selected video renderer through its supported asset mechanism.

**Optional Suno route:** if a better-suited track already exists, or ElevenLabs cannot supply usable music, use an owner-provided lawful download or an officially supported authorized integration. Do not assume an unofficial “Suno API” is provided by Suno. Verify the track's generation/account history, permitted download and commercial-use status under current terms; a later paid subscription does not automatically clear free-tier creations. Do not use a shared remix without checking its restrictions. Request the audio file and necessary rights confirmation only if this route is needed. Keep ElevenLabs for effects if useful. [S20–S21]

### 8. Composition and export contract

Use a fresh, clearly named output directory so earlier work survives. Build the composition from the captured footage and approved overlays. Resolve assets locally or through the connector's supported asset mechanism; verify every clip loads and seeks correctly.

The current Apple specification supports the following proposed master. Recheck the correct device row before rendering. [S3]

| Property | Master target |
| --- | --- |
| Destination | iPhone with Dynamic Island, large-display family including iPhone 16 Pro Max |
| Canvas | **886 × 1920 pixels**, portrait; Apple's accepted preview resolution, not raw capture dimensions |
| Duration | **29.0 seconds**; allowed range 15–30 seconds |
| Video | H.264 in `.mp4`, progressive, High Profile no higher than Level 4.0 |
| Frame rate | Constant **30 fps**; Apple maximum 30 fps |
| Video bitrate | **10–12 Mbps** |
| Audio | AAC, **256 kbps**, stereo, **48 kHz**; enabled audio track |
| File size | Below **500 MB** |

Our additional interoperability choices: SDR, `yuv420p`, square pixels, upright encoded frames without a rotation dependency, and MP4 fast-start metadata. Inspect the output rather than assuming the renderer defaults meet them. Do not stretch a generic 1080 × 1920 composition into the narrower canvas. Keep aspect ratio, plan overlays for the target, and avoid cropping useful UI. Small source-ratio differences need a deliberate, inspected fit.

Run the current Hyperframes validation/preview/render workflow on the editable project; BRAG specifies `npx hyperframes check` as a pre-render gate. Fix actual errors and inspect sampled coverage. Independently validate the final downloaded or locally rendered file. Never report a check that was not run. [S6, S23–S24]

Select a poster **from the final rendered video** and supply its exact timestamp and an extracted image. Apple's default is five seconds, but choose the strongest actual frame. Do not insert a one-frame thumbnail flash to satisfy BRAG's generic social-video convention; an exported poster image does not itself set App Store Connect's poster selection. [S2–S4]

### 9. Review the result, not just the render log

Inspect representative stills before the full render, including the timetable, import review, task interaction, alarm scene and ecosystem shots. Then watch the entire final export both muted and with sound, at full resolution and approximately phone display size.

Use FFprobe/FFmpeg or equivalent actual tools to verify the export contract, decodability, frame count, audio duration and start/end behavior. Save the command outputs. Check for black/frozen accidental frames, missing fonts, unloaded video, text clipping, mismatched seeds, unexplained UI jumps and unreadable holds. Examine scene boundaries as well as midpoints.

Have the existing QA reviewer check:

- Each advertised behavior against the feature matrix and source captures.
- AI wording, Watch capabilities, reminder/alarm claims and release entitlements.
- The handling of ecosystem footage and remaining review uncertainty.
- English quality, narrative clarity, caption timing, color consistency and final encoding.

Fix findings and recheck the changed parts. Be explicit about anything still unverified. Do not edit production feature behavior, bypass entitlement logic or manufacture a demonstration just to rescue a marketing shot.

### 10. Deliverables and operating boundaries

Deliver:

1. `tabula-app-preview-en-iphone-29s.mp4` — final master, with its review status stated honestly.
2. `poster.png` and its timestamp in the final master.
3. Editable Hyperframes project, required assets and a repeatable render command. Include the composition brief and any MCP composition/job identifiers used. Record the selected full-BRAG mode, tool versions and single-workflow look-test findings. If a service cannot export source, use the local project as specified above; do not substitute a hosted preview URL for editable source.
4. `storyboard.md` — final timings, captions, shots and audio choices.
5. `capture-manifest.md` — source/build/run/fixture provenance and original clip mapping.
6. `feature-evidence.md` — verified claims, feature availability and unresolved limits.
7. `qa-report.md` — checks actually run, encoding evidence, source links and review findings.
8. `licenses.md` — third-party media/font licenses and required attribution.
9. `handoff.md` — exact intended upload slot, English localization, poster timestamp and remaining owner steps. Do not upload to App Store Connect or submit for review.
10. Only if necessary, a separately named `tabula-marketing-alternate-en.mp4` containing authentic ecosystem footage excluded from the master, clearly labeled as not the App Store submission file.

Keep large captures/renders out of source control unless this repository already has an approved asset workflow. Preserve my existing files. Make only minimal reversible capture/fixture changes needed for this task, and report their diff. Respect explicit repository approval gates; do not add routine approval stops of your own. Ask before paid services, account changes, distribution or changes to the release offer.

Start by reporting, in no more than ten lines: the current build you will capture, the recovered CI/Python workflow, full BRAG and Hyperframes availability, the local/MCP access actually usable, the most important evidence gaps, and the proposed shot plan. Then execute the work that is available. Ask targeted questions only after local/project context cannot answer them.

## Sources to consult and revalidate

Research checked 3 November 2026. Apple is authoritative for App Store requirements; general video advice and skill defaults are subordinate to those requirements. The storyboard, timing allocation, fallback strategy and mix/text targets above are editorial recommendations for Tabula.

- **[S1] Apple — App Review Guidelines**, especially 2.3.1–2.3.4 and 2.3.8–2.3.9: https://developer.apple.com/app-store/review/guidelines/
- **[S2] Apple — Show more with app previews:** https://developer.apple.com/app-store/app-previews/
- **[S3] Apple — App preview specifications:** https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/
- **[S4] Apple — Upload app previews and screenshots:** https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- **[S5] BRAG — upstream README, installation, full/slim routing and asset credits:** https://github.com/latent-spaces/brag
- **[S6] BRAG — full skill and linked production references:** https://github.com/latent-spaces/brag/blob/main/skills/brag/SKILL.md
- **[S7] Hyperframes — Claude Code workflow:** https://hyperframes.heygen.com/guides/with-claude-code
- **[S8] Hyperframes — official repository and skill installation:** https://github.com/heygen-com/hyperframes
- **[S9] Hyperframes — hosted MCP connector and limitations:** https://hyperframes.heygen.com/guides/mcp
- **[S10] Hyperframes — briefing and video prompting guidance:** https://hyperframes.heygen.com/prompting/overview
- **[S11] Wistia — software product video production guidance:** https://wistia.com/blog/software-product-video-tips
- **[S12] Wistia — scripting guide:** https://wistia.com/blog/wistias-scripting-tips
- **[S13] BRAG Slim — implementation-independent workflow:** https://github.com/latent-spaces/brag/blob/main/skills/brag-slim/SKILL.md
- **[S14] ElevenLabs — music composition API:** https://elevenlabs.io/docs/api-reference/music/compose
- **[S15] ElevenLabs — sound effects API:** https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
- **[S16] ElevenLabs — music models and capabilities:** https://elevenlabs.io/docs/overview/capabilities/music
- **[S17] ElevenLabs — Music Terms and plan-specific rights:** https://elevenlabs.io/music-terms
- **[S18] ElevenLabs — API Terms:** https://elevenlabs.io/elevenapi-terms
- **[S19] ElevenLabs — Creative Terms, Sound Effects exhibit:** https://elevenlabs.io/creative-terms
- **[S20] Suno — Terms of Service, permitted commercial use and downloads:** https://suno.com/terms
- **[S21] Suno — pre-subscription song rights:** https://help.suno.com/en/articles/2425729

- **[S22] BRAG — composition handoff:** https://github.com/latent-spaces/brag/blob/main/skills/brag/references/step-3-compose.md
- **[S23] BRAG — validation and delivery:** https://github.com/latent-spaces/brag/blob/main/skills/brag/references/step-4-deliver.md
- **[S24] Hyperframes — CLI workflow and verification:** https://github.com/heygen-com/hyperframes/blob/main/skills/hyperframes-cli/SKILL.md

Local source context: the owner's attached `CLAUDE.md`, kickoff/specification kit, Phase 0–9 reports including Phase 4U, `UX_DEVICE.md`, `PHASE9_DEVICE.md`, app entry point, package manifest and icon. These were supplied as snapshots; the current repository must resolve subsequent implementation changes.
