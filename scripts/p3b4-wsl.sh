#!/bin/bash
source ~/.local/share/swiftly/env.sh
cd "$(dirname "$0")/.."
export TABULA_WORKDIR=/root/.cache/tabula/p3b4-work TABULA_SCRATCH=/root/.cache/tabula/p3b4
export XCODEGEN=/root/.cache/tabula/XcodeGen/.build/release/xcodegen
exec "$@"
