#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Atomic Port Allocation Engine                     #
#=========================================================================#

PORTS_DB="${STATE_DIR}/ports.db"
PORT_LOCK_FILE="${STATE_DIR}/ports.lock"

_acquire_port_lock() {
    mkdir -p "$(dirname "$PORT_LOCK_FILE")"

    # 1. Native Linux flock if available
    if command -v flock &>/dev/null; then
        touch "$PORT_LOCK_FILE"
        chmod 600 "$PORT_LOCK_FILE" 2>/dev/null || true
        exec 200>"$PORT_LOCK_FILE"
        if ! flock -x -w 15 200; then
            log_error "Timeout: Failed to acquire port allocation lock ($PORT_LOCK_FILE)."
            return 1
        fi
        return 0
    fi

    # 2. Universal POSIX atomic directory spinlock (guaranteed atomic on BSD/macOS/Linux)
    local lock_dir="${PORT_LOCK_FILE}.lock.d"
    local elapsed=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        sleep 0.05
        elapsed=$((elapsed + 1))
        # 300 iterations * 0.05s = 15 seconds timeout
        if [ "$elapsed" -ge 300 ]; then
            log_error "Timeout: Failed to acquire port allocation lock ($lock_dir)."
            return 1
        fi
    done
    return 0
}

_release_port_lock() {
    if command -v flock &>/dev/null; then
        flock -u 200 2>/dev/null || true
        exec 200>&- 2>/dev/null || true
    fi
    local lock_dir="${PORT_LOCK_FILE}.lock.d"
    rmdir "$lock_dir" 2>/dev/null || true
}

_ensure_db_exists() {
    mkdir -p "$(dirname "$PORTS_DB")"
    if [ ! -f "$PORTS_DB" ]; then
        touch "$PORTS_DB"
        chmod 640 "$PORTS_DB" 2>/dev/null || true
        echo -e "# PORT\tUSER\tDOMAIN\tALLOCATED_AT" > "$PORTS_DB"
    fi
}

