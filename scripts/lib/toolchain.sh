# shellcheck shell=bash
# Sourced (never executed) by every script that calls swift, swiftc, clang or xtool.
#
# Why: swiftly installs the toolchain into ~/.local/share/swiftly/bin and only adds it to PATH via
# ~/.profile. Non-login, non-interactive shells (`wsl.exe -- bash -c …`, `wsl.exe --exec`, cron, CI) never
# read ~/.profile, so `swift`/`clang` are missing there. VERIFIED failure (2026-10-06): the first
# `xtool sdk install` died at 99 % with "Could not find executable 'clang' in PATH" for exactly this reason.
#
# Usage:
#   . "$REPO_ROOT/scripts/lib/toolchain.sh"
#   tabula_load_toolchain              # sources swiftly's env.sh if it exists (no-op on macOS CI / swift containers)
#   tabula_require swift clang xtool   # exits with a clear message if a tool is still missing
#
# Lookup order for swiftly's env.sh: $SWIFTLY_HOME_DIR, $XDG_DATA_HOME/swiftly, $HOME/.local/share/swiftly,
# then /root/.local/share/swiftly (covers `sudo` with a changed HOME). Override with TABULA_SWIFTLY_ENV=/path/env.sh.

tabula_load_toolchain() {
  local f candidates=()
  [ -n "${TABULA_SWIFTLY_ENV:-}" ] && candidates+=("$TABULA_SWIFTLY_ENV")
  [ -n "${SWIFTLY_HOME_DIR:-}" ] && candidates+=("$SWIFTLY_HOME_DIR/env.sh")
  [ -n "${XDG_DATA_HOME:-}" ] && candidates+=("$XDG_DATA_HOME/swiftly/env.sh")
  [ -n "${HOME:-}" ] && candidates+=("$HOME/.local/share/swiftly/env.sh")
  candidates+=("/root/.local/share/swiftly/env.sh")
  for f in "${candidates[@]}"; do
    if [ -r "$f" ]; then
      # shellcheck source=/dev/null
      . "$f"
      TABULA_SWIFTLY_ENV_LOADED="$f"
      break
    fi
  done
  hash -r 2>/dev/null || true
  return 0
}

tabula_require() {
  local tool missing=0
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "error: '$tool' is not on PATH (swiftly env: ${TABULA_SWIFTLY_ENV_LOADED:-not found})." >&2
      case "$tool" in
        swift|swiftc|clang) echo "       Install Swift via swiftly (docs/ENVIRONMENT.md §1) or set TABULA_SWIFTLY_ENV." >&2 ;;
        xtool) echo "       Install xtool per docs/ENVIRONMENT.md §2." >&2 ;;
      esac
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1
}
