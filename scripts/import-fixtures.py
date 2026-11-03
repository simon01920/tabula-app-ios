#!/usr/bin/env python3
"""Generate the Phase 9 import eval fixtures (Packages/TimetableCore/Tests/Fixtures/import/*.json).

Each fixture is ground truth (the timetable as printed) rendered into a `RecognizedTable` the way the Vision adapter
would deliver it: table `cells` (RecognizeDocumentsRequest) or loose `lines` with boxes (VNRecognizeTextRequest
fallback), with injected OCR noise (look-alike characters, missing diacritics, low confidence, unreadable labels).
`expected` is the truth the parser should recover. Deterministic, stdlib only. Re-run after editing a spec:

    python3 scripts/import-fixtures.py            # writes the JSON files
    python3 scripts/import-fixtures.py --check    # fails when the committed files are stale (not wired into CI)
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Packages", "TimetableCore", "Tests", "Fixtures", "import")


def t(minutes):
    return "%02d:%02d" % divmod(minutes, 60)


def m(text):
    h, mm = text.split(":")
    return int(h) * 60 + int(mm)


def bell(starts, length):
    """[(number, start, end)] from start strings and one lesson length."""
    return [(i + 1, s, t(m(s) + length)) for i, s in enumerate(starts)]


def numbered(periods, first=1):
    return [(first + i, s, e) for i, (_, s, e) in enumerate(periods)]


def dotted(hhmm):  # "07:00" -> "7.00"
    h, mm = hhmm.split(":")
    return "%d.%s" % (int(h), mm)


HEADERS = {
    "asc": lambda n, s, e: "%d\n%s" % (n, dotted(s)),
    "num_range": lambda n, s, e: "%d\n%s-%s" % (n, s, e),
    "range": lambda n, s, e: "%s–%s" % (s, e),
    "dotted_range": lambda n, s, e: "%s-%s" % (dotted(s), dotted(e)),
    "num": lambda n, s, e: "%d" % n,
    "hod": lambda n, s, e: "%d. hod\n%s-%s" % (n, s, e),
    "std": lambda n, s, e: "%d. Std\n%s-%s" % (n, s, e),
    "ora": lambda n, s, e: "%d. óra\n%s-%s" % (n, s, e),
    "period": lambda n, s, e: "Period %d\n%s" % (n, s),
    "ja": lambda n, s, e: "%d限\n%s-%s" % (n, s, e),
    "zh": lambda n, s, e: "第%d节\n%s-%s" % (n, s, e),
    "fr": lambda n, s, e: "%d\n%s-%s" % (n, s.replace(":", "h"), e.replace(":", "h")),
    "start": lambda n, s, e: s,
    "us12": lambda n, s, e: "Period %d\n%s–%s%s" % (n, h12(s), h12(e), meridiem(n, s, e)),
}


def h12(hhmm):  # "13:00" -> "1:00"
    h, mm = hhmm.split(":")
    return "%d:%s" % ((int(h) - 1) % 12 + 1, mm)


def meridiem(n, s, e):  # only on the end time, the way US schools print it; noon has none
    if int(e[:2]) >= 13:
        return " p.m." if n % 2 else " PM"
    return " a.m." if int(s[:2]) < 12 else ""


class Cell:
    def __init__(self, day, period, text, lessons, span=1, conf=0.95, block=0):
        self.day, self.period, self.text, self.lessons = day, period, text, lessons
        self.span, self.conf, self.block = span, conf, block


def lesson(subject, room=None, teacher=None, kind=None, weeks=None, notes=None):
    return {"subject": subject, "room": room, "teacher": teacher, "lessonType": kind, "weeks": weeks, "notes": notes}


def simple(day, period, subject, room=None, teacher=None, kind=None, span=1, text=None, conf=0.95, block=0, fmt="lines"):
    """One lesson in one cell. `text` overrides the printed text (noise); `fmt` picks how fields are printed."""
    if text is None:
        parts = [subject] + [x for x in (teacher, room) if x]
        if fmt == "lines":
            text = "\n".join([subject] + [x for x in (room, teacher) if x])
        elif fmt == "teacher_first":
            text = "\n".join(parts)
        elif fmt == "one_line":
            text = " ".join([subject] + [x for x in (room,) if x])
        else:
            raise ValueError(fmt)
    weeks = [block + 1] if block else None
    return Cell(day, period, text, [lesson(subject, room, teacher, kind, weeks)], span, conf, block)


# ---------------------------------------------------------------------------------------------------------------
# Rendering


def render(spec):
    days, periods, cells = spec["days"], spec["periods"], spec["cells"]
    blocks = spec.get("blocks", 1)
    header = spec.get("header", "num_range")
    header_rows = 0 if header == "none" else (2 if header == "two_rows" else 1)
    day_rows = len(days) * blocks
    labels = spec.get("labels") or days  # printed labels (noise) per day index, repeated per block
    grid = []  # (row, col, rowspan, colspan, text, conf) in the days-as-rows frame
    if header == "two_rows":
        for i, (n, s, e) in enumerate(periods):
            grid.append((0, i + 1, 1, 1, str(n), 0.97))
            grid.append((1, i + 1, 1, 1, "%s-%s" % (s, e), 0.97))
    elif header != "none":
        for i, (n, s, e) in enumerate(periods):
            grid.append((0, i + 1, 1, 1, HEADERS[header](n, s, e), 0.97))
    label_conf = spec.get("label_conf", {})
    for b in range(blocks):
        for d, label in enumerate(labels):
            if label is None:
                continue
            row = header_rows + b * len(days) + d
            grid.append((row, 0, 1, 1, label, label_conf.get(d, 0.97)))
    column_of = {n: i + 1 for i, (n, _, _) in enumerate(periods)}
    for c in cells:
        row = header_rows + c.block * len(days) + c.day
        grid.append((row, column_of[c.period], 1, c.span, c.text, c.conf))
    if spec.get("title"):
        grid.append((-1, 0, 1, len(periods) + 1, spec["title"], 0.9))
    rows_total = header_rows + day_rows + (1 if spec.get("title") else 0)
    shift = 1 if spec.get("title") else 0
    grid = [(r + shift, c, rs, cs, text, conf) for r, c, rs, cs, text, conf in grid]

    # Geometry in the days-as-rows frame.
    cols_total = len(periods) + 1
    x0, w0 = 0.02, 0.08
    col_w = (0.98 - x0 - w0) / (cols_total - 1)
    y0, row_h = 0.05, 0.9 / rows_total

    def box(r, c, rs, cs):
        x = x0 if c == 0 else x0 + w0 + (c - 1) * col_w
        w = w0 if c == 0 else cs * col_w
        return [x, y0 + r * row_h, w, rs * row_h]

    columns_layout = spec["layout"] == "columns"
    table = {"version": 1, "pageWidth": 2480, "pageHeight": 3508, "languages": spec.get("languages", [spec["language"]])}
    if spec["mode"] == "cells":
        out = []
        for r, c, rs, cs, text, conf in sorted(grid, key=lambda g: (g[0], g[1])):
            bx = box(r, c, rs, cs)
            if columns_layout:
                r, c, rs, cs = c, r, cs, rs
                bx = [bx[1], bx[0], bx[3], bx[2]]
            cell = {"text": text, "row": r, "column": c}
            if rs != 1:
                cell["rowSpan"] = rs
            if cs != 1:
                cell["columnSpan"] = cs
            cell["box"] = rect(bx)
            cell["confidence"] = conf
            out.append(cell)
        table["cells"] = out
    else:
        out = []
        for r, c, rs, cs, text, conf in sorted(grid, key=lambda g: (g[0], g[1])):
            bx = box(r, c, rs, cs)
            text_lines = text.split("\n")
            lh = min(0.016, bx[3] / (len(text_lines) + 1))
            top = bx[1] + (bx[3] - lh * 1.15 * len(text_lines)) / 2
            for k, line in enumerate(text_lines):
                width = min(bx[2] * 0.9, sum(0.014 if ord(ch) > 0x2E80 else 0.0072 for ch in line))
                lb = [bx[0] + (bx[2] - width) / 2, top + k * lh * 1.15, width, lh]
                if columns_layout:
                    lb = [lb[1], lb[0], lb[3], lb[2]]
                out.append({"text": line, "box": rect(lb), "confidence": conf})
        table["lines"] = out
    return table


def rect(b):
    return {"x": round(b[0], 4), "y": round(b[1], 4), "width": round(b[2], 4), "height": round(b[3], 4)}


def expected(spec):
    lessons = []
    for c in spec["cells"]:
        for ls in c.lessons:
            entry = {"day": spec["day_values"][c.day], "period": c.period, "span": c.span}
            entry.update({k: v for k, v in ls.items() if v is not None})
            if spec.get("blocks", 1) > 1:
                entry["weeks"] = [c.block + 1]
            lessons.append(entry)
    blocks = spec.get("blocks", 1)
    cycle = 2 if blocks > 1 or any(ls.get("weeks") for c in spec["cells"] for ls in c.lessons) else None
    exp = {
        "orientation": "daysAsColumns" if spec["layout"] == "columns" else "daysAsRows",
        "days": spec["day_values"],
        "periods": [{"number": n, "start": s, "end": e} for n, s, e in spec["periods"]],
        "checkTimes": spec.get("check_times", True),
        "weekCycleLength": cycle,
        "lessons": lessons,
    }
    return exp


# ---------------------------------------------------------------------------------------------------------------
# Specs

WEEK = [0, 1, 2, 3, 4]
MON_FRI = [1, 2, 3, 4, 5]
ASC_STARTS = ["07:00", "07:50", "08:40", "09:30", "10:20", "11:10", "12:00", "12:50", "13:50", "14:40", "15:30",
              "16:20", "17:10"]
ASC = bell(ASC_STARTS, 45)
SCHOOL = bell(["08:00", "08:55", "09:50", "10:55", "11:50", "12:45", "13:35"], 45)
UNI = [(1, "08:00", "09:30"), (2, "09:45", "11:15"), (3, "11:30", "13:00"), (4, "13:30", "15:00"), (5, "15:15", "16:45")]
UNI_SK = bell(["07:30", "09:10", "10:50", "12:30", "14:10"], 90)


def human_cells(fmt="lines", noisy=False):
    """The human's Slovak aSc example (positions the human did not give: Tue SPAJ 1, SPAJ 5, TPVAJ1 10; Wed ZaExk 3)."""
    s = lambda *a, **k: simple(*a, fmt=fmt, **k)
    cells = [
        s(0, 2, "prax", "aaa", span=6),
        s(1, 1, "SPAJ", "3P1"), s(1, 3, "SAL", "3S1", span=2), s(1, 5, "SPAJ", "Aula"),
        s(1, 8, "TPVAJ1", "Aula", span=2), s(1, 10, "TPVAJ1", "3S1"),
        s(2, 1, "MPV", "1S1"), s(2, 3, "ZaExk", "3P1"), s(2, 8, "Muzejná pedagogika", "H5S1", span=2),
        s(3, 3, "Teor. a prax vyuč. hist. I", "H4P1", span=3), s(3, 6, "Reg. dej. vo vyuč. dej. str.", "H4P1", span=2),
        s(4, 9, "MPV", "Aula"), s(4, 12, "SAL", "Aula"),
    ]
    if noisy:
        cells[6] = simple(2, 1, "MPV", "1S1", text="MPV\nlS1", conf=0.41)  # l for 1 next to a letter: not fixable
        cells[8] = simple(2, 8, "Muzejná pedagogika", "H5S1", span=2, text="Muzejna pedagogika\nH5S1", conf=0.55)
        cells[9] = simple(3, 3, "Teor. a prax vyuč. hist. I", "H4P1", span=3, text="Teor. a prax vyuc. hist. I\nH4PI", conf=0.48)
    return cells


