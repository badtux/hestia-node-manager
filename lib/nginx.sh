#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Nginx & Template Management                       #
#=========================================================================#

NGINX_TEMPLATE_SRC="${STATE_DIR}/templates/nginx/app-proxy.conf.template"
UPGRADE_MAP_SRC="${STATE_DIR}/templates/nginx/hestia-node-upgrade.conf"
UPGRADE_MAP_DST="${NGINX_CONF_DIR}/conf.d/hestia-node-upgrade.conf"

HESTIA_TPL_DIR="${HESTIA_ROOT}/data/templates/web/nginx"
HESTIA_TPL_SRC="${STATE_DIR}/templates/hestia/HestiaNode.tpl"
HESTIA_STPL_SRC="${STATE_DIR}/templates/hestia/HestiaNode.stpl"

nginx_is_installed() {
    command -v nginx &>/dev/null
}

nginx_test_config() {
    if ! nginx_is_installed; then
        return 0
    fi
    nginx -t &>/dev/null
}

nginx_install_global_websocket_map() {
    if [ ! -d "${NGINX_CONF_DIR}/conf.d" ]; then
        log_debug "Nginx conf.d directory not found; skipping WebSocket global map."
        return 0
    fi

    # Check if connection_upgrade map is already defined anywhere in /etc/nginx/
    if grep -rq "connection_upgrade" "${NGINX_CONF_DIR}" 2>/dev/null; then
        log_debug "WebSocket connection_upgrade map already defined in Nginx configuration."
        return 0
    fi

    if [ -f "$UPGRADE_MAP_SRC" ]; then
        log_info "Installing WebSocket connection upgrade map to $UPGRADE_MAP_DST..."
        run_cmd cp "$UPGRADE_MAP_SRC" "$UPGRADE_MAP_DST"
        run_cmd chmod 644 "$UPGRADE_MAP_DST"
    fi
}

nginx_install_hestia_templates() {
    if [ ! -d "$HESTIA_TPL_DIR" ]; then
        log_warn "Hestia template directory $HESTIA_TPL_DIR not found; skipping template installation."
        return 0
    fi

    log_info "Installing Hestia Proxy Templates ($PROXY_TEMPLATE_NAME)..."
    if [ -f "$HESTIA_TPL_SRC" ]; then
        run_cmd cp "$HESTIA_TPL_SRC" "$HESTIA_TPL_DIR/${PROXY_TEMPLATE_NAME}.tpl"
        run_cmd chmod 644 "$HESTIA_TPL_DIR/${PROXY_TEMPLATE_NAME}.tpl"
    fi

    if [ -f "$HESTIA_STPL_SRC" ]; then
        run_cmd cp "$HESTIA_STPL_SRC" "$HESTIA_TPL_DIR/${PROXY_TEMPLATE_NAME}.stpl"
        run_cmd chmod 644 "$HESTIA_TPL_DIR/${PROXY_TEMPLATE_NAME}.stpl"
    fi
    log_success "Hestia templates installed: ${PROXY_TEMPLATE_NAME}.tpl / ${PROXY_TEMPLATE_NAME}.stpl"
}

nginx_uninstall_hestia_templates() {
    if [ -d "$HESTIA_TPL_DIR" ]; then
        log_info "Removing Hestia Proxy Templates for $PROXY_TEMPLATE_NAME..."
        run_cmd rm -f "$HESTIA_TPL_DIR/${PROXY_TEMPLATE_NAME}.tpl" \
                     "$HESTIA_TPL_DIR/${PROXY_TEMPLATE_NAME}.stpl"
    fi

    if [ -f "$UPGRADE_MAP_DST" ]; then
        run_cmd rm -f "$UPGRADE_MAP_DST"
    fi
}

nginx_generate_domain_proxy_conf() {
    local user="$1"
    local domain="$2"
    local port="$3"

    local dest_file="${STATE_DIR}/nginx/${user}_${domain}.conf"
    local backup_file="${dest_file}.bak"
    local tmp_file
    tmp_file=$(mktemp)

    local template_file="$NGINX_TEMPLATE_SRC"
    # Fallback if installed in different directory
    if [ ! -f "$template_file" ]; then
        template_file="$(dirname "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")")/templates/nginx/app-proxy.conf.template"
    fi

    if [ ! -f "$template_file" ]; then
        log_error "Nginx template file not found: $template_file"
        rm -f "$tmp_file"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")

    # Perform safe placeholder substitution
    sed -e "s|{{USER}}|$user|g" \
        -e "s|{{DOMAIN}}|$domain|g" \
        -e "s|{{PORT}}|$port|g" \
        -e "s|{{NODE_BIND_ADDRESS}}|$NODE_BIND_ADDRESS|g" \
        -e "s|{{HTTP_TIMEOUT}}|$DEFAULT_HTTP_TIMEOUT|g" \
        -e "s|{{UPLOAD_SIZE}}|$DEFAULT_UPLOAD_SIZE|g" \
        -e "s|{{GENERATED_AT}}|$timestamp|g" \
        "$template_file" > "$tmp_file"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${COLOR_YELLOW}[DRY-RUN]${COLOR_RESET} Would generate Nginx proxy config at $dest_file:"
        cat "$tmp_file"
        rm -f "$tmp_file"
        return 0
    fi

    mkdir -p "$(dirname "$dest_file")"

    # Backup if exists
    if [ -f "$dest_file" ]; then
        cp "$dest_file" "$backup_file"
    fi

    # Write new configuration
    cat "$tmp_file" > "$dest_file"
    chmod 644 "$dest_file"
    rm -f "$tmp_file"

    # Validate Nginx syntax if Nginx is active
    if nginx_is_installed; then
        if ! nginx_test_config; then
            log_error "Nginx configuration test failed with new proxy config! Rolling back..."
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$dest_file"
            else
                rm -f "$dest_file"
            fi
            return 1
        fi
    fi

    rm -f "$backup_file"
    log_success "Generated Nginx proxy include: $dest_file"
    return 0
}

nginx_remove_domain_proxy_conf() {
    local user="$1"
    local domain="$2"
    local dest_file="${STATE_DIR}/nginx/${user}_${domain}.conf"

    if [ -f "$dest_file" ]; then
        run_cmd rm -f "$dest_file"
        log_info "Removed Nginx proxy include: $dest_file"
    fi
}
