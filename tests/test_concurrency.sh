#!/usr/bin/env bash
#=========================================================================#
# Test Suite: Concurrency & Atomic File Locking                           #
#=========================================================================#

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export HNM_ALLOW_NON_ROOT=1
export STATE_DIR="${TEST_TMP}/state"
export LOG_DIR="${TEST_TMP}/logs"
export PORT_MIN=51000
export PORT_MAX=51050

# shellcheck source=lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"
# shellcheck source=lib/ports.sh
source "${PROJECT_ROOT}/lib/ports.sh"

init_environment

echo "=== Running Concurrency & Race Condition Tests ==="

PARALLEL_JOBS=12
RESULTS_FILE="${TEST_TMP}/allocated_ports.txt"
touch "$RESULTS_FILE"

echo "Spawning $PARALLEL_JOBS simultaneous port allocation requests..."

for i in $(seq 1 "$PARALLEL_JOBS"); do
    (
        port=$(allocate_port "worker$i" "domain$i.test")
        echo "$port" >> "$RESULTS_FILE"
    ) &
done

# Wait for all background workers to finish
wait

TOTAL_ALLOCATED=$(wc -l < "$RESULTS_FILE" | tr -d ' ')
UNIQUE_ALLOCATED=$(sort -u "$RESULTS_FILE" | wc -l | tr -d ' ')

echo "Total allocations completed:  $TOTAL_ALLOCATED"
echo "Unique ports allocated:       $UNIQUE_ALLOCATED"

if [ "$TOTAL_ALLOCATED" -eq "$PARALLEL_JOBS" ] && [ "$UNIQUE_ALLOCATED" -eq "$PARALLEL_JOBS" ]; then
    echo -e "  [PASS] Zero collisions detected across $PARALLEL_JOBS concurrent allocations."
else
    echo -e "  [FAIL] Port collision detected! Unique ($UNIQUE_ALLOCATED) != Total ($TOTAL_ALLOCATED)"
    exit 1
fi

echo
echo "Concurrency test passed successfully."
