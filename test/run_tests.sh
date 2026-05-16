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
CONTAINER="clickhouse-matlab-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$SCRIPT_DIR/docker"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== ClickHouse $VERSION ==="

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

# Remove any leftover container from a previous run
cleanup

docker run -d \
    --name "$CONTAINER" \
    -p 9000:9000 \
    -p 9440:9440 \
    -v "$DOCKER_DIR/clickhouse-config.xml:/etc/clickhouse-server/config.d/tls.xml:ro" \
    -v "$DOCKER_DIR/clickhouse-users.xml:/etc/clickhouse-server/users.d/clickhouse-users.xml:ro" \
    -v "$DOCKER_DIR/server.crt:/etc/clickhouse-server/server.crt:ro" \
    -v "$DOCKER_DIR/server.key:/etc/clickhouse-server/server.key:ro" \
    --ulimit nofile=262144:262144 \
    --health-cmd "clickhouse-client --query 'SELECT 1'" \
    --health-interval 5s \
    --health-timeout 5s \
    --health-retries 12 \
    "clickhouse/clickhouse-server:$VERSION" >/dev/null

echo -n "Waiting for ClickHouse to be healthy"
for i in $(seq 1 60); do
    status="$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo 'starting')"
    if [ "$status" = "healthy" ]; then
        echo " ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo " timed out."
        docker logs "$CONTAINER" >&2
        exit 1
    fi
    echo -n "."
    sleep 1
done

"$MATLAB" -batch \
    "addpath(fullfile('$ROOT_DIR','src')); addpath(fullfile('$ROOT_DIR','test')); run_all_tests()"
