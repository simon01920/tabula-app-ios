#!/usr/bin/env python3
"""Compile a String Catalog (.xcstrings) into <lang>.lproj/<Table>.strings + .stringsdict.

Why: on the local xtool path nothing compiles .xcstrings (verified in Phase 0: SwiftPM/SwiftBuild on
Linux copy the catalog verbatim; Apple's `xcstringstool` is a macOS binary). iOS only reads compiled
tables at runtime, so without this step the app shows raw keys. The XcodeGen/CI path does NOT use this
script: Xcode compiles the same catalog itself. Output is git-ignored (.build-l10n/).

Supported: plain stringUnit values and single-argument plural variations. The table name is the file
stem, so InfoPlist.xcstrings -> InfoPlist.strings works too.
Skipped with a warning: units that are empty or in state "new"; the language then falls back to the
source-language value (same for keys that have no translation at all).
Rejected (non-zero exit): substitutions (multi-argument plurals) and device variations.

Usage: python3 scripts/l10n-compile.py Resources/Localizable.xcstrings .build-l10n
       python3 scripts/l10n-compile.py --self-test
"""
import json
import pathlib
import plistlib
import re
import sys
import tempfile

PRINTF = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSp])")
PLURAL_CATEGORIES = ("zero", "one", "two", "few", "many", "other")


def value_type(forms: dict, key: str) -> str:
    """Format type of the plural-driving argument (argument 1) from the plural forms of one language.

    "%%" is a literal percent sign, not a specifier. Positional specifiers are honoured: a translation may put
    "%2$@" before "%1$lld" (word order), so the first match is not necessarily argument 1. Falls back to the
    first specifier found when no form mentions argument 1 explicitly."""
    first = None
    for text in [forms["other"]] + [t for c, t in forms.items() if c != "other"]:
        seq = 0
        for match in PRINTF.finditer(text.replace("%%", "")):
            seq += 1
            position = int(match.group(0).split("$")[0][1:]) if "$" in match.group(0) else seq
            kind = (match.group(1) or "") + match.group(2)
            if position == 1:
                return kind
            first = first or kind
    if first is None:
        raise ValueError(f"plural variant for '{key}' has no format specifier: {forms['other']!r}")
    return first


def usable(unit: dict | None) -> bool:
    return bool(unit) and unit.get("state") != "new" and unit.get("value", "") != ""


