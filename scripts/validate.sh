#!/usr/bin/env bash
# Linux/WSL validation of everything that can be checked WITHOUT the Darwin SDK.
# Also runs in the CI Linux job (the XcodeGen step is skipped there unless xcodegen is available).
# Usage (inside WSL):  bash scripts/validate.sh
# Env: TABULA_SCRATCH (default ~/.cache/tabula), XCODEGEN (path to xcodegen; optional)
# Needs: swift 6.4, python3 + PyYAML, rsync (for the XcodeGen step).
set -uo pipefail

# shellcheck source=/dev/null
[ -f "$HOME/.local/share/swiftly/env.sh" ] && . "$HOME/.local/share/swiftly/env.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${TABULA_SCRATCH:-$HOME/.cache/tabula}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tabula-validate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAILS=0
step() { printf '\n=== %s\n' "$*"; }
ok()   { printf 'OK   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; FAILS=$((FAILS + 1)); }

step "Toolchain"
swift --version 2>&1 | head -1
command -v xtool >/dev/null && xtool --version || echo "xtool: not installed"
XCODEGEN="${XCODEGEN:-$(command -v xcodegen || echo "$SCRATCH/XcodeGen/.build/release/xcodegen")}"
[ -x "$XCODEGEN" ] && "$XCODEGEN" --version || echo "xcodegen: not available"

step "TimetableCore tests (Linux)"
if bash "$REPO_ROOT/scripts/core-test.sh" >"$TMP/core.log" 2>&1; then
  ok "$(grep -E 'Test run with .* passed' "$TMP/core.log" | tail -1)"
else
  tail -30 "$TMP/core.log"; bad "swift test TimetableCore"
fi

step "TimetableUI builds on Linux (SwiftUI/AlarmKit code is behind #if canImport(...))"
if swift build --package-path "$REPO_ROOT/Packages/TimetableUI" --scratch-path "$SCRATCH/TimetableUI" >"$TMP/ui.log" 2>&1; then
  ok "swift build Packages/TimetableUI"
else
  tail -20 "$TMP/ui.log"; bad "swift build Packages/TimetableUI"
fi

step "Root Package.swift (xtool path): products"
if (cd "$REPO_ROOT" && swift package --scratch-path "$SCRATCH/root-describe" describe --type json) >"$TMP/root.json" 2>"$TMP/root.err"; then
  python3 - "$TMP/root.json" <<'PY' || FAILS=$((FAILS + 1))
import json, sys
raw = open(sys.argv[1]).read(); d = json.loads(raw[raw.index("{"):])
prods = {p["name"]: p for p in d["products"]}
targets = {t["name"]: t for t in d["targets"]}
bad = 0
for name, path in {"TabulaApp": "App/Sources", "TabulaWidgets": "WidgetExtension/Sources"}.items():
    p = prods.get(name)
    if not p or p.get("type", {}).get("library") != ["automatic"]:
        print(f"FAIL product {name} must be an automatic library (xtool requirement): {p and p.get('type')}"); bad += 1
    elif targets[name]["path"] != path:
        print(f"FAIL target {name} path {targets[name]['path']} != {path}"); bad += 1
    else:
        print(f"OK   product {name}: automatic library, path {path}")
sys.exit(1 if bad else 0)
PY
else
  cat "$TMP/root.err"; bad "swift package describe (root)"
fi

step "Manifest dumps (default, TABULA_MACRO_PROBES=1, TimetableCore, TimetableUI)"
dump() { # dump <out> <package path> [env assignment]
  local out="$1" pkg="$2"; shift 2
  if env "$@" swift package --package-path "$pkg" --scratch-path "$SCRATCH/dump-$(basename "$out" .json)" dump-package >"$out" 2>"$out.err"; then
    ok "dump-package $(basename "$out")"
  else
    cat "$out.err"; bad "dump-package $(basename "$out")"
  fi
}
dump "$TMP/dump-default.json" "$REPO_ROOT" -u TABULA_MACRO_PROBES
dump "$TMP/dump-macro.json" "$REPO_ROOT" TABULA_MACRO_PROBES=1
dump "$TMP/dump-core.json" "$REPO_ROOT/Packages/TimetableCore"
dump "$TMP/dump-ui.json" "$REPO_ROOT/Packages/TimetableUI"

step "Plists & entitlements (Python plistlib + swift-corelibs Foundation, which xtool uses on Linux)"
for f in "$REPO_ROOT"/Config/*.plist "$REPO_ROOT"/Config/*.entitlements "$REPO_ROOT"/Config/Privacy/*/PrivacyInfo.xcprivacy; do
  # Parse, and reject $(VAR) placeholders in any value (xtool merges the dict verbatim; comments are ignored).
  if python3 - "$f" <<'PY'
import plistlib, sys
def walk(v):
    if isinstance(v, dict): return any(walk(x) for x in list(v.keys()) + list(v.values()))
    if isinstance(v, list): return any(walk(x) for x in v)
    return isinstance(v, str) and "$(" in v
sys.exit(2 if walk(plistlib.load(open(sys.argv[1], "rb"))) else 0)
PY
  then ok "plistlib ${f#"$REPO_ROOT"/} (no \$(VAR) placeholders)"
  else bad "${f#"$REPO_ROOT"/}: unparsable or contains a \$(VAR) placeholder (xtool would copy it literally)"
  fi
done
cat >"$TMP/plistcheck.swift" <<'SWIFT'
import Foundation
var failed = false
for path in CommandLine.arguments.dropFirst() {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard obj is [String: Any] else { print("FAIL not a dict: \(path)"); failed = true; continue }
        print("OK   Foundation PropertyListSerialization \(URL(fileURLWithPath: path).lastPathComponent)")
    } catch { print("FAIL \(path): \(error)"); failed = true }
}
exit(failed ? 1 : 0)
SWIFT
if (cd "$TMP" && swiftc -o plistcheck plistcheck.swift >/dev/null 2>&1) \
   && "$TMP/plistcheck" "$REPO_ROOT"/Config/*.plist "$REPO_ROOT"/Config/*.entitlements "$REPO_ROOT"/Config/Privacy/*/PrivacyInfo.xcprivacy; then :
