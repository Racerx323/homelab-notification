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
#   --production        Fresh-host rootful systemd install of Apprise API,
#                       Mailrise, and lifecycle artifacts; requires both digests
#   --production-config FILE
#                       Strict desired-state file for --production
#   --preflight-only    Validate --production inputs and fresh-host state only
#   --apprise-digest SHA256
#                       Exact reviewed Apprise platform digest for --production
#   --mailrise-digest SHA256
#                       Exact reviewed Mailrise platform digest for --production
#   --port PORT         Set API port (default: 8000)
#   --mailrise          Install and configure Mailrise SMTP relay
#   --mailrise-port PORT
#                       Set Mailrise SMTP port (default: 8025)
#   --mailrise-apprise-key KEY
#                       Set Apprise API config key for Mailrise (default: your_apprise_config_key)
#
# Environment overrides:
#   APPRISE_IMAGE       Container image (default: docker.io/caronc/apprise:latest)
#   MAILRISE_IMAGE      Container image (default: docker.io/yoryan/mailrise:latest)
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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

# Color output (ANSI escape codes)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m' # No Color

# Configuration
APPRISE_PORT="${APPRISE_PORT:-8000}"
APPRISE_CONTAINER_NAME="apprise-api"
APPRISE_IMAGE="${APPRISE_IMAGE:-docker.io/caronc/apprise:latest}"
APPRISE_REPOSITORY="docker.io/caronc/apprise"
APPRISE_DIGEST=""
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
MAILRISE_IMAGE="${MAILRISE_IMAGE:-docker.io/yoryan/mailrise:latest}"
MAILRISE_REPOSITORY="docker.io/yoryan/mailrise"
MAILRISE_DIGEST=""
MAILRISE_CONFIG_FILE="/etc/mailrise.conf"
MAILRISE_EXAMPLE_CONFIG_FILE=""
MAILRISE_PORT="${MAILRISE_PORT:-8025}"
MAILRISE_CONFIG_NAME="${MAILRISE_CONFIG_NAME:-notify}"
MAILRISE_APPRISE_CONFIG_KEY="${MAILRISE_APPRISE_CONFIG_KEY:-your_apprise_config_key}"
NOTIFY_NETWORK_NAME="notify-network"
ENABLE_SYSTEMD=false
ROOTLESS_MODE=false
ENABLE_MAILRISE=false
PRODUCTION_MODE=false
PRODUCTION_CONFIG_FILE=""
PRODUCTION_PREFLIGHT_ONLY=false
INSTALL_LIFECYCLE=false
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
PODMAN_GRAPH_ROOT=""
PODMAN_RUN_ROOT=""
LIFECYCLE_ARTIFACTS_INSTALLED=false
NETAVARK_LOCK_CREATED=false
PRODUCTION_SERVICES_ACTIVATED=false

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

