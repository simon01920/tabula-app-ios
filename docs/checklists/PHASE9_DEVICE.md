# Phase 9 on-device checklist: import from photo, scan or PDF (I2)

Entry points: onboarding step 2 "Import from Photo or PDF…", Timetable ⋯ › "Import from Photo…", Settings › Timetables
manager › "Import from Photo or PDF…", Settings › Import › "Import from Photo or PDF…". Launch routes: `import.capture`,
`import.processing`, `import.review`, `import.review-questions`, `settings.import-model` (the last four are DEBUG
fixtures). In DEBUG builds the capture screen has "Use Sample Picture (Debug)": the real Vision → parser → (Apple
Intelligence) pipeline on I1's aSc fixture drawn as a picture, without a printed timetable.

## Capture
- [ ] P9.1 Each entry point opens the "Import Timetable" sheet; Cancel closes it.
- [ ] P9.2 Scan Document opens VisionKit's document camera; the first time, iOS asks for the camera (text mentions a printed timetable); a scanned page goes to processing.
- [ ] P9.3 Camera denied in Settings: Scan Document shows "Camera Access Is Off" with Open Settings.
- [ ] P9.4 Choose Photo: the system picker (no photo-library prompt); a screenshot of an aSc timetable goes to processing.
- [ ] P9.5 Choose File: an image from Files works; a 1-page PDF goes straight to processing; a multi-page PDF shows "Choose a Page" with previews.
- [ ] P9.6 A non-image file / damaged PDF: "Can’t Import This" alert, the capture screen stays.
- [ ] P9.7 "Uses Apple Intelligence on this iPhone" appears ONLY when Settings › Import says Available.

## Processing
- [ ] P9.8 The picture appears, then Reading the image ✓ → Finding the table (spinner) → Understanding lessons; no artificial delay.
- [ ] P9.9 Cancel during "Finding the table" returns to the capture choices; nothing is saved; a second import works.
- [ ] P9.10 A photo with no text (wall, blank paper): "No text was found…" alert.
- [ ] P9.11 Note the time from tap to review for the aSc photo (record in docs/eval/IMPORT_EVAL.md).

## Review
- [ ] P9.12 Image / Timetable switch; the image zooms (pinch, double tap) and scrolls; uncertain cells are outlined in amber on the image and line up with the cells.
- [ ] P9.13 Counts: "… lessons", "… subjects", "… need checking" (or "All checked").
- [ ] P9.14 Grid: days as rows (Po–Pi), periods across with number and start time; double lessons span columns; room bottom-trailing; empty slots grey; uncertain cells amber outline + warning symbol.
- [ ] P9.15 Questions: tapping an answer applies it to every listed lesson, the question disappears, counts update.
- [ ] P9.16 A/B timetable: "Which week is A: this week or next week?" appears; Approve stays disabled until answered; after import, the Timetable shows week A in the chosen week.
- [ ] P9.17 Tap a lesson → Edit Lesson: "Read as" shows the OCR text verbatim, reasons listed, fields editable; with identical cells, "Apply to all N identical cells" changes all of them.
- [ ] P9.18 Looks Right clears the flag; Remove Lesson removes it (and its identical cells when the switch is on).
- [ ] P9.19 Swipe-down does not close the review (edits would be lost); Cancel does.
- [ ] P9.20 Approve → "Add Timetable" summary → "Add as New Timetable": the new timetable becomes active, the Timetable tab shows it, lesson count matches.
- [ ] P9.21 Replace "…": the alert names what goes; after confirming, a "pre-import" backup exists in Settings › Backup; the old timetable is gone.
- [ ] P9.22 From onboarding: approving finishes onboarding and lands on the tabs with the imported timetable.
- [ ] P9.23 A Slovak timetable on a device in Slovak never calls Apple Intelligence (Settings › Import shows "Language Not Supported" or "Off"); the review still works (Tier D).
- [ ] P9.24 Device in English with Apple Intelligence on: uncertain cells may show "Apple Intelligence suggested a change" and new questions; no lesson appears that is not in the picture.

## Settings › Import
- [ ] P9.25 Apple Intelligence status matches reality: Available / Off / Language Not Supported / Not on This iPhone / Getting Ready (iPhone 16 Pro Max should not say "Not on This iPhone"); re-check after toggling Apple Intelligence and coming back.
- [ ] P9.26 Recognition model: explanation, "About 1.1 GB", "Available in a later version", Download disabled; nothing downloads, no progress.

## Every screen above
- [ ] P9.27 States: empty (a picture with no lessons), normal, long text (aSc "Teor. a prax vyuc. hist. I" cells), Dynamic Type XXL and AX5 (the grid becomes per-day lists), dark mode, German, Slovak, Japanese / Simplified Chinese.
- [ ] P9.28 VoiceOver: steps read "Finding the table, in progress"; each grid cell reads "Tuesday, period 3. SAL. 3S1" (+ "Needs checking" and the reason as hint); empty slots are skipped; question answers are buttons; the image reads "Picture of your timetable" and supports zoom (three-finger swipe up / down with the rotor's Zoom action).
- [ ] P9.29 Reduce Motion: no step / zoom animation.

## Not verifiable without a device
Vision table recognition quality on real photos, document camera behaviour, Foundation Models availability, its
language check and the guided-generation output, memory and time per import, PDFKit rendering of real PDFs.
