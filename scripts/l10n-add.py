#!/usr/bin/env python3
"""Add strings to Resources/Localizable.xcstrings without hand-editing JSON (merge-friendly).

Why: several agents add strings in parallel. Writing the catalog exactly the way Xcode does (keys sorted,
2-space indent, " : " separators, UTF-8, trailing newline) keeps every diff to the added entries, so git merges
parallel additions with different key prefixes cleanly. Verified 2026-10-09: loading and re-writing the
committed catalog this way reproduces it byte for byte.

Every entry needs an English value and a context comment (CLAUDE.md, LOCALIZATION.md). Existing keys are
refused unless --replace is given. Only English is written; other languages come from the localisation stage.
--replace changes the English value and the comment but KEEPS existing translations (their state becomes
"needs_review" when the English text changed); add --drop-translations to remove them instead.

Usage:
  python3 scripts/l10n-add.py KEY "English value" "Context comment for translators"
  python3 scripts/l10n-add.py KEY --one "%lld lesson" --other "%lld lessons" "Comment (plural on arg 1)"
  python3 scripts/l10n-add.py --from strings.json      # {"key": {"en": "...", "comment": "..."} |
                                                         #         {"one": "...", "other": "...", "comment": "..."}}
  python3 scripts/l10n-add.py --check                  # verify the file is in canonical form (exit 1 if not)
  python3 scripts/l10n-add.py --remove KEY [KEY ...]   # delete keys that are no longer used (all languages)
Options: --catalog PATH (default Resources/Localizable.xcstrings), --replace [--drop-translations]
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def dump(data: dict) -> str:
    return json.dumps(data, indent=2, separators=(",", " : "), ensure_ascii=False, sort_keys=True) + "\n"


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def mark_review(node):
    """A copy of a localization with every translated string unit marked needs_review."""
    if isinstance(node, dict):
        copy = {k: mark_review(v) for k, v in node.items()}
        if "stringUnit" in copy and copy["stringUnit"].get("state") == "translated":
            copy["stringUnit"] = {**copy["stringUnit"], "state": "needs_review"}
        return copy
    return node


def entry(spec: dict, key: str) -> dict:
    comment = (spec.get("comment") or "").strip()
    if not comment:
        raise SystemExit(f"error: {key}: a context comment is required")
    if "en" in spec:
        english = unit(spec["en"])
    elif "other" in spec:
        plural = {cat: unit(spec[cat]) for cat in ("zero", "one", "two", "few", "many", "other") if cat in spec}
        english = {"variations": {"plural": plural}}
    else:
        raise SystemExit(f"error: {key}: give an English value (en) or plural forms (one/other)")
    return {"comment": comment, "extractionState": "manual", "localizations": {"en": english}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("key", nargs="?")
    parser.add_argument("value", nargs="?")
    parser.add_argument("comment", nargs="?")
    parser.add_argument("--one")
    parser.add_argument("--other")
    parser.add_argument("--from", dest="source")
    parser.add_argument("--catalog", default=str(ROOT / "Resources/Localizable.xcstrings"))
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--drop-translations", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--remove", nargs="+", metavar="KEY", help="delete unused keys (every language)")
    args = parser.parse_args()

    path = pathlib.Path(args.catalog)
    raw = path.read_text(encoding="utf-8")
    data = json.loads(raw)
    if args.check:
        if dump(data) != raw:
            print(f"FAIL {path}: not in canonical form (run any l10n-add.py command to rewrite it)")
            return 1
        print(f"OK   {path}: canonical form, {len(data['strings'])} keys")
        return 0
    if args.remove:
        missing = [k for k in args.remove if k not in data.get("strings", {})]
        if missing:
            raise SystemExit(f"error: not in the catalog: {missing}")
        for key in args.remove:
            del data["strings"][key]
            print(f"removed {key} (all languages)")
        path.write_text(dump(data), encoding="utf-8")
        return 0

    specs: dict[str, dict] = {}
    if args.source:
        specs = json.loads(pathlib.Path(args.source).read_text(encoding="utf-8"))
    elif args.key and args.other:
        specs = {args.key: {"one": args.one, "other": args.other, "comment": args.value}} if args.one else \
            {args.key: {"other": args.other, "comment": args.value}}
        specs[args.key] = {k: v for k, v in specs[args.key].items() if v is not None}
    elif args.key and args.value is not None:
        specs = {args.key: {"en": args.value, "comment": args.comment}}
    else:
        parser.error("give KEY VALUE COMMENT, KEY --one/--other COMMENT, --from FILE or --check")

    strings = data.setdefault("strings", {})
    for key, spec in specs.items():
        if key in strings and not args.replace:
            raise SystemExit(f"error: {key} already exists (use --replace to overwrite)")
        new = entry(spec, key)
        old = strings.get(key)
        if old and not args.drop_translations:
            english_changed = old.get("localizations", {}).get("en") != new["localizations"]["en"]
            for lang, value in old.get("localizations", {}).items():
                if lang != "en":
                    new["localizations"][lang] = mark_review(value) if english_changed else value
        strings[key] = new
        print(f"{'replaced' if old else 'added'} {key}{' (translations kept)' if old and not args.drop_translations else ''}")
    path.write_text(dump(data), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