cleanup_lifecycle_artifacts() {
    if [[ $LIFECYCLE_ARTIFACTS_INSTALLED != true ]]; then
        return 0
    fi

    rm -f -- \
        /usr/local/libexec/apprise-api/check-container-updates.sh \
        /usr/local/libexec/apprise-api/notify-container-updates.sh \
        /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
        /etc/apprise-container-update-check.conf \
        /etc/systemd/system/apprise-container-update-check.service \
        /etc/systemd/system/apprise-container-update-check.timer
    rmdir /usr/local/libexec/apprise-api 2>/dev/null || true
    if [[ $NETAVARK_LOCK_CREATED == true ]]; then
        rm -f -- /etc/containers/networks/netavark.lock
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

    if [[ $PRODUCTION_SERVICES_ACTIVATED == true ]]; then
        systemctl disable --now mailrise.service apprise-api.service || true
    fi

    if command -v podman &>/dev/null; then
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
    cleanup_lifecycle_artifacts
    reload_systemd_after_cleanup

    if [[ -n "$MAILRISE_CONFIG_TARGET_FILE" && $MAILRISE_CONFIG_TARGET_PREEXISTED == false && -f "$MAILRISE_CONFIG_TARGET_FILE" ]]; then
        rm -f "$MAILRISE_CONFIG_TARGET_FILE"
        log_info "Removed Mailrise config generated by this run: $MAILRISE_CONFIG_TARGET_FILE"
    fi

    if [[ $MAILRISE_CONFIG_DIR_CREATED == true ]]; then
        rmdir "$(dirname "$MAILRISE_CONFIG_FILE")" 2>/dev/null || true
    fi

    if [[ $NOTIFY_NETWORK_CREATED == true ]] && command -v podman &>/dev/null; then
        podman network rm "$NOTIFY_NETWORK_NAME" >/dev/null 2>&1 || true
        log_info "Removed Podman network created by this run: $NOTIFY_NETWORK_NAME"
    fi

    if [[ $PRODUCTION_MODE == true && $APPRISE_DATA_DIR_CREATED == true &&
        $APPRISE_DATA_DIR == /var/lib/apprise ]]; then
        rm -rf -- /var/lib/apprise
        log_info "Removed production data directory created by this failed run"
    elif [[ $APPRISE_DATA_DIR_CREATED == true ]]; then
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

validate_exact_digest() {
    local digest_value="$1"
    local digest_label="$2"

    [[ $digest_value =~ ^sha256:[0-9a-f]{64}$ ]] || {
        log_error "$digest_label must be sha256: followed by 64 lowercase hexadecimal characters"
        exit 1
    }
}

load_production_config() {
    local config_line
    local config_key
    local config_value
    local seen_apprise=false
    local seen_mailrise=false
    local seen_notification_key=false
    local seen_apprise_user=false
    local seen_timezone=false
    local seen_mailrise_config_name=false

    [[ -n $PRODUCTION_CONFIG_FILE ]] || return 0
    [[ $PRODUCTION_MODE == true ]] || {
        log_error "--production-config requires --production"
        exit 1
    }
    [[ -f $PRODUCTION_CONFIG_FILE && ! -L $PRODUCTION_CONFIG_FILE ]] || {
        log_error "Production config is missing or unsafe: $PRODUCTION_CONFIG_FILE"
        exit 1
    }

    while IFS= read -r config_line || [[ -n $config_line ]]; do
        [[ -z $config_line || $config_line == \#* ]] && continue
        [[ $config_line == *=* ]] || {
            log_error "Invalid production config line"
            exit 1
        }
        config_key="${config_line%%=*}"
        config_value="${config_line#*=}"
        [[ -n $config_value && $config_value != *[[:space:]]* ]] || {
            log_error "Invalid production config value: $config_key"
            exit 1
        }
        case "$config_key" in
            APPRISE_PLATFORM_DIGEST)
                [[ $seen_apprise == false && -z $APPRISE_DIGEST ]] || {
                    log_error "Duplicate Apprise production digest"
                    exit 1
                }
                APPRISE_DIGEST="$config_value"
                seen_apprise=true
                ;;
            MAILRISE_PLATFORM_DIGEST)
                [[ $seen_mailrise == false && -z $MAILRISE_DIGEST ]] || {
                    log_error "Duplicate Mailrise production digest"
                    exit 1
                }
                MAILRISE_DIGEST="$config_value"
                seen_mailrise=true
                ;;
            MAILRISE_APPRISE_CONFIG_KEY)
                [[ $seen_notification_key == false &&
                    $MAILRISE_APPRISE_CONFIG_KEY == your_apprise_config_key ]] || {
                    log_error "Duplicate Mailrise Apprise configuration key"
                    exit 1
                }
                MAILRISE_APPRISE_CONFIG_KEY="$config_value"
                seen_notification_key=true
                ;;
            APPRISE_USER)
                [[ $seen_apprise_user == false && -z $APPRISE_USER ]] || {
                    log_error "Duplicate Apprise production user"
                    exit 1
                }
                APPRISE_USER="$config_value"
                seen_apprise_user=true
                ;;
            TZ)
                [[ $seen_timezone == false && -z $TZ ]] || {
                    log_error "Duplicate production timezone"
                    exit 1
                }
                TZ="$config_value"
                seen_timezone=true
                ;;
            MAILRISE_CONFIG_NAME)
                [[ $seen_mailrise_config_name == false &&
                    $MAILRISE_CONFIG_NAME == notify ]] || {
                    log_error "Duplicate Mailrise production configuration name"
                    exit 1
                }
                MAILRISE_CONFIG_NAME="$config_value"
                seen_mailrise_config_name=true
                ;;
            *)
                log_error "Unsupported production config key: $config_key"
                exit 1
                ;;
        esac
    done <"$PRODUCTION_CONFIG_FILE"
}

