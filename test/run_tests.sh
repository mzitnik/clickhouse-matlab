#!/usr/bin/env bash
# test/run_tests.sh — Start ClickHouse, run MATLAB tests, stop ClickHouse.
#
# Usage:
#   ./test/run_tests.sh [VERSION]
#
# Examples:
#   ./test/run_tests.sh              # uses default version (25.3)
#   ./test/run_tests.sh 25.8
#   ./test/run_tests.sh latest
#
# Environment:
#   MATLAB   path to matlab binary (auto-detected if not set)
#   CMAKE    path to cmake binary  (auto-detected if not set)

set -euo pipefail

VERSION="${1:-25.3}"

# ── Locate MATLAB ─────────────────────────────────────────────────────────────
if [ -z "${MATLAB:-}" ]; then
    if command -v matlab &>/dev/null; then
        MATLAB="$(command -v matlab)"
    else
        for candidate in \
            /usr/local/MATLAB/*/bin/matlab \
            /opt/MATLAB/*/bin/matlab \
            "$HOME/bin/r*/bin/matlab" \
            "$HOME/MATLAB/*/bin/matlab"; do
            for f in $candidate; do
                if [ -x "$f" ]; then MATLAB="$f"; break 2; fi
            done
        done
    fi
    if [ -z "${MATLAB:-}" ]; then
        echo "ERROR: MATLAB not found. Set MATLAB=/path/to/bin/matlab" >&2
        exit 1
    fi
    echo "Found MATLAB: $MATLAB"
fi
# ── Locate CMake ──────────────────────────────────────────────────────────────
if [ -z "${CMAKE:-}" ]; then
    if command -v cmake &>/dev/null; then
        CMAKE="$(command -v cmake)"
    else
        for candidate in \
            /usr/local/bin/cmake \
            /usr/bin/cmake \
            /opt/homebrew/bin/cmake \
            /snap/bin/cmake; do
            if [ -x "$candidate" ]; then CMAKE="$candidate"; break; fi
        done
    fi
    if [ -z "${CMAKE:-}" ]; then
        echo "ERROR: cmake not found. Set CMAKE=/path/to/cmake" >&2
        exit 1
    fi
    echo "Found CMake: $CMAKE"
fi
CMAKE_FLAGS="${CMAKE_FLAGS:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

trap '"$SCRIPT_DIR/stop_clickhouse.sh"' EXIT

# ── Build MEX (incremental — only recompiles changed files) ──────────────────
echo "=== Building MEX ==="
MATLAB_ROOT="$(dirname "$(dirname "$(realpath "$MATLAB")")")"
"$CMAKE" -S "$ROOT_DIR" -B "$ROOT_DIR/build" -DCMAKE_BUILD_TYPE=Release \
    -DMatlab_ROOT_DIR="$MATLAB_ROOT" -Wno-dev $CMAKE_FLAGS
"$CMAKE" --build "$ROOT_DIR/build" --config Release
cp "$ROOT_DIR/build/clickhouse_mex.mexa64"    "$ROOT_DIR/src/" 2>/dev/null || \
cp "$ROOT_DIR/build/clickhouse_mex.mexmaca64" "$ROOT_DIR/src/" 2>/dev/null || \
cp "$ROOT_DIR/build/clickhouse_mex.mexw64"    "$ROOT_DIR/src/" 2>/dev/null || true
echo "=== MEX ready ==="

# ── Start ClickHouse (shared with CI) ────────────────────────────────────────
"$SCRIPT_DIR/start_clickhouse.sh" "$VERSION"

"$MATLAB" -batch \
    "addpath(fullfile('$ROOT_DIR','src')); addpath(fullfile('$ROOT_DIR','test')); run_all_tests()"
