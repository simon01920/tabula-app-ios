# Phase 10 WP3 on-device checklist: export, share and import heavy operations

Fold into `PHASE10_DEVICE.md` at the gate. Best on the slowest device available (A13 class), plus the iPhone 16 Pro
Max. Run each screen in: light and dark mode, Dynamic Type XXL, German, Japanese or Simplified Chinese, VoiceOver.
Nothing here was compiled or run in the container that wrote it.

## Export: image (P1/B13)
- [ ] Image, Grid, Custom range of 6+ weeks: the share sheet opens, the progress indicator keeps spinning while it renders (no frozen UI), and the app is not killed. In Xcode's memory gauge (if a Mac is available), the peak stays below ≈ 150 MB.
- [ ] The 6-page PNG opens in Photos/Files: about 1684 px wide (scale 1.99), text sharp when zoomed. A 1-page PNG is 2526 px wide (scale 3), as before.

## Export: Week view fits the page (B1, decision P10-4)
- [ ] PDF, Week, a timetable with an 8-hour day (e.g. 08:00–16:00): the whole day is on the page, last lesson and last hour label visible above the bottom edge. Before the fix it was cut off.
- [ ] Same with a short day (08:00–12:00): blocks keep their normal on-screen height (not stretched).
- [ ] A very long day (07:00–22:00): fits with smaller blocks; short lessons still show their names.
- [ ] PDF, Day (portrait): a 10-hour day fits on one page.
- [ ] PDF, Grid: unchanged from Phase 8 (regression check: header, all periods, nothing shifted).

## Export: cancel and clean-up (B2, B14, C5)
- [ ] PDF of a full term (Range: Current term): tap Cancel mid-render. The sheet closes at once, no share sheet pops up afterwards, the app stays responsive.
- [ ] Same, but tap a reminder notification mid-render (deep link): the sheet closes, no share sheet appears later.
- [ ] Fast double tap on Export: one file, one share sheet.
- [ ] Excel and Calendar for a 366-day custom range: the spinner animates smoothly while the file is built; the share sheet opens.
- [ ] Share sheet: Save to Files, then check the file opens. Repeat and close the share sheet with a swipe instead. Both times, the next Export works (no leftover state).

## Week time-block view width (U9)
- [ ] 375 pt phone (SE / 13 mini) or Display Zoom on the Pro Max: Week view with 7 days and two overlapping lessons shows the period grid instead of thin blocks. With 5 days and no overlap it still shows blocks.
- [ ] Pro Max, 7 days with one overlap: blocks (27 pt lanes), names readable.
- [ ] Rotate to landscape and back: the view switches between blocks and grid without a glitch.

## Share Timetable sheet (P8/U12, B9)
- [ ] Open the sheet: the QR code appears after a brief spinner; VoiceOver reads "QR code for the timetable …".
- [ ] Scroll the sheet up and down quickly: no stutter (the QR code is not redrawn).
- [ ] A timetable too big for an inline link: a code appears. Toggle "Include open tasks and exams" on, then off: the first code comes back without a second "Preparing" upload (same code shown).
- [ ] Airplane mode: the upload error shows, Try Again uploads again.

## Share import preview (B4)
- [ ] Open a share link, tap "Add as New Timetable" twice quickly: exactly one new timetable.
- [ ] Replace, confirm, then tap the buttons again while it closes: one replacement, one backup copy, no error alert.

## Photo / file import (P9, P10, U11)
- [ ] Choose Photo with a 48 MP ProRAW / HEIC photo: processing starts without a long freeze; the app is not killed.
- [ ] Choose File, a 20 MB PDF from iCloud Drive: a spinner covers the choices while it opens; Cancel stops it.
- [ ] Multi-page PDF (10+ pages): the page grid appears at once; previews fill in as you scroll (spinners first).
- [ ] Password-protected PDF: alert "This PDF is password-protected…" (German and Japanese: text fits).
- [ ] A damaged or empty PDF: the "Can’t Import This" alert, or the "Can’t Show the Pages" screen with "Choose Another File", which returns to the choices.
- [ ] VoiceOver on the page grid: each page reads "Page N, button".