configure_production_mode() {
    if [[ $PRODUCTION_MODE != true ]]; then
        if [[ -n $APPRISE_DIGEST || -n $MAILRISE_DIGEST ||
            $PRODUCTION_PREFLIGHT_ONLY == true ]]; then
            log_error "production digest and preflight options require --production"
            exit 1
        fi
        return 0
    fi

    if [[ $ROOTLESS_MODE == true ]]; then
        log_error "--production supports only the rootful systemd deployment"
        exit 1
    fi

    ENABLE_SYSTEMD=true
    ENABLE_MAILRISE=true
    INSTALL_LIFECYCLE=true
    validate_exact_digest "$APPRISE_DIGEST" "--apprise-digest"
    validate_exact_digest "$MAILRISE_DIGEST" "--mailrise-digest"

    [[ $APPRISE_IMAGE == docker.io/caronc/apprise:latest ]] || {
        log_error "--production requires APPRISE_IMAGE=docker.io/caronc/apprise:latest"
        exit 1
    }
    [[ $MAILRISE_IMAGE == docker.io/yoryan/mailrise:latest ]] || {
        log_error "--production requires MAILRISE_IMAGE=docker.io/yoryan/mailrise:latest"
        exit 1
    }
    [[ $APPRISE_PORT == 8000 && $MAILRISE_PORT == 8025 ]] || {
        log_error "--production requires the lifecycle-managed host ports 8000 and 8025"
        exit 1
    }
    [[ $APPRISE_STATEFUL_MODE == simple && $APPRISE_WORKER_COUNT == 1 ]] || {
        log_error "--production requires APPRISE_STATEFUL_MODE=simple and APPRISE_WORKER_COUNT=1"
        exit 1
    }
    [[ $APPRISE_ADMIN == y && $APPRISE_STORAGE_DIR == /config ]] || {
        log_error "--production requires APPRISE_ADMIN=y and APPRISE_STORAGE_DIR=/config"
        exit 1
    }
    [[ $APPRISE_STORAGE_MODE == auto && $APPRISE_INTERPRET_EMOJIS == yes ]] || {
        log_error "--production requires APPRISE_STORAGE_MODE=auto and APPRISE_INTERPRET_EMOJIS=yes"
        exit 1
    }
    [[ $MAILRISE_CONFIG_NAME =~ ^[A-Za-z0-9_-]+$ ]] || {
        log_error "--production requires a simple Mailrise configuration name"
        exit 1
    }
    [[ $MAILRISE_APPRISE_CONFIG_KEY =~ ^[A-Za-z0-9_-]+$ &&
        $MAILRISE_APPRISE_CONFIG_KEY != your_apprise_config_key ]] || {
        log_error "--production requires a non-placeholder --mailrise-apprise-key"
        exit 1
    }
    [[ -n $APPRISE_USER ]] || {
        log_error "--production requires an explicit APPRISE_USER in the production config or environment"
        exit 1
    }
    [[ -n $TZ ]] || {
        log_error "--production requires an explicit TZ in the production config or environment"
        exit 1
    }
}

