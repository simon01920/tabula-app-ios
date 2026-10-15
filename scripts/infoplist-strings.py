#!/usr/bin/env python3
"""Generate <lang>.lproj/InfoPlist.strings from Resources/InfoPlist.xcstrings (xtool/local build path).

Why: Xcode compiles InfoPlist.xcstrings itself (XcodeGen/CI path, project.yml), but xtool/SwiftPM on Linux
cannot compile any .xcstrings. This is a thin wrapper over scripts/l10n-compile.py (the table name is the
catalog's file stem, so the output is InfoPlist.strings) that also checks the catalog covers every
user-visible key of Config/App-Info.plist, so a new NS*UsageDescription cannot ship unlocalised.
scripts/xtool-dev.sh runs it after the Localizable compile into the same .build-l10n/ directory; xtool.yml
copies the <lang>.lproj folders (InfoPlist.strings + Localizable.strings) into the .app and the widget appex.
Output is git-ignored (.build-l10n/), so there is nothing to keep in sync.

Usage: python3 scripts/infoplist-strings.py [OUT_DIR]      (default .build-l10n)
"""
import json
import pathlib
import plistlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "InfoPlist.xcstrings"
APP_PLIST = ROOT / "Config" / "App-Info.plist"


def user_visible_keys(plist: dict) -> set:
    """Keys of an Info.plist whose values are shown to people (usage descriptions + the display name)."""
    return {k for k in plist if k == "CFBundleDisplayName" or (k.startswith("NS") and k.endswith("UsageDescription"))}


def main() -> int:
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".build-l10n"
    wanted = user_visible_keys(plistlib.load(open(APP_PLIST, "rb")))
    have = set(json.loads(CATALOG.read_text(encoding="utf-8"))["strings"])
    if wanted - have:
        print(f"error: {APP_PLIST.name} keys missing from {CATALOG.name}: {sorted(wanted - have)}", file=sys.stderr)
        return 1
    return subprocess.call([sys.executable, "-B", str(ROOT / "scripts" / "l10n-compile.py"), str(CATALOG), str(out)])


if __name__ == "__main__":
    sys.exit(main())
