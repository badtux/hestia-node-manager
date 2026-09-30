# Hestia Node Manager (`hestia-node`)

> A native Node.js application manager for Hestia Control Panel.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: Debian 12 / Ubuntu](https://img.shields.io/badge/Platform-Debian%2012%20%7C%20Ubuntu-orange.svg)](#requirements)
[![HestiaCP Compatibility](https://img.shields.io/badge/HestiaCP-1.10.5%2B-green.svg)](#hestia-compatibility)

> **Disclaimer:** This is an independent open-source project and is not an official Hestia Control Panel project.

---

## Table of Contents

- [Overview](#overview)
- [Architecture & Design Philosophy](#architecture--design-philosophy)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [CLI Reference](#cli-reference)
- [Configuration](#configuration)
- [Port Management](#port-management)
- [PM2 Process Management](#pm2-process-management)
- [Nginx Reverse Proxy & WebSockets](#nginx-reverse-proxy--websockets)
- [Importing Existing Applications](#importing-existing-applications)
- [Hestia Upgrade Compatibility](#hestia-compatibility)
- [Security Model](#security-model)
- [Troubleshooting & Diagnostics](#troubleshooting--diagnostics)
- [Upgrade Procedure](#upgrade-procedure)
- [Uninstall Procedure](#uninstall-procedure)
- [Development & Testing](#development--testing)
- [License](#license)

---

## Overview

**Hestia Node Manager** (`hestia-node`) enables hosting and managing modern Node.js applications behind Hestia Control Panel's Nginx reverse proxy.

It delivers the capabilities of the legacy `hcpp-nodeapp` plugin with a completely modernized, decoupled architecture:
* **Zero Hestia core modifications**: Never modifies PHP core files or internal directories.
* **No `HestiaCP-Pluginable` dependency**: Standalone CLI and service state.
* **Upgrade-resilient**: Operates out-of-tree and survives Hestia updates (`apt upgrade hestia`) and domain rebuilds (`v-rebuild-web-domain`).
* **Non-destructive migration**: Seamlessly imports existing PM2 applications (such as live production domains) with zero downtime.

---

## Architecture & Design Philosophy

```text
                        Internet (Port 80 / 443)
                                   |
                                   v
                  [ Hestia Nginx Frontend Proxy ]
                                   |
                  Proxy Template: 'HestiaNode'
                  Includes: /etc/hestia-node-manager/nginx/%user%_%domain%.conf
                                   |
                                   v
             [ Reverse Proxy to 127.0.0.1:<allocated-port> ]
               HTTP/1.1 + WebSockets + Security Headers
                                   |
                                   v
           [ PM2 Process Manager (Running as Domain User) ]
                                   |
                                   v
                   [ Node.js Application Process ]
```

### Key Principles
1. **Decoupled State**: Application configurations, port allocations, and proxy snippets live in `/etc/hestia-node-manager/` (root-owned, permissions `0750`). No state is stored inside `/usr/local/hestia/data/`.
2. **Native Extension Points**: Uses Hestia's supported proxy template mechanism (`HestiaNode.tpl` / `HestiaNode.stpl`) and CLI commands (`v-change-web-domain-proxy-tpl`, `v-rebuild-web-domain`).
3. **Privilege Separation**: System and Nginx configuration operations run as `root`; PM2 processes and Node.js execution strictly run as the unprivileged domain user.
4. **Idempotence**: All installation, configuration, and allocation scripts are idempotent and safe to re-run.

---

## Requirements

* **Operating System**: Debian 12 (Bookworm) or Ubuntu 22.04 / 24.04 LTS
* **Control Panel**: Hestia Control Panel 1.10.x+ (tested on 1.10.5)
* **Web Server**: Nginx (configured as reverse proxy)
* **Node.js**: v18+, v20+, or v22+ (system package, NodeSource, or NVM)
* **PM2**: Global (`npm install -g pm2`) or user-level via NVM

---

## Installation

Run the idempotent installer as `root`:

```bash
git clone https://github.com/badtux/hestia-node-manager.git /usr/local/src/hestia-node-manager
cd /usr/local/src/hestia-node-manager
sudo ./install.sh
```

### What the installer does:
1. Validates OS and Hestia installation.
2. Creates state directories under `/etc/hestia-node-manager/` and `/var/log/hestia-node-manager/`.
3. Installs library modules and creates `/usr/local/bin/hestia-node`.
4. Installs the default configuration file to `/etc/hestia-node-manager/config.conf`.
5. Installs the `HestiaNode.tpl` and `HestiaNode.stpl` proxy templates into Hestia's template registry.
6. Installs the WebSocket connection upgrade map to `/etc/nginx/conf.d/hestia-node-upgrade.conf`.
7. Runs `hestia-node doctor` to verify system health.

---

## Quick Start

### 1. Create a New Node.js Application

Register a new application for user `sjbd` and domain `api.example.com`:

```bash
sudo hestia-node create sjbd api.example.com
```

This will:
* Automatically allocate an unused port from the range (e.g. `50000`).
* Generate `/home/sjbd/web/api.example.com/nodeapp/app.js` starter if absent.
* Assign the `HestiaNode` proxy template in Hestia.
* Generate the Nginx reverse proxy configuration.
* Start the application under PM2 as user `sjbd`.
* Persist the PM2 process list across system reboots.

### 2. Check Status and Metrics

```bash
sudo hestia-node status sjbd api.example.com
```

### 3. View Logs

```bash
sudo hestia-node logs sjbd api.example.com --lines 50
```

---

## CLI Reference

```text
hestia-node <COMMAND> [ARGUMENTS...] [OPTIONS...]
```

| Command | Arguments | Description |
|---|---|---|
| `create` | `<USER> <DOMAIN>` | Create, configure, and launch a Node.js application |
| `delete` | `<USER> <DOMAIN>` | Stop and deregister application (preserves source code) |
| `start` | `<USER> <DOMAIN>` | Start application process via PM2 |
| `stop` | `<USER> <DOMAIN>` | Stop application process via PM2 |
| `restart` | `<USER> <DOMAIN>` | Restart application process via PM2 |
| `status` | `<USER> [DOMAIN]` | View process state, memory, CPU, and port status |
| `logs` | `<USER> <DOMAIN>` | View application logs (supports `--lines <N>`) |
| `port` | `<USER> <DOMAIN>` | Output the allocated internal port number |
| `list` | *none* | List all registered applications (supports `--json`) |
| `import` | `<USER> <DOMAIN>` | Non-destructively import an existing running application |
| `doctor` | *none* | Run environment and health diagnostics |
| `version` | *none* | Display version |
| `--help` | *none* | Show help and usage examples |

### CLI Options

* `--app-root <PATH>`: Custom application directory (default: `/home/<USER>/web/<DOMAIN>/nodeapp`)
* `--entrypoint <FILE>`: Main script (default: `app.js`, `server.js`, `index.js`, etc.)
* `--port <PORT>`: Assign an explicit port instead of auto-allocation
* `--process-name <NAME>`: Custom PM2 process name (default: `<DOMAIN>` with hyphens)
* `--watch`: Enable PM2 file watching
* `--dry-run`: Preview actions without executing system modifications
* `--json`: Output lists in JSON format

---

## Configuration

Global settings are stored in `/etc/hestia-node-manager/config.conf`:

```ini
# Port Allocation Range
PORT_MIN=50000
PORT_MAX=59999

# Bind Address (127.0.0.1 prevents direct external port exposure)
NODE_BIND_ADDRESS="127.0.0.1"

# Hestia Proxy Template Name
PROXY_TEMPLATE_NAME="HestiaNode"

# Process Manager
PROCESS_MANAGER="pm2"
PM2_DEFAULT_WATCH="no"
PM2_MAX_MEMORY_RESTART="500M"

# Reverse Proxy Timeouts and Buffers
DEFAULT_HTTP_TIMEOUT=300
DEFAULT_UPLOAD_SIZE="100M"
ENABLE_WEBSOCKETS="yes"

# System Paths
STATE_DIR="/etc/hestia-node-manager"
LOG_DIR="/var/log/hestia-node-manager"
HESTIA_ROOT="/usr/local/hestia"
NGINX_CONF_DIR="/etc/nginx"
```

---

## Port Management

The port allocation engine guarantees zero port collisions through:
1. **Atomic File Locking**: Acquisitions use non-blocking exclusive locking (`flock` on Linux, with atomic POSIX mutex fallback) on `/etc/hestia-node-manager/ports.lock`.
2. **Persistent Registry**: `/etc/hestia-node-manager/ports.db` maintains an inspectable record of port, user, domain, and allocation timestamp.
3. **Kernel Socket Verification**: Even if a port is not in `ports.db`, the allocator queries `ss -tlpn`, `lsof`, and TCP socket probes before granting an allocation. Ports bound by foreign services are automatically skipped.
4. **Stale Eviction**: The registry cleans up deallocated or orphaned ports when applications are removed.

Example port lookup:
```bash
sudo hestia-node port myuser myapp.example.com
# Output: 50001
```

---

## PM2 Process Management

* **Security**: PM2 commands are executed strictly as the unprivileged domain user via `su -s /bin/bash - "$USER" -c ...`. Node.js applications **never** run with root privileges.
* **Environment Detection**: Detects PM2 across NVM paths (`~/.nvm/versions/node/*/bin/pm2`), user binaries (`~/.local/bin/pm2`), and system paths (`/usr/local/bin/pm2`, `/usr/bin/pm2`).
* **Reboot Persistence**: Automatically triggers `pm2 save` to persist processes across server reboots.

---

## Nginx Reverse Proxy & WebSockets

The `HestiaNode` template provides production-grade reverse proxying:
* **HTTP & HTTPS**: Full TLS termination via Hestia certificates (including automated Let's Encrypt renewal).
* **WebSockets**: Native WebSocket upgrades via `$http_upgrade` and `$connection_upgrade`.
* **Standard Headers**: Transmits `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`, and `X-Forwarded-Port`.
* **Large Payloads & Timeouts**: Configurable `client_max_body_size` and timeouts for long-running API requests.
* **Validation Guard**: Every configuration change is verified with `nginx -t` before reloading. If syntax check fails, configurations are automatically rolled back.

---

## Importing Existing Applications

To migrate existing applications (such as applications previously running under `hcpp-nodeapp` or manual PM2 setups):

```bash
sudo hestia-node import myuser myapp.example.com
```

### What import does:
1. Inspects the running PM2 processes and open sockets for user `sjbd`.
2. Auto-detects the active listening port (e.g. `50001`), application root, and entrypoint.
3. Registers the port in `ports.db` and generates the application record.
4. Generates the Nginx reverse proxy configuration.
5. Reassigns the domain's proxy template in Hestia to `HestiaNode`.
6. Reloads Nginx.
7. **Crucial**: The live PM2 process is **not killed or restarted**, guaranteeing 100% uptime during migration.

---

## Hestia Compatibility

Hestia Node Manager is engineered specifically to survive Hestia Control Panel upgrades:
* **Zero Core Modifications**: No files in `/usr/local/hestia/web/`, `inc/`, or `bin/` are modified.
* **Template Retention**: Hestia package updates only overwrite standard built-in templates (`default`, `caching`, etc.). Custom templates with unique names (`HestiaNode.tpl` / `HestiaNode.stpl`) are preserved.
* **Rebuild Resilient**: When Hestia regenerates domain configurations (`v-rebuild-web-domain`), the proxy include line remains intact:
  ```nginx
  include /etc/hestia-node-manager/nginx/%user%_%domain%.conf*;
  ```

---

## Security Model

* **Root Requirement**: Administrative CLI operations require root privileges; application execution runs as domain users.
* **Input Sanitization**: Domain names, usernames, entrypoints, and paths are strictly validated using RFC regex rules. Traversal attempts (`..`) and shell metacharacters are rejected.
* **No `eval`**: All configuration loaders and scripts execute without `eval`.
* **Internal Binding**: Applications bind by default to `127.0.0.1`, keeping application ports unexposed to the public internet.

---

## Troubleshooting & Diagnostics

Run the built-in diagnostic tool to inspect your setup:

```bash
sudo hestia-node doctor
```

Example output:
```text
======================================================
        Hestia Node Manager - System Diagnostics     
======================================================

Checking Operating System... [OK] Debian GNU/Linux 12 (bookworm 12)
Checking Hestia Control Panel... [OK] HestiaCP detected (v1.10.5)
Checking Nginx... [OK] Nginx detected and configuration syntax is valid
Checking Hestia Proxy Templates... [OK] HestiaNode templates installed in Hestia
Checking WebSocket Upgrade Map... [OK] WebSocket upgrade map active in Nginx
Checking System Node.js... [OK] Node.js detected (v22.22.2)
Checking PM2 Process Manager... [OK] Global PM2 detected (5.4.3)
Checking State Directory Permissions... [OK] /etc/hestia-node-manager is writable
Checking Port Allocation Database... [OK] Port database readable (1 active allocations, range 50000-59999)

Registered Applications Summary:
  - myapp.example.com (User: myuser, Port: 50001 [LISTENING], Process: myapp-example-com)

Diagnostic complete: All checks passed successfully.
```

---

## Upgrade Procedure

To upgrade Hestia Node Manager to the latest version:

```bash
cd /usr/local/src/hestia-node-manager
sudo git pull origin main
sudo ./install.sh
```

Existing configuration (`config.conf`), port allocations (`ports.db`), and application records will be preserved.

---

## Uninstall Procedure

To remove Hestia Node Manager components while preserving all user data and running PM2 processes:

```bash
cd /usr/local/src/hestia-node-manager
sudo ./uninstall.sh
```

To also delete all state records and logs, add `--purge`:
```bash
sudo ./uninstall.sh --purge
```

---

## Development & Testing

Run the automated test suite:

```bash
./tests/run_tests.sh
```

The test suite validates:
* **Validation & Security**: User format, domain injection protection, path traversal guards.
* **Port Allocation Engine**: First allocation, sequential allocation, release/re-allocation, explicit reservations, and collision prevention.
* **Concurrency**: 12 parallel background workers stress-testing the atomic locking mechanism.
* **CLI & Dry-Run**: CLI flags, doctor, list, JSON formatting, and dry-run execution.

---

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
