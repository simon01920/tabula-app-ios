#!/usr/bin/env bash
# Build / install the iOS app with xtool from an ext4 copy of the repo (inside WSL).
#
# Why a wrapper:
#  - xtool builds into ./xtool and ./xtool/.xtool-tmp/.build relative to the CWD; on /mnt/c (9P) that is slow.
#  - xtool cannot compile .xcstrings, so the catalog is compiled to .build-l10n/*.lproj first (xtool.yml copies them).
#  - Macro isolation (CLAUDE.md rule 5): the default build is the macro-free BASE variant. `--macro-probes`
#    sets TABULA_MACRO_PROBES=1 for manifest evaluation (Package.swift) and builds the MACRO variant in a
#    separate work dir, so the two variants never share build state.
#
# Usage (inside WSL, from anywhere):
#   bash scripts/xtool-dev.sh                      # base variant: xtool dev run (build + install + launch)
#   bash scripts/xtool-dev.sh build                # base variant: xtool dev build (unsigned .app)
#   bash scripts/xtool-dev.sh --macro-probes       # macro variant: build + install + launch
#   bash scripts/xtool-dev.sh --macro-probes build --ipa
# Env: TABULA_WORKDIR (default ~/.cache/tabula/work; the macro variant uses "<workdir>-macro")
set -euo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${TABULA_WORKDIR:-$HOME/.cache/tabula/work}"

VARIANT="base"
if [ "${1:-}" = "--macro-probes" ]; then
  shift
  VARIANT="macro-probes"
  WORK="$WORK-macro"
  export TABULA_MACRO_PROBES=1
else
  unset TABULA_MACRO_PROBES
fi

if ! command -v xtool >/dev/null 2>&1; then
  echo "error: xtool not on PATH. Install it per docs/ENVIRONMENT.md (xtool section)." >&2
  exit 1
fi
if xtool sdk status 2>/dev/null | grep -qi "not installed"; then
  echo "error: Darwin SDK not installed. Human step: run 'xtool setup' (see docs/ENVIRONMENT.md, Human steps)." >&2
  exit 2
fi

mkdir -p "$WORK"
# Keep xtool/ and .build/ in the work dir between runs; they are excluded from sync+delete.
rsync -a --delete \
  --exclude '.git/' --exclude 'xtool/' --exclude '.build/' --exclude '.build-l10n/' \
  --exclude 'examples/' --exclude 'spikes/' --exclude '*.zip' --exclude '*.xip' \
  "$REPO_ROOT/" "$WORK/"

rm -rf "$WORK/.build-l10n"
python3 "$WORK/scripts/l10n-compile.py" "$WORK/Resources/Localizable.xcstrings" "$WORK/.build-l10n"

cd "$WORK"
if [ "$#" -eq 0 ]; then set -- run; fi
echo "+ variant: $VARIANT (TABULA_MACRO_PROBES=${TABULA_MACRO_PROBES:-unset})"
echo "+ (cd $WORK && xtool dev $*)"
xtool dev "$@"
echo "xtool output directory: $WORK/xtool/"