validate_lifecycle_sources() {
    local lifecycle_source

    for lifecycle_source in \
        "$script_dir/scripts/check-container-updates.sh" \
        "$script_dir/scripts/notify-container-updates.sh" \
        "$script_dir/scripts/update-rootful-systemd-containers.sh" \
        "$script_dir/configs/container-update-check.conf.example" \
        "$script_dir/templates/apprise-container-update-check.service" \
        "$script_dir/templates/apprise-container-update-check.timer"; do
        [[ -f $lifecycle_source && ! -L $lifecycle_source ]] || {
            log_error "Missing or unsafe lifecycle source: $lifecycle_source"
            exit 1
        }
    done
}

validate_production_runtime_values() {
    [[ $PRODUCTION_MODE == true ]] || return 0

    [[ $APPRISE_USER =~ ^[0-9]+:[0-9]+$ ]] || {
        log_error "--production requires APPRISE_USER as numeric UID:GID"
        exit 1
    }
    [[ $TZ =~ ^[A-Za-z0-9_+./-]+$ && $TZ != *..* ]] || {
        log_error "--production resolved an unsafe timezone value"
        exit 1
    }
}

require_fresh_production_host() {
    local production_target

    [[ $PRODUCTION_MODE == true ]] || return 0

    for production_target in \
        /var/lib/apprise \
        /etc/mailrise.conf \
        /etc/mailrise.conf.example \
        /etc/systemd/system/apprise-api.service \
        /etc/systemd/system/mailrise.service \
        /etc/systemd/system/apprise-container-update-check.service \
        /etc/systemd/system/apprise-container-update-check.timer \
        /etc/apprise-container-update-check.conf \
        /usr/local/libexec/apprise-api/check-container-updates.sh \
        /usr/local/libexec/apprise-api/notify-container-updates.sh \
        /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh; do
        [[ ! -e $production_target && ! -L $production_target ]] || {
            log_error "--production is fresh-host-only; target already exists: $production_target"
            exit 1
        }
    done

    for production_target in "$APPRISE_CONTAINER_NAME" "$MAILRISE_CONTAINER_NAME"; do
        if podman container exists "$production_target" 2>/dev/null; then
            log_error "--production is fresh-host-only; container already exists: $production_target"
            exit 1
        fi
    done
    if podman network exists "$NOTIFY_NETWORK_NAME" 2>/dev/null; then
        log_error "--production is fresh-host-only; network already exists: $NOTIFY_NETWORK_NAME"
        exit 1
    fi
}

