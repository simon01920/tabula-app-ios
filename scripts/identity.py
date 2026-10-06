#!/usr/bin/env python3
"""Read Config/AppIdentity.xcconfig (the single source of identity values) the way Xcode would.

Supports exactly the subset the file is allowed to use: `NAME = value` lines, `//` comment lines, and
`$(NAME)` / `${NAME}` references including nested ones such as `$(TABULA_APP_ENTITLEMENTS_$(TABULA_PAID_ACCOUNT))`.
Unknown references resolve to "" (Xcode behaviour). Stdlib only: runs on WSL, the Linux CI container and macOS.

Usage
  python3 scripts/identity.py                         # all values, NAME=value lines (switch as in the file)
  python3 scripts/identity.py TABULA_BUNDLE_ID        # one value
  python3 scripts/identity.py --set TABULA_PAID_ACCOUNT=1 TABULA_APP_ENTITLEMENTS
  python3 scripts/identity.py --format github >> "$GITHUB_ENV"   # CI: export every value as an env var
"""
import argparse
import json
import pathlib
import re
import sys

DEFAULT_PATH = pathlib.Path(__file__).resolve().parent.parent / "Config" / "AppIdentity.xcconfig"
LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")
REF = re.compile(r"\$[({]([A-Za-z0-9_]+)[)}]")   # innermost reference (no nested $ inside the name)


def parse(path=DEFAULT_PATH):
    raw = {}
    for no, line in enumerate(pathlib.Path(path).read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = LINE.match(s)
        if not m or "//" in m.group(2) or s.startswith("#"):
            raise ValueError(f"{path}:{no}: unsupported xcconfig syntax (allowed: 'NAME = value' and '//' lines): {line!r}")
        raw[m.group(1)] = m.group(2)
    return raw


def resolve(raw, overrides=None):
    values = dict(raw)
    values.update(overrides or {})

    def expand(value, depth=0):
        if depth > 20:
            raise ValueError(f"reference cycle while expanding {value!r}")
        while True:
            m = REF.search(value)
            if not m:
                return value
            inner = expand(values.get(m.group(1), ""), depth + 1)
            value = value[:m.start()] + inner + value[m.end():]

    return {k: expand(v) for k, v in values.items()}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("--file", default=str(DEFAULT_PATH))
    ap.add_argument("--set", action="append", default=[], metavar="NAME=VALUE",
                    help="override a value (like an xcodebuild command-line setting)")
    ap.add_argument("--format", choices=("env", "github", "json"), default="env")
    a = ap.parse_args()
    overrides = dict(s.split("=", 1) for s in a.set)
    values = resolve(parse(a.file), overrides)
    if a.names:
        missing = [n for n in a.names if n not in values]
        if missing:
            sys.exit(f"error: not defined in {a.file}: {', '.join(missing)}")
        if len(a.names) == 1 and a.format == "env":
            print(values[a.names[0]])
            return
        values = {n: values[n] for n in a.names}
    if a.format == "json":
        print(json.dumps(values, indent=2, sort_keys=True))
    else:
        for k in sorted(values):
            print(f"{k}={values[k]}")


if __name__ == "__main__":
    main()
