#!/usr/bin/env bash
# test/stop_clickhouse.sh — Remove the ClickHouse test container.
#
# Usage:
#   ./test/stop_clickhouse.sh
#
# Used both by run_tests.sh (local) and by the GitHub CI workflow.

CONTAINER="clickhouse-matlab-test"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
