#!/bin/bash
#
# Apprise API Installation and Deployment Script for Podman
# Designed for Debian 12 on Raspberry Pi 5 with podman 4.3.1
#
# This script:
#   - Installs dependencies
#   - Pulls/builds the Apprise API container
#   - Configures and runs the container
#   - Optionally creates a systemd service
#
# Usage: ./install-apprise-podman.sh [OPTIONS]
# Usage (rootless): ./install-apprise-podman.sh --rootless [OPTIONS]
# Usage (system-wide): sudo ./install-apprise-podman.sh [OPTIONS]
#
# Options:
#   --help              Show this help message
#   --rootless          Run rootless (no sudo needed, uses ~/.apprise)
#   --systemd           Create a systemd service for auto-start
#   --port PORT         Set API port (default: 8000)
#

set -euo pipefail

# Color output (ANSI escape codes)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m' # No Color

# Configuration
APPRISE_PORT="${APPRISE_PORT:-8000}"
APPRISE_CONTAINER_NAME="apprise-api"
APPRISE_IMAGE="caronc/apprise"
APPRISE_DATA_DIR="/var/lib/apprise"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/apprise-api.service"
ENABLE_SYSTEMD=false
ROOTLESS_MODE=false

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
    sed -n '3,23p' "$0" | sed 's/^# //'
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

check_podman() {
    if ! command -v podman &> /dev/null; then
        log_error "podman is not installed"
        log_info "Installing podman..."
        apt-get update
        apt-get install -y podman
    fi
    
    local podman_version=$(podman --version | grep -oP '(?<=version )[0-9]+\.[0-9]+\.[0-9]+')
    log_info "Podman version: $podman_version"
}

configure_registries() {
    # Configure registry search for short-name image resolution
    # Required for: podman pull caronc/apprise (without docker.io prefix)
    
    local registries_conf="/etc/containers/registries.conf"
    
    if [[ ! -f "$registries_conf" ]]; then
        log_warn "Registries config not found: $registries_conf"
        log_info "Creating registries config..."
        mkdir -p "$(dirname "$registries_conf")"
        touch "$registries_conf"
    fi
    
    # Check if [registries.search] section already exists
    if grep -q "^\[registries\.search\]" "$registries_conf"; then
        log_info "Registry search already configured"
        return 0
    fi
    
    log_info "Configuring registry search in: $registries_conf"
    
    # Add [registries.search] section with Docker Hub and Quay.io
    cat >> "$registries_conf" << 'EOF'

[registries.search]
registries = ['docker.io', 'quay.io']
EOF
    
    if [[ $? -eq 0 ]]; then
        log_info "Registry search configuration added successfully"
        return 0
    else
        log_error "Failed to configure registry search"
        return 1
    fi
}

install_dependencies() {
    log_info "Installing system dependencies..."
    apt-get update
    apt-get install -y \
        podman \
        curl \
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
    
    mkdir -p "$APPRISE_DATA_DIR"
    chmod 755 "$APPRISE_DATA_DIR"
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
        log_info "  podman pull caronc/apprise"
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
    log_info "  sudo podman pull caronc/apprise"
    exit 1
}

stop_existing_container() {
    if podman container exists "$APPRISE_CONTAINER_NAME" 2>/dev/null; then
        log_info "Stopping existing container: $APPRISE_CONTAINER_NAME"
        podman stop "$APPRISE_CONTAINER_NAME" || true
        podman rm "$APPRISE_CONTAINER_NAME" || true
    fi
}

