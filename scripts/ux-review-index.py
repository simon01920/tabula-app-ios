#!/usr/bin/env python3
"""Build the UI/UX review package from CI simulator screenshots.

Usage: python3 scripts/ux-review-index.py <dir with ui-screenshots-*/screenshots/*.png> [out_dir]

Copies every PNG into <out_dir>/screens/<section>/ (default out_dir: docs/ux-review) and writes <out_dir>/README.md:
app context for the reviewer, then one table per section (screen, what it is, how to reach it, light / dark /
largest-text images). The PNGs are git-ignored (size); README.md and this script are committed.
"""
import pathlib
import re
import shutil
import sys

# route id -> (section, title, what it is / how to reach it)
SCREENS = {
    "onboarding": ("1 Onboarding", "Welcome · School type", "First launch, step 1 of 4: product line, four school-type cards, compact 'App language · Change' row (opens iOS Settings)."),
    "onboarding.school-type": ("1 Onboarding", "School type (selected)", "Step 1 with Secondary selected; Continue enabled."),
    "onboarding.start": ("1 Onboarding", "How do you want to start?", "Step 2: 'Set up my timetable' (default) or 'Just look around' (sample data, removable). Imports hidden until they work."),
    "onboarding.week": ("1 Onboarding", "Your week", "Step 3: school-day chips, repeat pattern; here alternating weeks with 'Which week is this week?', calendar odd/even and term dates."),
    "onboarding.week-days": ("1 Onboarding", "Your week — alternating days", "Step 3 (elementary): Day A / Day B anchored on today or the next school day."),
    "onboarding.times": ("1 Onboarding", "Lesson times", "Step 4: fixed lesson periods (generator + preview), steppers + direct minute entry, 'I'll Do This Later', 'Start Using Tabula'."),
    "onboarding.times-individual": ("1 Onboarding", "Lesson times — individual", "Step 4 (university): individual start and end times with a default length."),
    "onboarding.sample-banner": ("1 Onboarding", "Sample-data banner", "After 'Just look around': 'This is sample data · Remove' above Today; Remove deletes only the sample."),
    "today": ("2 Today", "Today — in a lesson", "Tab 1, one order for every profile: hero (NOW · until 10:45, room, ink progress, '25 min left', next lesson line), Due today with '1 overdue task ›', Rest of today (+ collapsed 'Earlier today'), Next exam (title first). Subtitle 'Tue, Oct 13 · Week B'."),
    "today.before-school": ("2 Today", "Today — before school", "Fixed clock 7:20: 'First lesson · in 40 min', subject, room, time, bring list when present."),
    "today.break": ("2 Today", "Today — break", "Fixed clock 8:53: 'Next · in 2 min', Chemistry, its room and time."),
    "today.after-school": ("2 Today", "Today — after school", "Fixed clock 16:00: 'Done for today', tomorrow's first lesson, pack list; the day's lessons under 'Earlier today', then Tomorrow."),
    "today.holiday": ("2 Today", "Today — holiday", "Thu Oct 29: 'Jesenné prázdniny · until Fri, Oct 30' and Monday's first lesson."),
    "timetable": ("3 Timetable", "Timetable (default view)", "Tab 2, in the profile's default view."),
    "timetable.grid": ("3 Timetable", "Grid view", "Week grid (periods x days): room always on line 2, one badge slot (cancelled > exam > tasks > change), highlighter on the current period, quiet free slots."),
    "timetable.grid-next-week": ("3 Timetable", "Grid — next week", "The grid one week ahead: the 'Today' button appears and the subtitle shows the other rotation week."),
    "timetable.grid-legend": ("3 Timetable", "Grid — symbol legend", "The one-time TipKit legend of the change symbols (forced visible for the screenshot)."),
    "timetable.week": ("3 Timetable", "Week time-blocks", "Proportional week view (university default); now line above the blocks with a time label in the gutter."),
    "timetable.day": ("3 Timetable", "Day view", "One day, proportional time blocks (time is the primary datum). At the largest text size: compact date header (previous / date picker / next) and full-width subject names."),
    "timetable.tiles": ("3 Timetable", "Tiles view", "Big vertical tiles (elementary default): past tiles dimmed, highlighter 'NOW' on the current tile."),
    "timetable.lesson-detail": ("3 Timetable", "Lesson detail", "Tap a lesson: time (a changed time in the change colour, usual time struck through), room, teacher, homework, changes on this day."),
    "timetable.quick-add": ("3 Timetable", "Quick add", "Tap a free slot: opaque sheet, header 'Every Monday · Week B · Period 7 (13:40–14:25)'."),
    "editor.timetables": ("4 Editors", "Timetables manager", "Settings/Timetable: list of timetables (multiple allowed)."),
    "editor.timetable": ("4 Editors", "Timetable editor", "Name, rotation, term dates, time zone."),
    "editor.subjects": ("4 Editors", "Subjects list", "All subjects; Reorder mode (new in Phase 4)."),
    "editor.subject": ("4 Editors", "Subject editor", "Name, colour, emoji/icon, teacher, room."),
    "editor.lesson": ("4 Editors", "Lesson editor", "Edit an existing lesson (day, period/time, room, week A/B...)."),
    "editor.lesson-new": ("4 Editors", "New lesson", "Same editor, empty."),
    "editor.bell": ("4 Editors", "Bell schedule", "One row per period with computed breaks; schedule picker (Regular / Shortened / New)."),
    "editor.bell-period": ("4 Editors", "Bell period detail", "Name, kind, start/end of one period; 'Used by N lessons'; Delete Period."),
    "editor.terms": ("4 Editors", "Terms & holidays", "School year, semesters, breaks, exam periods."),
    "editor.day-change": ("4 Editors", "Change for one day", "One-off override: cancel / move / substitute / room change."),
    "tasks": ("5 Tasks", "Tasks — Today", "Tab 3. Segments Today / Upcoming / Overdue / Completed, quick add."),
    "tasks.upcoming": ("5 Tasks", "Tasks — Upcoming", "Upcoming segment."),
    "tasks.overdue": ("5 Tasks", "Tasks — Overdue", "Overdue segment."),
    "tasks.completed": ("5 Tasks", "Tasks — Completed", "Completed segment."),
    "tasks.detail": ("5 Tasks", "Task detail", "Tap a task: type, due, repeat, notes, subtasks, attachments."),
    "tasks.editor": ("5 Tasks", "Task editor", "Edit a task (title, kind, subject, due incl. 'next lesson', priority, subtasks, repeat, reminder, attachments)."),
    "tasks.editor-new": ("5 Tasks", "New task", "Same editor, empty."),
    "exams": ("6 Exams", "Exams — Upcoming", "Tab 4. Prominent next exam with countdown; exam period (university)."),
    "exams.history": ("6 Exams", "Exams — History", "Past exams."),
    "exams.detail": ("6 Exams", "Exam detail", "Tap an exam."),
    "exams.editor": ("6 Exams", "Exam editor", "Kind, date, times, room/building, topics, reminder."),
    "exams.editor-new": ("6 Exams", "New exam", "Same editor, empty."),
    "settings": ("7 Settings", "Settings", "Tab 5. Timetable / Notifications / General / About & Feedback groups with icon tiles; every row pushes."),
    "settings.colours": ("7 Settings", "Colors", "Colour palette picker (swatch preview, Pro capsule + lock), preview tile, Apply to All Subjects with Undo. No Light/Dark override (D3). Alias: settings.appearance."),
    "settings.calendar": ("7 Settings", "Date & Time", "Week start, time format (System by default), time zone inside the collapsed Advanced group."),
    "settings.about": ("7 Settings", "About & Feedback", "Version, Send Feedback / Privacy Policy (placeholder targets), privacy summary, Acknowledgements."),
    "settings.reminders": ("7 Settings", "Reminders", "One row per kind (name + summary, Off), quiet hours, loud alarms, Test reminders & troubleshoot; attention row only for user-fixable problems."),
    "settings.reminder-rule": ("7 Settings", "Reminder kind page", "Remind me switch, times, follow-up, delivery (Standard / Loud alarm; Time Sensitive only where supported), quiet hours."),
    "settings.reminder-health": ("7 Settings", "Reminder check", "Summary of user-fixable problems, checks with Open Settings buttons, collapsed Technical details, test buttons."),
    "settings.live-activities": ("7 Settings", "Live Activities", "Lesson / exam-day Live Activity switches, Start automatically."),
    "reminders.permission": ("7 Settings", "Notification permission explainer", "Shown in context before iOS asks for notification permission."),
    "widgets.gallery": ("8 Widgets & Live Activities", "Now & Next widget", "DEBUG gallery: Home Screen small/medium + Lock Screen families (during a lesson, in a break)."),
    "widgets.gallery-evening": ("8 Widgets & Live Activities", "Now & Next — evening/holiday", "After school and holiday states."),
    "widgets.gallery-pro": ("8 Widgets & Live Activities", "Pro / unavailable states", "Free-tier 'Available in Tabula Pro' and 'Open Tabula' states."),
    "widgets.gallery-today": ("8 Widgets & Live Activities", "Today widget", "Medium/large."),
    "widgets.gallery-homework": ("8 Widgets & Live Activities", "Homework widget", "Small/medium/large."),
    "widgets.gallery-exam": ("8 Widgets & Live Activities", "Next exam widget", "Small + Lock Screen."),
    "widgets.gallery-live": ("8 Widgets & Live Activities", "Lesson Live Activity", "Lock Screen + Dynamic Island (approximation)."),
    "widgets.gallery-live-exam": ("8 Widgets & Live Activities", "Exam-day Live Activity", "Lock Screen + Dynamic Island (approximation)."),
}
VARIANTS = [("light", "Light"), ("dark", "Dark"), ("ax-xxxl-text", "Largest text")]
NAME = re.compile(r"^(?P<id>[a-z][a-z0-9.-]*)_(?P<seed>[a-z]+)(?:_(?P<lang>[a-z]{2}(?:-[A-Za-z]+)?))?-(?P<variant>light|dark|ax-xxxl-text)\.png$")

