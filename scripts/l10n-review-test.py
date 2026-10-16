#!/usr/bin/env python3
"""Round-trip test of the translation-review tooling (export -> reviewer CSV -> import). Standard library only.

Works on a copy of the real catalogs in a temp directory; never touches the repository. Run by scripts/validate.sh.
"""
import csv
import io
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PY = sys.executable
FAILED = []


def check(name, cond, detail=""):
    print(("OK   " if cond else "FAIL ") + name + ("" if cond else f"  {detail}"))
    if not cond:
        FAILED.append(name)


def sh(*args):
    p = subprocess.run([PY, "-B", *map(str, args)], capture_output=True, text=True, encoding="utf-8", cwd=ROOT)
    return p.returncode, p.stdout + p.stderr


def read_csv(path, delim=","):
    text = pathlib.Path(path).read_bytes().decode("utf-8-sig")
    return list(csv.DictReader(io.StringIO(text, newline=""), delimiter=delim))


def write_csv(path, rows, delim, bom):
    buf = io.StringIO(newline="")
    w = csv.DictWriter(buf, fieldnames=list(rows[0].keys()), delimiter=delim, lineterminator="\r\n")
    w.writeheader()
    w.writerows(rows)
    pathlib.Path(path).write_bytes((("﻿" if bom else "") + buf.getvalue()).encode("utf-8"))


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="l10n-review-test."))
    try:
        (tmp / "Resources").mkdir()
        for name in ("Localizable.xcstrings", "InfoPlist.xcstrings"):
            shutil.copy(ROOT / "Resources" / name, tmp / "Resources" / name)
        cat = tmp / "Resources/Localizable.xcstrings"
        before = cat.read_text(encoding="utf-8")
        review = tmp / "review"

        code, out = sh("scripts/l10n-review-export.py", "--catalog-root", tmp, "--out", review)
        check("export runs", code == 0, out)
        for f in ("index.html", "README.md", "SOURCE_HASH", "sk.csv", "sr-Latn.csv", "zh-Hans.csv"):
            check(f"export wrote {f}", (review / f).exists())
        code2, out2 = sh("scripts/l10n-review-export.py", "--catalog-root", tmp, "--out", review, "--check")
        check("--check passes on a fresh export", code2 == 0, out2)
        first = {p.name: p.read_bytes() for p in review.iterdir()}
        sh("scripts/l10n-review-export.py", "--catalog-root", tmp, "--out", review)
        check("export is deterministic", first == {p.name: p.read_bytes() for p in review.iterdir()})
        check("CSV starts with a UTF-8 BOM", (review / "sk.csv").read_bytes().startswith(b"\xef\xbb\xbf"))
        html = (review / "index.html").read_text(encoding="utf-8")
        page = html.split('<script id="data"', 1)[0] + html.split("</script>", 1)[1]   # markup without the catalog data
        check("index.html is self-contained (no external resources)",
              not any(t in page for t in ("<link", " src=", "@import", "url(", "http://", "https://")), "external reference found")

        rows = read_csv(review / "sk.csv")
        keys = [(r["key"], r["plural_form"]) for r in rows]
        check("rows sorted by key", [k for k, _ in keys] == sorted(k for k, _ in keys))
        plural_rows = [r for r in rows if r["plural_form"]]
        check("plural rows present with forms", {r["plural_form"] for r in plural_rows} >= {"one", "few", "many", "other"})
        plain = next(r for r in rows if r["key"] == "shell.tab.today")
        pl = next(r for r in rows if r["key"] == "a11y.lesson.tasks" and r["plural_form"] == "few")
        pl_other = next(r for r in rows if r["key"] == "a11y.lesson.tasks" and r["plural_form"] == "other")
        pl_one = next(r for r in rows if r["key"] == "a11y.lesson.tasks" and r["plural_form"] == "one")
        check("english for a plural form that English lacks falls back to 'other'", "%lld" in pl["english"])

        plain["corrected"] = "Dnes (opravené)"
        pl["corrected"] = "%lld nesplnené úlohy"
        pl_other["corrected"] = "bez zástupného znaku"     # must be rejected: placeholder missing
        pl_one["corrected"] = "[ok]"
        plain["note"] = "test note"
        sent = tmp / "sk-corrected.csv"
        write_csv(sent, rows, ";", bom=False)               # Excel in a Slovak locale: ';' and no BOM

        code, out = sh("scripts/l10n-review-import.py", "--dry-run", sent, "--catalog", cat,
                       "--infoplist", tmp / "Resources/InfoPlist.xcstrings", "--baseline", review / "baseline.json")
        check("dry run reports 2 changed, 1 approved, 1 rejected", "2 changed, 1 approved" in out and "1 rejected" in out, out)
        check("dry run exits 1 because of the rejection", code == 1)
        check("dry run leaves the catalog untouched", cat.read_text(encoding="utf-8") == before)

        code, out = sh("scripts/l10n-review-import.py", sent, "--catalog", cat,
                       "--infoplist", tmp / "Resources/InfoPlist.xcstrings", "--baseline", review / "baseline.json")
        check("import applies and reports the rejection", code == 1 and "REJECTED" in out and "placeholders differ" in out, out)
        data = json.loads(cat.read_text(encoding="utf-8"))
        sk = data["strings"]["shell.tab.today"]["localizations"]["sk"]["stringUnit"]
        check("plain value set, state translated", sk == {"state": "translated", "value": "Dnes (opravené)"}, sk)
        plural = data["strings"]["a11y.lesson.tasks"]["localizations"]["sk"]["variations"]["plural"]
        check("plural form 'few' set, state translated",
              plural["few"]["stringUnit"] == {"state": "translated", "value": "%lld nesplnené úlohy"}, plural["few"])
        check("rejected plural form 'other' unchanged and still needs_review",
              plural["other"]["stringUnit"]["state"] == "needs_review" and "%lld" in plural["other"]["stringUnit"]["value"])
        check("[ok] approves without changing text",
              plural["one"]["stringUnit"]["state"] == "translated" and plural["one"]["stringUnit"]["value"] == pl_one["current"])
        check("untouched rows keep needs_review",
              data["strings"]["shell.tab.tasks"]["localizations"]["sk"]["stringUnit"]["state"] == "needs_review"
              if "shell.tab.tasks" in data["strings"] else True)
        code, out = sh("scripts/l10n-add.py", "--check", "--catalog", cat)
        check("catalog is still in canonical form", code == 0, out)
        check("English untouched",
              data["strings"]["shell.tab.today"]["localizations"]["en"] == json.loads(before)["strings"]["shell.tab.today"]["localizations"]["en"])

        # Serbian: a corrected Cyrillic row re-derives Latin
        srrows = read_csv(review / "sr.csv")
        target = next(r for r in srrows if r["key"] == "shell.tab.today")
        target["corrected"] = "Данас"
        sr_csv = tmp / "sr.csv"
        write_csv(sr_csv, srrows, ",", bom=True)
        code, out = sh("scripts/l10n-review-import.py", sr_csv, "--catalog", cat,
                       "--infoplist", tmp / "Resources/InfoPlist.xcstrings", "--baseline", review / "baseline.json")
        data = json.loads(cat.read_text(encoding="utf-8"))
        lat = data["strings"]["shell.tab.today"]["localizations"]["sr-Latn"]["stringUnit"]
        check("sr correction re-derives sr-Latn", code == 0 and lat["value"] == "Danas", (out, lat))

        # Staleness and the changed-since-review flag after the import
        code, out = sh("scripts/l10n-review-export.py", "--catalog-root", tmp, "--out", review, "--check")
        check("--check reports stale after the catalog changed", code == 1 and "STALE" in out, out)
        sh("scripts/l10n-review-export.py", "--catalog-root", tmp, "--out", review)
        code, out = sh("scripts/l10n-review-export.py", "--catalog-root", tmp, "--out", review, "--check")
        check("--check passes again after regenerating", code == 0, out)
        rows2 = read_csv(review / "sk.csv")
        check("re-export shows the corrected text as current",
              next(r for r in rows2 if r["key"] == "shell.tab.today")["current"] == "Dnes (opravené)")

        # Header problems / unknown key
        bad = tmp / "de.csv"
        bad.write_bytes("﻿key,plural_form,corrected\nno.such.key,,Hallo\n".encode("utf-8"))
        code, out = sh("scripts/l10n-review-import.py", bad, "--catalog", cat,
                       "--infoplist", tmp / "Resources/InfoPlist.xcstrings", "--baseline", review / "baseline.json")
        check("unknown key rejected", code == 1 and "key not in the catalogs" in out, out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"{'ALL OK' if not FAILED else str(len(FAILED)) + ' FAILED'}: {len(FAILED)} failures")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