def human_expected_fix(spec):
    # With OCR noise the truth is still the printed text; the parser cannot know the diacritics.
    return spec


SPECS = []


def add(**spec):
    spec.setdefault("day_values", MON_FRI)
    SPECS.append(spec)


# 1–4 The human's aSc example.
add(id="sk-asc-human", language="sk", layout="rows", mode="cells", header="asc", periods=ASC,
    days=["Po", "Ut", "St", "Št", "Pi"], cells=human_cells(),
    description="The human's Slovak aSc timetable: rows Po-Pi, periods 1-13 headed '1' over '7.00'.")
add(id="sk-asc-human-lines", language="sk", layout="rows", mode="lines", header="asc", periods=ASC,
    days=["Po", "Ut", "St", "Št", "Pi"], cells=human_cells(),
    description="The aSc example as loose OCR lines (no table structure): geometric clustering.")
add(id="sk-asc-human-oneline", language="sk", layout="rows", mode="lines", header="asc", periods=ASC,
    days=["Po", "Ut", "St", "Št", "Pi"], cells=human_cells(fmt="one_line"),
    description="The aSc example with subject and room on one line ('SPAJ 3P1'), loose lines.")
add(id="sk-asc-human-noisy", language="sk", layout="rows", mode="cells", header="asc", periods=ASC,
    days=["Po", "Ut", "St", "Št", "Pi"], labels=["Po", "Ut", "St", "St", "Pi"], cells=human_cells(noisy=True),
    description="The aSc example with OCR noise: 'Št' read as 'St', missing diacritics, 'lS1', 'H4PI', low confidence.")

