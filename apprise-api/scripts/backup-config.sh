#!/bin/bash
#
# Apprise API - Backup Configuration Script
#
# This script backs up Apprise API configuration and persistent data
# Usage: ./backup-config.sh [BACKUP_DIR]
#
# Examples:
#   ./backup-config.sh
#   ./backup-config.sh /mnt/backups
#

set -euo pipefail

# Configuration
BACKUP_DIR="${1:-.}"
BACKUP_FILENAME="apprise-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILENAME"
APPRISE_DATA_DIR="${APPRISE_DATA_DIR:-}"
MAILRISE_CONFIG_FILE="${MAILRISE_CONFIG_FILE:-}"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_apprise_data_dir() {
    if [[ -n "$APPRISE_DATA_DIR" ]]; then
        return 0
    fi

    if [[ -d /var/lib/apprise ]]; then
        APPRISE_DATA_DIR="/var/lib/apprise"
    elif [[ -d "$HOME/.apprise" ]]; then
        APPRISE_DATA_DIR="$HOME/.apprise"
    else
        APPRISE_DATA_DIR="/var/lib/apprise"
    fi
}

detect_mailrise_config_file() {
    if [[ -n "$MAILRISE_CONFIG_FILE" ]]; then
        return 0
    fi

    if [[ -f /etc/mailrise.conf ]]; then
        MAILRISE_CONFIG_FILE="/etc/mailrise.conf"
    elif [[ -f "$HOME/.config/mailrise/mailrise.conf" ]]; then
        MAILRISE_CONFIG_FILE="$HOME/.config/mailrise/mailrise.conf"
    fi
}

add_backup_path() {
    local path="$1"
    local -n paths_ref="$2"

    if [[ -e "$path" ]]; then
        paths_ref+=("$path")
        log_info "Including: $path"
    fi
}

detect_apprise_data_dir
detect_mailrise_config_file

# Validate apprise data directory exists
if [[ ! -d "$APPRISE_DATA_DIR" ]]; then
    log_error "Apprise data directory not found: $APPRISE_DATA_DIR"
    log_info "Set APPRISE_DATA_DIR to the correct path if using a custom location."
    exit 1
fi

# Create backup directory if needed
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_warn "Creating backup directory: $BACKUP_DIR"
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        sudo install -d -m 0755 -o "$(id -u)" -g "$(id -g)" "$BACKUP_DIR"
    fi
fi

# Verify write permissions
if [[ ! -w "$BACKUP_DIR" ]]; then
    log_error "No write permissions to backup directory: $BACKUP_DIR"
    log_info "Try running with sudo"
    exit 1
fi

log_info "Starting backup..."
log_info "Source: $APPRISE_DATA_DIR"
log_info "Destination: $BACKUP_PATH"

BACKUP_PATHS=()
add_backup_path "$APPRISE_DATA_DIR" BACKUP_PATHS
add_backup_path "$MAILRISE_CONFIG_FILE" BACKUP_PATHS

if [[ -n "$MAILRISE_CONFIG_FILE" ]]; then
    mailrise_example_file="$(dirname "$MAILRISE_CONFIG_FILE")/mailrise.conf.example"
    add_backup_path "$mailrise_example_file" BACKUP_PATHS
fi

# Create backup. Use the current user when possible and fall back to sudo only
# when the selected rootful paths are not readable.
if tar czf "$BACKUP_PATH" "${BACKUP_PATHS[@]}" 2>/dev/null ||
    sudo tar czf "$BACKUP_PATH" "${BACKUP_PATHS[@]}"; then
    # Fix permissions if the sudo fallback created the archive.
    sudo chown "$(id -u):$(id -g)" "$BACKUP_PATH" 2>/dev/null || true

    # Get file size
    SIZE=$(du -h "$BACKUP_PATH" | cut -f1)

    log_info "Backup created successfully!"
    log_info "File: $BACKUP_FILENAME"
    log_info "Size: $SIZE"
    log_info "Path: $BACKUP_PATH"

    # Create checksum for integrity verification
    (cd "$BACKUP_DIR" && sha256sum "$BACKUP_FILENAME" >"$BACKUP_FILENAME.sha256")
    log_info "Checksum: $BACKUP_FILENAME.sha256"

    # Retention information
    log_info ""
    log_info "Backup retention recommendations:"
    log_info "  - Keep daily backups for 7 days"
    log_info "  - Keep weekly backups for 1 month"
    log_info "  - Keep monthly backups for 1 year"
    log_info ""
    log_info "Clean up old backups:"
    log_info "  find $BACKUP_DIR -name 'apprise-backup-*.tar.gz' -mtime +30 -delete"
else
    log_error "Backup failed"
    exit 1
fi

# Optional: Upload to remote storage
log_info ""
log_info "To upload to remote storage:"
log_info "  scp $BACKUP_PATH user@backup-server:/backups/"
log_info "  aws s3 cp $BACKUP_PATH s3://my-backup-bucket/"
log_info "  rsync -avz $BACKUP_PATH backup-server:/backups/"
