#!/usr/bin/env python3
"""Find the catalog keys that lack a complete translation, and merge translations back (re-runnable).

Workflow when new English strings are added (scripts/l10n-add.py), e.g. after the B2/B3 merges:
  1. python3 scripts/l10n-translate-missing.py status
  2. python3 scripts/l10n-translate-missing.py list --out /tmp/missing.json
     -> JSON with, per missing key: the English text, the translator comment, and the languages + plural
        categories still needed; "template" is a ready-to-fill {lang: {key: "" | {category: ""}}} object.
  3. A translator (human or model) fills the template: a plain string, or {category: text} for plural keys
     (categories per language: see "plural_categories" in the list output / scripts/lib/l10n_common.py).
     Keep the format specifiers (%@, %lld, %1$lld ...) identical in type and number; no concatenation.
     Serbian: translate Cyrillic ("sr") only; "sr-Latn" is transliterated from it automatically on merge.
  4. python3 scripts/l10n-translate-missing.py merge filled.json   # {lang: {key: value}} or a dir of <lang>.json
     Every merged unit gets state "needs_review" (never native quality; log new keys in
     docs/localization/REVIEW.md). Existing complete translations are kept unless --replace is given.
     The merge refuses entries with wrong specifiers/categories and writes the catalog in canonical form.
  5. bash scripts/validate.sh  (the completeness check in validate_config.py is a FAIL for any gap)

Options: --catalog PATH (default Resources/Localizable.xcstrings), --langs sk,cs,... (default: all 12 targets)
"""
import argparse
import json
import pathlib
import sys

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
import l10n_common as L  # noqa: E402


def parse_langs(arg):
    langs = tuple(x for x in arg.split(",") if x) if arg else L.TARGETS
    bad = [x for x in langs if x not in L.TARGETS]
    if bad:
        raise SystemExit(f"error: unknown language(s) {bad}; known: {', '.join(L.TARGETS)}")
    return langs


def gaps(catalog, langs):
    """{key: {lang: [problem, ...]}} for every incomplete or malformed translation."""
    out = {}
    for key in sorted(catalog["strings"]):
        for lang in langs:
            found = L.problems(key, catalog["strings"][key], lang)
            if found:
                out.setdefault(key, {})[lang] = found
    return out


def cmd_status(catalog, langs):
    total = len(catalog["strings"])
    gap = gaps(catalog, langs)
    print(f"{total} keys x {len(langs)} languages")
    for lang in langs:
        n = sum(1 for k in gap if lang in gap[k])
        print(f"  {lang:8} {total - n:4}/{total} complete" + (f"  ({n} to do)" if n else ""))
    return 1 if gap else 0


def cmd_list(catalog, langs, out_path):
    gap = gaps(catalog, langs)
    keys, template = {}, {lang: {} for lang in langs}
    for key, per_lang in gap.items():
        entry = catalog["strings"][key]
        if "sr" in per_lang and "sr-Latn" in per_lang:
            per_lang = {k: v for k, v in per_lang.items() if k != "sr-Latn"}   # derived from sr on merge
        kind, value = L.english_shape(entry)
        needs = {lang: ("string" if kind == "string" else list(L.PLURAL_CATEGORIES[lang])) for lang in per_lang}
        keys[key] = {"comment": entry.get("comment", ""), "en": value, "needs": needs, "problems": per_lang}
        for lang in per_lang:
            template[lang][key] = "" if kind == "string" else {c: "" for c in L.PLURAL_CATEGORIES[lang]}
    doc = {
        "instructions": "Fill 'template' (plain string, or {category: text} for plural keys). Keep format specifiers "
                        "identical in type and number. Then: python3 scripts/l10n-translate-missing.py merge <file>",
        "plural_categories": {lang: list(L.PLURAL_CATEGORIES[lang]) for lang in langs},
        "missing_keys": len(keys),
        "keys": keys,
        "template": {lang: t for lang, t in template.items() if t},
    }
    text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
    if out_path:
        pathlib.Path(out_path).write_text(text, encoding="utf-8")
        print(f"{len(keys)} keys need translation -> {out_path}")
    else:
        sys.stdout.write(text)
    return 0


