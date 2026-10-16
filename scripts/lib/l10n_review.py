"""Shared helpers for the translation-review tooling (scripts/l10n-review-export.py, l10n-review-import.py).

Reads Resources/Localizable.xcstrings and Resources/InfoPlist.xcstrings into flat review rows (one per key and
plural form), computes the catalog hash used for the staleness check, and keeps the review baseline.
Standard library only.
"""
import hashlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from l10n_common import ALL_CATEGORIES, LANGS, SOURCE, TARGETS, load_catalog  # noqa: E402,F401

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
CATALOGS = (("L", "Resources/Localizable.xcstrings"), ("I", "Resources/InfoPlist.xcstrings"))
REVIEW_DIR = ROOT / "docs/localization/review"
BASELINE_NAME = "baseline.json"
HASH_NAME = "SOURCE_HASH"
EXPORT_VERSION = "1"   # bump when the export format changes: the hash changes and validate.sh warns until regenerated
APPROVE = "[ok]"       # corrected-cell marker: "the current translation is right, mark it reviewed"

LANG_NAMES = {
    "en": "English", "sk": "Slovenčina", "cs": "Čeština", "pl": "Polski", "hu": "Magyar", "ro": "Română",
    "de": "Deutsch", "fr": "Français", "uk": "Українська", "sr": "Српски (ćirilica)", "sr-Latn": "Srpski (latinica)",
    "ja": "日本語", "zh-Hans": "简体中文",
}


def catalog_paths(root=ROOT):
    return [(cid, pathlib.Path(root) / rel) for cid, rel in CATALOGS]


def source_hash(paths=None, baseline_path=None) -> str:
    """sha256 over both catalogs (CR removed, so a CRLF checkout hashes the same), the baseline and the format version."""
    h = hashlib.sha256(EXPORT_VERSION.encode())
    for cid, p in (paths or catalog_paths()):
        h.update(cid.encode())
        h.update(pathlib.Path(p).read_bytes().replace(b"\r", b""))
    bp = pathlib.Path(baseline_path) if baseline_path else REVIEW_DIR / BASELINE_NAME
    h.update(bp.read_bytes().replace(b"\r", b"") if bp.exists() else b"")
    return h.hexdigest()


def form_order(form: str) -> int:
    return ALL_CATEGORIES.index(form) if form in ALL_CATEGORIES else -1


def lang_cells(loc: dict) -> dict:
    """{form: (text, state)} for one language localization. A plain string unit has the single form ''."""
    if not loc:
        return {}
    if "stringUnit" in loc:
        u = loc["stringUnit"]
        return {"": (u.get("value", ""), u.get("state", "translated"))}
    out = {}
    for cat, node in loc.get("variations", {}).get("plural", {}).items():
        u = node.get("stringUnit", {})
        out[cat] = (u.get("value", ""), u.get("state", "translated"))
    return out


def english_ref(en_cells: dict, form: str) -> str:
    """The English text a translation of `form` is compared with (format specifiers) and shown next to."""
    if form in en_cells:
        return en_cells[form][0]
    if "other" in en_cells:
        return en_cells["other"][0]
    return en_cells[""][0] if "" in en_cells else ""


def collect(paths=None):
    """Entries sorted by key: {key, cat, comment, forms:[...], cells:{lang:{form:(text,state)}}}."""
    entries, seen = [], {}
    for cid, p in (paths or catalog_paths()):
        data = load_catalog(p)
        for key, v in data["strings"].items():
            if key in seen:
                raise SystemExit(f"error: key {key} exists in both catalogs; review tooling needs unique keys")
            seen[key] = cid
            locs = v.get("localizations", {})
            cells = {lang: lang_cells(locs.get(lang)) for lang in LANGS}
            forms = {f for c in cells.values() for f in c}
            if any(f for f in forms):   # a plural entry: a language holding a plain unit shows under "other"
                for lang, c in cells.items():
                    if "" in c:
                        c["other"] = c.pop("")
                        forms.discard("")
                        forms.add("other")
            entries.append({"key": key, "cat": cid, "comment": v.get("comment", ""),
                            "forms": sorted(forms, key=form_order), "cells": cells})
    entries.sort(key=lambda e: e["key"])
    return entries


def row_id(lang, cat, key, form) -> str:
    return f"{lang}|{cat}:{key}|{form}"


def row_hash(english: str, value: str) -> str:
    return hashlib.sha1((english + "\x1f" + value).encode("utf-8")).hexdigest()[:12]


def load_baseline(path=None) -> dict:
    p = pathlib.Path(path) if path else REVIEW_DIR / BASELINE_NAME
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def dump_baseline(data: dict) -> str:
    return json.dumps(data, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def is_changed(baseline, lang, cat, key, form, english, value, state) -> bool:
    """Differs from what a reviewer last signed off. With no baseline entry: changed = not yet marked translated."""
    if lang == SOURCE:
        return False
    old = baseline.get(row_id(lang, cat, key, form))
    if old is not None:
        return old != row_hash(english, value)
    return state != "translated"