# 5 Transposed aSc.
add(id="sk-asc-transposed", language="sk", layout="columns", mode="cells", header="asc", periods=ASC,
    days=["Pondelok", "Utorok", "Streda", "Štvrtok", "Piatok"], cells=human_cells(),
    description="The aSc example transposed: days as columns with full names, periods down.")

# 6–7 English.
add(id="en-columns", language="en", layout="columns", mode="cells", header="num_range", periods=SCHOOL,
    days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
    cells=[simple(0, 1, "Maths", "Room 12", "Mr Smith"), simple(0, 2, "English", "Room 4", "Ms Brown"),
           simple(1, 1, "Biology", "Lab 2"), simple(1, 3, "History", "B12", span=2), simple(2, 4, "Art", "A01"),
           simple(3, 1, "Physics", "Lab 1", "Dr Jones"), simple(4, 6, "PE", "Gym")],
    description="English secondary school, days as columns, '1' over '08:00-08:45'.")
add(id="en-rows-period", language="en", layout="rows", mode="lines", header="period", periods=SCHOOL,
    days=["Mon", "Tue", "Wed", "Thu", "Fri"],
    cells=[simple(0, 1, "Maths", "Rm 4"), simple(0, 2, "Chemistry", "S2"), simple(1, 5, "French", "L3"),
           simple(2, 1, "Geography", "H1", span=2), simple(3, 7, "Music", "M1"), simple(4, 3, "Drama", "Hall")],
    description="English, days as rows (Mon-Fri), 'Period 1' over a start time only; loose lines.")

