#!/usr/bin/env python3
"""Apply a reviewer's corrected CSV (from docs/localization/review/<lang>.csv) to the String Catalogs.

For every row whose `corrected` cell is not empty:
  * `[ok]`           the current text is right: state becomes `translated` (reviewed), text unchanged
  * any other text   format specifiers must match the English text in type and count (%@, %lld, %1$lld ...);
                     then the value is set and the state becomes `translated`
Rows with an empty `corrected` are skipped. A rejected row never blocks the others; the exit code is 1 if any row was
rejected (nothing is written for it). Corrected `sr` rows also re-derive `sr-Latn` (1:1 transliteration).
The catalogs are written in the canonical Xcode form (the one scripts/l10n-add.py --check verifies).

Excel quirks handled: `;` or tab separated files (Slovak/German/Czech locales), UTF-8 with or without BOM, UTF-16
("Unicode text"), and a legacy cp1250/cp1252 fallback (with a warning: Cyrillic/CJK would already be lost there).

Usage:
  python3 scripts/l10n-review-import.py sk.csv
  python3 scripts/l10n-review-import.py --dry-run sk-corrected.csv      # report only, change nothing
  python3 scripts/l10n-review-import.py --lang sr reviewed.csv          # when the file name does not start with the id
Options: --catalog PATH / --infoplist PATH (defaults: Resources/*.xcstrings), --baseline PATH, --notes (print notes)
Afterwards: python3 scripts/l10n-review-export.py ; bash scripts/validate.sh ; update docs/localization/REVIEW.md
"""
import argparse
import csv
import io
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "lib"))
from l10n_common import dump, load_catalog, specs, sr_to_latin  # noqa: E402
from l10n_review import (APPROVE, BASELINE_NAME, LANGS, REVIEW_DIR, ROOT, SOURCE, dump_baseline,  # noqa: E402
                         english_ref, lang_cells, load_baseline, row_hash, row_id)


def decode(raw: bytes):
    """(text, warning|None)"""
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16"), None
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8"), None
    try:
        return raw.decode("utf-8"), None
    except UnicodeDecodeError:
        pass
    for enc in ("cp1250", "cp1252"):
        try:
            return raw.decode(enc), (f"file is not UTF-8; read as {enc}. Characters outside that code page may already be "
                                     f"lost: save as 'CSV UTF-8' next time")
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1"), "file is not UTF-8; read as latin-1"


def read_rows(path: pathlib.Path):
    """(rows as dicts keyed by lower-case header, warnings)"""
    text, warn = decode(path.read_bytes())
    warns = [warn] if warn else []
    first = text.split("\n", 1)[0]
    counts = {d: first.count(d) for d in (",", ";", "\t")}
    delim = max(counts, key=counts.get)
    if counts[delim] == 0:
        raise SystemExit(f"error: {path}: no header row with a ',' ';' or tab separator")
    reader = csv.reader(io.StringIO(text, newline=""), delimiter=delim)
    header = [h.strip().lower() for h in next(reader)]
    for need in ("key", "plural_form", "corrected"):
        if need not in header:
            raise SystemExit(f"error: {path}: column '{need}' missing (header: {', '.join(header)})")
    rows = []
    for n, rec in enumerate(reader, start=2):
        if not any(c.strip() for c in rec):
            continue
        rec = rec + [""] * (len(header) - len(rec))
        d = dict(zip(header, rec))
        d["_line"] = n
        rows.append(d)
    if delim != ",":
        warns.append(f"separator '{'TAB' if delim == chr(9) else delim}' detected")
    return rows, warns


def guess_lang(path: pathlib.Path):
    stem = path.stem
    for lang in sorted(LANGS, key=len, reverse=True):
        if lang != SOURCE and re.fullmatch(re.escape(lang) + r"(?:[^A-Za-z0-9].*)?", stem):
            return lang
    return None


def locate(catalogs, key):
    for cid, cat in catalogs.items():
        if key in cat["data"]["strings"]:
            return cid, cat["data"]["strings"][key]
    return None, None


def apply_cell(loc, form, value, state):
    """Set one text+state in a localization node. Returns False when the form does not exist."""
    if form:
        node = loc.get("variations", {}).get("plural", {}).get(form)
        if node is None:
            return False
        node["stringUnit"] = {"state": state, "value": value}
        return True
    if "stringUnit" not in loc:
        return False
    loc["stringUnit"] = {"state": state, "value": value}
    return True