else bad "Foundation plist parse"; fi

step "Cross-path consistency, macro isolation, privacy manifests, workflow (scripts/validate_config.py)"
if [ -s "$TMP/dump-default.json" ] && [ -s "$TMP/dump-macro.json" ]; then
  python3 "$REPO_ROOT/scripts/validate_config.py" "$REPO_ROOT" \
    "$TMP/dump-default.json" "$TMP/dump-macro.json" "$TMP/dump-core.json" "$TMP/dump-ui.json" || FAILS=$((FAILS + 1))
else
  bad "manifest dumps missing; skipped validate_config.py"
fi

step "String Catalog -> .lproj (xtool path compiler)"
if python3 "$REPO_ROOT/scripts/l10n-compile.py" --self-test >"$TMP/l10n-self.log" 2>&1; then
  ok "l10n-compile --self-test ($(grep -c '^OK' "$TMP/l10n-self.log") edge cases: %% , empty, state new, fallback)"
else
  cat "$TMP/l10n-self.log"; bad "l10n-compile --self-test"
fi
if python3 "$REPO_ROOT/scripts/l10n-compile.py" "$REPO_ROOT/Resources/Localizable.xcstrings" "$TMP/l10n"; then ok "l10n-compile Resources/Localizable.xcstrings"; else bad "l10n-compile"; fi

step "App icon PNG"
python3 - "$REPO_ROOT/Resources/AppIcon.png" <<'PY' || FAILS=$((FAILS + 1))
import struct, sys
d = open(sys.argv[1], "rb").read()
w, h, depth, ctype = struct.unpack(">IIBB", d[16:26])
good = d[:8] == b"\x89PNG\r\n\x1a\n" and (w, h) == (1024, 1024) and ctype == 2
print(("OK  " if good else "FAIL") + f" AppIcon.png {w}x{h} colour type {ctype} (2 = RGB, no alpha)")
sys.exit(0 if good else 1)
PY

step "XcodeGen generate (proves project.yml parses and resolves)"
if [ -x "$XCODEGEN" ] && command -v rsync >/dev/null; then
  rsync -a --exclude .git --exclude examples --exclude spikes --exclude '*.zip' --exclude xtool --exclude .build "$REPO_ROOT/" "$TMP/xg/"
  if (cd "$TMP/xg" && TABULA_DEVELOPMENT_TEAM="" "$XCODEGEN" generate --spec project.yml --quiet); then
    P="$TMP/xg/Tabula.xcodeproj/project.pbxproj"
    grep -q 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"' "$P" && ok "watch app embedded (Embed Watch Content)" || bad "watch embed phase missing"
    grep -q 'TabulaWidgets.appex in Embed Foundation Extensions' "$P" && ok "widget embedded (PlugIns)" || bad "widget embed phase missing"
    [ "$(grep -c 'PrivacyInfo.xcprivacy in Resources \*/ = {isa = PBXBuildFile' "$P")" -eq 2 ] && ok "both privacy manifests (app + widget) in Resources phases" || bad "privacy manifests not in Resources phases"
    grep -q 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) TABULA_MACRO_PROBES"' "$P" && ok "TabulaApp defines TABULA_MACRO_PROBES (CI macro variant)" || bad "macro define missing in pbxproj"
    if grep -q '^[[:space:]]*ARCHS = ' "$P"; then bad "ARCHS overridden in project (could drop arm64_32)"; else ok "no ARCHS override (watch keeps ARCHS_STANDARD incl. arm64_32)"; fi
    [ -f "$TMP/xg/Tabula.xcodeproj/xcshareddata/xcschemes/TabulaApp.xcscheme" ] && ok "shared scheme TabulaApp" || bad "scheme missing"
    for f in Config/App-Info.plist Config/Widgets-Info.plist Config/Watch-Info.plist; do
      cmp -s "$TMP/xg/$f" "$REPO_ROOT/$f" && ok "xcodegen left $f untouched" || bad "xcodegen rewrote $f"
    done
  else
    bad "xcodegen generate"
  fi
else
  echo "SKIP xcodegen or rsync not available (set XCODEGEN=/path/to/xcodegen)"
fi

printf '\n%s\n' "$([ "$FAILS" -eq 0 ] && echo 'ALL CHECKS PASSED' || echo "$FAILS CHECK(S) FAILED")"
exit "$FAILS"