# 8–9 German.
add(id="de-rows", language="de", layout="rows", mode="cells", header="std", periods=SCHOOL,
    days=["Mo", "Di", "Mi", "Do", "Fr"],
    cells=[simple(0, 1, "Mathe", "R104"), simple(0, 2, "Deutsch", "R104"), simple(1, 3, "Englisch", "R201", span=2),
           simple(2, 1, "Physik", "N12", "Herr Becker"), simple(3, 5, "Sport", "Turnhalle", span=2),
           simple(4, 2, "Kunst", "K1")],
    description="German Gymnasium, 'Mo Di Mi Do Fr', '1. Std' over a range.")
add(id="de-columns-lines", language="de", layout="columns", mode="lines", header="num_range", periods=SCHOOL,
    days=["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"],
    cells=[simple(0, 1, "Mathematik", "R12"), simple(1, 2, "Biologie", "B3", "Frau Weber"),
           simple(2, 3, "Chemie", "C2", span=2), simple(4, 6, "Religion", "R7")],
    description="German, days as columns with full names; loose lines.")

# 10–11 Czech.
add(id="cs-rows-teachers", language="cs", layout="rows", mode="cells", header="hod", periods=SCHOOL,
    days=["Po", "Út", "St", "Čt", "Pá"],
    cells=[simple(0, 1, "Matematika", "204", "Mgr. Novák"), simple(1, 2, "Fyzika", "105", "RNDr. Dvořák"),
           simple(2, 3, "Chemie", "Lab 3", span=2), simple(3, 1, "Dějepis", "301", "Mgr. Svobodová"),
           simple(4, 4, "Tělocvik", "Tělocvična", span=2)],
    description="Czech, 'Po Út St Čt Pá', '1. hod' over a range; subject, room, teacher with titles.")
add(id="cs-no-diacritics-ocr", language="cs", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Po", "Út", "St", "Čt", "Pá"], labels=["Po", "Ut", "St", "Ct", "Pa"],
    cells=[simple(0, 1, "Matematika", "204", text="Matematika\n2O4", conf=0.58),
           simple(1, 2, "Fyzika", "105", text="Fyzika\n1O5", conf=0.62),
           simple(2, 3, "Chemie", "312", text="Chemie\n3l2", conf=0.5), simple(3, 4, "Biologie", "220"),
           simple(4, 5, "Zeměpis", "118")],
    description="Czech without diacritics on the day labels; rooms read as '2O4', '1O5', '3l2'.")

