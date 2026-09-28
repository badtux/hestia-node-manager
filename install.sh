#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Installer                                         #
#=========================================================================#

set -Eeuo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"

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

echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo -e "${COLOR_BOLD}          Hestia Node Manager - Installation          ${COLOR_RESET}"
echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
echo

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} The installer must be run as root or with sudo." >&2
    exit 1
fi

# 2. OS Compatibility Check
echo -n "Checking operating system compatibility... "
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "$ID" in
        debian|ubuntu)
            echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $PRETTY_NAME detected"
            ;;
        *)
            echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} Unsupported OS '$ID'. Proceeding anyway..."
            ;;
    esac
else
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} /etc/os-release not found. Proceeding with caution..."
fi

# 3. Hestia Control Panel Detection
echo -n "Checking Hestia Control Panel installation... "
if [ -d "$HESTIA_ROOT" ] && [ -x "$HESTIA_ROOT/bin/v-list-users" ]; then
    h_version="unknown"
    if [ -f "$HESTIA_ROOT/conf/hestia.conf" ]; then
        h_version=$(grep "^VERSION=" "$HESTIA_ROOT/conf/hestia.conf" | cut -d"'" -f2 2>/dev/null || echo "detected")
    fi
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} HestiaCP detected (v$h_version)"
else
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} HestiaCP not detected at $HESTIA_ROOT."
    echo "       Hestia Node Manager will still be installed, but template auto-registration requires Hestia."
fi

# 4. Create Directories
echo -n "Setting up state and log directories... "
mkdir -p "$STATE_DIR" \
         "$STATE_DIR/apps" \
         "$STATE_DIR/nginx" \
         "$STATE_DIR/templates/hestia" \
         "$STATE_DIR/templates/nginx" \
         "$LOG_DIR" \
         "$LIB_DEST" \
         "$LIB_DEST/bin" \
         "$LIB_DEST/lib"

chmod 750 "$STATE_DIR"
chmod 750 "$STATE_DIR/apps"
chmod 755 "$STATE_DIR/nginx"
chmod 750 "$LOG_DIR"
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

# 5. Install Library and Binaries
echo -n "Installing library modules and CLI... "
cp -r "${SCRIPT_DIR}/lib/"* "${LIB_DEST}/lib/"
cp "${SCRIPT_DIR}/bin/hestia-node" "${LIB_DEST}/bin/hestia-node"
chmod +x "${LIB_DEST}/bin/hestia-node"

# Symlink CLI to /usr/local/bin
ln -sf "${LIB_DEST}/bin/hestia-node" "$BIN_DEST"
chmod 755 "$BIN_DEST"
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

# 6. Install Default Configuration (if not exists)
echo -n "Configuring global settings... "
if [ ! -f "${STATE_DIR}/config.conf" ]; then
    cp "${SCRIPT_DIR}/conf/hestia-node-manager.conf" "${STATE_DIR}/config.conf"
    chmod 640 "${STATE_DIR}/config.conf"
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Created default config at ${STATE_DIR}/config.conf"
else
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Existing config retained"
fi

# Copy template sources to state dir for reference
cp -r "${SCRIPT_DIR}/templates/"* "${STATE_DIR}/templates/"

# 7. Initialize Port Database
if [ ! -f "${STATE_DIR}/ports.db" ]; then
    echo -e "# PORT\tUSER\tDOMAIN\tALLOCATED_AT" > "${STATE_DIR}/ports.db"
    chmod 640 "${STATE_DIR}/ports.db"
fi
touch "${STATE_DIR}/ports.lock"
chmod 600 "${STATE_DIR}/ports.lock"

# 8. Install Hestia Proxy Templates
if [ -d "${HESTIA_ROOT}/data/templates/web/nginx" ]; then
    echo -n "Installing Hestia Proxy Templates (HestiaNode)... "
    cp "${SCRIPT_DIR}/templates/hestia/HestiaNode.tpl" "${HESTIA_ROOT}/data/templates/web/nginx/HestiaNode.tpl"
    cp "${SCRIPT_DIR}/templates/hestia/HestiaNode.stpl" "${HESTIA_ROOT}/data/templates/web/nginx/HestiaNode.stpl"
    chmod 644 "${HESTIA_ROOT}/data/templates/web/nginx/HestiaNode.tpl" \
              "${HESTIA_ROOT}/data/templates/web/nginx/HestiaNode.stpl"
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
fi

# 9. Install Global Nginx WebSocket Map
if [ -d "${NGINX_CONF_DIR}/conf.d" ]; then
    echo -n "Installing Nginx WebSocket upgrade mapping... "
    if ! grep -rq "connection_upgrade" "${NGINX_CONF_DIR}" 2>/dev/null; then
        cp "${SCRIPT_DIR}/templates/nginx/hestia-node-upgrade.conf" "${NGINX_CONF_DIR}/conf.d/hestia-node-upgrade.conf"
        chmod 644 "${NGINX_CONF_DIR}/conf.d/hestia-node-upgrade.conf"
        if command -v nginx &>/dev/null; then
            if nginx -t &>/dev/null; then
                systemctl reload nginx 2>/dev/null || true
            fi
        fi
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
    else
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Already present"
    fi
fi

echo
echo -e "${COLOR_GREEN}${COLOR_BOLD}Installation finished successfully!${COLOR_RESET}"
echo
echo "Verifying installation diagnostics:"
"$BIN_DEST" doctor
echo
echo "To get started, run:"
echo "    hestia-node --help"