detect_os_timezone() {
    local detected_timezone=""
    local localtime_target=""

    if command -v timedatectl &>/dev/null; then
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
    if ! command -v podman &>/dev/null; then
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

configure_podman_storage_paths() {
    PODMAN_GRAPH_ROOT="$(podman info --format '{{.Store.GraphRoot}}')"
    PODMAN_RUN_ROOT="$(podman info --format '{{.Store.RunRoot}}')"

    if [[ -z $PODMAN_GRAPH_ROOT || -z $PODMAN_RUN_ROOT ]]; then
        log_error "Unable to determine Podman storage paths"
        exit 1
    fi

    log_info "Podman graph root: $PODMAN_GRAPH_ROOT"
    log_info "Podman run root: $PODMAN_RUN_ROOT"
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

    cat >"$target_config_file" <<EOF
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

pull_production_image() {
    local image_tag="$1"
    local image_repository="$2"
    local image_digest="$3"
    local image_label="$4"
    local image_reference="$image_repository@$image_digest"
    local host_architecture
    local image_architecture

    podman pull "$image_reference" || return 1
    host_architecture="$(podman info --format '{{.Host.Arch}}')"
    image_architecture="$(podman image inspect "$image_reference" --format '{{.Architecture}}')"
    [[ $image_architecture == "$host_architecture" ]] || {
        log_error "$image_label architecture $image_architecture does not match host $host_architecture"
        return 1
    }
    podman tag "$image_reference" "$image_tag"
    [[ $(podman image inspect "$image_reference" --format '{{.Id}}') == "$(podman image inspect "$image_tag" --format '{{.Id}}')" ]]
}

pull_apprise_image() {
    log_info "Pulling official Apprise API Docker image from Docker Hub..."
    log_info "Image: $APPRISE_IMAGE"

    # Pull the official caronc/apprise image (unauthenticated)
    if [[ $PRODUCTION_MODE == true ]]; then
        pull_production_image "$APPRISE_IMAGE" "$APPRISE_REPOSITORY" \
            "$APPRISE_DIGEST" "Apprise API"
    elif podman pull "$APPRISE_IMAGE"; then
        log_info "Successfully pulled: $APPRISE_IMAGE"
        return 0
    else
        log_error "Failed to pull Docker image: $APPRISE_IMAGE"
        log_info "Try manual pull for diagnostics:"
        log_info "  podman pull $APPRISE_IMAGE"
        return 1
    fi || return 1

    log_info "Successfully pinned $APPRISE_IMAGE to $APPRISE_DIGEST"
}

pull_mailrise_image() {
    log_info "Pulling Mailrise Docker image from Docker Hub..."
    log_info "Image: $MAILRISE_IMAGE"

    if [[ $PRODUCTION_MODE == true ]]; then
        pull_production_image "$MAILRISE_IMAGE" "$MAILRISE_REPOSITORY" \
            "$MAILRISE_DIGEST" "Mailrise"
    elif podman pull "$MAILRISE_IMAGE"; then
        log_info "Successfully pulled: $MAILRISE_IMAGE"
        return 0
    else
        log_error "Failed to pull Docker image: $MAILRISE_IMAGE"
        log_info "Try manual pull for diagnostics:"
        log_info "  podman pull $MAILRISE_IMAGE"
        return 1
    fi || return 1

    log_info "Successfully pinned $MAILRISE_IMAGE to $MAILRISE_DIGEST"
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
        cat <<EOF
[Unit]
Description=Apprise API Service
After=network-online.target
Wants=network-online.target
RequiresMountsFor=$PODMAN_GRAPH_ROOT $PODMAN_RUN_ROOT $APPRISE_DATA_DIR
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
NotifyAccess=all
Environment=PODMAN_SYSTEMD_UNIT=%n

Restart=always
RestartSec=10
TimeoutStopSec=70

# Track the exact container created by this unit and remove it after every stop.
ExecStartPre=/bin/rm -f %t/%n.ctr-id
ExecStart=/usr/bin/podman run \\
    --cidfile=%t/%n.ctr-id \\
    --cgroups=no-conmon \\
    --rm \\
    --sdnotify=conmon \\
    --replace \\
    --pull=never \\
    -d \\
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
        cat <<EOF
    --log-driver journald \\
    $APPRISE_IMAGE

ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile=%t/%n.ctr-id

[Install]
WantedBy=$wanted_by
EOF
    } >"$service_file"

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

    cat >"$service_file" <<EOF
[Unit]
Description=Mailrise SMTP notification relay
After=network-online.target apprise-api.service
Wants=network-online.target apprise-api.service
RequiresMountsFor=$PODMAN_GRAPH_ROOT $PODMAN_RUN_ROOT $(dirname "$MAILRISE_CONFIG_FILE")
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=notify
NotifyAccess=all
Environment=PODMAN_SYSTEMD_UNIT=%n

Restart=always
RestartSec=10
TimeoutStopSec=70

# Track the exact container created by this unit and remove it after every stop.
ExecStartPre=/bin/rm -f %t/%n.ctr-id
ExecStart=/usr/bin/podman run \\
    --cidfile=%t/%n.ctr-id \\
    --cgroups=no-conmon \\
    --rm \\
    --sdnotify=conmon \\
    --replace \\
    --pull=never \\
    -d \\
    --name $MAILRISE_CONTAINER_NAME \\
    -p $MAILRISE_PORT:8025 \\
    -v $MAILRISE_CONFIG_FILE:/etc/mailrise.conf:ro \\
    --network $NOTIFY_NETWORK_NAME \\
    --log-driver journald \\
    $MAILRISE_IMAGE

ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile=%t/%n.ctr-id

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

install_lifecycle_artifacts() {
    [[ $INSTALL_LIFECYCLE == true ]] || return 0
    validate_lifecycle_sources

    LIFECYCLE_ARTIFACTS_INSTALLED=true
    install -d -o root -g root -m 0755 /usr/local/libexec/apprise-api
    install -o root -g root -m 0755 \
        "$script_dir/scripts/check-container-updates.sh" \
        "$script_dir/scripts/notify-container-updates.sh" \
        "$script_dir/scripts/update-rootful-systemd-containers.sh" \
        /usr/local/libexec/apprise-api/
    awk -v config_key="$MAILRISE_APPRISE_CONFIG_KEY" '
        /^APPRISE_CONFIG_KEY=/ { print "APPRISE_CONFIG_KEY=" config_key; next }
        { print }
    ' "$script_dir/configs/container-update-check.conf.example" \
        >/etc/apprise-container-update-check.conf
    chown root:root /etc/apprise-container-update-check.conf
    chmod 0600 /etc/apprise-container-update-check.conf
    install -o root -g root -m 0644 \
        "$script_dir/templates/apprise-container-update-check.service" \
        "$script_dir/templates/apprise-container-update-check.timer" \
        /etc/systemd/system/
    install -d -o root -g root -m 0755 /etc/containers/networks
    if [[ ! -e /etc/containers/networks/netavark.lock ]]; then
        install -o root -g root -m 0644 /dev/null /etc/containers/networks/netavark.lock
        NETAVARK_LOCK_CREATED=true
    elif [[ -L /etc/containers/networks/netavark.lock ||
        ! -f /etc/containers/networks/netavark.lock ]]; then
        log_error "Unsafe Podman netavark lock path"
        exit 1
    fi

    systemd-analyze verify \
        /etc/systemd/system/apprise-api.service \
        /etc/systemd/system/mailrise.service \
        /etc/systemd/system/apprise-container-update-check.service \
        /etc/systemd/system/apprise-container-update-check.timer
    systemctl daemon-reload
    log_info "Installed lifecycle helpers and inactive weekly update-check timer"
}

wait_for_production_services() {
    local health_attempt

    for ((health_attempt = 1; health_attempt <= 30; health_attempt++)); do
        if systemctl is-active --quiet apprise-api.service mailrise.service &&
            [[ $(podman container inspect "$APPRISE_CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null) == running ]] &&
            [[ $(podman container inspect "$MAILRISE_CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null) == running ]] &&
            curl --silent --show-error --fail --max-time 5 \
                "http://127.0.0.1:$APPRISE_PORT/status" >/dev/null 2>&1 &&
            [[ -n $(podman port "$MAILRISE_CONTAINER_NAME" 8025/tcp 2>/dev/null) ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

verify_production_acceptance() {
    local actual_image_id
    local expected_environment
    local expected_image_id

    systemctl is-enabled --quiet apprise-api.service
    systemctl is-enabled --quiet mailrise.service
    if systemctl is-enabled --quiet apprise-container-update-check.timer; then
        log_error "Production update-check timer was enabled without authorization"
        return 1
    fi

    expected_image_id="$(podman image inspect "$APPRISE_IMAGE" --format '{{.Id}}')"
    actual_image_id="$(podman container inspect "$APPRISE_CONTAINER_NAME" --format '{{.Image}}')"
    [[ $actual_image_id == "$expected_image_id" ]] || {
        log_error "Running Apprise API image does not match the reviewed local tag"
        return 1
    }
    expected_image_id="$(podman image inspect "$MAILRISE_IMAGE" --format '{{.Id}}')"
    actual_image_id="$(podman container inspect "$MAILRISE_CONTAINER_NAME" --format '{{.Image}}')"
    [[ $actual_image_id == "$expected_image_id" ]] || {
        log_error "Running Mailrise image does not match the reviewed local tag"
        return 1
    }

    [[ $(podman container inspect "$APPRISE_CONTAINER_NAME" --format '{{.Config.User}}') == "$APPRISE_USER" ]] || {
        log_error "Running Apprise API user does not match production desired state"
        return 1
    }
    for expected_environment in \
        "APPRISE_STATEFUL_MODE=$APPRISE_STATEFUL_MODE" \
        "APPRISE_WORKER_COUNT=$APPRISE_WORKER_COUNT" \
        "APPRISE_ADMIN=$APPRISE_ADMIN" \
        "APPRISE_STORAGE_DIR=$APPRISE_STORAGE_DIR" \
        "APPRISE_STORAGE_MODE=$APPRISE_STORAGE_MODE" \
        "APPRISE_INTERPRET_EMOJIS=$APPRISE_INTERPRET_EMOJIS" \
        "TZ=$TZ"; do
        podman container inspect "$APPRISE_CONTAINER_NAME" |
            jq -e --arg expected "$expected_environment" \
                '.[0].Config.Env | index($expected) != null' >/dev/null || {
            log_error "Running Apprise API environment is missing: $expected_environment"
            return 1
        }
    done
}

activate_production_services() {
    [[ $PRODUCTION_MODE == true ]] || return 0

    PRODUCTION_SERVICES_ACTIVATED=true
    systemctl enable apprise-api.service mailrise.service
    systemctl start apprise-api.service
    systemctl start mailrise.service
    wait_for_production_services || {
        log_error "Production service acceptance failed"
        exit 1
    }
    verify_production_acceptance || exit 1
    log_info "Production application services are enabled and healthy"
    log_info "The update-check timer is installed but remains disabled"
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
        --pull=never \
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
        --pull=never \
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
            if curl -fsS "http://localhost:$APPRISE_PORT/status" >/dev/null 2>&1; then
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

show_direct_container_commands() {
    local command_prefix=''

    if [[ $ROOTLESS_MODE == false ]]; then
        command_prefix='sudo '
    fi

    cat <<EOF
View logs:
  ${command_prefix}podman logs -f $APPRISE_CONTAINER_NAME

Stop container:
  ${command_prefix}podman stop $APPRISE_CONTAINER_NAME

Start container:
  ${command_prefix}podman start $APPRISE_CONTAINER_NAME

Remove container:
  ${command_prefix}podman rm -f $APPRISE_CONTAINER_NAME
$(if [[ $ENABLE_MAILRISE == true ]]; then
        cat <<MAILRISE_COMMANDS

View Mailrise logs:
  ${command_prefix}podman logs -f $MAILRISE_CONTAINER_NAME

Stop Mailrise:
  ${command_prefix}podman stop $MAILRISE_CONTAINER_NAME

Start Mailrise:
  ${command_prefix}podman start $MAILRISE_CONTAINER_NAME
MAILRISE_COMMANDS
    fi)
EOF
}

show_info() {
    cat <<EOF

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
$(if [[ $PRODUCTION_MODE == true ]]; then
        cat <<PRODUCTION_SUMMARY
Production Profile: Enabled
Apprise Digest:     $APPRISE_DIGEST
Mailrise Digest:    $MAILRISE_DIGEST
Lifecycle Helpers:  /usr/local/libexec/apprise-api
Update Timer:       Installed, disabled
PRODUCTION_SUMMARY
    fi)
$(if [[ $ENABLE_MAILRISE == true ]]; then
        cat <<MAILRISE_SUMMARY
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

$(if [[ $ENABLE_SYSTEMD == true ]]; then
        if [[ $ROOTLESS_MODE == true ]]; then
            cat <<SYSTEMD_LOGS
View logs:
  journalctl --user -u apprise-api -f
$(if [[ $ENABLE_MAILRISE == true ]]; then echo "  journalctl --user -u mailrise -f"; fi)
SYSTEMD_LOGS
        else
            cat <<SYSTEMD_LOGS
View logs:
  sudo journalctl -u apprise-api -f
$(if [[ $ENABLE_MAILRISE == true ]]; then echo "  sudo journalctl -u mailrise -f"; fi)
SYSTEMD_LOGS
        fi
    else
        show_direct_container_commands
    fi)

Access API:
  http://localhost:$APPRISE_PORT
  
Configuration Interface:
  http://localhost:$APPRISE_PORT/

$(if [[ $ROOTLESS_MODE == true ]]; then
        cat <<ROOTLESS
${GREEN}Rootless Mode Notes:${NC}

- Container runs as your user ($(whoami))
- No system-wide access needed
- Data stored in: $HOME/.apprise
- Use 'podman' commands directly (no sudo needed for user containers)

$(if [[ $ENABLE_SYSTEMD == true ]]; then
            cat <<ROOTLESS_SYSTEMD
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
                cat <<ROOTLESS_MAILRISE_SYSTEMD

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
        if [[ $ENABLE_SYSTEMD == true ]]; then
            cat <<ROOTFUL
${GREEN}Systemd Management:${NC}

Enable auto-start:
  sudo systemctl enable apprise-api

Start service:
  sudo systemctl start apprise-api

Stop service:
  sudo systemctl stop apprise-api

View service logs:
  sudo journalctl -u apprise-api -f
$(if [[ $ENABLE_MAILRISE == true ]]; then
                cat <<ROOTFUL_MAILRISE_SYSTEMD

Enable Mailrise auto-start:
  sudo systemctl enable mailrise

Start Mailrise service:
  sudo systemctl start mailrise

View Mailrise service logs:
  sudo journalctl -u mailrise -f
ROOTFUL_MAILRISE_SYSTEMD
            fi)
ROOTFUL
        fi
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
        --production)
            PRODUCTION_MODE=true
            shift
            ;;
        --production-config)
            if [[ $# -lt 2 || -z $2 ]]; then
                log_error "--production-config requires a file"
                exit 1
            fi
            PRODUCTION_CONFIG_FILE="$2"
            shift 2
            ;;
        --preflight-only)
            PRODUCTION_PREFLIGHT_ONLY=true
            shift
            ;;
        --apprise-digest)
            if [[ $# -lt 2 || -z $2 ]]; then
                log_error "--apprise-digest requires a digest"
                exit 1
            fi
            APPRISE_DIGEST="$2"
            shift 2
            ;;
        --mailrise-digest)
            if [[ $# -lt 2 || -z $2 ]]; then
                log_error "--mailrise-digest requires a digest"
                exit 1
            fi
            MAILRISE_DIGEST="$2"
            shift 2
            ;;
        --port)
            if [[ $# -lt 2 ]]; then
                log_error "--port requires a port number"
                exit 1
            fi
            if [[ ! "$2" =~ ^[0-9]+$ ]] || (($2 < 1 || $2 > 65535)); then
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
            if [[ ! "$2" =~ ^[0-9]+$ ]] || (($2 < 1 || $2 > 65535)); then
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
    load_production_config
    configure_production_mode
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
    validate_production_runtime_values
    require_fresh_production_host
    if [[ $PRODUCTION_MODE == true ]]; then
        validate_lifecycle_sources
        if [[ $PRODUCTION_PREFLIGHT_ONLY == true ]]; then
            printf 'PREFLIGHT_OK: production_config=%s apprise_digest=%s mailrise_digest=%s timer=disabled\n' \
                "${PRODUCTION_CONFIG_FILE:-command-line}" "$APPRISE_DIGEST" "$MAILRISE_DIGEST"
            return 0
        fi
    fi

    # Only install system dependencies if not rootless
    if [[ $ROOTLESS_MODE == false ]]; then
        install_dependencies
    else
        log_info "Rootless mode: skipping system dependency installation"
        log_info "Ensure podman and ca-certificates are installed"
    fi
    check_podman
    configure_podman_storage_paths
    require_fresh_production_host

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
        install_lifecycle_artifacts
        activate_production_services
        log_info "Systemd service created. Enable and start with:"
        if [[ $PRODUCTION_MODE == true ]]; then
            log_info "  application services already enabled and started"
            log_info "  review, then separately enable apprise-container-update-check.timer"
        elif [[ $ROOTLESS_MODE == true ]]; then
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