# 12–13 Polish.
add(id="pl-columns", language="pl", layout="columns", mode="cells", header="num_range", periods=SCHOOL,
    days=["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek"],
    cells=[simple(0, 1, "Matematyka", "sala 12", fmt="one_line"), simple(1, 2, "Fizyka", "sala 7", fmt="one_line"),
           simple(2, 3, "Chemia", "s14"), simple(3, 1, "Historia", "21"), simple(4, 2, "WF", "Sala gimnastyczna")],
    description="Polish, days as columns, rooms 'sala 12' on the subject line.")
add(id="pl-no-diacritics", language="pl", layout="rows", mode="lines", header="num_range", periods=SCHOOL,
    days=["Pon", "Wt", "Śr", "Czw", "Pt"], labels=["Pon", "Wt", "Sr", "Czw", "Pt"],
    cells=[simple(0, 1, "Polski", "12"), simple(1, 2, "Angielski", "14"), simple(2, 3, "Biologia", "B2", span=2),
           simple(3, 6, "Muzyka", "M1"), simple(4, 1, "Informatyka", "I3")],
    description="Polish abbreviations without diacritics ('Sr' for 'Śr'); loose lines.")

# 14–15 Hungarian.
add(id="hu-rows", language="hu", layout="rows", mode="cells", header="ora", periods=SCHOOL,
    days=["Hétfő", "Kedd", "Szerda", "Csütörtök", "Péntek"],
    cells=[simple(0, 1, "Matematika", "104"), simple(1, 2, "Magyar", "12"), simple(2, 3, "Történelem", "201", span=2),
           simple(3, 1, "Fizika", "F1"), simple(4, 5, "Testnevelés", "Tornaterem")],
    description="Hungarian, full day names, '1. óra' headers.")
add(id="hu-letters", language="hu", layout="rows", mode="cells", header="num", periods=SCHOOL, check_times=False,
    days=["H", "K", "Sze", "Cs", "P"],
    cells=[simple(0, 1, "Matek", "104"), simple(1, 1, "Angol", "11"), simple(2, 2, "Kémia", "K2"),
           simple(3, 3, "Biológia", "B1"), simple(4, 4, "Ének", "E1")],
    description="Hungarian one/two-letter day labels (H K Sze Cs P), period numbers only: times are assumed.")

# 16–17 Romanian.
add(id="ro-rows", language="ro", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Luni", "Marți", "Miercuri", "Joi", "Vineri"],
    cells=[simple(0, 1, "Matematică", "Sala 5"), simple(1, 2, "Română", "Sala 3"), simple(2, 3, "Fizică", "Lab 1"),
           simple(3, 4, "Istorie", "12"), simple(4, 1, "Sport", "Sala de sport")],
    description="Romanian, full day names, 'Sala 5' rooms.")
add(id="ro-no-diacritics", language="ro", layout="columns", mode="lines", header="dotted_range", periods=SCHOOL,
    days=["Luni", "Marți", "Miercuri", "Joi", "Vineri"], labels=["Luni", "Marti", "Miercuri", "Joi", "Vineri"],
    cells=[simple(0, 1, "Matematica", "5"), simple(1, 2, "Chimie", "L2"), simple(2, 3, "Biologie", "B4"),
           simple(4, 7, "Engleza", "E1")],
    description="Romanian without diacritics, days as columns, '8.00-8.45' headers; loose lines.")

# 18–19 French.
add(id="fr-columns", language="fr", layout="columns", mode="cells", header="fr",
    periods=bell(["08:00", "08:55", "10:05", "11:00", "13:30", "14:25"], 55),
    days=["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi"],
    cells=[simple(0, 1, "Mathématiques", "Salle 101", "M. Dupont"), simple(1, 2, "Français", "Salle 12"),
           simple(2, 3, "Histoire-Géo", "B204", span=2), simple(3, 5, "SVT", "Labo 2"), simple(4, 6, "EPS", "Gymnase")],
    description="French collège, days as columns, '8h00-8h55' headers, 55-minute lessons.")
add(id="fr-abbrev", language="fr", layout="rows", mode="cells", header="range", periods=SCHOOL,
    days=["Lun", "Mar", "Mer", "Jeu", "Ven"],
    cells=[simple(0, 1, "Anglais", "A12"), simple(1, 2, "Physique", "P3"), simple(2, 1, "Musique", "M2"),
           simple(3, 4, "Espagnol", "E5"), simple(4, 2, "Philosophie", "C7")],
    description="French abbreviations, range-only headers ('08:00–08:45').")

