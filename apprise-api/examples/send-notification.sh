#!/bin/bash
#
# Apprise API - Send Notification Example Script
#
# This script demonstrates how to send notifications via Apprise API
# Usage: ./send-notification.sh [KEY] [TITLE] [BODY] [TYPE]
#
# Examples:
#   ./send-notification.sh alerts "System Update" "Debian packages updated" info
#   ./send-notification.sh critical-alerts "Disk Full" "Root partition at 95%" failure
#   ./send-notification.sh all "Backup Complete" "Daily backup finished" success
#

set -euo pipefail

# Configuration
APPRISE_URL="${APPRISE_URL:-http://localhost:8000}"
APPRISE_KEY="${1:-apprise}"
APPRISE_TITLE="${2:-Notification}"
APPRISE_BODY="${3:-This is a test notification}"
APPRISE_TYPE="${4:-info}"

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate inputs
if [[ -z "$APPRISE_KEY" ]]; then
    log_error "Configuration key is required"
    echo "Usage: $0 KEY [TITLE] [BODY] [TYPE]"
    exit 1
fi

# Validate notification type
if ! [[ "$APPRISE_TYPE" =~ ^(info|success|warning|failure)$ ]]; then
    log_error "Invalid type: $APPRISE_TYPE (must be: info, success, warning, failure)"
    exit 1
fi

log_info "Sending notification..."
log_info "  URL: $APPRISE_URL"
log_info "  Configuration key: $APPRISE_KEY"
log_info "  Title: $APPRISE_TITLE"
log_info "  Body: $APPRISE_BODY"
log_info "  Type: $APPRISE_TYPE"

# Send notification
# Build JSON safely using jq to prevent injection from user-supplied strings
if command -v jq &> /dev/null; then
    PAYLOAD=$(jq -n \
        --arg title "$APPRISE_TITLE" \
        --arg body "$APPRISE_BODY" \
        --arg type "$APPRISE_TYPE" \
        '{title: $title, body: $body, type: $type}')
else
    log_error "jq is required but not installed. Install with: sudo apt-get install -y jq"
    exit 1
fi

RESPONSE=$(curl -s -X POST "$APPRISE_URL/notify/$APPRISE_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# Check response
if echo "$RESPONSE" | grep -q '"status":"ok"'; then
    log_info "Notification sent successfully!"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
else
    log_error "Failed to send notification"
    echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    exit 1
fi
