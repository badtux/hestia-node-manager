#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - System Diagnostics (Doctor)                       #
#=========================================================================#

run_doctor() {
    echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}        Hestia Node Manager - System Diagnostics     ${COLOR_RESET}"
    echo -e "${COLOR_BOLD}======================================================${COLOR_RESET}"
    echo

    local issues=0

    # 1. OS & Architecture Check
    echo -n "Checking Operating System... "
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $PRETTY_NAME ($ID $VERSION_ID)"
    else
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} Unknown OS (not Debian/Ubuntu)"
        ((issues++)) || true
    fi

    # 2. Hestia Control Panel Check
    echo -n "Checking Hestia Control Panel... "
    if hestia_is_installed; then
        local h_ver
        h_ver=$(hestia_get_version)
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} HestiaCP detected (v$h_ver)"
    else
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} HestiaCP CLI not found at $HESTIA_ROOT"
        ((issues++)) || true
    fi

    # 3. Nginx Installation & Syntax Check
    echo -n "Checking Nginx... "
    if nginx_is_installed; then
        local ngx_ver
        ngx_ver=$(nginx -v 2>&1 | cut -d'/' -f2 || echo "detected")
        if nginx_test_config; then
            echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Nginx $ngx_ver detected and configuration syntax is valid"
        else
            echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} Nginx $ngx_ver detected but 'nginx -t' syntax check failed"
            ((issues++)) || true
        fi
    else
        echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} Nginx is not installed or not in PATH"
        ((issues++)) || true
    fi

    # 4. Hestia Proxy Templates Check
    echo -n "Checking Hestia Proxy Templates... "
    local tpl_ok=1
    local tpl_path="${HESTIA_ROOT}/data/templates/web/nginx/${PROXY_TEMPLATE_NAME}.tpl"
    local stpl_path="${HESTIA_ROOT}/data/templates/web/nginx/${PROXY_TEMPLATE_NAME}.stpl"
    if [ ! -f "$tpl_path" ] || [ ! -f "$stpl_path" ]; then
        tpl_ok=0
    fi

    if [ "$tpl_ok" -eq 1 ]; then
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $PROXY_TEMPLATE_NAME templates installed in Hestia"
    else
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} Templates not installed (${PROXY_TEMPLATE_NAME}.tpl / .stpl missing in Hestia directory)"
        ((issues++)) || true
    fi

    # 5. WebSocket Upgrade Map Check
    echo -n "Checking WebSocket Upgrade Map... "
    if [ -f "${NGINX_CONF_DIR}/conf.d/hestia-node-upgrade.conf" ] || grep -rq "connection_upgrade" "${NGINX_CONF_DIR}" 2>/dev/null; then
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} WebSocket upgrade map active in Nginx"
    else
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} WebSocket upgrade map not found in ${NGINX_CONF_DIR}/conf.d/"
        ((issues++)) || true
    fi

    # 6. Node.js Runtime Check
    echo -n "Checking System Node.js... "
    if command -v node &>/dev/null; then
        local node_ver
        node_ver=$(node -v 2>/dev/null || echo "detected")
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Node.js detected ($node_ver)"
    else
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} System Node.js binary not found in PATH (user may use NVM)"
    fi

    # 7. PM2 Check
    echo -n "Checking PM2 Process Manager... "
    if command -v pm2 &>/dev/null || [ -x /usr/local/bin/pm2 ] || [ -x /usr/bin/pm2 ]; then
        local pm2_ver
        pm2_ver=$(pm2 -v 2>/dev/null || echo "detected")
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Global PM2 detected ($pm2_ver)"
    else
        echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} Global PM2 not in PATH (will fall back to per-user NVM/local PM2)"
    fi

    # 8. State Directory & Permissions Check
    echo -n "Checking State Directory Permissions... "
    if [ -d "$STATE_DIR" ] && [ -w "$STATE_DIR" ]; then
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $STATE_DIR is writable"
    else
        echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} $STATE_DIR is missing or not writable"
        ((issues++)) || true
    fi

    # 9. Port Database Integrity Check
    echo -n "Checking Port Allocation Database... "
    _ensure_db_exists
    if [ -f "$PORTS_DB" ]; then
        local count
        count=$(awk -F'\t' '$1 !~ /^#/ && NF >= 3 { c++ } END { print c+0 }' "$PORTS_DB")
        echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} Port database readable ($count active allocations, range $PORT_MIN-$PORT_MAX)"
    else
        echo -e "${COLOR_RED}[FAIL]${COLOR_RESET} Port database $PORTS_DB inaccessible"
        ((issues++)) || true
    fi

    # 10. Registered Applications Check
    echo
    echo -e "${COLOR_BOLD}Registered Applications Summary:${COLOR_RESET}"
    local app_count=0
    if [ -d "$STATE_DIR/apps" ]; then
        while IFS= read -r app_conf; do
            [ -z "$app_conf" ] && continue
            ((app_count++)) || true
            local u="" d="" p="" s=""
            while IFS='=' read -r k v; do
                v="${v%\"}" ; v="${v#\"}"
                case "$k" in
                    USER) u="$v" ;;
                    DOMAIN) d="$v" ;;
                    PORT) p="$v" ;;
                    PROCESS_NAME) s="$v" ;;
                esac
            done < "$app_conf"

            local os_status="NOT LISTENING"
            if is_port_in_use_by_os "$p"; then
                os_status="LISTENING"
            fi
            echo -e "  - ${COLOR_CYAN}$d${COLOR_RESET} (User: $u, Port: $p [$os_status], Process: $s)"
        done < <(find "$STATE_DIR/apps" -type f -name "*.conf" 2>/dev/null || true)
    fi

    if [ "$app_count" -eq 0 ]; then
        echo "  (No applications registered yet)"
    fi

    echo
    if [ "$issues" -eq 0 ]; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}Diagnostic complete: All checks passed successfully.${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}Diagnostic complete: Found $issues warning(s)/issue(s). See above for details.${COLOR_RESET}"
    fi
    return 0
}
