"""Shared helpers for the String Catalog tooling (scripts/l10n-*.py and scripts/validate_config.py).

Languages shipped at launch (docs/specs/LOCALIZATION.md) and the CLDR plural categories each one needs.
Identifiers are the ones used as keys in Resources/Localizable.xcstrings and as <id>.lproj folder names:
  sr      = Serbian, Cyrillic (bare "sr" is Cyrillic in Apple's tables; CLDR likely-subtags sr -> sr-Cyrl-RS)
  sr-Latn = Serbian, Latin
  zh-Hans = Chinese, Simplified
"""
import json
import pathlib
import re

SOURCE = "en"
TARGETS = ("sk", "cs", "pl", "hu", "ro", "de", "fr", "uk", "sr", "sr-Latn", "ja", "zh-Hans")
LANGS = (SOURCE,) + TARGETS

# CLDR 46 plural categories for integer counts (what %lld receives). "many" for sk/cs only matters for
# fractions and is filled with the "other" text; fr "many" (1 000 000) falls back to "other" in stringsdict.
# sr has NO "many" in CLDR (one/few/other); the brief asked for four Serbian categories, CLDR says three.
PLURAL_CATEGORIES = {
    "en": ("one", "other"),
    "sk": ("one", "few", "many", "other"),
    "cs": ("one", "few", "many", "other"),
    "pl": ("one", "few", "many", "other"),
    "uk": ("one", "few", "many", "other"),
    "sr": ("one", "few", "other"),
    "sr-Latn": ("one", "few", "other"),
    "ro": ("one", "few", "other"),
    "hu": ("one", "other"),
    "de": ("one", "other"),
    "fr": ("one", "other"),
    "ja": ("other",),
    "zh-Hans": ("other",),
}
ALL_CATEGORIES = ("zero", "one", "two", "few", "many", "other")
REVIEW_STATE = "needs_review"
ACCEPTED_STATES = ("translated", "needs_review", "stale")   # anything but "new"

SPEC = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSp])")


def dump(data: dict) -> str:
    """Canonical catalog form (identical to scripts/l10n-add.py and Xcode)."""
    return json.dumps(data, indent=2, separators=(",", " : "), ensure_ascii=False, sort_keys=True) + "\n"


def load_catalog(path) -> dict:
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def specs(text: str) -> list:
    """Sorted [(argument position, length modifier + type)]; unnumbered specifiers are numbered in order."""
    out, seq = [], 0
    for m in SPEC.finditer(text.replace("%%", "")):
        seq += 1
        out.append((int(m.group(1)) if m.group(1) else seq, (m.group(2) or "") + m.group(3)))
    return sorted(out)


def unit(value: str) -> dict:
    return {"stringUnit": {"state": REVIEW_STATE, "value": value}}


def english_shape(entry: dict):
    """('string', 'text') or ('plural', {category: text}) for the English localisation of one catalog entry."""
    en = entry.get("localizations", {}).get(SOURCE)
    if en is None:
        return None
    if "stringUnit" in en:
        return ("string", en["stringUnit"]["value"])
    plural = en.get("variations", {}).get("plural")
    if plural:
        return ("plural", {c: u["stringUnit"]["value"] for c, u in plural.items()})
    return None


def translation_forms(loc: dict | None):
    """('string', text|None, state) / ('plural', {cat: (text, state)}) / None for one language's localisation."""
    if not loc:
        return None
    if "stringUnit" in loc:
        u = loc["stringUnit"]
        return ("string", u.get("value"), u.get("state"))
    plural = loc.get("variations", {}).get("plural")
    if plural:
        return ("plural", {c: (u.get("stringUnit", {}).get("value"), u.get("stringUnit", {}).get("state"))
                           for c, u in plural.items()})
    return None


def problems(key: str, entry: dict, lang: str) -> list:
    """Why <lang> is not a complete, well-formed translation of <entry> (empty list = OK)."""
    shape = english_shape(entry)
    if shape is None:
        return [f"{key}: no English source value"]
    forms = translation_forms(entry.get("localizations", {}).get(lang))
    if forms is None:
        return [f"{key} [{lang}]: missing"]
    out = []
    kind, en_value = shape
    if kind == "string":
        if forms[0] != "string":
            return [f"{key} [{lang}]: English is a plain string, translation uses plural variations"]
        _, value, state = forms
        if not value:
            return [f"{key} [{lang}]: empty value"]
        if state not in ACCEPTED_STATES:
            out.append(f"{key} [{lang}]: state {state!r} (new)")
        if specs(value) != specs(en_value):
            out.append(f"{key} [{lang}]: format specifiers {specs(value)} != English {specs(en_value)}")
        return out
    if forms[0] != "plural":
        return [f"{key} [{lang}]: English has plural variations, translation is a plain string"]
    have = forms[1]
    need = PLURAL_CATEGORIES[lang]
    missing = [c for c in need if c not in have]
    if missing:
        out.append(f"{key} [{lang}]: missing plural categories {missing} (needs {list(need)})")
    reference = specs(en_value["other"])
    for cat, (value, state) in have.items():
        if cat not in ALL_CATEGORIES:
            out.append(f"{key} [{lang}]: unknown plural category {cat!r}")
        elif cat not in need and cat != "many":
            out.append(f"{key} [{lang}]: plural category {cat!r} does not exist in this language")
        elif not value:
            out.append(f"{key} [{lang}]: empty plural form {cat!r}")
        elif state not in ACCEPTED_STATES:
            out.append(f"{key} [{lang}]: plural form {cat!r} has state {state!r}")
        elif specs(value) != reference:
            out.append(f"{key} [{lang}]: plural form {cat!r} specifiers {specs(value)} != English {reference}")
    return out


def all_problems(catalog: dict, langs=TARGETS) -> list:
    out = []
    for key in sorted(catalog["strings"]):
        for lang in langs:
            out.extend(problems(key, catalog["strings"][key], lang))
    return out
