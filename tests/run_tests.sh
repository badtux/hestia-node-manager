#!/usr/bin/env bash
#=========================================================================#
# Master Test Runner for Hestia Node Manager                              #
#=========================================================================#

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"

echo "======================================================"
echo "      Hestia Node Manager - Master Test Suite         "
echo "======================================================"
echo

bash "${SCRIPT_DIR}/test_validation.sh"
echo
bash "${SCRIPT_DIR}/test_ports.sh"
echo
bash "${SCRIPT_DIR}/test_concurrency.sh"
echo
bash "${SCRIPT_DIR}/test_cli.sh"

echo
echo "======================================================"
echo "         ALL TESTS COMPLETED SUCCESSFULLY!            "
echo "======================================================"
