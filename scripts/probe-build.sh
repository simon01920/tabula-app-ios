#!/usr/bin/env bash
# Build one of the isolated Phase 0 probe packages under Probes/ with xtool (inside WSL, needs the Darwin SDK).
# Probes are separate SwiftPM packages so an expected failure cannot break the main app build.
#
#   bash scripts/probe-build.sh MacroProbeSwiftData   # expect FAIL: SwiftDataMacros not provided (xtool #149)
#   bash scripts/probe-build.sh XCStringsSwiftPM       # does SwiftBuild compile a catalog for iOS on Linux?
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"

NAME="${1:?usage: probe-build.sh <ProbeDirName>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/Probes/$NAME"
WORK="${TABULA_WORKDIR:-$HOME/.cache/tabula/work}-probes/$NAME"
[ -d "$SRC" ] || { echo "error: no such probe: $SRC" >&2; exit 1; }

mkdir -p "$WORK"
rsync -a --delete --exclude 'xtool/' --exclude '.build/' "$SRC/" "$WORK/"
cd "$WORK"
echo "+ (cd $WORK && xtool dev build)"
set +e
xtool dev build 2>&1 | tee build.log
STATUS=${PIPESTATUS[0]}
set -e
echo "xtool dev build exit status: $STATUS (log: $WORK/build.log)"
if [ -d xtool ]; then
  echo "--- bundle contents (lproj / xcstrings / strings files):"
  find xtool -maxdepth 4 \( -name '*.lproj' -o -name '*.xcstrings' -o -name '*.strings' -o -name '*.stringsdict' -o -name '*.bundle' \) | sort
fi
exit "$STATUS"
