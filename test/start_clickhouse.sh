#!/usr/bin/env bash
# test/start_clickhouse.sh — Start the ClickHouse test container and wait until healthy.
#
# Usage:
#   ./test/start_clickhouse.sh [VERSION]
#
# Examples:
#   ./test/start_clickhouse.sh           # uses default version (25.3)
#   ./test/start_clickhouse.sh 25.8
#   ./test/start_clickhouse.sh latest
#
# Used both by run_tests.sh (local) and by the GitHub CI workflow.

set -euo pipefail

VERSION="${1:-25.3}"

CONTAINER="clickhouse-matlab-test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/docker"

echo "=== ClickHouse $VERSION ==="

# Remove any leftover container from a previous run
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

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
