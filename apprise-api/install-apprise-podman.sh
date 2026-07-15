#!/bin/bash
#
# Apprise API Installation and Deployment Script for Podman
# Designed for Debian 12 with Podman
#
# This script:
#   - Installs dependencies
#   - Pulls the official Apprise API container image
#   - Configures and runs the container
#   - Optionally creates a systemd service
#   - Uses hardened runtime settings and persistent /config, /plugin, /attach state
#
# Usage: ./install-apprise-podman.sh [OPTIONS]
# Usage (rootless): ./install-apprise-podman.sh --rootless [OPTIONS]
# Usage (system-wide): sudo ./install-apprise-podman.sh [OPTIONS]
#
# Options:
#   --help              Show this help message
#   --rootless          Run rootless (no sudo needed, uses ~/.apprise)
#   --systemd           Create a systemd service (enable/start separately)
#   --port PORT         Set API port (default: 8000)
#   --mailrise          Install and configure Mailrise SMTP relay
#   --mailrise-port PORT
#                       Set Mailrise SMTP port (default: 8025)
#   --mailrise-apprise-key KEY
#                       Set Apprise API config key for Mailrise (default: your_apprise_config_key)
#
# Environment overrides:
#   APPRISE_IMAGE       Container image (default: docker.io/caronc/apprise:latest)
#   PUID, PGID          Container user/group (rootful default: 1000:1000;
#                       rootless default: current uid:gid)
#   APPRISE_STATEFUL_MODE
#                       Apprise stateful mode (default: simple)
#   APPRISE_WORKER_COUNT
#                       Apprise worker count (default: 1)
#   APPRISE_ADMIN       Enable Apprise admin mode (default: y)
#   APPRISE_STORAGE_DIR
#                       Apprise storage directory inside container (default: /config)
#   APPRISE_STORAGE_MODE
#                       Apprise storage mode (default: auto)
#   APPRISE_INTERPRET_EMOJIS
#                       Interpret emoji shortcodes in notifications (default: yes)
#   TZ                  Container timezone (default: operating system timezone)
#

set -Eeuo pipefail

# Color output (ANSI escape codes)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m' # No Color

# Configuration
APPRISE_PORT="${APPRISE_PORT:-8000}"
APPRISE_CONTAINER_NAME="apprise-api"
APPRISE_IMAGE="${APPRISE_IMAGE:-docker.io/caronc/apprise:latest}"
APPRISE_DATA_DIR="/var/lib/apprise"
APPRISE_CONFIG_DIR=""
APPRISE_PLUGIN_DIR=""
APPRISE_ATTACH_DIR=""
APPRISE_STATEFUL_MODE="${APPRISE_STATEFUL_MODE:-simple}"
APPRISE_WORKER_COUNT="${APPRISE_WORKER_COUNT:-1}"
APPRISE_ADMIN="${APPRISE_ADMIN:-y}"
APPRISE_STORAGE_DIR="${APPRISE_STORAGE_DIR:-/config}"
APPRISE_STORAGE_MODE="${APPRISE_STORAGE_MODE:-auto}"
APPRISE_INTERPRET_EMOJIS="${APPRISE_INTERPRET_EMOJIS:-yes}"
TZ="${TZ:-}"
APPRISE_USER="${APPRISE_USER:-}"
MAILRISE_CONTAINER_NAME="mailrise"
MAILRISE_IMAGE="docker.io/yoryan/mailrise:latest"
MAILRISE_CONFIG_FILE="/etc/mailrise.conf"
MAILRISE_EXAMPLE_CONFIG_FILE=""
MAILRISE_PORT="${MAILRISE_PORT:-8025}"
MAILRISE_CONFIG_NAME="${MAILRISE_CONFIG_NAME:-notify}"
MAILRISE_APPRISE_CONFIG_KEY="${MAILRISE_APPRISE_CONFIG_KEY:-your_apprise_config_key}"
NOTIFY_NETWORK_NAME="notify-network"
ENABLE_SYSTEMD=false
ROOTLESS_MODE=false
ENABLE_MAILRISE=false
INSTALL_COMPLETED=false
APPRISE_CONTAINER_CREATED=false
MAILRISE_CONTAINER_CREATED=false
APPRISE_DATA_DIR_CREATED=false
APPRISE_CONFIG_DIR_CREATED=false
APPRISE_PLUGIN_DIR_CREATED=false
APPRISE_ATTACH_DIR_CREATED=false
MAILRISE_CONFIG_DIR_CREATED=false
MAILRISE_CONFIG_TARGET_FILE=""
MAILRISE_CONFIG_TARGET_PREEXISTED=false
NOTIFY_NETWORK_CREATED=false
APPRISE_SERVICE_FILE=""
APPRISE_SERVICE_PREEXISTED=false
APPRISE_SERVICE_BACKUP_FILE=""
MAILRISE_SERVICE_FILE=""
MAILRISE_SERVICE_PREEXISTED=false
MAILRISE_SERVICE_BACKUP_FILE=""

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

