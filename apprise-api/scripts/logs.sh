#!/bin/bash
#
# Apprise API - View Logs Script
#
# This script provides easy access to Apprise API logs
# Usage: ./logs.sh [OPTIONS]
#
# Options:
#   -f, --follow        Follow logs in real-time (like tail -f)
#   -n, --lines NUM     Show last N lines (default: 50)
#   -e, --errors        Show only errors
#   -s, --since TIME    Show logs since (e.g., "1 hour ago", "10 minutes ago")
#   --systemd           Show systemd journal logs (if using systemd service)
#   --user              Show user systemd journal logs
#   --service NAME      Service/container to show (apprise-api or mailrise)
#   --mailrise          Shortcut for --service mailrise
#   --help              Show this help
#

set -euo pipefail

# Configuration
LINES=50
FOLLOW=false
ERRORS_ONLY=false
SINCE=""
USE_SYSTEMD=false
USE_USER_SYSTEMD=false
SERVICE_NAME="apprise-api"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

show_help() {
    cat <<EOF
Apprise API - View Logs

Usage: $0 [OPTIONS]

Options:
    -f, --follow        Follow logs in real-time (like tail -f)
    -n, --lines NUM     Show last N lines (default: 50)
    -e, --errors        Show only errors and warnings
    -s, --since TIME    Show logs since (e.g., "1 hour ago", "10 minutes ago")
    --systemd           Show systemd journal logs (if using systemd service)
    --user              Show user systemd journal logs
    --service NAME      Service/container to show (apprise-api or mailrise)
    --mailrise          Shortcut for --service mailrise
    --help              Show this help

Examples:
    # Real-time logs
    $0 --follow

    # Last 100 lines
    $0 -n 100

    # Errors only
    $0 -e

    # Logs from last 30 minutes
    $0 -s "30 minutes ago"

    # Systemd journal
    $0 --systemd

    # Mailrise container logs
    $0 --mailrise

    # Rootless user systemd Mailrise logs
    $0 --user --mailrise
EOF
}

validate_service_name() {
    case "$SERVICE_NAME" in
        apprise-api | mailrise) ;;
        *)
            echo "Error: unsupported service '$SERVICE_NAME'"
            echo "Supported services: apprise-api, mailrise"
            exit 1
            ;;
    esac
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f | --follow)
            FOLLOW=true
            shift
            ;;
        -n | --lines)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "Error: $1 requires a line count"
                show_help
                exit 1
            fi
            LINES="$2"
            shift 2
            ;;
        -e | --errors)
            ERRORS_ONLY=true
            shift
            ;;
        -s | --since)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "Error: $1 requires a time value"
                show_help
                exit 1
            fi
            SINCE="$2"
            shift 2
            ;;
        --systemd)
            USE_SYSTEMD=true
            shift
            ;;
        --user)
            USE_SYSTEMD=true
            USE_USER_SYSTEMD=true
            shift
            ;;
        --service)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "Error: --service requires a service name"
                show_help
                exit 1
            fi
            SERVICE_NAME="$2"
            shift 2
            ;;
        --mailrise)
            SERVICE_NAME="mailrise"
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

validate_service_name

# Check if container or systemd exists
if [[ "$USE_SYSTEMD" == true ]]; then
    if ! command -v journalctl &>/dev/null; then
        log_info "journalctl not found, falling back to podman logs"
        USE_SYSTEMD=false
    fi
fi

if [[ "$USE_SYSTEMD" == false ]]; then
    # Check if container exists
    if ! podman container exists "$SERVICE_NAME" 2>/dev/null; then
        echo "Error: Container '$SERVICE_NAME' not found"
        echo "Is $SERVICE_NAME running? Start it with:"
        echo "  podman start $SERVICE_NAME"
        echo "  or"
        echo "  systemctl start $SERVICE_NAME"
        exit 1
    fi
fi

echo -e "${BLUE}=== $SERVICE_NAME Logs ===${NC}"
echo ""

# Display logs using appropriate method
if [[ "$USE_SYSTEMD" == true ]]; then
    # Using systemd journal
    log_info "Showing systemd journal logs for $SERVICE_NAME"

    JOURNALCTL_ARGS=("-u" "$SERVICE_NAME")
    if [[ "$USE_USER_SYSTEMD" == true ]]; then
        JOURNALCTL_ARGS=("--user" "${JOURNALCTL_ARGS[@]}")
    fi

    if [[ "$FOLLOW" == true ]]; then
        JOURNALCTL_ARGS+=("-f")
    else
        JOURNALCTL_ARGS+=("-n" "$LINES")
    fi

    if [[ -n "$SINCE" ]]; then
        JOURNALCTL_ARGS+=("--since" "$SINCE")
    fi

    if [[ "$ERRORS_ONLY" == true ]]; then
        JOURNALCTL_ARGS+=("-p" "err")
    fi

    if [[ "$USE_USER_SYSTEMD" == true ]]; then
        journalctl "${JOURNALCTL_ARGS[@]}"
    else
        sudo journalctl "${JOURNALCTL_ARGS[@]}"
    fi
else
    # Using podman logs
    PODMAN_ARGS=()

    if [[ "$FOLLOW" == true ]]; then
        PODMAN_ARGS+=("-f")
    else
        PODMAN_ARGS+=("--tail" "$LINES")
    fi

    if [[ "$ERRORS_ONLY" == true ]]; then
        log_info "Filtering for errors..."
        podman logs "${PODMAN_ARGS[@]}" "$SERVICE_NAME" 2>&1 | grep -i "error\|exception\|fail\|traceback\|warning" || true
    else
        podman logs "${PODMAN_ARGS[@]}" "$SERVICE_NAME"
    fi
fi

echo ""
echo -e "${BLUE}=== End of Logs ===${NC}"