def load_inputs(paths):
    """-> {lang: {key: value}} from combined files ({lang: {...}}) or <lang>.json files / directories."""
    merged = {}
    files = []
    for p in map(pathlib.Path, paths):
        files.extend(sorted(p.glob("*.json")) if p.is_dir() else [p])
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        if f.stem in L.TARGETS:
            data = {f.stem: data}
        elif "template" in data and isinstance(data["template"], dict):
            data = data["template"]
        for lang, table in data.items():
            if lang not in L.TARGETS:
                raise SystemExit(f"error: {f}: unknown language {lang!r}")
            merged.setdefault(lang, {}).update(table)
    return merged


def localisation(value, lang):
    if isinstance(value, str):
        return L.unit(value)
    return {"variations": {"plural": {cat: L.unit(text) for cat, text in value.items()}}}


def cmd_merge(path, catalog, langs, inputs, replace):
    data = load_inputs(inputs)
    strings = catalog["strings"]
    errors, added, kept = [], 0, 0
    for lang, table in data.items():
        if lang not in langs:
            continue
        for key, value in table.items():
            if key not in strings:
                errors.append(f"{key} [{lang}]: not in the catalog")
                continue
            if value in ("", None) or (isinstance(value, dict) and not any(value.values())):
                continue   # unfilled template slot
            entry = strings[key]
            if not L.problems(key, entry, lang) and not replace:
                kept += 1
                continue
            candidate = json.loads(json.dumps(entry))
            candidate["localizations"][lang] = localisation(value, lang)
            found = L.problems(key, candidate, lang)
            if found:
                errors.extend(found)
                continue
            entry["localizations"][lang] = candidate["localizations"][lang]
            added += 1
    if errors:
        print("\n".join(f"error: {e}" for e in errors), file=sys.stderr)
        print(f"{len(errors)} problem(s); catalog NOT written", file=sys.stderr)
        return 1
    derived = derive_sr_latn(catalog) if "sr-Latn" in langs else 0
    path.write_text(L.dump(catalog), encoding="utf-8")
    print(f"merged {added} translations (state {L.REVIEW_STATE}); kept {kept} existing; "
          f"{derived} sr-Latn derived from sr; catalog written")
    return 0


def derive_sr_latn(catalog):
    """sr (Cyrillic) is the authored Serbian; sr-Latn is its mechanical transliteration (1:1 alphabet mapping).
    Fills every key where sr is complete and sr-Latn is not."""
    n = 0
    for key, entry in catalog["strings"].items():
        if L.problems(key, entry, "sr") or not L.problems(key, entry, "sr-Latn"):
            continue
        src = entry["localizations"]["sr"]
        if "stringUnit" in src:
            entry["localizations"]["sr-Latn"] = L.unit(L.sr_to_latin(src["stringUnit"]["value"]))
        else:
            plural = src["variations"]["plural"]
            entry["localizations"]["sr-Latn"] = {"variations": {"plural": {
                c: L.unit(L.sr_to_latin(u["stringUnit"]["value"])) for c, u in plural.items()}}}
        n += 1
    return n


