#!/bin/bash
#
# Apprise API - Health Check Script
#
# This script checks the health and status of Apprise API
# Usage: ./health-check.sh [OPTIONS]
#
# Options:
#   --verbose           Show detailed information
#   --monitor           Monitor status continuously
#   --help              Show this help
#

set -euo pipefail

# Configuration
APPRISE_URL="${APPRISE_URL:-http://localhost:8000}"
VERBOSE=false
MONITOR=false

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    cat << EOF
Apprise API - Health Check

Usage: $0 [OPTIONS]

Options:
    --verbose           Show detailed information
    --monitor           Monitor status continuously (updates every 10s)
    --help              Show this help

Examples:
    # Basic health check
    $0

    # Verbose output
    $0 --verbose

    # Continuous monitoring
    $0 --monitor
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        -h|--help)
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

# Health check function
run_health_check() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$MONITOR" != true ]]; then
        echo -e "${BLUE}=== Apprise API Health Check ===${NC}"
        echo "Time: $timestamp"
        echo "URL: $APPRISE_URL"
        echo ""
    fi
    
    local all_ok=true
    
    # Check 1: Container Status
    echo -n "Container Status: "
    if podman container exists apprise-api 2>/dev/null; then
        local status=$(podman container inspect apprise-api --format='{{.State.Status}}' 2>/dev/null)
        if [[ "$status" == "running" ]]; then
            log_info "Running"
        else
            log_error "Not running ($status)"
            all_ok=false
        fi
    else
        log_error "Container not found"
        all_ok=false
    fi
    
    # Check 2: API Connectivity
    echo -n "API Connectivity: "
    if curl -s -m 5 "$APPRISE_URL" > /dev/null 2>&1; then
        log_info "OK"
    else
        log_error "Cannot reach API"
        all_ok=false
    fi
    
    # Check 3: API Response
    echo -n "API Response Time: "
    local response_time=$(curl -s -m 10 -w "%{time_total}" -o /dev/null "$APPRISE_URL" 2>/dev/null)
    if [[ -n "$response_time" ]]; then
        response_time_ms=$(echo "$response_time * 1000" | bc)
        if (( $(echo "$response_time < 1" | bc -l) )); then
            log_info "${response_time_ms}ms"
        else
            log_warn "${response_time_ms}ms (slow)"
        fi
    else
        log_error "No response"
        all_ok=false
    fi
    
    # Check 4: Notification Endpoints
    echo -n "Notification Endpoint: "
    if curl -s -m 5 "$APPRISE_URL/notify" > /dev/null 2>&1; then
        log_info "OK"
    else
        log_error "Not responding"
        all_ok=false
    fi
    
    # Check 5: Storage
    echo -n "Storage: "
    if [[ -d /var/lib/apprise ]]; then
        local available=$(df /var/lib/apprise | tail -1 | awk '{print $4}')
        if [[ $available -gt 104857600 ]]; then  # > 100MB free
            log_info "OK ($(df -h /var/lib/apprise | tail -1 | awk '{print $4}') free)"
        else
            log_warn "Low space ($(df -h /var/lib/apprise | tail -1 | awk '{print $4}') free)"
        fi
    else
        log_error "Storage not found"
        all_ok=false
    fi
    
    # Check 6: Resource Usage
    echo -n "Memory Usage: "
    if podman container exists apprise-api 2>/dev/null; then
        local mem=$(podman stats apprise-api --no-stream --format="{{.MemUsage}}" 2>/dev/null)
        if [[ -n "$mem" ]]; then
            log_info "$mem"
        else
            log_warn "Unable to determine"
        fi
    fi
    
    # Check 7: Systemd Service (if enabled)
    if systemctl is-enabled apprise-api 2>/dev/null; then
        echo -n "Systemd Service: "
        if systemctl is-active apprise-api > /dev/null 2>&1; then
            log_info "Active"
        else
            log_error "Inactive"
            all_ok=false
        fi
    fi
    
    # Detailed Information
    if [[ "$VERBOSE" == true ]]; then
        echo ""
        echo -e "${BLUE}=== Detailed Information ===${NC}"
        
        # Container details
        if podman container exists apprise-api 2>/dev/null; then
            echo ""
            echo -e "${BLUE}Container Details:${NC}"
            podman inspect apprise-api --format='
  ID: {{.ID}}
  Created: {{.Created}}
  Status: {{.State.Status}}
  Restart Count: {{.RestartCount}}' 2>/dev/null || true
        fi
        
        # API endpoints
        echo ""
        echo -e "${BLUE}Available Endpoints:${NC}"
        local endpoints=$(curl -s "$APPRISE_URL/docs" 2>/dev/null | grep -oP '"path":"[^"]+' | cut -d'"' -f4 | sort -u | head -10)
        if [[ -n "$endpoints" ]]; then
            echo "$endpoints" | sed 's/^/  /'
        else
            echo "  Unable to retrieve endpoints"
        fi
        
        # Configuration count
        echo ""
        echo -e "${BLUE}Configuration Summary:${NC}"
        if curl -s "$APPRISE_URL/urls" > /dev/null 2>&1; then
            local count=$(curl -s "$APPRISE_URL/urls" | jq -r '. | keys | length' 2>/dev/null || echo "unknown")
            echo "  Configured Tags/URLs: $count"
        fi
    fi
    
    echo ""
    if [[ "$all_ok" == true ]]; then
        log_info "All checks passed!"
    else
        log_error "Some checks failed!"
    fi
    
    return $([ "$all_ok" = true ] && echo 0 || echo 1)
}

# Main execution
if [[ "$MONITOR" == true ]]; then
    echo -e "${BLUE}=== Apprise API Health Monitor ===${NC}"
    echo "Monitoring Apprise API status (updates every 10 seconds, Ctrl+C to stop)"
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}=== Apprise API Health Monitor ===${NC}"
        echo "Last check: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        run_health_check || true
        
        sleep 10
    done
else
    run_health_check
fi