CONTEXT = """# Tabula — UI/UX review package

**What Tabula is:** an iOS 26+ (and later watchOS) school and university timetable app with homework, exams and
reminders. Users: pupils in elementary and secondary school, and university students. Five tabs: **Today ·
Timetable · Tasks · Exams · Settings**. It runs in 12 languages (en, sk, cs, pl, hu, ro, de, fr, uk, sr Cyrillic and
Latin, ja, zh-Hans).

**How these screenshots were made:**
- iOS Simulator (largest iPhone Pro Max), from a DEBUG build on GitHub Actions.
- Every screen is in **light**, **dark** and **largest accessibility text** (AX-XXXL).
- **Sample data:** a Slovak secondary school (class 2.B, A/B weeks), plus university and elementary profiles. The
  subject names are in Slovak even in the English UI; that is the sample data, not untranslated UI.
- The clock is fixed at **Tue 13 Oct 2026, 10:20** (Europe/Bratislava), so "Now" is a Slovak lesson.
- The `…_sk` files show the Slovak UI.

**Fixed constraints:**
- Standard SwiftUI controls (iOS 26 Liquid Glass applies automatically).
- Dynamic Type and VoiceOver must keep working.
- Text on user-chosen subject colours must stay readable.
- No hard-coded or concatenated strings; everything is translated.
- There is no designer yet: the current look is engineering defaults.

**Not in screenshots:** real Home Screen widgets and Live Activities (shown here through a DEBUG gallery that
approximates them), system permission dialogs, notifications and alarms, the Watch app (Phase 5).

**Seeds used:** `empty` (onboarding), `secondary`, `university`, `elementary`.
"""


