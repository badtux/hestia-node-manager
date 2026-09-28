#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - HestiaCP CLI Wrapper                              #
#=========================================================================#

hestia_is_installed() {
    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        return 0
    fi
    [ -d "$HESTIA_ROOT" ] && [ -x "$HESTIA_ROOT/bin/v-list-users" ]
}

hestia_get_version() {
    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        echo "1.10.5"
        return 0
    fi

    if [ -f "$HESTIA_ROOT/conf/hestia.conf" ]; then
        local ver
        ver=$(grep "^VERSION=" "$HESTIA_ROOT/conf/hestia.conf" | cut -d"'" -f2 2>/dev/null || true)
        if [ -n "$ver" ]; then
            echo "$ver"
            return 0
        fi
    fi
    echo "unknown"
}

hestia_user_exists() {
    local user="$1"
    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        return 0
    fi

    if ! hestia_is_installed; then
        log_warn "HestiaCP not detected; skipping Hestia user check."
        return 0
    fi

    "$HESTIA_ROOT/bin/v-list-user" "$user" json &>/dev/null
}

hestia_domain_exists() {
    local user="$1"
    local domain="$2"
    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        return 0
    fi

    if ! hestia_is_installed; then
        log_warn "HestiaCP not detected; skipping Hestia domain check."
        return 0
    fi

    "$HESTIA_ROOT/bin/v-list-web-domain" "$user" "$domain" json &>/dev/null
}

hestia_get_domain_info() {
    local user="$1"
    local domain="$2"
    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        echo '{"PROXY":"NodeApp","SUSPENDED":"no"}'
        return 0
    fi

    if ! hestia_is_installed; then
        return 1
    fi

    "$HESTIA_ROOT/bin/v-list-web-domain" "$user" "$domain" json 2>/dev/null || true
}

hestia_set_proxy_template() {
    local user="$1"
    local domain="$2"
    local template="${3:-$PROXY_TEMPLATE_NAME}"

    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        log_info "[Mock Hestia] Assigned proxy template '$template' to $domain"
        return 0
    fi

    if ! hestia_is_installed; then
        log_warn "HestiaCP not detected. Proxy template cannot be updated via Hestia CLI."
        return 0
    fi

    log_info "Setting Hestia proxy template for domain '$domain' to '$template'..."
    run_cmd "$HESTIA_ROOT/bin/v-change-web-domain-proxy-tpl" "$user" "$domain" "$template" yes
}

hestia_rebuild_web_domain() {
    local user="$1"
    local domain="$2"

    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        log_info "[Mock Hestia] Rebuilt web domain $domain"
        return 0
    fi

    if ! hestia_is_installed; then
        log_warn "HestiaCP not detected. Rebuild skipped."
        return 0
    fi

    log_info "Rebuilding Hestia web domain configuration for '$domain'..."
    run_cmd "$HESTIA_ROOT/bin/v-rebuild-web-domain" "$user" "$domain" yes
}

hestia_restart_proxy() {
    if [ "${HNM_MOCK_HESTIA:-0}" -eq 1 ]; then
        log_info "[Mock Hestia] Restarted proxy server"
        return 0
    fi

    if ! hestia_is_installed; then
        if command -v systemctl &>/dev/null; then
            run_cmd systemctl reload nginx || run_cmd systemctl restart nginx
        fi
        return 0
    fi

    log_info "Reloading Hestia reverse proxy..."
    run_cmd "$HESTIA_ROOT/bin/v-restart-proxy"
}