create_systemd_service() {
    local service_file
    local service_dir
    local enable_cmd
    local start_cmd
    local stop_cmd
    
    if [[ $ROOTLESS_MODE == true ]]; then
        service_dir="$HOME/.config/systemd/user"
        service_file="$service_dir/apprise-api.service"
        enable_cmd="systemctl --user enable apprise-api"
        start_cmd="systemctl --user start apprise-api"
        stop_cmd="systemctl --user stop apprise-api"
        log_info "Creating user-level systemd service: $service_file"
    else
        service_dir="/etc/systemd/system"
        service_file="$service_dir/apprise-api.service"
        enable_cmd="systemctl enable apprise-api"
        start_cmd="systemctl start apprise-api"
        stop_cmd="systemctl stop apprise-api"
        log_info "Creating system-level systemd service: $service_file"
    fi
    
    mkdir -p "$service_dir"
    
    # Determine WantedBy target
    local wanted_by="multi-user.target"
    if [[ $ROOTLESS_MODE == true ]]; then
        wanted_by="default.target"
    fi
    
    cat > "$service_file" << EOF
[Unit]
Description=Apprise API Service
After=network.target
$(if [[ $ROOTLESS_MODE == false ]]; then echo "Wants=podman.service"; fi)

[Service]
Type=simple
Restart=always
RestartSec=10
StartLimitInterval=60s
StartLimitBurst=3

# Run the container with podman
ExecStart=/usr/bin/podman run --rm \\
    --name $APPRISE_CONTAINER_NAME \\
    -p $APPRISE_PORT:8000 \\
    -v $APPRISE_DATA_DIR:/apprise \\
    --log-driver journald \\
    $APPRISE_IMAGE

ExecStop=/usr/bin/podman stop -t 10 $APPRISE_CONTAINER_NAME

[Install]
WantedBy=$wanted_by
EOF
    
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

run_container_direct() {
    log_info "Running Apprise API container..."
    
    podman run -d \
        --name "$APPRISE_CONTAINER_NAME" \
        -p "$APPRISE_PORT:8000" \
        -v "$APPRISE_DATA_DIR:/apprise" \
        --restart=always \
        --log-driver=journald \
        "$APPRISE_IMAGE"
    
    log_info "Container started successfully"
    log_info "Apprise API is running on http://localhost:$APPRISE_PORT"
}

verify_installation() {
    log_info "Verifying installation..."
    
    sleep 3
    
    if podman container exists "$APPRISE_CONTAINER_NAME" 2>/dev/null; then
        local status=$(podman container inspect "$APPRISE_CONTAINER_NAME" --format='{{.State.Status}}')
        if [[ "$status" == "running" ]]; then
            log_info "Container is running"
            
            # Try to reach the API
            if curl -s "http://localhost:$APPRISE_PORT/notify" > /dev/null 2>&1; then
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
}

show_info() {
    cat << EOF

${GREEN}========== Apprise API Installation Complete ==========${NC}

Container Name:     $APPRISE_CONTAINER_NAME
API Port:           $APPRISE_PORT
Data Directory:     $APPRISE_DATA_DIR
Image:              $APPRISE_IMAGE
Mode:               $(if [[ $ROOTLESS_MODE == true ]]; then echo "Rootless (user)"; else echo "Rootful (system)"; fi)

${GREEN}Useful Commands:${NC}

View logs:
  podman logs -f $APPRISE_CONTAINER_NAME

Stop container:
  podman stop $APPRISE_CONTAINER_NAME

Start container:
  podman start $APPRISE_CONTAINER_NAME

Remove container:
  podman rm -f $APPRISE_CONTAINER_NAME

Access API:
  http://localhost:$APPRISE_PORT
  
API Documentation:
  http://localhost:$APPRISE_PORT/docs

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
            if [[ ! "$2" =~ ^[0-9]+$ ]] || (( $2 < 1 || $2 > 65535 )); then
                log_error "Invalid port: $2 (must be 1-65535)"
                exit 1
            fi
            APPRISE_PORT="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    if [[ $ROOTLESS_MODE == true ]]; then
        log_info "Starting Apprise API installation in ROOTLESS mode"
        log_info "Data directory: $HOME/.apprise"
    else
        log_info "Starting Apprise API installation on Debian 12 for Raspberry Pi 5"
    fi
    
    log_info "Using official Apprise API Docker image: $APPRISE_IMAGE"
    log_info "Podman version 4.3.1+"
    
    check_privileges
    check_podman
    
    # Only install system dependencies if not rootless
    if [[ $ROOTLESS_MODE == false ]]; then
        install_dependencies
        # Configure registry search for short-name image resolution
        if ! configure_registries; then
            log_warn "Registry configuration failed, but continuing..."
        fi
    else
        log_info "Rootless mode: skipping system dependency installation"
        log_info "Ensure podman and ca-certificates are installed"
    fi
    
    setup_apprise_directory
    
    # Pull the official Docker image
    if pull_apprise_image; then
        log_info "Official Apprise API Docker image loaded"
    else
        log_error "Failed to pull the official Apprise API Docker image"
        exit 1
    fi
    
    stop_existing_container
    
    if [[ $ENABLE_SYSTEMD == true ]]; then
        create_systemd_service
        log_info "Systemd service created. Enable and start with:"
        log_info "  systemctl enable apprise-api"
        log_info "  systemctl start apprise-api"
    else
        run_container_direct
        verify_installation
    fi
    
    show_info
    
    log_info "Installation completed successfully!"
}

# Run main function
main "$@"
