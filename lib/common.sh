#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Common Utilities and Logging                     #
#=========================================================================#

# Ensure strict bash execution mode if sourced
set -Eeuo pipefail

# ANSI color codes with terminal detection
if [ -t 1 ]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
    COLOR_BOLD='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_CYAN=''
    COLOR_BOLD=''
    COLOR_RESET=''
fi

DRY_RUN=${DRY_RUN:-0}
VERBOSE=${VERBOSE:-0}
LOG_DIR="${LOG_DIR:-/var/log/hestia-node-manager}"
MANAGER_LOG="${LOG_DIR}/manager.log"
ERROR_LOG="${LOG_DIR}/error.log"

_log_to_file() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")

    if [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ]; then
        echo "[$timestamp] [$level] $msg" >> "$MANAGER_LOG" 2>/dev/null || true
        if [ "$level" = "ERROR" ]; then
            echo "[$timestamp] [ERROR] $msg" >> "$ERROR_LOG" 2>/dev/null || true
        fi
    fi
}

log_info() {
    local msg="$*"
    echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $msg"
    _log_to_file "INFO" "$msg"
}

log_success() {
    local msg="$*"
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $msg"
    _log_to_file "SUCCESS" "$msg"
}

log_warn() {
    local msg="$*"
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $msg" >&2
    _log_to_file "WARN" "$msg"
}

log_error() {
    local msg="$*"
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $msg" >&2
    _log_to_file "ERROR" "$msg"
}

log_debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        local msg="$*"
        echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $msg"
        _log_to_file "DEBUG" "$msg"
    fi
}

check_root() {
    if [ "${HNM_ALLOW_NON_ROOT:-0}" -eq 1 ]; then
        return 0
    fi
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This command requires root privileges. Please run with sudo or as root."
        exit 1
    fi
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${COLOR_YELLOW}[DRY-RUN]${COLOR_RESET} Would execute: $*"
        return 0
    fi
    "$@"
}
