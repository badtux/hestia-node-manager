#!/usr/bin/env bash
#=========================================================================#
# Test Suite: Port Allocation Engine                                      #
#=========================================================================#

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export HNM_ALLOW_NON_ROOT=1
export STATE_DIR="${TEST_TMP}/state"
export LOG_DIR="${TEST_TMP}/logs"
export PORT_MIN=50000
export PORT_MAX=50005

# shellcheck source=lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"
# shellcheck source=lib/ports.sh
source "${PROJECT_ROOT}/lib/ports.sh"

init_environment

PASSED=0
FAILED=0

assert_eq() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo -e "  [PASS] $desc (got $actual)"
        ((PASSED++)) || true
    else
        echo -e "  [FAIL] $desc (expected '$expected', got '$actual')"
        ((FAILED++)) || true
    fi
}

echo "=== Running Port Allocation Tests ==="

# 1. First allocation
port1=$(allocate_port "user1" "app1.example.com")
assert_eq "First allocated port is PORT_MIN" "50000" "$port1"

# 2. Idempotent check (same user and domain gets same port)
port1_repeat=$(allocate_port "user1" "app1.example.com")
assert_eq "Re-requesting port for same app returns identical port" "50000" "$port1_repeat"

# 3. Second allocation for another app
port2=$(allocate_port "user2" "app2.example.com")
assert_eq "Second allocated port increments" "50001" "$port2"

# 4. Third allocation
port3=$(allocate_port "user3" "app3.example.com")
assert_eq "Third allocated port increments" "50002" "$port3"

# 5. Release port and verify reallocation reuses released slot
release_port "user2" "app2.example.com"
released_check=$(get_port_allocation "user2" "app2.example.com" || true)
assert_eq "Released port is no longer associated with user2" "" "$released_check"

# Now allocate for new user4: should reuse 50001
port4=$(allocate_port "user4" "app4.example.com")
assert_eq "Reallocation reuses released port" "50001" "$port4"

# 6. Explicit port reservation (e.g. 50005)
reserve_explicit_port "sjbd" "d.sjbdigital.org" 50005
imported_port=$(get_port_allocation "sjbd" "d.sjbdigital.org")
assert_eq "Explicit reservation assigns designated port" "50005" "$imported_port"

# 7. Collision prevention: trying to reserve 50005 for another domain fails
if reserve_explicit_port "other" "other.com" 50005 >/dev/null 2>&1; then
    echo -e "  [FAIL] Collision prevention failed: allowed duplicate port reservation"
    ((FAILED++)) || true
else
    echo -e "  [PASS] Collision prevention succeeded: duplicate port reservation rejected"
    ((PASSED++)) || true
fi

# 8. Port range exhaustion
# Currently allocated: 50000 (user1), 50001 (user4), 50002 (user3), 50005 (sjbd)
# Let's allocate 50003 and 50004
allocate_port "fill1" "fill1.com" >/dev/null # 50003
allocate_port "fill2" "fill2.com" >/dev/null # 50004

# Now all 50000-50005 are occupied. Next allocation should fail!
if allocate_port "overflow" "overflow.com" >/dev/null 2>&1; then
    echo -e "  [FAIL] Expected port exhaustion failure, but allocation succeeded"
    ((FAILED++)) || true
else
    echo -e "  [PASS] Port range exhaustion handled safely with error"
    ((PASSED++)) || true
fi

# 9. Stale audit test
# Create mock config for user1, but not for fill1
mkdir -p "${STATE_DIR}/apps/user1"
touch "${STATE_DIR}/apps/user1/app1.example.com.conf"
audit_stale_ports >/dev/null
stale_check=$(get_port_allocation "fill1" "fill1.com" || true)
assert_eq "Audit correctly evicted stale port without app config" "" "$stale_check"

echo
echo "Port tests completed: $PASSED passed, $FAILED failed."
[ "$FAILED" -eq 0 ]
