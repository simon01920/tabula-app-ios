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
    path.write_text(L.dump(catalog), encoding="utf-8")
    print(f"merged {added} translations (state {L.REVIEW_STATE}); kept {kept} existing; catalog written")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("status", "list", "merge"))
    parser.add_argument("inputs", nargs="*", help="merge: JSON file(s) or directory of <lang>.json")
    parser.add_argument("--catalog", default=str(ROOT / "Resources/Localizable.xcstrings"))
    parser.add_argument("--langs")
    parser.add_argument("--out")
    parser.add_argument("--replace", action="store_true", help="merge: overwrite complete existing translations")
    args = parser.parse_args()
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
