# Phase 8 on-device checklist: Export (E2)

Route: Timetable tab, ⋯ menu, "Export…" (also launch route `export.sheet`). Tier is all-access, so the Pro gate is not
visible; to see it, run a build whose entitlements deny `ProFeature.exports` (button disabled, footer "Exports are part of
Tabula Pro.").

## Sheet states
- [ ] Opens as a medium/large sheet; Cancel closes it; Export is the prominent confirmation button.
- [ ] Type = Image or PDF shows the View picker (Grid / Week / Day); CSV, Excel, Calendar hide it.
- [ ] Range: This week, Current term, Custom dates (From / To appear; To cannot precede From).
- [ ] Current term with no term containing today: footer says the next 4 weeks are exported.
- [ ] Image with a range longer than one page: footer about 6 pages shows.
- [ ] Empty timetable (no lessons): export still works (empty file / blank pages), no crash.
- [ ] Dynamic Type XXL and AX5, dark mode, German, Slovak, Japanese, Simplified Chinese: nothing clipped, labels readable.
- [ ] VoiceOver: pickers read label + value; Export button, Cancel, progress indicator reachable; share sheet opens.
- [ ] Fast double tap on Export builds one file, not two.

## File names (visible in the share sheet header)
- [ ] `Timetable 2.B – week 42.pdf` style: timetable name, en dash, localised range, extension.
- [ ] A timetable named `a/b:c*?` or `../x` gives a safe name (no slashes, no leading dot).

## PDF and image (the risk: ImageRenderer with GeometryReader / ScrollView content)
- [ ] PDF, Grid, This week: one landscape page; header (name + "12 Oct – 16 Oct"), all days, all periods, lesson names and rooms; white background, black text even in dark mode; no today highlight or now line.
- [ ] PDF, Week (time blocks): lessons placed at the right times, blocks not clipped, hour axis visible.
- [ ] PDF, Day: one portrait page per school day; all lessons of the day visible, nothing cut at the bottom.
- [ ] PDF, Current term: one page per week, page count matches the term.
- [ ] Cancelled lessons are struck through / dimmed, changed lessons show their change symbol (also in print layout).
- [ ] Image: PNG opens in Photos/Files, sharp when zoomed (3x), stacked pages up to 6.
- [ ] Share sheet: AirDrop, Save to Files, Print (PDF), Mail attachment name is the sanitised name.
- [ ] If any view renders blank or clipped (ScrollView inside ImageRenderer), note which view; fallback plan: render the canvas without the ScrollView.

## CSV
- [ ] Open in Numbers (Files > Open in Numbers) and Excel: UTF-8 BOM gives correct accents, Slovak / Japanese text; columns Date, Start, End, Subject, Room, Teacher, Change.
- [ ] A subject starting with `=`, `+`, `-` or `@` shows with a leading apostrophe, not as a formula.
- [ ] Cancelled and changed lessons have text in Change (localised, reasons joined with the locale's "and").

## Excel (.xlsx)
- [ ] Opens in Excel without a repair prompt; opens in Numbers. Missing-styles risk: the file has no styles part, so check that dates/times show as text, columns are readable, and the sheet name is the timetable name.
- [ ] Same rows as the CSV.

## Calendar (.ics)
- [ ] Share to Calendar ("Add to Calendar"): events appear on the right days and times.
- [ ] Time zone: with Settings > Calendar > fixed time zone different from the device, events keep the chosen zone (TZID); with follow-device they stay at the same wall-clock time ("floating").
- [ ] Cancelled lessons appear as cancelled/struck events (STATUS:CANCELLED), not as normal events.
- [ ] Re-import after changing a lesson (room) and exporting again: the existing events update, nothing is duplicated. Re-import after cancelling a lesson: the earlier event is cancelled.
- [ ] Description shows teacher and change text; calendar name is the timetable name.

## QA re-check items (2026-11-01)
- [ ] Debug build: open the `export.preview` route (Developer screen or `-TabulaScreen export.preview`). The rendered image shows the full week grid, not a blank or clipped page.
- [ ] Export a term-long PDF in Day view: the spinner keeps moving, the sheet can't be swiped away while it works, and the share sheet appears at the end.
- [ ] Share the exported file with AirDrop, Mail and Save to Files. Each one gets the file, even though the temp folder is deleted when the share sheet closes.
- [ ] A week-view page taller than the paper size is clipped (known limit); note how bad it looks.
