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
APPRISE_DATA_DIR="/var/lib/apprise"
BACKUP_DIR="${1:-.}"
BACKUP_FILENAME="apprise-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILENAME"

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

# Validate apprise data directory exists
if [[ ! -d "$APPRISE_DATA_DIR" ]]; then
    log_error "Apprise data directory not found: $APPRISE_DATA_DIR"
    exit 1
fi

# Create backup directory if needed
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_warn "Creating backup directory: $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
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

# Create backup
if sudo tar czf "$BACKUP_PATH" -C / var/lib/apprise; then
    # Fix permissions if using sudo
    sudo chown $USER:$USER "$BACKUP_PATH" 2>/dev/null || true
    
    # Get file size
    SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
    
    log_info "Backup created successfully!"
    log_info "File: $BACKUP_FILENAME"
    log_info "Size: $SIZE"
    log_info "Path: $BACKUP_PATH"
    
    # Create checksum for integrity verification
    (cd "$BACKUP_DIR" && sha256sum "$BACKUP_FILENAME" > "$BACKUP_FILENAME.sha256")
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