cleanup_service_file() {
    local service_file="$1"
    local preexisted="$2"
    local backup_file="$3"
    local label="$4"

    if [[ -z "$service_file" ]]; then
        return 0
    fi

    if [[ "$preexisted" == true ]]; then
        if [[ -n "$backup_file" && -f "$backup_file" ]]; then
            mv -f "$backup_file" "$service_file"
            log_info "Restored previous $label service file: $service_file"
        else
            log_warn "Leaving pre-existing $label service file in place: $service_file"
        fi
    elif [[ -f "$service_file" ]]; then
        rm -f "$service_file"
        log_info "Removed $label service file created by this run: $service_file"
    fi
}

reload_systemd_after_cleanup() {
    if [[ -n "$APPRISE_SERVICE_FILE$MAILRISE_SERVICE_FILE" ]]; then
        if [[ $ROOTLESS_MODE == true ]]; then
            systemctl --user daemon-reload || true
        else
            systemctl daemon-reload || true
        fi
    fi
}

cleanup_success_backups() {
    if [[ -n "$APPRISE_SERVICE_BACKUP_FILE" && -f "$APPRISE_SERVICE_BACKUP_FILE" ]]; then
        rm -f "$APPRISE_SERVICE_BACKUP_FILE"
    fi

    if [[ -n "$MAILRISE_SERVICE_BACKUP_FILE" && -f "$MAILRISE_SERVICE_BACKUP_FILE" ]]; then
        rm -f "$MAILRISE_SERVICE_BACKUP_FILE"
    fi
}

cleanup_on_exit() {
    local exit_code=$?

    if [[ $exit_code -eq 0 || $INSTALL_COMPLETED == true ]]; then
        return 0
    fi

    trap - EXIT
    set +e

    log_error "Installation failed with exit code $exit_code. Cleaning up artifacts created by this run..."

    if command -v podman &> /dev/null; then
        if [[ $MAILRISE_CONTAINER_CREATED == true ]] && podman container exists "$MAILRISE_CONTAINER_NAME" 2>/dev/null; then
            podman stop "$MAILRISE_CONTAINER_NAME" || true
            podman rm "$MAILRISE_CONTAINER_NAME" || true
            log_info "Removed Mailrise container created by this run"
        fi

        if [[ $APPRISE_CONTAINER_CREATED == true ]] && podman container exists "$APPRISE_CONTAINER_NAME" 2>/dev/null; then
            podman stop "$APPRISE_CONTAINER_NAME" || true
            podman rm "$APPRISE_CONTAINER_NAME" || true
            log_info "Removed Apprise API container created by this run"
        fi
    fi

    cleanup_service_file "$MAILRISE_SERVICE_FILE" "$MAILRISE_SERVICE_PREEXISTED" "$MAILRISE_SERVICE_BACKUP_FILE" "Mailrise"
    cleanup_service_file "$APPRISE_SERVICE_FILE" "$APPRISE_SERVICE_PREEXISTED" "$APPRISE_SERVICE_BACKUP_FILE" "Apprise API"
    reload_systemd_after_cleanup

    if [[ -n "$MAILRISE_CONFIG_TARGET_FILE" && $MAILRISE_CONFIG_TARGET_PREEXISTED == false && -f "$MAILRISE_CONFIG_TARGET_FILE" ]]; then
        rm -f "$MAILRISE_CONFIG_TARGET_FILE"
        log_info "Removed Mailrise config generated by this run: $MAILRISE_CONFIG_TARGET_FILE"
    fi

    if [[ $MAILRISE_CONFIG_DIR_CREATED == true ]]; then
        rmdir "$(dirname "$MAILRISE_CONFIG_FILE")" 2>/dev/null || true
    fi

    if [[ $NOTIFY_NETWORK_CREATED == true ]] && command -v podman &> /dev/null; then
        podman network rm "$NOTIFY_NETWORK_NAME" >/dev/null 2>&1 || true
        log_info "Removed Podman network created by this run: $NOTIFY_NETWORK_NAME"
    fi

    if [[ $APPRISE_DATA_DIR_CREATED == true ]]; then
        rmdir "$APPRISE_ATTACH_DIR" 2>/dev/null || true
        rmdir "$APPRISE_PLUGIN_DIR" 2>/dev/null || true
        rmdir "$APPRISE_CONFIG_DIR" 2>/dev/null || true
        rmdir "$APPRISE_DATA_DIR" 2>/dev/null || true
    else
        if [[ $APPRISE_ATTACH_DIR_CREATED == true ]]; then
            rmdir "$APPRISE_ATTACH_DIR" 2>/dev/null || true
        fi
        if [[ $APPRISE_PLUGIN_DIR_CREATED == true ]]; then
            rmdir "$APPRISE_PLUGIN_DIR" 2>/dev/null || true
        fi
        if [[ $APPRISE_CONFIG_DIR_CREATED == true ]]; then
            rmdir "$APPRISE_CONFIG_DIR" 2>/dev/null || true
        fi
    fi

    log_warn "Cleanup complete. Review the logs above for the original failure."
}