def compile_catalog(catalog_path: pathlib.Path, out_dir: pathlib.Path) -> int:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    source = catalog.get("sourceLanguage", "en")
    table = catalog_path.stem
    strings: dict[str, dict[str, str]] = {}
    plurals: dict[str, dict[str, dict]] = {}
    errors: list[str] = []
    warnings: list[str] = []
    keys = sorted(catalog.get("strings", {}))

    for key in keys:
        locs = catalog["strings"][key].get("localizations", {})
        if source not in locs:
            # Xcode uses the key itself as the source value when no explicit source localization exists.
            strings.setdefault(source, {})[key] = key
        for lang, loc in locs.items():
            if "substitutions" in loc:
                errors.append(f"{key} [{lang}]: substitutions are not supported")
                continue
            if "stringUnit" in loc:
                if usable(loc["stringUnit"]):
                    strings.setdefault(lang, {})[key] = loc["stringUnit"]["value"]
                else:
                    warnings.append(f"{key} [{lang}]: empty or state 'new' -> skipped")
                continue
            variations = loc.get("variations", {})
            if "device" in variations:
                errors.append(f"{key} [{lang}]: device variations are not supported")
                continue
            plural = variations.get("plural")
            if not plural:
                errors.append(f"{key} [{lang}]: no stringUnit or plural variation")
                continue
            forms = {cat: plural[cat]["stringUnit"]["value"] for cat in PLURAL_CATEGORIES
                     if cat in plural and usable(plural[cat].get("stringUnit"))}
            if "other" not in forms:
                warnings.append(f"{key} [{lang}]: plural lacks a usable 'other' form -> skipped")
                continue
            try:
                value_kind = value_type(forms, key)
            except ValueError as exc:
                errors.append(str(exc))
                continue
            arg = {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": value_kind}
            arg.update(forms)
            plurals.setdefault(lang, {})[key] = {"NSStringLocalizedFormatKey": "%#@arg@", "arg": arg}

    # Every key must exist in the source language; other languages fall back to it.
    for key in keys:
        if key not in strings.get(source, {}) and key not in plurals.get(source, {}):
            errors.append(f"{key} [{source}]: no usable source-language value")
    all_langs = set(strings) | set(plurals)
    for lang in sorted(all_langs - {source}):
        for key in keys:
            if key in strings.get(lang, {}) or key in plurals.get(lang, {}):
                continue
            if key in plurals.get(source, {}):
                plurals.setdefault(lang, {})[key] = plurals[source][key]
            elif key in strings.get(source, {}):
                strings.setdefault(lang, {})[key] = strings[source][key]
            warnings.append(f"{key} [{lang}]: no usable translation -> source language ({source}) value used")

    if errors:
        for message in errors:
            print(f"error: {message}", file=sys.stderr)
        return 1

    for lang in sorted(all_langs):
        lproj = out_dir / f"{lang}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)
        # Property-list formatted .strings files are valid (Xcode itself can emit binary plists).
        with open(lproj / f"{table}.strings", "wb") as fh:
            plistlib.dump(strings.get(lang, {}), fh, fmt=plistlib.FMT_XML, sort_keys=True)
        if lang in plurals:
            with open(lproj / f"{table}.stringsdict", "wb") as fh:
                plistlib.dump(plurals[lang], fh, fmt=plistlib.FMT_XML, sort_keys=True)
        print(f"{lproj}: {len(strings.get(lang, {}))} strings, {len(plurals.get(lang, {}))} plurals")
    for message in warnings:
        print(f"warning: {message}", file=sys.stderr)
    return 0


def self_test() -> int:
    """Edge cases: '%%' before a specifier, empty and 'new' units, missing translations, every plural category set
    (sk 4, sr 3, ja 1), hyphenated lproj names (sr-Latn, zh-Hans), positional re-ordering (%2$@ before %1$lld)."""
    unit = lambda value, state="translated": {"stringUnit": {"state": state, "value": value}}  # noqa: E731
    catalog = {"sourceLanguage": "en", "version": "1.0", "strings": {
        "pct %lld": {"localizations": {"en": {"variations": {"plural": {
            "one": unit("100%% of %lld"), "other": unit("100%% of %lld items")}}}}},
        "hello": {"localizations": {"en": unit("Hello"), "sk": unit("", "translated"), "de": unit("Hallo", "new")}},
        "bye": {"localizations": {"en": unit("Bye"), "sk": unit("Ahoj")}},
        "days": {"localizations": {
            "en": {"variations": {"plural": {"one": unit("In %1$lld day (%2$@)"), "other": unit("In %1$lld days (%2$@)")}}},
            "sk": {"variations": {"plural": {c: unit(f"Za %1$lld {c} (%2$@)") for c in ("one", "few", "many", "other")}}},
            "sr": {"variations": {"plural": {c: unit(f"Za %1$lld {c} (%2$@)") for c in ("one", "few", "other")}}},
            "sr-Latn": {"variations": {"plural": {c: unit(f"Za %1$lld {c} (%2$@)") for c in ("one", "few", "other")}}},
            "ja": {"variations": {"plural": {"other": unit("%2$@の%1$lld日後")}}},
            "zh-Hans": {"variations": {"plural": {"other": unit("%1$lld天后（%2$@）")}}},
        }},
    }}
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "Localizable.xcstrings"
        src.write_text(json.dumps(catalog), encoding="utf-8")
        out = pathlib.Path(tmp) / "out"
        rc = compile_catalog(src, out)
        en_pl = plistlib.load(open(out / "en.lproj/Localizable.stringsdict", "rb"))
        sk = plistlib.load(open(out / "sk.lproj/Localizable.strings", "rb"))
        sk_pl = plistlib.load(open(out / "sk.lproj/Localizable.stringsdict", "rb"))
        sk_days = sk_pl["days"]["arg"]
        sr_days = plistlib.load(open(out / "sr.lproj/Localizable.stringsdict", "rb"))["days"]["arg"]
        ja_days = plistlib.load(open(out / "ja.lproj/Localizable.stringsdict", "rb"))["days"]["arg"]
        checks = {
            "exit code 0": rc == 0,
            "sk emits one/few/many/other": all(c in sk_days for c in ("one", "few", "many", "other")),
            "sr emits one/few/other and no many": all(c in sr_days for c in ("one", "few", "other")) and "many" not in sr_days,
            "ja emits other only": [c for c in ja_days if c in PLURAL_CATEGORIES] == ["other"],
            "positional: %2$@ before %1$lld still gives lld": ja_days["NSStringFormatValueTypeKey"] == "lld",
            "hyphenated lproj folders sr-Latn and zh-Hans": (out / "sr-Latn.lproj").is_dir() and (out / "zh-Hans.lproj").is_dir(),
            "'%%' ignored -> value type lld": en_pl["pct %lld"]["arg"]["NSStringFormatValueTypeKey"] == "lld",
            "empty sk unit falls back to en": sk.get("hello") == "Hello",
            "real sk translation kept": sk.get("bye") == "Ahoj",
            "missing sk plural falls back to en": sk_pl.get("pct %lld") == en_pl["pct %lld"],
            "'new' de unit not emitted as German": not (out / "de.lproj").exists(),
        }
    for name, ok in checks.items():
        print(("OK   " if ok else "FAIL ") + name)
    return 0 if all(checks.values()) else 1


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    return compile_catalog(pathlib.Path(argv[1]), pathlib.Path(argv[2]))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
