#!/usr/bin/env bash
#=========================================================================#
# Test Suite: Input Validation and Security                               #
#=========================================================================#

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export HNM_ALLOW_NON_ROOT=1
# shellcheck source=lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=lib/validation.sh
source "${PROJECT_ROOT}/lib/validation.sh"

PASSED=0
FAILED=0

assert_success() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  [PASS] $desc"
        ((PASSED++)) || true
    else
        echo -e "  [FAIL] $desc (expected success, got failure)"
        ((FAILED++)) || true
    fi
}

assert_failure() {
    local desc="$1"
    shift
    if ! "$@" >/dev/null 2>&1; then
        echo -e "  [PASS] $desc"
        ((PASSED++)) || true
    else
        echo -e "  [FAIL] $desc (expected failure, got success)"
        ((FAILED++)) || true
    fi
}

echo "=== Running Validation & Security Tests ==="

# 1. Username tests
assert_success "Valid standard username" validate_username "sjbd"
assert_success "Valid username with underscore" validate_username "my_user"
assert_success "Valid username with hyphen" validate_username "web-app1"
assert_failure "Empty username" validate_username ""
assert_failure "Username starting with number" validate_username "1user"
assert_failure "Username with illegal characters" validate_username "user;rm -rf"
assert_failure "Username with spaces" validate_username "user name"

# 2. Domain tests
assert_success "Valid standard domain" validate_domain "d.sjbdigital.org"
assert_success "Valid domain with hyphen" validate_domain "my-app.example.com"
assert_success "Valid simple domain" validate_domain "example.com"
assert_failure "Empty domain" validate_domain ""
assert_failure "Domain without dot" validate_domain "localhost"
assert_failure "Domain with path traversal" validate_domain "../../etc/passwd"
assert_failure "Domain with command injection" validate_domain "example.com;whoami"
assert_failure "Domain with backticks" validate_domain '`whoami`.com'
assert_failure "Domain with newline" validate_domain $'test\n.com'

# 3. Entrypoint tests
assert_success "Standard app.js" validate_entrypoint "app.js"
assert_success "Standard server.js" validate_entrypoint "server.js"
assert_success "Subfolder entrypoint" validate_entrypoint "dist/index.js"
assert_failure "Empty entrypoint" validate_entrypoint ""
assert_failure "Path traversal in entrypoint" validate_entrypoint "../../../bin/sh"
assert_failure "Leading slash absolute path" validate_entrypoint "/etc/shadow"
assert_failure "Command injection in entrypoint" validate_entrypoint "app.js;reboot"

# 4. Port format tests
assert_success "Valid port in range" validate_port 50001
assert_success "Port 80" validate_port 80
assert_failure "Non-numeric port" validate_port "abc"
assert_failure "Negative port" validate_port "-1"
assert_failure "Port out of range (>65535)" validate_port 70000

echo
echo "Validation tests completed: $PASSED passed, $FAILED failed."
[ "$FAILED" -eq 0 ]