is_port_in_use_by_os() {
    local port="$1"

    # 1. ss check (most reliable on modern Linux/Debian)
    if command -v ss &>/dev/null; then
        if ss -tlpn "sport = :$port" 2>/dev/null | grep -q ":$port\b"; then
            return 0
        fi
    fi

    # 2. lsof check
    if command -v lsof &>/dev/null; then
        if lsof -iTCP:"$port" -sTCP:LISTEN -P -n &>/dev/null; then
            return 0
        fi
    fi

    # 3. fuser check
    if command -v fuser &>/dev/null; then
        if fuser "$port/tcp" &>/dev/null; then
            return 0
        fi
    fi

    # 4. Built-in bash TCP probe (fallback socket connect)
    # If connection succeeds, something is actively listening
    if (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
        exec 3>&- 2>/dev/null || true
        return 0
    fi

    return 1
}

get_port_allocation() {
    local user="$1"
    local domain="$2"

    _ensure_db_exists
    if [ ! -f "$PORTS_DB" ]; then
        return 1
    fi

    # Search for user and domain in TSV
    local port
    port=$(awk -F'\t' -v u="$user" -v d="$domain" '
        $1 !~ /^#/ && $2 == u && $3 == d { print $1 }
    ' "$PORTS_DB" | tail -n1)

    if [ -n "$port" ]; then
        echo "$port"
        return 0
    fi
    return 1
}

allocate_port() {
    local user="$1"
    local domain="$2"

    _ensure_db_exists

    if ! _acquire_port_lock; then
        return 1
    fi

    # Check if this user and domain already has an allocated port
    local existing_port
    existing_port=$(awk -F'\t' -v u="$user" -v d="$domain" '
        $1 !~ /^#/ && $2 == u && $3 == d { print $1 }
    ' "$PORTS_DB" | tail -n1)

    if [ -n "$existing_port" ]; then
        _release_port_lock
        echo "$existing_port"
        return 0
    fi

    # Read all currently assigned ports from DB into a temporary lookup list
    local assigned_ports
    assigned_ports=$(awk -F'\t' '$1 !~ /^#/ { print $1 }' "$PORTS_DB" | sort -n)

    local candidate_port
    local found_port=""

    for ((candidate_port=PORT_MIN; candidate_port<=PORT_MAX; candidate_port++)); do
        # 1. Database check
        if echo "$assigned_ports" | grep -qw "$candidate_port"; then
            continue
        fi

        # 2. Operating system kernel socket check
        if is_port_in_use_by_os "$candidate_port"; then
            log_debug "Port $candidate_port absent from database but actively listening in OS; skipping."
            continue
        fi

        # Port is free both in DB and on OS!
        found_port="$candidate_port"
        break
    done

    if [ -z "$found_port" ]; then
        _release_port_lock
        log_error "No available ports remaining in range $PORT_MIN - $PORT_MAX."
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")

    # Record port allocation atomically in DB
    printf "%s\t%s\t%s\t%s\n" "$found_port" "$user" "$domain" "$timestamp" >> "$PORTS_DB"

    _release_port_lock
    echo "$found_port"
    return 0
}

reserve_explicit_port() {
    local user="$1"
    local domain="$2"
    local port="$3"

    _ensure_db_exists

    if ! _acquire_port_lock; then
        return 1
    fi

    # Check if port is already assigned to another application
    local current_owner
    current_owner=$(awk -F'\t' -v p="$port" '
        $1 !~ /^#/ && $1 == p { print $2 "@" $3 }
    ' "$PORTS_DB" | tail -n1)

    if [ -n "$current_owner" ] && [ "$current_owner" != "${user}@${domain}" ]; then
        _release_port_lock
        log_error "Port $port is already registered to another application ($current_owner)."
        return 1
    fi

    # Remove any existing entries for this user and domain
    local tmp_file
    tmp_file=$(mktemp)
    awk -F'\t' -v u="$user" -v d="$domain" -v p="$port" '
        $1 ~ /^#/ || ($2 != u && $3 != d && $1 != p) { print $0 }
    ' "$PORTS_DB" > "$tmp_file"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
    printf "%s\t%s\t%s\t%s\n" "$port" "$user" "$domain" "$timestamp" >> "$tmp_file"

    cat "$tmp_file" > "$PORTS_DB"
    rm -f "$tmp_file"

    _release_port_lock
    return 0
}

release_port() {
    local user="$1"
    local domain="$2"

    _ensure_db_exists

    if ! _acquire_port_lock; then
        return 1
    fi

    local tmp_file
    tmp_file=$(mktemp)
    awk -F'\t' -v u="$user" -v d="$domain" '
        $1 ~ /^#/ || ($2 != u || $3 != d) { print $0 }
    ' "$PORTS_DB" > "$tmp_file"

    cat "$tmp_file" > "$PORTS_DB"
    rm -f "$tmp_file"

    _release_port_lock
    return 0
}

audit_stale_ports() {
    _ensure_db_exists

    if ! _acquire_port_lock; then
        return 1
    fi

    local stale_count=0
    local tmp_file
    tmp_file=$(mktemp)

    # Keep header
    grep "^#" "$PORTS_DB" > "$tmp_file" || true

    while IFS=$'\t' read -r port user domain allocated_at; do
        [[ "$port" =~ ^# ]] && continue
        [ -z "$port" ] && continue

        local app_cfg="${STATE_DIR}/apps/${user}/${domain}.conf"
        if [ ! -f "$app_cfg" ]; then
            log_warn "Purging stale port allocation: Port $port for $user/$domain (config missing)."
            ((stale_count++)) || true
        else
            printf "%s\t%s\t%s\t%s\n" "$port" "$user" "$domain" "$allocated_at" >> "$tmp_file"
        fi
    done < "$PORTS_DB"

    cat "$tmp_file" > "$PORTS_DB"
    rm -f "$tmp_file"

    _release_port_lock
    log_info "Audit complete: $stale_count stale port records purged."
    return 0
}
