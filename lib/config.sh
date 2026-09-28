#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Configuration Loader                              #
#=========================================================================#

# Default configuration settings
PORT_MIN=${PORT_MIN:-50000}
PORT_MAX=${PORT_MAX:-59999}
NODE_BIND_ADDRESS="${NODE_BIND_ADDRESS:-127.0.0.1}"
PROXY_TEMPLATE_NAME="${PROXY_TEMPLATE_NAME:-HestiaNode}"
PROCESS_MANAGER="${PROCESS_MANAGER:-pm2}"
PM2_DEFAULT_WATCH="${PM2_DEFAULT_WATCH:-no}"
PM2_MAX_MEMORY_RESTART="${PM2_MAX_MEMORY_RESTART:-500M}"
DEFAULT_HTTP_TIMEOUT=${DEFAULT_HTTP_TIMEOUT:-300}
DEFAULT_UPLOAD_SIZE="${DEFAULT_UPLOAD_SIZE:-100M}"
ENABLE_WEBSOCKETS="${ENABLE_WEBSOCKETS:-yes}"

STATE_DIR="${STATE_DIR:-/etc/hestia-node-manager}"
LOG_DIR="${LOG_DIR:-/var/log/hestia-node-manager}"
HESTIA_ROOT="${HESTIA_ROOT:-/usr/local/hestia}"
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx}"
CONFIG_FILE="${STATE_DIR}/config.conf"

load_config() {
    local cfg_file="${1:-$CONFIG_FILE}"

    if [ ! -f "$cfg_file" ]; then
        log_debug "Configuration file $cfg_file not found; using defaults."
        return 0
    fi

    # Parse config safely line-by-line without eval
    while IFS= read -r line || [ -n "$line" ]; do
        # Trim leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip comments and empty lines
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi

        # Match KEY=VALUE
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"

            # Strip enclosing single or double quotes
            if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then
                val="${BASH_REMATCH[1]}"
            fi

            case "$key" in
                PORT_MIN) PORT_MIN="$val" ;;
                PORT_MAX) PORT_MAX="$val" ;;
                NODE_BIND_ADDRESS) NODE_BIND_ADDRESS="$val" ;;
                PROXY_TEMPLATE_NAME) PROXY_TEMPLATE_NAME="$val" ;;
                PROCESS_MANAGER) PROCESS_MANAGER="$val" ;;
                PM2_DEFAULT_WATCH) PM2_DEFAULT_WATCH="$val" ;;
                PM2_MAX_MEMORY_RESTART) PM2_MAX_MEMORY_RESTART="$val" ;;
                DEFAULT_HTTP_TIMEOUT) DEFAULT_HTTP_TIMEOUT="$val" ;;
                DEFAULT_UPLOAD_SIZE) DEFAULT_UPLOAD_SIZE="$val" ;;
                ENABLE_WEBSOCKETS) ENABLE_WEBSOCKETS="$val" ;;
                STATE_DIR) STATE_DIR="$val" ;;
                LOG_DIR) LOG_DIR="$val" ;;
                HESTIA_ROOT) HESTIA_ROOT="$val" ;;
                NGINX_CONF_DIR) NGINX_CONF_DIR="$val" ;;
                *) log_debug "Ignoring unknown configuration key: $key" ;;
            esac
        fi
    done < "$cfg_file"
}

init_environment() {
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi

    mkdir -p "$STATE_DIR" \
             "$STATE_DIR/apps" \
             "$STATE_DIR/nginx" \
             "$LOG_DIR"

    chmod 750 "$STATE_DIR" 2>/dev/null || true
    chmod 750 "$STATE_DIR/apps" 2>/dev/null || true
    chmod 755 "$STATE_DIR/nginx" 2>/dev/null || true
    chmod 750 "$LOG_DIR" 2>/dev/null || true
}
