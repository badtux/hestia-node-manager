#!/usr/bin/env bash
#=========================================================================#
# Hestia Node Manager - Input Validation & Security                       #
#=========================================================================#

validate_username() {
    local user="$1"
    if [[ -z "$user" ]]; then
        log_error "Username cannot be empty."
        return 1
    fi

    # Linux standard user format: lower case letter or underscore, alphanumeric, hyphens, max 32 chars
    if ! [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        log_error "Invalid username format: '$user'. Must start with a letter/underscore and contain only [a-z0-9_-]."
        return 1
    fi

    if [ "${HNM_ALLOW_NON_ROOT:-0}" -eq 0 ]; then
        if ! id "$user" &>/dev/null; then
            log_error "System user '$user' does not exist."
            return 1
        fi
    fi
    return 0
}

validate_domain() {
    local domain="$1"
    if [[ -z "$domain" ]]; then
        log_error "Domain name cannot be empty."
        return 1
    fi

    # Domain name regex check: RFC compliant, alphanumeric + hyphens per label, at least one dot, valid TLD
    local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$"
    if ! [[ "$domain" =~ $domain_regex ]]; then
        log_error "Invalid domain name format: '$domain'."
        return 1
    fi

    # Guard against shell or path injection attempts
    if [[ "$domain" =~ [/\\\'\"\`\$\<\>\&\|\;\*\?] ]]; then
        log_error "Domain name contains illegal characters."
        return 1
    fi
    return 0
}

validate_entrypoint() {
    local entrypoint="$1"
    if [[ -z "$entrypoint" ]]; then
        log_error "Entrypoint cannot be empty."
        return 1
    fi

    # Prevent path traversal
    if [[ "$entrypoint" =~ \.\. ]]; then
        log_error "Entrypoint cannot contain directory traversal ('..')."
        return 1
    fi

    # Reject leading slashes (must be relative to APP_ROOT)
    if [[ "$entrypoint" =~ ^/ ]]; then
        log_error "Entrypoint should be relative to the application root directory (e.g., app.js or dist/index.js)."
        return 1
    fi

    # Guard against dangerous characters
    if [[ "$entrypoint" =~ [\'\"\`\$\<\>\&\|\;\*\?] ]]; then
        log_error "Entrypoint contains illegal characters."
        return 1
    fi
    return 0
}

validate_app_root() {
    local app_root="$1"
    local user="${2:-}"

    if [[ -z "$app_root" ]]; then
        log_error "Application root cannot be empty."
        return 1
    fi

    # Must be absolute path
    if ! [[ "$app_root" =~ ^/ ]]; then
        log_error "Application root must be an absolute path starting with '/'."
        return 1
    fi

    # Prevent path traversal
    if [[ "$app_root" =~ \.\. ]]; then
        log_error "Application root cannot contain directory traversal ('..')."
        return 1
    fi

    # Check existence
    if [ ! -d "$app_root" ]; then
        log_error "Application root directory does not exist: $app_root"
        return 1
    fi

    # Check ownership / access if user provided
    if [ -n "$user" ] && [ "${HNM_ALLOW_NON_ROOT:-0}" -eq 0 ]; then
        if ! su -s /bin/sh "$user" -c "test -d '$app_root' && test -r '$app_root'" 2>/dev/null; then
            log_error "Directory '$app_root' is not readable by user '$user'."
            return 1
        fi
    fi
    return 0
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port: '$port'. Must be a positive integer."
        return 1
    fi

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Port '$port' is out of valid range (1-65535)."
        return 1
    fi
    return 0
}
