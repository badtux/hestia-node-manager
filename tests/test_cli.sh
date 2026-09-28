#!/usr/bin/env bash
#=========================================================================#
# Test Suite: CLI Router and Dry-Run Workflows                           #
#=========================================================================#

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export HNM_ALLOW_NON_ROOT=1
export HNM_MOCK_HESTIA=1
export HNM_MOCK_PM2=1
export STATE_DIR="${TEST_TMP}/state"
export LOG_DIR="${TEST_TMP}/logs"

CLI="${PROJECT_ROOT}/bin/hestia-node"

PASSED=0
FAILED=0

assert_output_contains() {
    local desc="$1"
    local pattern="$2"
    shift 2

    local output
    output=$("$@" 2>&1 || true)
    if echo "$output" | grep -F -q "$pattern"; then
        echo -e "  [PASS] $desc"
        ((PASSED++)) || true
    else
        echo -e "  [FAIL] $desc (pattern '$pattern' not found in output: $output)"
        ((FAILED++)) || true
    fi
}

echo "=== Running CLI Integration Tests ==="

# 1. Version test
assert_output_contains "CLI reports version" "Hestia Node Manager v" "$CLI" version

# 2. Help test
assert_output_contains "CLI shows help header" "Hestia Node Manager (hestia-node)" "$CLI" --help

# 3. Doctor test
assert_output_contains "Doctor runs diagnostics" "System Diagnostics" "$CLI" doctor

# 4. List empty test
assert_output_contains "List displays table headers" "USER" "$CLI" list

# 5. List JSON test
assert_output_contains "List --json outputs JSON" "[" "$CLI" list --json

# 6. Dry run create test
assert_output_contains "Dry run create simulates execution" "DRY-RUN" "$CLI" create testuser app.example.com --dry-run

# 7. Dry run import test
assert_output_contains "Dry run import verifies profile" "DRY-RUN" "$CLI" import testuser app.example.com --port 50001 --dry-run

echo
echo "CLI tests completed: $PASSED passed, $FAILED failed."
[ "$FAILED" -eq 0 ]