# 20–21 Ukrainian.
add(id="uk-rows", language="uk", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Пн", "Вт", "Ср", "Чт", "Пт"],
    cells=[simple(0, 1, "Математика", "каб. 21"), simple(1, 2, "Українська мова", "каб. 14"),
           simple(2, 3, "Фізика", "каб. 30", span=2), simple(3, 1, "Історія", "12"), simple(4, 5, "Хімія", "каб. 5")],
    description="Ukrainian abbreviations (Пн Вт Ср Чт Пт), rooms 'каб. 21'.")
add(id="uk-columns-full", language="uk", layout="columns", mode="lines", header="num_range", periods=SCHOOL,
    days=["Понеділок", "Вівторок", "Середа", "Четвер", "П'ятниця"],
    cells=[simple(0, 1, "Алгебра", "21"), simple(1, 2, "Географія", "15"), simple(3, 3, "Біологія", "8", span=2),
           simple(4, 4, "Англійська", "33")],
    description="Ukrainian full names, days as columns; loose lines.")

# 22–23 Serbian.
add(id="sr-cyrl-rows", language="sr", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Понедељак", "Уторак", "Среда", "Четвртак", "Петак"],
    cells=[simple(0, 1, "Математика", "12"), simple(1, 2, "Српски језик", "8"), simple(2, 3, "Физика", "21"),
           simple(3, 4, "Хемија", "Лаб 2"), simple(4, 1, "Историја", "5")],
    description="Serbian Cyrillic, full day names.")
add(id="sr-latn-no-diacritics", language="sr-Latn", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Pon", "Uto", "Sre", "Čet", "Pet"], labels=["Pon", "Uto", "Sre", "Cet", "Pet"],
    cells=[simple(0, 1, "Matematika", "12"), simple(1, 2, "Srpski", "8"), simple(2, 3, "Fizika", "21"),
           simple(3, 4, "Hemija", "L2"), simple(4, 1, "Istorija", "5")],
    description="Serbian Latin abbreviations, 'Cet' without the caron.")

# 24–25 Japanese and Chinese.
add(id="ja-uni-columns", language="ja", layout="columns", mode="cells", header="ja", periods=UNI,
    days=["月", "火", "水", "木", "金"],
    cells=[simple(0, 1, "線形代数", "301", "田中先生"), simple(1, 2, "英語", "205"), simple(2, 3, "物理学", "401"),
           simple(3, 1, "経済学", "102"), simple(4, 4, "情報科学", "501")],
    description="Japanese university, 月-金 as columns, '1限' over 90-minute ranges.")
add(id="zh-rows", language="zh-Hans", layout="rows", mode="cells", header="zh", periods=SCHOOL,
    days=["星期一", "星期二", "星期三", "星期四", "星期五"],
    cells=[simple(0, 1, "语文", "201"), simple(1, 2, "数学", "202"), simple(2, 3, "英语", "203", span=2),
           simple(3, 1, "物理", "301"), simple(4, 5, "体育", "操场")],
    description="Simplified Chinese, 星期一-星期五, '第1节' headers.")
add(id="zh-columns-zhou", language="zh-Hans", layout="columns", mode="lines", header="num_range", periods=SCHOOL,
    days=["周一", "周二", "周三", "周四", "周五"],
    cells=[simple(0, 1, "化学", "实验室1"), simple(1, 2, "历史", "105"), simple(3, 4, "地理", "106"),
           simple(4, 1, "音乐", "音乐室")],
    description="Chinese 周一-周五 as columns; loose lines.")

# 26–27 University 90-minute blocks.
add(id="en-uni-types", language="en", layout="rows", mode="cells", header="num_range", periods=UNI,
    days=["Mon", "Tue", "Wed", "Thu", "Fri"],
    cells=[simple(0, 1, "Algorithms", "C1.04", kind="lecture", text="Algorithms (Lecture)\nC1.04"),
           simple(0, 2, "Algorithms", "B204", kind="lab", text="Algorithms (Lab)\nB204"),
           simple(1, 3, "Statistics", "A12", kind="tutorial", text="Statistics (Tutorial)\nA12"),
           simple(2, 1, "Databases", "C1.04", "Dr Miller", kind="lecture", text="Databases (Lecture)\nC1.04\nDr Miller"),
           simple(3, 4, "Ethics", "Aula", kind="seminar", text="Ethics (Seminar)\nAula")],
    description="English university, 90-minute ranges, types in brackets.")
