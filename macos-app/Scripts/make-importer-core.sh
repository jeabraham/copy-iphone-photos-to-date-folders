#!/bin/bash
# Derives the app's importer source from the standalone script: drops the shebang and the
# script entry point so the rest compiles as a library file (build with -D IMPORTER_LIBRARY).
set -euo pipefail

SRC="$1"
OUT="$2"
MARK='// MARK: script entry point'

grep -qF "$MARK" "$SRC" || { echo "error: entry-point marker missing in $SRC" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
awk -v mark="$MARK" 'NR == 1 && /^#!/ { next } index($0, mark) == 1 { exit } { print }' "$SRC" > "$OUT"