check_privileges() {
    if [[ $ROOTLESS_MODE == false && $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo) or with --rootless flag"
        exit 1
    fi
    
    if [[ $ROOTLESS_MODE == true && $EUID -eq 0 ]]; then
        log_error "Rootless mode cannot be used with sudo. Run as regular user."
        exit 1
    fi
}

detect_os_timezone() {
    local detected_timezone=""
    local localtime_target=""

    if command -v timedatectl &> /dev/null; then
        detected_timezone="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
    fi

    if [[ -z "$detected_timezone" && -f /etc/timezone ]]; then
        detected_timezone="$(sed -n '1p' /etc/timezone 2>/dev/null || true)"
    fi

    if [[ -z "$detected_timezone" && -L /etc/localtime ]]; then
        localtime_target="$(readlink /etc/localtime 2>/dev/null || true)"
        if [[ "$localtime_target" == *"/zoneinfo/"* ]]; then
            detected_timezone="${localtime_target#*/zoneinfo/}"
        fi
    fi

    if [[ -z "$detected_timezone" ]]; then
        detected_timezone="UTC"
    fi

    printf '%s\n' "$detected_timezone"
}

configure_timezone() {
    if [[ -n "$TZ" ]]; then
        log_info "Using container timezone from TZ: $TZ"
        return 0
    fi

    TZ="$(detect_os_timezone)"
    log_info "Using operating system timezone for container: $TZ"
}

configure_apprise_user() {
    if [[ -n "$APPRISE_USER" ]]; then
        log_info "Using Apprise container user from APPRISE_USER: $APPRISE_USER"
        return 0
    fi

    if [[ $ROOTLESS_MODE == true ]]; then
        APPRISE_USER="${PUID:-$(id -u)}:${PGID:-$(id -g)}"
    else
        APPRISE_USER="${PUID:-1000}:${PGID:-1000}"
    fi

    log_info "Using Apprise container user: $APPRISE_USER"
}

mailrise_account() {
    if [[ "$MAILRISE_CONFIG_NAME" == *"@"* ]]; then
        printf '%s\n' "$MAILRISE_CONFIG_NAME"
    else
        printf '%s@mailrise.xyz\n' "$MAILRISE_CONFIG_NAME"
    fi
}

check_podman() {
    if ! command -v podman &> /dev/null; then
        log_error "podman is not installed"
        if [[ $ROOTLESS_MODE == true ]]; then
            log_error "Install Podman and rootless prerequisites as an administrator before using --rootless"
            exit 1
        fi
        log_info "Installing podman..."
        apt-get update
        apt-get install -y podman
    fi
    
    local podman_version
    podman_version=$(podman --version | grep -oP '(?<=version )[0-9]+\.[0-9]+\.[0-9]+')
    log_info "Podman version: $podman_version"
}

install_dependencies() {
    log_info "Installing system dependencies..."
    apt-get update
    apt-get install -y \
        podman \
        curl \
        jq \
        wget \
        ca-certificates
    
    log_info "Updating CA certificates for Docker Hub access..."
    apt-get install -y --reinstall ca-certificates
    update-ca-certificates --fresh
    
    log_info "CA certificates updated successfully"
}

setup_apprise_directory() {
    if [[ $ROOTLESS_MODE == true ]]; then
        APPRISE_DATA_DIR="$HOME/.apprise"
        log_info "Rootless mode: using user data directory: $APPRISE_DATA_DIR"
    else
        log_info "Setting up Apprise data directory: $APPRISE_DATA_DIR"
    fi
    
    if [[ ! -d "$APPRISE_DATA_DIR" ]]; then
        APPRISE_DATA_DIR_CREATED=true
    fi

    APPRISE_CONFIG_DIR="$APPRISE_DATA_DIR/config"
    APPRISE_PLUGIN_DIR="$APPRISE_DATA_DIR/plugin"
    APPRISE_ATTACH_DIR="$APPRISE_DATA_DIR/attach"

    if [[ ! -d "$APPRISE_CONFIG_DIR" ]]; then
        APPRISE_CONFIG_DIR_CREATED=true
        log_info "Creating Apprise config directory: $APPRISE_CONFIG_DIR"
    else
        log_info "Using existing Apprise config directory: $APPRISE_CONFIG_DIR"
    fi
    if [[ ! -d "$APPRISE_PLUGIN_DIR" ]]; then
        APPRISE_PLUGIN_DIR_CREATED=true
        log_info "Creating Apprise plugin directory: $APPRISE_PLUGIN_DIR"
    else
        log_info "Using existing Apprise plugin directory: $APPRISE_PLUGIN_DIR"
    fi
    if [[ ! -d "$APPRISE_ATTACH_DIR" ]]; then
        APPRISE_ATTACH_DIR_CREATED=true
        log_info "Creating Apprise attachment directory: $APPRISE_ATTACH_DIR"
    else
        log_info "Using existing Apprise attachment directory: $APPRISE_ATTACH_DIR"
    fi

    mkdir -p "$APPRISE_CONFIG_DIR" "$APPRISE_PLUGIN_DIR" "$APPRISE_ATTACH_DIR"
    chmod 755 "$APPRISE_DATA_DIR" "$APPRISE_CONFIG_DIR" "$APPRISE_PLUGIN_DIR" "$APPRISE_ATTACH_DIR"

    if [[ $ROOTLESS_MODE == false ]]; then
        chown "$APPRISE_USER" "$APPRISE_DATA_DIR"
        chown -R "$APPRISE_USER" "$APPRISE_CONFIG_DIR" "$APPRISE_PLUGIN_DIR" "$APPRISE_ATTACH_DIR"
    fi
}

setup_mailrise_config() {
    local config_dir
    local target_config_file

    if [[ $ROOTLESS_MODE == true ]]; then
        MAILRISE_CONFIG_FILE="$HOME/.config/mailrise/mailrise.conf"
    fi

    config_dir="$(dirname "$MAILRISE_CONFIG_FILE")"
    MAILRISE_EXAMPLE_CONFIG_FILE="$config_dir/mailrise.conf.example"
    if [[ ! -d "$config_dir" ]]; then
        MAILRISE_CONFIG_DIR_CREATED=true
    fi
    mkdir -p "$config_dir"

    if [[ -f "$MAILRISE_CONFIG_FILE" ]]; then
        target_config_file="$MAILRISE_EXAMPLE_CONFIG_FILE"
        log_warn "Existing Mailrise config found: $MAILRISE_CONFIG_FILE"
        log_info "Leaving existing config unchanged"
        log_info "Writing example Mailrise config: $target_config_file"
    else
        target_config_file="$MAILRISE_CONFIG_FILE"
        log_info "Creating Mailrise config: $target_config_file"
    fi
    MAILRISE_CONFIG_TARGET_FILE="$target_config_file"
    if [[ -f "$target_config_file" ]]; then
        MAILRISE_CONFIG_TARGET_PREEXISTED=true
    fi

    cat > "$target_config_file" << EOF
configs:
  $MAILRISE_CONFIG_NAME:
    urls:
      - apprise://$APPRISE_CONTAINER_NAME:8000/$MAILRISE_APPRISE_CONFIG_KEY
EOF

    chmod 644 "$target_config_file"
}

create_notify_network() {
    if podman network exists "$NOTIFY_NETWORK_NAME" 2>/dev/null; then
        log_info "Podman network already exists: $NOTIFY_NETWORK_NAME"
        return 0
    fi

    log_info "Creating Podman network: $NOTIFY_NETWORK_NAME"
    podman network create "$NOTIFY_NETWORK_NAME"
    NOTIFY_NETWORK_CREATED=true
}

pull_apprise_image() {
    log_info "Pulling official Apprise API Docker image from Docker Hub..."
    log_info "Image: $APPRISE_IMAGE"
    
    # Pull the official caronc/apprise image (unauthenticated)
    if podman pull "$APPRISE_IMAGE"; then
        log_info "Successfully pulled: $APPRISE_IMAGE"
        return 0
    else
        log_error "Failed to pull Docker image: $APPRISE_IMAGE"
        log_info "Try manual pull for diagnostics:"
        log_info "  podman pull $APPRISE_IMAGE"
        return 1
    fi
}

pull_mailrise_image() {
    log_info "Pulling Mailrise Docker image from Docker Hub..."
    log_info "Image: $MAILRISE_IMAGE"

    if podman pull "$MAILRISE_IMAGE"; then
        log_info "Successfully pulled: $MAILRISE_IMAGE"
        return 0
    else
        log_error "Failed to pull Docker image: $MAILRISE_IMAGE"
        log_info "Try manual pull for diagnostics:"
        log_info "  podman pull $MAILRISE_IMAGE"
        return 1
    fi
}

build_apprise_image_locally() {
    log_error "Local image build is not supported with the official Docker image"
    log_info "The installer uses the caronc/apprise image from Docker Hub"
    log_info "Ensure you have:"
    log_info "  1. Internet connectivity"
    log_info "  2. Access to Docker Hub registry"
    log_info "  3. Sufficient disk space (~500MB)"
    log_info ""
    log_info "If the pull failed, try manually:"
    log_info "  sudo podman pull $APPRISE_IMAGE"
    exit 1
}

stop_existing_container() {
    if podman container exists "$APPRISE_CONTAINER_NAME" 2>/dev/null; then
        log_info "Stopping existing container: $APPRISE_CONTAINER_NAME"
        podman stop "$APPRISE_CONTAINER_NAME" || true
        if podman container exists "$APPRISE_CONTAINER_NAME" 2>/dev/null; then
            podman rm "$APPRISE_CONTAINER_NAME" || true
        fi
    fi
}

stop_existing_mailrise_container() {
    if podman container exists "$MAILRISE_CONTAINER_NAME" 2>/dev/null; then
        log_info "Stopping existing container: $MAILRISE_CONTAINER_NAME"
        podman stop "$MAILRISE_CONTAINER_NAME" || true
        if podman container exists "$MAILRISE_CONTAINER_NAME" 2>/dev/null; then
            podman rm "$MAILRISE_CONTAINER_NAME" || true
        fi
    fi
}

create_systemd_service() {
    local service_file
    local service_dir
    local enable_cmd
    local start_cmd
    
    if [[ $ROOTLESS_MODE == true ]]; then
        service_dir="$HOME/.config/systemd/user"
        service_file="$service_dir/apprise-api.service"
        enable_cmd="systemctl --user enable apprise-api"
        start_cmd="systemctl --user start apprise-api"
        log_info "Creating user-level systemd service: $service_file"
    else
        service_dir="/etc/systemd/system"
        service_file="$service_dir/apprise-api.service"
        enable_cmd="systemctl enable apprise-api"
        start_cmd="systemctl start apprise-api"
        log_info "Creating system-level systemd service: $service_file"
    fi

    APPRISE_SERVICE_FILE="$service_file"
    if [[ -f "$service_file" ]]; then
        APPRISE_SERVICE_PREEXISTED=true
        APPRISE_SERVICE_BACKUP_FILE="$service_file.pre-install.$(date +%Y%m%d%H%M%S).bak"
        cp -p "$service_file" "$APPRISE_SERVICE_BACKUP_FILE"
    fi
    
    mkdir -p "$service_dir"
    
    # Determine WantedBy target
    local wanted_by="multi-user.target"
    if [[ $ROOTLESS_MODE == true ]]; then
        wanted_by="default.target"
    fi
    
    {
        cat << EOF
[Unit]
Description=Apprise API Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
Restart=always
RestartSec=10

# Run the container with podman
ExecStart=/usr/bin/podman run --rm \\
    --name $APPRISE_CONTAINER_NAME \\
    --user $APPRISE_USER \\
$(if [[ $ROOTLESS_MODE == true ]]; then echo "    --userns keep-id \\"; fi)
    --read-only \\
    --security-opt no-new-privileges=true \\
    --cap-drop ALL \\
    --tmpfs /tmp \\
    -p $APPRISE_PORT:8000 \\
    -e APPRISE_STATEFUL_MODE=$APPRISE_STATEFUL_MODE \\
    -e APPRISE_WORKER_COUNT=$APPRISE_WORKER_COUNT \\
    -e APPRISE_ADMIN=$APPRISE_ADMIN \\
    -e APPRISE_STORAGE_DIR=$APPRISE_STORAGE_DIR \\
    -e APPRISE_STORAGE_MODE=$APPRISE_STORAGE_MODE \\
    -e APPRISE_INTERPRET_EMOJIS=$APPRISE_INTERPRET_EMOJIS \\
    -e TZ=$TZ \\
    -v $APPRISE_CONFIG_DIR:/config \\
    -v $APPRISE_PLUGIN_DIR:/plugin \\
    -v $APPRISE_ATTACH_DIR:/attach \\
EOF
        if [[ $ENABLE_MAILRISE == true ]]; then
            echo "    --network $NOTIFY_NETWORK_NAME \\"
        fi
        cat << EOF
    --log-driver journald \\
    $APPRISE_IMAGE

ExecStop=/usr/bin/podman stop -t 10 $APPRISE_CONTAINER_NAME

[Install]
WantedBy=$wanted_by
EOF
    } > "$service_file"
    
    chmod 644 "$service_file"
    
    if [[ $ROOTLESS_MODE == true ]]; then
        systemctl --user daemon-reload
        log_info "User-level systemd service created successfully"
    else
        systemctl daemon-reload
        log_info "System-level systemd service created successfully"
    fi
    
    log_info "Enable with: $enable_cmd"
    log_info "Start with: $start_cmd"
}

create_mailrise_systemd_service() {
    local service_file
    local service_dir
    local enable_cmd
    local start_cmd
    local wanted_by="multi-user.target"

    if [[ $ROOTLESS_MODE == true ]]; then
        service_dir="$HOME/.config/systemd/user"
        service_file="$service_dir/mailrise.service"
        enable_cmd="systemctl --user enable mailrise"
        start_cmd="systemctl --user start mailrise"
        wanted_by="default.target"
        log_info "Creating user-level Mailrise systemd service: $service_file"
    else
        service_dir="/etc/systemd/system"
        service_file="$service_dir/mailrise.service"
        enable_cmd="systemctl enable mailrise"
        start_cmd="systemctl start mailrise"
        log_info "Creating system-level Mailrise systemd service: $service_file"
    fi

    MAILRISE_SERVICE_FILE="$service_file"
    if [[ -f "$service_file" ]]; then
        MAILRISE_SERVICE_PREEXISTED=true
        MAILRISE_SERVICE_BACKUP_FILE="$service_file.pre-install.$(date +%Y%m%d%H%M%S).bak"
        cp -p "$service_file" "$MAILRISE_SERVICE_BACKUP_FILE"
    fi

    mkdir -p "$service_dir"

    cat > "$service_file" << EOF
[Unit]
Description=Mailrise SMTP notification relay
After=network-online.target apprise-api.service
Wants=network-online.target apprise-api.service
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
Restart=always
RestartSec=10

# Run the container with podman
ExecStart=/usr/bin/podman run --rm \\
    --name $MAILRISE_CONTAINER_NAME \\
    -p $MAILRISE_PORT:8025 \\
    -v $MAILRISE_CONFIG_FILE:/etc/mailrise.conf:ro \\
    --network $NOTIFY_NETWORK_NAME \\
    --log-driver journald \\
    $MAILRISE_IMAGE

ExecStop=/usr/bin/podman stop -t 10 $MAILRISE_CONTAINER_NAME

[Install]
WantedBy=$wanted_by
EOF

    chmod 644 "$service_file"

    if [[ $ROOTLESS_MODE == true ]]; then
        systemctl --user daemon-reload
        log_info "User-level Mailrise systemd service created successfully"
    else
        systemctl daemon-reload
        log_info "System-level Mailrise systemd service created successfully"
    fi

    log_info "Enable with: $enable_cmd"
    log_info "Start with: $start_cmd"
}

run_container_direct() {
    local network_args=()
    local userns_args=()

    log_info "Running Apprise API container..."

    if [[ $ENABLE_MAILRISE == true ]]; then
        network_args=(--network "$NOTIFY_NETWORK_NAME")
    fi
    if [[ $ROOTLESS_MODE == true ]]; then
        userns_args=(--userns keep-id)
    fi
    
    podman run -d \
        --name "$APPRISE_CONTAINER_NAME" \
        --user "$APPRISE_USER" \
        "${userns_args[@]}" \
        --read-only \
        --security-opt no-new-privileges=true \
        --cap-drop ALL \
        --tmpfs /tmp \
        -p "$APPRISE_PORT:8000" \
        -e "APPRISE_STATEFUL_MODE=$APPRISE_STATEFUL_MODE" \
        -e "APPRISE_WORKER_COUNT=$APPRISE_WORKER_COUNT" \
        -e "APPRISE_ADMIN=$APPRISE_ADMIN" \
        -e "APPRISE_STORAGE_DIR=$APPRISE_STORAGE_DIR" \
        -e "APPRISE_STORAGE_MODE=$APPRISE_STORAGE_MODE" \
        -e "APPRISE_INTERPRET_EMOJIS=$APPRISE_INTERPRET_EMOJIS" \
        -e "TZ=$TZ" \
        -v "$APPRISE_CONFIG_DIR:/config" \
        -v "$APPRISE_PLUGIN_DIR:/plugin" \
        -v "$APPRISE_ATTACH_DIR:/attach" \
        "${network_args[@]}" \
        --restart=always \
        --log-driver=journald \
        "$APPRISE_IMAGE"
    APPRISE_CONTAINER_CREATED=true
    
    log_info "Container started successfully"
    log_info "Apprise API is running on http://localhost:$APPRISE_PORT"
}

run_mailrise_container_direct() {
    log_info "Running Mailrise container..."

    podman run -d \
        --name "$MAILRISE_CONTAINER_NAME" \
        -p "$MAILRISE_PORT:8025" \
        -v "$MAILRISE_CONFIG_FILE:/etc/mailrise.conf:ro" \
        --network "$NOTIFY_NETWORK_NAME" \
        --restart=always \
        --log-driver=journald \
        "$MAILRISE_IMAGE"
    MAILRISE_CONTAINER_CREATED=true

    log_info "Mailrise SMTP relay is running on port $MAILRISE_PORT"
}

verify_installation() {
    log_info "Verifying installation..."
    
    sleep 3
    
    if podman container exists "$APPRISE_CONTAINER_NAME" 2>/dev/null; then
        local status
        status=$(podman container inspect "$APPRISE_CONTAINER_NAME" --format='{{.State.Status}}')
        if [[ "$status" == "running" ]]; then
            log_info "Container is running"
            
            # Try to reach the API
            if curl -fsS "http://localhost:$APPRISE_PORT/status" > /dev/null 2>&1; then
                log_info "API is responding"
            else
                log_warn "Could not verify API response (may take a moment to start)"
            fi
        else
            log_error "Container is not running. Status: $status"
            log_error "Logs: $(podman logs $APPRISE_CONTAINER_NAME 2>&1 | tail -n 10)"
            exit 1
        fi
    fi

    if [[ $ENABLE_MAILRISE == true ]] && podman container exists "$MAILRISE_CONTAINER_NAME" 2>/dev/null; then
        local mailrise_status
        mailrise_status=$(podman container inspect "$MAILRISE_CONTAINER_NAME" --format='{{.State.Status}}')
        if [[ "$mailrise_status" == "running" ]]; then
            log_info "Mailrise container is running"
        else
            log_error "Mailrise container is not running. Status: $mailrise_status"
            log_error "Logs: $(podman logs $MAILRISE_CONTAINER_NAME 2>&1 | tail -n 10)"
            exit 1
        fi
    fi
}

show_info() {
    cat << EOF

${GREEN}========== Apprise API Installation Complete ==========${NC}

Container Name:     $APPRISE_CONTAINER_NAME
API Port:           $APPRISE_PORT
Data Directory:     $APPRISE_DATA_DIR
Config Directory:   $APPRISE_CONFIG_DIR
Plugin Directory:   $APPRISE_PLUGIN_DIR
Attach Directory:   $APPRISE_ATTACH_DIR
Image:              $APPRISE_IMAGE
Container User:     $APPRISE_USER
Timezone:           $TZ
Storage Directory:  $APPRISE_STORAGE_DIR
Storage Mode:       $APPRISE_STORAGE_MODE
Interpret Emojis:   $APPRISE_INTERPRET_EMOJIS
Mode:               $(if [[ $ROOTLESS_MODE == true ]]; then echo "Rootless (user)"; else echo "Rootful (system)"; fi)
Mailrise:           $(if [[ $ENABLE_MAILRISE == true ]]; then echo "Enabled"; else echo "Disabled"; fi)
$(if [[ $ENABLE_MAILRISE == true ]]; then
cat << MAILRISE_SUMMARY
Mailrise Image:     $MAILRISE_IMAGE
Mailrise SMTP Port: $MAILRISE_PORT
Mailrise Config:    $MAILRISE_CONFIG_FILE
Mailrise Account:   $(mailrise_account)
$(if [[ -n $MAILRISE_EXAMPLE_CONFIG_FILE && -f $MAILRISE_EXAMPLE_CONFIG_FILE ]]; then echo "Mailrise Example:   $MAILRISE_EXAMPLE_CONFIG_FILE"; fi)
Podman Network:     $NOTIFY_NETWORK_NAME
Apprise URL:        apprise://$APPRISE_CONTAINER_NAME:8000/$MAILRISE_APPRISE_CONFIG_KEY
MAILRISE_SUMMARY
fi)

${GREEN}Useful Commands:${NC}

View logs:
  podman logs -f $APPRISE_CONTAINER_NAME

Stop container:
  podman stop $APPRISE_CONTAINER_NAME

Start container:
  podman start $APPRISE_CONTAINER_NAME

Remove container:
  podman rm -f $APPRISE_CONTAINER_NAME

$(if [[ $ENABLE_MAILRISE == true ]]; then
cat << MAILRISE_COMMANDS
View Mailrise logs:
  podman logs -f $MAILRISE_CONTAINER_NAME

Stop Mailrise:
  podman stop $MAILRISE_CONTAINER_NAME

Start Mailrise:
  podman start $MAILRISE_CONTAINER_NAME

MAILRISE_COMMANDS
fi)

Access API:
  http://localhost:$APPRISE_PORT
  
Configuration Interface:
  http://localhost:$APPRISE_PORT/

$(if [[ $ROOTLESS_MODE == true ]]; then
cat << ROOTLESS
${GREEN}Rootless Mode Notes:${NC}

- Container runs as your user ($(whoami))
- No system-wide access needed
- Data stored in: $HOME/.apprise
- Use 'podman' commands directly (no sudo needed for user containers)

$(if [[ $ENABLE_SYSTEMD == true ]]; then
cat << ROOTLESS_SYSTEMD
${GREEN}User Systemd Management:${NC}

Enable auto-start:
  systemctl --user enable apprise-api

Start service:
  systemctl --user start apprise-api

Stop service:
  systemctl --user stop apprise-api

View service logs:
  journalctl --user -u apprise-api -f
$(if [[ $ENABLE_MAILRISE == true ]]; then
cat << ROOTLESS_MAILRISE_SYSTEMD

Enable Mailrise auto-start:
  systemctl --user enable mailrise

Start Mailrise service:
  systemctl --user start mailrise

View Mailrise service logs:
  journalctl --user -u mailrise -f
ROOTLESS_MAILRISE_SYSTEMD
fi)

Enable lingering (run services even when not logged in):
  loginctl enable-linger
ROOTLESS_SYSTEMD
fi)
ROOTLESS
else
cat << ROOTFUL
${GREEN}Systemd Management (if enabled):${NC}

Enable auto-start:
  systemctl enable apprise-api

Start service:
  systemctl start apprise-api

Stop service:
  systemctl stop apprise-api

View service logs:
  journalctl -u apprise-api -f
$(if [[ $ENABLE_MAILRISE == true ]]; then
cat << ROOTFUL_MAILRISE_SYSTEMD

Enable Mailrise auto-start:
  systemctl enable mailrise

Start Mailrise service:
  systemctl start mailrise

View Mailrise service logs:
  journalctl -u mailrise -f
ROOTFUL_MAILRISE_SYSTEMD
fi)
ROOTFUL
fi)

${GREEN}========================================================${NC}

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --rootless)
            ROOTLESS_MODE=true
            shift
            ;;
        --systemd)
            ENABLE_SYSTEMD=true
            shift
            ;;
        --port)
            if [[ $# -lt 2 ]]; then
                log_error "--port requires a port number"
                exit 1
            fi
            if [[ ! "$2" =~ ^[0-9]+$ ]] || (( $2 < 1 || $2 > 65535 )); then
                log_error "Invalid port: $2 (must be 1-65535)"
                exit 1
            fi
            APPRISE_PORT="$2"
            shift 2
            ;;
        --mailrise)
            ENABLE_MAILRISE=true
            shift
            ;;
        --mailrise-port)
            if [[ $# -lt 2 ]]; then
                log_error "--mailrise-port requires a port number"
                exit 1
            fi
            if [[ ! "$2" =~ ^[0-9]+$ ]] || (( $2 < 1 || $2 > 65535 )); then
                log_error "Invalid Mailrise port: $2 (must be 1-65535)"
                exit 1
            fi
            MAILRISE_PORT="$2"
            shift 2
            ;;
        --mailrise-apprise-key)
            if [[ $# -lt 2 || -z "$2" ]]; then
                log_error "--mailrise-apprise-key requires a config key"
                exit 1
            fi
            MAILRISE_APPRISE_CONFIG_KEY="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

trap cleanup_on_exit EXIT

# Main execution
main() {
    if [[ $ROOTLESS_MODE == true ]]; then
        log_info "Starting Apprise API installation in ROOTLESS mode"
        log_info "Data directory: $HOME/.apprise"
    else
        log_info "Starting Apprise API installation on Debian 12 for Raspberry Pi 5"
    fi
    
    log_info "Using official Apprise API Docker image: $APPRISE_IMAGE"
    if [[ $ENABLE_MAILRISE == true ]]; then
        log_info "Mailrise installation enabled"
        log_info "Using Mailrise Docker image: $MAILRISE_IMAGE"
    fi
    check_privileges
    configure_timezone
    configure_apprise_user
    check_podman
    
    # Only install system dependencies if not rootless
    if [[ $ROOTLESS_MODE == false ]]; then
        install_dependencies
    else
        log_info "Rootless mode: skipping system dependency installation"
        log_info "Ensure podman and ca-certificates are installed"
    fi
    
    setup_apprise_directory
    if [[ $ENABLE_MAILRISE == true ]]; then
        setup_mailrise_config
        create_notify_network
    fi
    
    # Pull the official Docker image
    if pull_apprise_image; then
        log_info "Official Apprise API Docker image loaded"
    else
        log_error "Failed to pull the official Apprise API Docker image"
        exit 1
    fi
    if [[ $ENABLE_MAILRISE == true ]]; then
        if pull_mailrise_image; then
            log_info "Mailrise Docker image loaded"
        else
            log_error "Failed to pull the Mailrise Docker image"
            exit 1
        fi
    fi
    
    stop_existing_container
    if [[ $ENABLE_MAILRISE == true ]]; then
        stop_existing_mailrise_container
    fi
    
    if [[ $ENABLE_SYSTEMD == true ]]; then
        create_systemd_service
        if [[ $ENABLE_MAILRISE == true ]]; then
            create_mailrise_systemd_service
        fi
        log_info "Systemd service created. Enable and start with:"
        if [[ $ROOTLESS_MODE == true ]]; then
            log_info "  systemctl --user enable apprise-api"
            log_info "  systemctl --user start apprise-api"
            if [[ $ENABLE_MAILRISE == true ]]; then
                log_info "  systemctl --user enable mailrise"
                log_info "  systemctl --user start mailrise"
            fi
        else
            log_info "  systemctl enable apprise-api"
            log_info "  systemctl start apprise-api"
            if [[ $ENABLE_MAILRISE == true ]]; then
                log_info "  systemctl enable mailrise"
                log_info "  systemctl start mailrise"
            fi
        fi
    else
        run_container_direct
        if [[ $ENABLE_MAILRISE == true ]]; then
            run_mailrise_container_direct
        fi
        verify_installation
    fi
    
    show_info
    cleanup_success_backups || true
    INSTALL_COMPLETED=true
    
    log_info "Installation completed successfully!"
}

# Run main function
main "$@"
