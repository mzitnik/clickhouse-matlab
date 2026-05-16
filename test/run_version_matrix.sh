#!/usr/bin/env bash
# test/run_version_matrix.sh — Run the test suite against every supported version.
#
# Usage:
#   ./test/run_version_matrix.sh
#
# Override versions:
#   VERSIONS="25.3 25.8" ./test/run_version_matrix.sh
#
# Environment:
#   MATLAB   path to matlab binary (default: matlab)

set -uo pipefail

VERSIONS="${VERSIONS:-25.3 25.8 25.10 25.11 25.12 latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

passed=()
failed=()

for version in $VERSIONS; do
    echo ""
    echo "############################################################"
    echo "  ClickHouse $version"
    echo "############################################################"
    if "$SCRIPT_DIR/run_tests.sh" "$version"; then
        passed+=("$version")
    else
        failed+=("$version")
    fi
done

echo ""
echo "############################################################"
echo "  VERSION MATRIX SUMMARY"
echo "############################################################"
for v in "${passed[@]+"${passed[@]}"}"; do echo "  PASS  $v"; done
for v in "${failed[@]+"${failed[@]}"}"; do echo "  FAIL  $v"; done
echo ""

[ ${#failed[@]} -eq 0 ]
