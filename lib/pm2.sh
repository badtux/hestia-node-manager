#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - PM2 Process Management Engine                     #
#=========================================================================#

pm2_find_binary() {
    local user="$1"

    # 1. Check user-specific NVM versions (newest first)
    if [ -d "/home/$user/.nvm/versions/node" ]; then
        local nvm_pm2
        nvm_pm2=$(find "/home/$user/.nvm/versions/node" -maxdepth 3 -type f -name pm2 2>/dev/null | sort -V | tail -n1 || true)
        if [ -n "$nvm_pm2" ] && [ -x "$nvm_pm2" ]; then
            echo "$nvm_pm2"
            return 0
        fi
    fi

    # 2. Check user's home .local/bin or .npm-global/bin
    if [ -x "/home/$user/.local/bin/pm2" ]; then
        echo "/home/$user/.local/bin/pm2"
        return 0
    fi
    if [ -x "/home/$user/.npm-global/bin/pm2" ]; then
        echo "/home/$user/.npm-global/bin/pm2"
        return 0
    fi

    # 3. Check system PATH
    if command -v pm2 &>/dev/null; then
        command -v pm2
        return 0
    fi

    # 4. Standard system locations
    for loc in /usr/local/bin/pm2 /usr/bin/pm2; do
        if [ -x "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done

    # 5. Check companion next to system node
    if command -v node &>/dev/null; then
        local node_dir
        node_dir=$(dirname "$(command -v node)")
        if [ -x "$node_dir/pm2" ]; then
            echo "$node_dir/pm2"
            return 0
        fi
    fi

    return 1
}

pm2_exec_as_user() {
    local user="$1"
    shift
    local cmd=("$@")

    local pm2_bin
    pm2_bin=$(pm2_find_binary "$user" || true)

    if [ -z "$pm2_bin" ]; then
        if [ "${HNM_MOCK_PM2:-0}" -eq 1 ]; then
            pm2_bin="/usr/bin/mock-pm2"
        else
            log_error "PM2 executable could not be found for user '$user' or on system PATH."
            log_error "Please ensure PM2 is installed: npm install -g pm2 (or under the user's NVM/Node environment)."
            return 1
        fi
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${COLOR_YELLOW}[DRY-RUN]${COLOR_RESET} Would run as $user: PM2_HOME=/home/$user/.pm2 $pm2_bin ${cmd[*]}"
        return 0
    fi

    if [ "${HNM_MOCK_PM2:-0}" -eq 1 ]; then
        echo "[Mock PM2] executed for $user: ${cmd[*]}"
        return 0
    fi

    # Execute strictly as the unprivileged user with HOME and PM2_HOME set
    if [ "$(id -u)" -eq 0 ]; then
        su -s /bin/bash - "$user" -c "
            export HOME='/home/$user'
            export PM2_HOME='/home/$user/.pm2'
            export PATH=\"/home/$user/.nvm/versions/node/\$(ls /home/$user/.nvm/versions/node 2>/dev/null | tail -n1)/bin:/home/$user/.local/bin:\$PATH\"
            '$pm2_bin' ${cmd[*]}
        "
    else
        export HOME="/home/$user"
        export PM2_HOME="/home/$user/.pm2"
        "$pm2_bin" "${cmd[@]}"
    fi
}

pm2_start() {
    local user="$1"
    local process_name="$2"
    local app_root="$3"
    local entrypoint="$4"
    local port="$5"

    log_info "Starting application process '$process_name' as user '$user' on port $port..."

    local pm2_args=(
        "start" "$entrypoint"
        "--name" "$process_name"
        "--cwd" "$app_root"
        "--update-env"
    )

    if [ "$PM2_DEFAULT_WATCH" = "yes" ]; then
        pm2_args+=("--watch")
    fi

    if [ -n "$PM2_MAX_MEMORY_RESTART" ]; then
        pm2_args+=("--max-memory-restart" "$PM2_MAX_MEMORY_RESTART")
    fi

    # Start application passing PORT env variable
    if [ "$DRY_RUN" -eq 1 ]; then
        echo -e "${COLOR_YELLOW}[DRY-RUN]${COLOR_RESET} PORT=$port pm2 ${pm2_args[*]}"
        return 0
    fi

    if [ "${HNM_MOCK_PM2:-0}" -eq 1 ]; then
        log_success "[Mock PM2] Process '$process_name' started on port $port"
        return 0
    fi

    local pm2_bin
    pm2_bin=$(pm2_find_binary "$user" || true)

    if [ "$(id -u)" -eq 0 ]; then
        su -s /bin/bash - "$user" -c "
            export HOME='/home/$user'
            export PM2_HOME='/home/$user/.pm2'
            export PORT='$port'
            export NODE_ENV='production'
            '$pm2_bin' ${pm2_args[*]}
        "
    else
        export HOME="/home/$user"
        export PM2_HOME="/home/$user/.pm2"
        export PORT="$port"
        export NODE_ENV="production"
        "$pm2_bin" "${pm2_args[@]}"
    fi

    # Save process list for system reboot persistence
    pm2_save "$user"
    log_success "Application '$process_name' started and registered with PM2."
}

pm2_stop() {
    local user="$1"
    local process_name="$2"

    log_info "Stopping application process '$process_name'..."
    pm2_exec_as_user "$user" stop "$process_name"
    pm2_save "$user"
    log_success "Application '$process_name' stopped."
}

pm2_restart() {
    local user="$1"
    local process_name="$2"

    log_info "Restarting application process '$process_name'..."
    pm2_exec_as_user "$user" restart "$process_name" --update-env
    pm2_save "$user"
    log_success "Application '$process_name' restarted."
}

pm2_delete() {
    local user="$1"
    local process_name="$2"

    log_info "Removing process '$process_name' from PM2..."
    pm2_exec_as_user "$user" delete "$process_name" 2>/dev/null || true
    pm2_save "$user"
}

pm2_save() {
    local user="$1"
    log_debug "Persisting PM2 state for user '$user'..."
    pm2_exec_as_user "$user" save &>/dev/null || true
}

pm2_status() {
    local user="$1"
    local process_name="${2:-}"

    if [ -n "$process_name" ]; then
        pm2_exec_as_user "$user" describe "$process_name"
    else
        pm2_exec_as_user "$user" list
    fi
}

pm2_logs() {
    local user="$1"
    local process_name="$2"
    local lines="${3:-100}"

    pm2_exec_as_user "$user" logs "$process_name" --lines "$lines" --nostream
}

pm2_get_process_info_json() {
    local user="$1"
    local process_name="${2:-}"

    local pm2_bin
    pm2_bin=$(pm2_find_binary "$user" || true)
    if [ -z "$pm2_bin" ]; then
        return 1
    fi

    if [ "$(id -u)" -eq 0 ]; then
        su -s /bin/bash - "$user" -c "
            export HOME='/home/$user'
            export PM2_HOME='/home/$user/.pm2'
            '$pm2_bin' jlist 2>/dev/null
        "
    else
        export HOME="/home/$user"
        export PM2_HOME="/home/$user/.pm2"
        "$pm2_bin" jlist 2>/dev/null
    fi
}
