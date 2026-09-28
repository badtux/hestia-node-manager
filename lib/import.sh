#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Application Import & Migration                    #
#=========================================================================#

import_application() {
    local user="$1"
    local domain="$2"
    local explicit_port="${3:-}"
    local explicit_app_root="${4:-}"
    local explicit_entrypoint="${5:-}"

    log_info "Inspecting environment to import application for $user / $domain..."

    # Validate user and domain
    validate_username "$user" || return 1
    validate_domain "$domain" || return 1

    # Check if app is already registered
    local app_conf="${STATE_DIR}/apps/${user}/${domain}.conf"
    if [ -f "$app_conf" ]; then
        log_warn "Application $user / $domain is already registered in Hestia Node Manager."
        echo "Configuration file: $app_conf"
        return 0
    fi

    local detected_app_root=""
    local detected_entrypoint=""
    local detected_port=""
    local detected_process_name=""
    local detected_node_version=""
    local pm2_status="unknown"

    # Common candidate directories
    local candidate_roots=(
        "/home/$user/web/$domain/nodeapp"
        "/home/$user/web/$domain/app"
        "/home/$user/web/$domain/public_html"
        "/home/$user/web/$domain"
    )

    if [ -n "$explicit_app_root" ]; then
        detected_app_root="$explicit_app_root"
    else
        for dir in "${candidate_roots[@]}"; do
            if [ -d "$dir" ]; then
                detected_app_root="$dir"
                break
            fi
        done
    fi

    # Inspect PM2 process list
    local pm2_bin
    pm2_bin=$(pm2_find_binary "$user" || true)

    if [ -n "$pm2_bin" ]; then
        log_info "Querying PM2 for user '$user'..."
        local pm2_json
        pm2_json=$(pm2_get_process_info_json "$user" || true)

        if [ -n "$pm2_json" ] && command -v python3 &>/dev/null; then
            # Parse PM2 JSON using python
            local pm2_match
            pm2_match=$(python3 -c "
import sys, json

try:
    data = json.loads('''$pm2_json''')
    target_domain = '$domain'
    target_root = '$detected_app_root'

    match = None
    for proc in data:
        name = proc.get('name', '')
        pm2_env = proc.get('pm2_env', {})
        cwd = pm2_env.get('pm_cwd', '')
        exec_path = pm2_env.get('pm_exec_path', '')
        status = pm2_env.get('status', 'unknown')
        node_v = pm2_env.get('node_version', '')
        port = pm2_env.get('env', {}).get('PORT', '')

        if target_domain in name or (target_root and target_root in cwd):
            match = (name, cwd, exec_path, status, node_v, str(port))
            break

    if match:
        print('|'.join(match))
except Exception as e:
    pass
" 2>/dev/null || true)

            if [ -n "$pm2_match" ]; then
                IFS='|' read -r detected_process_name p_cwd p_exec pm2_status detected_node_version p_port <<< "$pm2_match"
                [ -n "$p_cwd" ] && detected_app_root="$p_cwd"
                if [ -n "$p_exec" ]; then
                    detected_entrypoint=$(basename "$p_exec")
                fi
                [ -n "$p_port" ] && detected_port="$p_port"
            fi
        fi
    fi

    # Check common entrypoints if not yet detected
    if [ -z "$detected_entrypoint" ] && [ -n "$detected_app_root" ]; then
        for ep in app.js server.js index.js main.js; do
            if [ -f "$detected_app_root/$ep" ]; then
                detected_entrypoint="$ep"
                break
            fi
        done
    fi

    # Explicit overrides take precedence
    [ -n "$explicit_entrypoint" ] && detected_entrypoint="$explicit_entrypoint"
    [ -n "$explicit_port" ] && detected_port="$explicit_port"

    # If port is still unknown, check open listening ports for this user
    if [ -z "$detected_port" ]; then
        log_info "Detecting active listening socket for user '$user'..."
        if command -v lsof &>/dev/null; then
            detected_port=$(lsof -a -u "$user" -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1 { print $9 }' | cut -d':' -f2 | sort -u | tail -n1 || true)
        fi
    fi

    # Final fallbacks and sanitization
    detected_process_name="${detected_process_name:-${domain//./-}}"
    detected_entrypoint="${detected_entrypoint:-app.js}"
    detected_app_root="${detected_app_root:-/home/$user/web/$domain/nodeapp}"

    echo
    echo -e "${COLOR_BOLD}Detected Application Profile for Import:${COLOR_RESET}"
    echo -e "  Domain:           ${COLOR_CYAN}$domain${COLOR_RESET}"
    echo -e "  User:             ${COLOR_CYAN}$user${COLOR_RESET}"
    echo -e "  Application Root: $detected_app_root"
    echo -e "  Entrypoint:       $detected_entrypoint"
    echo -e "  Process Name:     $detected_process_name"
    echo -e "  Listening Port:   ${detected_port:-'(Not found)'}"
    echo -e "  PM2 Status:       $pm2_status"
    echo -e "  Node Version:     ${detected_node_version:-'System'}"
    echo

    if [ -z "$detected_port" ]; then
        log_error "Could not automatically determine listening port for application."
        log_error "Please specify port explicitly: hestia-node import $user $domain --port <PORT>"
        return 1
    fi

    validate_port "$detected_port" || return 1

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Verification complete. Application would be imported without restarting PM2."
        return 0
    fi

    # 1. Register explicit port in database
    log_info "Registering port $detected_port in allocation database..."
    reserve_explicit_port "$user" "$domain" "$detected_port"

    # 2. Write application config file
    log_info "Creating application record in $app_conf..."
    mkdir -p "$(dirname "$app_conf")"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")

    cat <<EOF > "$app_conf"
# Hestia Node Manager Application Record (Imported)
USER="$user"
DOMAIN="$domain"
APP_ROOT="$detected_app_root"
ENTRYPOINT="$detected_entrypoint"
PORT="$detected_port"
PROCESS_MANAGER="pm2"
PROCESS_NAME="$detected_process_name"
NODE_VERSION="${detected_node_version:-system}"
AUTOSTART="yes"
CREATED_AT="$timestamp"
UPDATED_AT="$timestamp"
IMPORTED="yes"
EOF
    chmod 640 "$app_conf"

    # 3. Generate Nginx proxy include snippet
    nginx_generate_domain_proxy_conf "$user" "$domain" "$detected_port"

    # 4. If Hestia is installed, assign proxy template if requested
    if hestia_is_installed; then
        hestia_set_proxy_template "$user" "$domain" "$PROXY_TEMPLATE_NAME"
        hestia_restart_proxy
    fi

    log_success "Application $domain successfully imported into Hestia Node Manager!"
    log_info "Note: The running PM2 process was NOT restarted, ensuring zero downtime."
    return 0
}