def run(csv_path, lang, catalog, infoplist, baseline_path, dry_run=False, show_notes=False, out=print) -> int:
    rows, warns = read_rows(pathlib.Path(csv_path))
    catalogs = {"L": {"path": pathlib.Path(catalog), "data": load_catalog(catalog)},
                "I": {"path": pathlib.Path(infoplist), "data": load_catalog(infoplist)}}
    baseline = load_baseline(baseline_path)
    changed, approved, rejected, skipped, notes = [], [], [], 0, []
    derived = 0
    for w in warns:
        out(f"note: {w}")

    for r in rows:
        key, form, corrected = r["key"].strip(), r.get("plural_form", "").strip(), r["corrected"].strip(" \t\r\n")
        where = f"line {r['_line']} {key}{'[' + form + ']' if form else ''}"
        note = r.get("note", "").strip()
        if note and show_notes:
            notes.append(f"{where}: {note}")
        if not corrected:
            skipped += 1
            continue
        cid, entry = locate(catalogs, key)
        if entry is None:
            rejected.append((where, "key not in the catalogs"))
            continue
        locs = entry.get("localizations", {})
        loc = locs.get(lang)
        cells = lang_cells(loc)
        if form not in cells:
            rejected.append((where, f"plural form '{form}' does not exist for {lang}" if form else
                             "this key is plural: plural_form must be filled"))
            continue
        en_cells = lang_cells(locs.get(SOURCE))
        english = english_ref(en_cells, form)
        current, state = cells[form]
        if r.get("current", "") and r["current"] != current:
            out(f"warning: {where}: the catalog text changed since the export (CSV 'current' differs); applying anyway")
        if corrected == APPROVE:
            value, kind = current, "approved"
        else:
            value, kind = corrected, "changed"
            want, have = specs(english), specs(value)
            if want != have:
                rejected.append((where, f"placeholders differ: English has {[t for _, t in want] or 'none'}, "
                                        f"corrected has {[t for _, t in have] or 'none'}"))
                continue
        if not dry_run:
            apply_cell(loc, form, value, "translated")
            baseline[row_id(lang, cid, key, form)] = row_hash(english, value)
        (approved if kind == "approved" else changed).append((where, current, value))
        if lang == "sr" and "sr-Latn" in locs:
            lat_loc = locs["sr-Latn"]
            lat_cells = lang_cells(lat_loc)
            if form in lat_cells:
                lat = sr_to_latin(value)
                if not dry_run:
                    apply_cell(lat_loc, form, lat, "translated")
                    baseline[row_id("sr-Latn", cid, key, form)] = row_hash(english, lat)
                derived += 1

    out(f"{'DRY RUN: ' if dry_run else ''}{csv_path} -> {lang}: {len(changed)} changed, {len(approved)} approved "
        f"([ok]), {len(rejected)} rejected, {skipped} skipped (empty corrected)"
        + (f", {derived} sr-Latn re-derived" if derived else ""))
    for where, old, new in changed:
        out(f"  changed  {where}: {old!r} -> {new!r}")
    for where, old, new in approved:
        out(f"  approved {where}")
    for where, why in rejected:
        out(f"  REJECTED {where}: {why}")
    for n in notes:
        out(f"  note     {n}")
    if not dry_run and (changed or approved):
        for cat in catalogs.values():
            cat["path"].write_text(dump(cat["data"]), encoding="utf-8", newline="\n")
        pathlib.Path(baseline_path).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(baseline_path).write_text(dump_baseline(baseline), encoding="utf-8", newline="\n")
        out("catalogs written in canonical form; next: python3 scripts/l10n-review-export.py")
    return 1 if rejected else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("--lang")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--notes", action="store_true", help="also print the reviewer's notes")
    ap.add_argument("--catalog", default=str(ROOT / "Resources/Localizable.xcstrings"))
    ap.add_argument("--infoplist", default=str(ROOT / "Resources/InfoPlist.xcstrings"))
    ap.add_argument("--baseline", default=str(REVIEW_DIR / BASELINE_NAME))
    a = ap.parse_args()
    lang = a.lang or guess_lang(pathlib.Path(a.csv))
    if lang not in LANGS or lang == SOURCE:
        raise SystemExit(f"error: cannot tell the language from '{a.csv}'; pass --lang (one of {', '.join(LANGS[1:])})")
    return run(a.csv, lang, a.catalog, a.infoplist, a.baseline, a.dry_run, a.notes)


if __name__ == "__main__":
    sys.exit(main())