def self_test():
    import contextlib
    import io
    import tempfile
    en = lambda v: {"stringUnit": {"state": "translated", "value": v}}  # noqa: E731
    catalog = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "a": {"comment": "c", "localizations": {"en": en("Hi %@")}},
        "p": {"comment": "c", "localizations": {"en": {"variations": {"plural": {
            "one": en("%lld day"), "other": en("%lld days")}}}}},
    }}
    quiet = contextlib.redirect_stderr(io.StringIO())
    with tempfile.TemporaryDirectory() as tmp, quiet:
        path = pathlib.Path(tmp) / "Localizable.xcstrings"
        path.write_text(L.dump(catalog), encoding="utf-8")

        def merge(table, replace=False):
            f = pathlib.Path(tmp) / "in.json"
            f.write_text(json.dumps(table), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                return cmd_merge(path, L.load_catalog(path), L.TARGETS, [str(f)], replace)

        def cat():
            return L.load_catalog(path)
        checks = {}
        checks["12 languages x 2 keys missing at the start"] = sum(len(v) for v in gaps(cat(), L.TARGETS).values()) == 24
        before = path.read_text(encoding="utf-8")
        checks["wrong specifier type refused, catalog untouched"] = (
            merge({"sk": {"a": "Ahoj %lld"}}) == 1 and path.read_text(encoding="utf-8") == before)
        checks["missing specifier refused"] = merge({"sk": {"a": "Ahoj"}}) == 1
        checks["missing plural category (sk needs few, many) refused"] = (
            merge({"sk": {"p": {"one": "%lld deň", "other": "%lld dní"}}}) == 1)
        checks["category that does not exist (ja one) refused"] = merge({"ja": {"p": {"one": "%lld日"}}}) == 1
        ok = merge({"sk": {"a": "Ahoj %@", "p": {"one": "%lld deň", "few": "%lld dni", "many": "%lld dňa", "other": "%lld dní"}},
                    "sr": {"a": "Здраво %@", "p": {"one": "%lld дан", "few": "%lld дана", "other": "%lld дана"}},
                    "ja": {"p": {"other": "%lld日"}}}) == 0
        c = cat()["strings"]
        checks["valid merge accepted, state needs_review"] = (
            ok and c["a"]["localizations"]["sk"]["stringUnit"]["state"] == "needs_review")
        checks["sr-Latn derived from sr (text and plural)"] = (
            c["a"]["localizations"]["sr-Latn"]["stringUnit"]["value"] == "Zdravo %@"
            and c["p"]["localizations"]["sr-Latn"]["variations"]["plural"]["few"]["stringUnit"]["value"] == "%lld dana")
        merge({"sk": {"a": "Zmenené %@"}})
        checks["existing complete translation kept without --replace"] = (
            cat()["strings"]["a"]["localizations"]["sk"]["stringUnit"]["value"] == "Ahoj %@")
        merge({"sk": {"a": "Zmenené %@"}}, replace=True)
        checks["--replace overwrites"] = cat()["strings"]["a"]["localizations"]["sk"]["stringUnit"]["value"] == "Zmenené %@"
        g = gaps(cat(), L.TARGETS)
        checks["gaps shrink: sk, sr, sr-Latn done, ja half done"] = (
            "sk" not in g.get("a", {}) and "sk" not in g.get("p", {}) and "sr-Latn" not in g.get("a", {})
            and "ja" in g.get("a", {}) and "ja" not in g.get("p", {}))
        out = pathlib.Path(tmp) / "list.json"
        with contextlib.redirect_stdout(io.StringIO()):
            cmd_list(cat(), L.TARGETS, str(out))
        listed = json.loads(out.read_text(encoding="utf-8"))
        checks["list: template has plural categories per language"] = (
            "p" in listed["template"].get("pl", {}) and set(listed["template"]["pl"]["p"]) == {"one", "few", "many", "other"}
            and "sr-Latn" not in listed["template"])
    for name, passed in checks.items():
        print(("OK   " if passed else "FAIL ") + name)
    return 0 if all(checks.values()) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("status", "list", "merge", "self-test"))
    parser.add_argument("inputs", nargs="*", help="merge: JSON file(s) or directory of <lang>.json")
    parser.add_argument("--catalog", default=str(ROOT / "Resources/Localizable.xcstrings"))
    parser.add_argument("--langs")
    parser.add_argument("--out")
    parser.add_argument("--replace", action="store_true", help="merge: overwrite complete existing translations")
    args = parser.parse_args()
    if args.command == "self-test":
        return self_test()
    path = pathlib.Path(args.catalog)
    catalog = L.load_catalog(path)
    langs = parse_langs(args.langs)
    if args.command == "status":
        return cmd_status(catalog, langs)
    if args.command == "list":
        return cmd_list(catalog, langs, args.out)
    if not args.inputs:
        parser.error("merge needs at least one input file or directory")
    return cmd_merge(path, catalog, langs, args.inputs, args.replace)


if __name__ == "__main__":
    sys.exit(main())
