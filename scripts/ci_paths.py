#!/usr/bin/env python3
"""Decide whether a change set needs the macOS jobs of .github/workflows/ios.yml (private repo: billed minutes).

Reads changed paths (one per line, e.g. `git diff --name-only BASE HEAD`) on stdin and prints `app=true|false`
for $GITHUB_OUTPUT; the matched paths go to stderr. The Linux job always runs for code changes; only the
macOS jobs (XcodeGen build, xtool build) are gated by this. workflow_dispatch bypasses it (always runs all).

App-relevant = anything compiled or packaged into the app (orchestrator decision 2026-10-06). Tests-only
changes, docs, Probes/, spikes/ and other scripts do NOT start a macOS runner. Deviations from the
orchestrator's list, both documented in docs/ENVIRONMENT.md §8: `Packages/TimetableUI/**` is narrowed to
Sources + Package.swift (its Tests/ are Linux-only), and `scripts/identity.py` is added because the
ios-xcodegen job executes it.

  git diff --name-only "$BASE" HEAD | python3 scripts/ci_paths.py >> "$GITHUB_OUTPUT"
  python3 scripts/ci_paths.py --self-test
"""
import sys

# Entries ending in "/" match a directory prefix; all others match one exact path.
APP_RELEVANT = (
    "App/",
    "WidgetExtension/",
    "WatchApp/",
    "Packages/TimetableUI/Sources/",
    "Packages/TimetableUI/Package.swift",
    "Packages/TimetableCore/Sources/",
    "Packages/TimetableCore/Package.swift",
    "Config/",
    "Resources/",
    "Package.swift",
    "project.yml",
    "xtool.yml",
    "scripts/l10n-compile.py",
    "scripts/identity.py",
    ".github/workflows/ios.yml",
)


def is_app_relevant(path):
    path = path.strip()
    path = path[2:] if path.startswith("./") else path
    return any(path.startswith(p) if p.endswith("/") else path == p for p in APP_RELEVANT)


def classify(paths):
    hits = [p.strip() for p in paths if p.strip() and is_app_relevant(p)]
    return bool(hits), hits


CASES = {
    "App/Sources/TabulaApp.swift": True,
    "WidgetExtension/Sources/TabulaWidgets.swift": True,
    "WatchApp/Sources/TabulaWatchApp.swift": True,
    "Packages/TimetableUI/Sources/TimetableUI/TimetableUI.swift": True,
    "Packages/TimetableUI/Package.swift": True,
    "Packages/TimetableCore/Sources/TimetableCore/AppGroup.swift": True,
    "Packages/TimetableCore/Package.swift": True,
    "Config/AppIdentity.xcconfig": True,
    "Config/Entitlements/PaidAccount/Tabula.entitlements": True,
    "Resources/Localizable.xcstrings": True,
    "Package.swift": True,
    "project.yml": True,
    "xtool.yml": True,
    "scripts/l10n-compile.py": True,
    "scripts/identity.py": True,
    ".github/workflows/ios.yml": True,
    "Packages/TimetableCore/Tests/TimetableCoreTests/TimetableCoreTests.swift": False,
    "Packages/TimetableUI/Tests/TimetableUITests/LaunchArgumentsTests.swift": False,
    "docs/ENVIRONMENT.md": False,
    "CLAUDE.md": False,
    "Probes/MacroProbeSwiftData/Package.swift": False,
    "spikes/llm-runtime/README.md": False,
    "scripts/validate.sh": False,
    "scripts/validate_config.py": False,
    ".github/workflows/ui-screenshots.yml": False,
    "Package.swift.orig": False,
    "AppendixNotes.md": False,
    "./.github/workflows/ios.yml": True,
    "./App/Sources/TabulaApp.swift": True,
}


def self_test():
    bad = [(p, want) for p, want in CASES.items() if is_app_relevant(p) != want]
    for p, want in bad:
        print(f"FAIL {p}: expected app={str(want).lower()}")
    empty, _ = classify([])
    if empty:
        bad.append(("<empty>", False)); print("FAIL empty change set must not be app-relevant")
    mixed, hits = classify(["docs/x.md", "App/Sources/a.swift", ""])
    if not mixed or hits != ["App/Sources/a.swift"]:
        bad.append(("<mixed>", True)); print(f"FAIL mixed change set: {mixed} {hits}")
    print(f"ci_paths self-test: {len(CASES) + 2 - len(bad)}/{len(CASES) + 2} cases OK")
    return 1 if bad else 0


def main():
    if "--self-test" in sys.argv[1:]:
        sys.exit(self_test())
    relevant, hits = classify(sys.stdin.read().splitlines())
    print(f"app-relevant paths: {hits or 'none'}", file=sys.stderr)
    print(f"app={'true' if relevant else 'false'}")


if __name__ == "__main__":
    main()