add(id="sk-uni-start-only", language="sk", layout="rows", mode="cells", header="start", periods=UNI_SK,
    days=["Pondelok", "Utorok", "Streda", "Štvrtok", "Piatok"],
    cells=[simple(0, 1, "Analýza", "Aula", kind="lecture", text="Analýza (P)\nAula"),
           simple(0, 2, "Analýza", "H3", kind="tutorial", text="Analýza (C)\nH3"),
           simple(1, 3, "Programovanie", "B-204", kind="lecture", text="Programovanie (P)\nB-204"),
           simple(2, 1, "Databázy", "C2", kind="lab", text="Databázy (L)\nC2"),
           simple(4, 4, "Filozofia", "A1", kind="seminar", text="Filozofia (S)\nA1")],
    description="Slovak university, start times only (7:30, 9:10, ...): 90-minute ends inferred; (P)/(C)/(L)/(S) types.")

# 28–29 A/B weeks.
add(id="sk-ab-markers", language="sk", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Po", "Ut", "St", "Št", "Pi"],
    cells=[Cell(0, 1, "MAT 204 (A)\nFYZ 105 (B)", [lesson("MAT", "204", weeks=[1]), lesson("FYZ", "105", weeks=[2])]),
           Cell(1, 2, "A: ANJ 112\nB: NEJ 113", [lesson("ANJ", "112", weeks=[1]), lesson("NEJ", "113", weeks=[2])]),
           simple(2, 3, "SJL", "204"), simple(3, 4, "BIO", "Lab B"),
           Cell(4, 1, "INF\n(A)\nTSV\n(B)", [lesson("INF", weeks=[1]), lesson("TSV", weeks=[2])])],
    description="Slovak A/B weeks marked in the cells: 'MAT 204 (A)', 'A: ANJ 112', a bare '(A)' line.")
add(id="de-ab-blocks", language="de", layout="rows", mode="cells", header="num_range", periods=SCHOOL, blocks=2,
    days=["Mo", "Di", "Mi", "Do", "Fr"],
    cells=[simple(0, 1, "Mathe", "R1"), simple(1, 2, "Deutsch", "R2"), simple(4, 3, "Kunst", "K1"),
           simple(0, 1, "Physik", "P1", block=1), simple(2, 2, "Chemie", "C1", block=1), simple(4, 3, "Musik", "M1", block=1)],
    description="German A/B weeks as two runs of days (Mo-Fr, Mo-Fr).")

add(id="en-us-12-hour", language="en", layout="columns", mode="cells", header="us12",
    periods=[(1, "10:00", "10:50"), (2, "11:00", "11:50"), (3, "12:00", "12:50"), (4, "13:00", "13:50"), (5, "14:00", "14:50")],
    days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
    cells=[simple(0, 1, "Algebra", "Rm 101"), simple(1, 3, "Lunch Club", "Hall"), simple(2, 4, "Biology", "Lab 2"),
           simple(3, 5, "Spanish", "Rm 12"), simple(4, 4, "Chorus", "Rm 7", span=2)],
    description="US 12-hour times: '10:00–10:50 a.m.', '12:00–12:50', then '1:00–1:50 p.m.' and '2:00–2:50 PM'.")

# 30–36 Structure and noise edge cases.
add(id="sk-no-header", language="sk", layout="rows", mode="cells", header="none", periods=SCHOOL, check_times=False,
    days=["Po", "Ut", "St", "Št", "Pi"],
    cells=[simple(0, 1, "MAT", "204"), simple(0, 2, "SJL", "204"), simple(1, 1, "ANJ", "112"), simple(3, 3, "DEJ", "105"),
           simple(4, 7, "TSV", "Telocvičňa")],
    description="No header row: periods by position and an assumed bell schedule.")
add(id="en-two-header-rows", language="en", layout="rows", mode="cells", header="two_rows", periods=SCHOOL,
    days=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
    cells=[simple(0, 1, "Maths", "M1"), simple(1, 2, "Science", "S1", span=2), simple(2, 5, "Art", "A2"),
           simple(4, 7, "Computing", "IT1")],
    description="Two header rows: period numbers, then ranges.")
add(id="sk-unreadable-label", language="sk", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Po", "Ut", "St", "Št", "Pi"], labels=["Po", "Ut", "5t?", "Št", "Pi"], label_conf={2: 0.3},
    cells=[simple(0, 1, "MAT", "204"), simple(1, 2, "FYZ", "105"), simple(2, 3, "CHE", "Lab CH"), simple(3, 4, "BIO", "Lab B"),
           simple(4, 5, "DEJ", "105")],
    description="One day label unreadable ('5t?'): the day comes from the order.")
