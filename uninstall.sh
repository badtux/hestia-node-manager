#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Safe Uninstaller                                  #
#=========================================================================#

set -Eeuo pipefail

INSTALL_PREFIX="/usr/local"
LIB_DEST="${INSTALL_PREFIX}/lib/hestia-node-manager"
BIN_DEST="${INSTALL_PREFIX}/bin/hestia-node"
STATE_DIR="/etc/hestia-node-manager"
LOG_DIR="/var/log/hestia-node-manager"
HESTIA_ROOT="/usr/local/hestia"
NGINX_CONF_DIR="/etc/nginx"

# Terminal Colors
if [ -t 1 ]; then
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_RED='\033[0;31m'
    COLOR_BOLD='\033[1m'
    COLOR_RESET='\033[0m'
else
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_RED=''
    COLOR_BOLD=''
    COLOR_RESET=''
fi

FORCE=0
PURGE=0

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--force) FORCE=1 ;;
        --purge) PURGE=1 ;;
        *) ;;
    esac
done

echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}         Hestia Node Manager - Uninstallation         ${COLOR_RESET}"
echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} The uninstaller must be run as root or with sudo." >&2
    exit 1
fi

if [ "$FORCE" -eq 0 ]; then
    echo "This script will remove the Hestia Node Manager CLI, libraries, and templates."
    echo "Note: Running Node applications, PM2 processes, and application files WILL NOT be deleted."
    echo
    read -r -p "Are you sure you want to proceed with uninstallation? [y/N] " confirmation
    if [[ ! "$confirmation" =~ ^[yY]([eE][sS])?$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
fi

# 1. Remove CLI symlink and library files
echo -n "Removing CLI and libraries... "
rm -f "$BIN_DEST"
rm -rf "$LIB_DEST"
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

# 2. Remove Hestia templates
if [ -d "${HESTIA_ROOT}/data/templates/web/nginx" ]; then
    echo -n "Removing Hestia Proxy Templates... "
    rm -f "${HESTIA_ROOT}/data/templates/web/nginx/HestiaNode.tpl" \
          "${HESTIA_ROOT}/data/templates/web/nginx/HestiaNode.stpl"
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
fi

# 3. Remove WebSocket mapping in Nginx
if [ -f "${NGINX_CONF_DIR}/conf.d/hestia-node-upgrade.conf" ]; then
    echo -n "Removing Nginx WebSocket upgrade mapping... "
    rm -f "${NGINX_CONF_DIR}/conf.d/hestia-node-upgrade.conf"
    if command -v nginx &>/dev/null && nginx -t &>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
    fi
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
fi

# 4. Handle State and Logs
if [ "$PURGE" -eq 1 ]; then
    echo -n "Purging state directory and logs (--purge specified)... "
    rm -rf "$STATE_DIR" "$LOG_DIR"
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}[NOTE]${COLOR_RESET} State directory ($STATE_DIR) and logs ($LOG_DIR) preserved."
    echo "       To completely erase all state and port databases, re-run with: ./uninstall.sh --purge"
fi

echo
echo -e "${COLOR_GREEN}${COLOR_BOLD}Hestia Node Manager has been successfully uninstalled.${COLOR_RESET}"