def main() -> int:
    src = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "docs/ux-review")
    shots = sorted(src.rglob("*.png"))
    entries: dict[tuple[str, str, str], dict[str, pathlib.Path]] = {}
    unknown = []
    for p in shots:
        m = NAME.match(p.name)
        if not m:
            unknown.append(p.name)
            continue
        key = (m["id"], m["seed"], m["lang"] or "en")
        entries.setdefault(key, {})[m["variant"]] = p
    if (out / "screens").exists():
        shutil.rmtree(out / "screens")
    lines = [CONTEXT]
    by_section: dict[str, list] = {}
    for (rid, seed, lang), variants in entries.items():
        section, title, what = SCREENS.get(rid, ("9 Other", rid, ""))
        by_section.setdefault(section, []).append((rid, seed, lang, title, what, variants))
    total = 0
    for section in sorted(by_section):
        lines.append(f"\n## {section[2:]}\n")
        lines.append("| Screen | What it is / how to reach it | Seed · language | " + " | ".join(v[1] for v in VARIANTS) + " |")
        lines.append("|---|---|---|" + "---|" * len(VARIANTS))
        folder = out / "screens" / re.sub(r"[^a-z0-9]+", "-", section.lower()).strip("-")
        folder.mkdir(parents=True, exist_ok=True)
        rows = sorted(by_section[section], key=lambda e: (list(SCREENS).index(e[0]) if e[0] in SCREENS else 999, e[1], e[2]))
        for rid, seed, lang, title, what, variants in rows:
            cells = []
            for vkey, _ in VARIANTS:
                p = variants.get(vkey)
                if p is None:
                    cells.append("—")
                    continue
                dest = folder / p.name
                shutil.copy2(p, dest)
                total += 1
                cells.append(f"[{vkey}]({dest.relative_to(out).as_posix()})")
            lines.append(f"| **{title}** (`{rid}`) | {what} | {seed} · {lang} | " + " | ".join(cells) + " |")
    lines.append(f"\n---\n{total} screenshots in {len(entries)} screen/seed/language combinations. "
                 "Regenerate: `python3 scripts/ux-review-index.py <downloaded artifacts dir>`.\n")
    if unknown:
        lines.append("Unrecognised files: " + ", ".join(unknown) + "\n")
    (out / "README.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{total} screenshots, {len(entries)} combinations -> {out}/README.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
