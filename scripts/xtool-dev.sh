#!/usr/bin/env bash
# Build / install the iOS app with xtool from an ext4 copy of the repo (inside WSL).
#
# Why a wrapper:
#  - xtool builds into ./xtool and ./xtool/.xtool-tmp/.build relative to the CWD; on /mnt/c (9P) that is slow.
#  - xtool cannot compile .xcstrings, so the catalog is compiled to .build-l10n/*.lproj first (xtool.yml copies them):
#    app = Localizable + InfoPlist.strings, widget = .build-l10n/widget/*.lproj with Localizable only (as project.yml).
#  - Macro isolation (CLAUDE.md rule 5): the default build is the macro-free BASE variant. `--macro-probes`
#    sets TABULA_MACRO_PROBES=1 for manifest evaluation (Package.swift) and builds the MACRO variant in a
#    separate work dir, so the two variants never share build state.
#  - `--simulator` builds an arm64 iOS-Simulator .app (unsigned, ad-hoc entitlements) in its own work dir.
#    VERIFIED 2026-10-06: produces Mach-O platform 7 (iOS Simulator). There is no simulator on Windows/WSL; the
#    .app is only useful for a hosted simulator service or a Mac (docs/ENVIRONMENT.md §19).
#  - After every build it checks the widget appex still contains code (regression guard for the empty-appex
#    bug fixed in Package.swift, see ENVIRONMENT §5).
#
# Usage (inside WSL, from anywhere):
#   bash scripts/xtool-dev.sh                      # base variant: xtool dev run (build + install + launch)
#   bash scripts/xtool-dev.sh build                # base variant: xtool dev build (unsigned .app)
#   bash scripts/xtool-dev.sh --macro-probes       # macro variant: build + install + launch
#   bash scripts/xtool-dev.sh --macro-probes build --ipa
#   bash scripts/xtool-dev.sh --simulator          # base variant, iOS Simulator .app (build only)
# Env: TABULA_WORKDIR (default ~/.cache/tabula/work; variants append -macro / -sim)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/toolchain.sh
. "$REPO_ROOT/scripts/lib/toolchain.sh"
tabula_load_toolchain          # swift + clang from swiftly, also in non-login shells (wsl.exe -- bash -c …)
WORK="${TABULA_WORKDIR:-$HOME/.cache/tabula/work}"

VARIANT="base"
SIMULATOR=0
unset TABULA_MACRO_PROBES
while [ "$#" -gt 0 ]; do
  case "$1" in
    --macro-probes) VARIANT="macro-probes"; WORK="$WORK-macro"; export TABULA_MACRO_PROBES=1; shift ;;
    --simulator) SIMULATOR=1; WORK="$WORK-sim"; shift ;;
    *) break ;;
  esac
done

tabula_require swift clang xtool
if xtool sdk status 2>/dev/null | grep -qi "not installed"; then
  echo "error: Darwin SDK not installed. Human step: run 'xtool setup' (see docs/ENVIRONMENT.md, Human steps)." >&2
  exit 2
fi

mkdir -p "$WORK"
# Keep xtool/ and .build/ in the work dir between runs; they are excluded from sync+delete.
rsync -a --delete \
  --exclude '.git/' --exclude '.claude/' --exclude 'xtool/' --exclude '.build/' --exclude '.build-l10n/' \
  --exclude 'examples/' --exclude 'spikes/' --exclude '*.zip' --exclude '*.xip' \
  "$REPO_ROOT/" "$WORK/"

rm -rf "$WORK/.build-l10n"
python3 "$WORK/scripts/l10n-compile.py" "$WORK/Resources/Localizable.xcstrings" "$WORK/.build-l10n"
python3 "$WORK/scripts/infoplist-strings.py" "$WORK/.build-l10n"
# The widget gets its own Localizable-only copy (xtool.yml): InfoPlist.strings (the app's display name and usage
# descriptions) must not reach the appex, matching project.yml where InfoPlist.xcstrings is an app-only resource.
python3 "$WORK/scripts/l10n-compile.py" "$WORK/Resources/Localizable.xcstrings" "$WORK/.build-l10n/widget"
# Package into a fresh .app so files from an older layout cannot linger in it (the build cache stays).
rm -rf "$WORK/xtool/TabulaApp.app"

cd "$WORK"
if [ "$SIMULATOR" -eq 1 ]; then
  [ "$#" -eq 0 ] || { echo "error: --simulator takes no further xtool arguments (it always runs a build)" >&2; exit 64; }
  set -- build --triple arm64-apple-ios-simulator
elif [ "$#" -eq 0 ]; then
  set -- run
fi
echo "+ variant: $VARIANT (TABULA_MACRO_PROBES=${TABULA_MACRO_PROBES:-unset})$([ "$SIMULATOR" -eq 1 ] && echo ', iOS Simulator')"
echo "+ (cd $WORK && xtool dev $*)"
xtool dev "$@"

for bundle in "$WORK/xtool/TabulaApp.app" "$WORK/xtool/TabulaApp.app/PlugIns/TabulaWidgets.appex"; do
  if [ -d "$bundle" ]; then
    echo "+ localisations in ${bundle#"$WORK"/xtool/}: $(cd "$bundle" && ls -d ./*.lproj | sed 's|^\./||; s|\.lproj$||' | tr '\n' ' ')"
    echo "+ InfoPlist.strings in ${bundle#"$WORK"/xtool/}: $(cd "$bundle" && ls ./*.lproj/InfoPlist.strings 2>/dev/null | wc -l) files"
  fi
done
WIDGET_BUNDLE="$WORK/xtool/TabulaApp.app/PlugIns/TabulaWidgets.appex"
if [ -d "$WIDGET_BUNDLE" ] && ls "$WIDGET_BUNDLE"/*.lproj/InfoPlist.strings >/dev/null 2>&1; then
  echo "error: the widget appex contains InfoPlist.strings (the app's display name would override 'Tabula Widgets'); see xtool.yml." >&2
  exit 4
fi
APPEX="$WORK/xtool/TabulaApp.app/PlugIns/TabulaWidgets.appex/TabulaWidgets"
if [ -f "$APPEX" ] && command -v llvm-objdump >/dev/null 2>&1; then
  sections="$(llvm-objdump --macho --section-headers "$APPEX" 2>/dev/null || true)"
  for sect in __text __swift5_entry; do
    if ! grep -qw "$sect" <<<"$sections"; then
      echo "error: widget appex has no $sect section: its Swift code was not linked (see Package.swift, TabulaWidgets linkerSettings)." >&2
      exit 3
    fi
  done
  echo "+ widget appex check: __text + __swift5_entry present"
fi
echo "xtool output directory: $WORK/xtool/"
