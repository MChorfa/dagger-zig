#!/usr/bin/env bash
# Render a CPU flamegraph SVG from the offline benchmark binary.
#
# Zig has no built-in profiler, so this drives an external sampling profiler.
# It uses `flamegraph` (cargo install flamegraph), which emits an .svg directly:
# perf on Linux, dtrace on macOS (dtrace needs sudo).
#
# Usage:
#   scripts/bench-flamegraph.sh [output.svg]   # default: flamegraph.svg
set -euo pipefail

OUT="${1:-flamegraph.svg}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="zig-out/bin/bench"

[ -x "$BIN" ] || {
  echo "error: $BIN not found. Run `zig build flamegraph` so the install step creates it first." >&2
  exit 1
}

if command -v flamegraph >/dev/null 2>&1; then
  echo "==> Profiling $BIN -> $OUT"
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "    (macOS: the dtrace backend may prompt for sudo)"
  fi
  exec flamegraph -o "$OUT" -- "$BIN"
fi

cat >&2 <<'MSG'
error: no supported profiler found.

This repository does not bundle a profiler — Zig has none built in. Install one:

  cargo install flamegraph     # emits a .svg directly (perf on Linux, dtrace on macOS)

then re-run:

  zig build flamegraph                       # writes flamegraph.svg
  # or: scripts/bench-flamegraph.sh out.svg  # custom path

Interactive alternative (no sudo on macOS, but not a .svg file):

  cargo install samply
  zig build bench
  samply record -- ./zig-out/bin/bench
MSG
exit 1