add(id="sk-zero-period", language="sk", layout="rows", mode="cells", header="num_range",
    periods=numbered(bell(["07:10", "08:00", "08:55", "09:50", "10:55"], 45), first=0), days=["Po", "Ut", "St", "Št", "Pi"],
    cells=[simple(0, 0, "Krúžok", "12"), simple(0, 1, "MAT", "204"), simple(2, 2, "SJL", "204"), simple(4, 4, "INF", "PC1")],
    description="A zero period (0 at 7:10) before period 1.")
add(id="sk-merged-lines", language="sk", layout="rows", mode="lines", header="asc", periods=ASC,
    days=["Po", "Ut", "St", "Št", "Pi"],
    cells=[simple(0, 1, "Odborná prax v škole", "ZŠ Hlboká", span=4), simple(1, 5, "SAL", "3S1", span=2),
           simple(2, 9, "Seminár z dejín", "H4P1", span=3), simple(3, 1, "MPV", "1S1"), simple(4, 11, "TPVAJ1", "Aula", span=3)],
    description="Long merged cells (spans 2-4) as loose lines; long subject text centred over several columns.")
add(id="sk-teachers-known", language="sk", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Po", "Ut", "St", "Št", "Pi"], options={"knownSubjects": ["Biológia", "Matematika", "Dejepis"]},
    cells=[simple(0, 1, "Bio", "Lab B", "Mgr. Lukáč"), simple(1, 2, "Matematika", "201", "RNDr. Novák"),
           simple(2, 3, "Fyzika", "Lab F", "Mgr. Horváth, PhD."), simple(3, 4, "Dejepis", "105", "PhDr. Varga")],
    description="Teachers with Slovak titles (incl. 'PhD.' after the name) and a known-subject abbreviation ('Bio').")
add(id="de-hidden-teacher", language="de", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Mo", "Di", "Mi", "Do", "Fr"], options={"enabledFields": ["room"]},
    cells=[Cell(0, 1, "Mathe\nR104\nHerr Becker", [lesson("Mathe", "R104", notes="Herr Becker")]),
           Cell(1, 2, "Englisch\nR201\nFrau Klein", [lesson("Englisch", "R201", notes="Frau Klein")])],
    description="Teacher field hidden by the user: teachers go to notes, never dropped.")
add(id="sk-low-confidence", language="sk", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Po", "Ut", "St", "Št", "Pi"],
    cells=[simple(0, 1, "MAT", "204", text="MAT\n2O4", conf=0.35), simple(1, 2, "SJL", "204", text="S JL\n204", conf=0.4),
           simple(2, 3, "ANJ", "112"), simple(3, 4, "NEJ", "113", text="NEJ\n1I3", conf=0.45),
           simple(4, 5, "INF", "PC1", text="lNF\nPC1", conf=0.38)],
    description="Badly lit photo: low OCR confidence, 'S JL', 'lNF', '1I3'.")
add(id="sk-title-row", language="sk", layout="rows", mode="cells", header="num_range", periods=SCHOOL,
    days=["Po", "Ut", "St", "Št", "Pi"], title="Rozvrh hodín 3.A 2026/2027",
    cells=[simple(0, 1, "MAT", "204"), simple(1, 2, "SJL", "204"), simple(2, 3, "ANJ", "112", span=2),
           simple(4, 6, "TSV", "Telocvičňa")],
    description="A title row above the header ('Rozvrh hodín 3.A 2026/2027') must not become a lesson.")


def build(spec):
    fixture = {"id": spec["id"], "description": spec["description"], "language": spec["language"],
               "mode": spec["mode"], "layout": spec["layout"]}
    if spec.get("options"):
        fixture["options"] = spec["options"]
    fixture["table"] = render(spec)
    fixture["expected"] = expected(spec)
    return fixture


def main():
    check = "--check" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    stale = 0
    for spec in SPECS:
        text = json.dumps(build(spec), ensure_ascii=False, indent=1) + "\n"
        path = os.path.join(OUT, spec["id"] + ".json")
        if check:
            if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
                print("STALE", path)
                stale += 1
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
    print("%d fixtures %s" % (len(SPECS), "checked" if check else "written to " + os.path.relpath(OUT, ROOT)))
    sys.exit(1 if stale else 0)


if __name__ == "__main__":
    main()
