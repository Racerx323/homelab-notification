#!/bin/bash

set -Eeuo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly test_dir
readonly installer="$test_dir/../install-apprise-podman.sh"
readonly production_config="$test_dir/../configs/svmf-production.env"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

function_body() {
    local function_name="$1"

    awk -v signature="$function_name() {" '
        $0 == signature { in_function = 1 }
        in_function { print }
        in_function && /^}$/ { exit }
    ' "$installer"
}

assert_contains() {
    local content="$1"
    local expected="$2"
    local label="$3"

    [[ $content == *"$expected"* ]] || fail "$label missing: $expected"
}

assert_not_contains() {
    local content="$1"
    local rejected="$2"
    local label="$3"

    [[ $content != *"$rejected"* ]] || fail "$label contains: $rejected"
}

assert_before() {
    local content="$1"
    local first="$2"
    local second="$3"
    local label="$4"

    [[ $content == *"$first"*"$second"* ]] ||
        fail "$label does not place '$first' before '$second'"
}

check_service_generator() {
    local function_name="$1"
    local label="$2"
    local body

    body="$(function_body "$function_name")"
    [[ -n $body ]] || fail "$label generator not found"

    assert_contains "$body" 'Type=notify' "$label"
    assert_contains "$body" 'NotifyAccess=all' "$label"
    assert_contains "$body" 'Environment=PODMAN_SYSTEMD_UNIT=%n' "$label"
    assert_contains "$body" "RequiresMountsFor=\$PODMAN_GRAPH_ROOT \$PODMAN_RUN_ROOT" "$label"
    assert_contains "$body" 'TimeoutStopSec=70' "$label"
    assert_contains "$body" 'ExecStartPre=/bin/rm -f %t/%n.ctr-id' "$label"
    assert_contains "$body" '--cidfile=%t/%n.ctr-id' "$label"
    assert_contains "$body" '--cgroups=no-conmon' "$label"
    assert_contains "$body" '--rm' "$label"
    assert_contains "$body" '--sdnotify=conmon' "$label"
    assert_contains "$body" '--replace' "$label"
    assert_contains "$body" '--pull=never' "$label"
    assert_contains "$body" '    -d ' "$label"
    assert_contains "$body" 'ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id -t 10' "$label"
    assert_contains "$body" 'ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile=%t/%n.ctr-id' "$label"
    assert_not_contains "$body" 'KillMode=none' "$label"
}

check_service_generator create_systemd_service 'Apprise API service'
check_service_generator create_mailrise_systemd_service 'Mailrise service'

production_mode_body="$(function_body configure_production_mode)"
production_config_body="$(function_body load_production_config)"
fresh_host_body="$(function_body require_fresh_production_host)"
production_pull_body="$(function_body pull_production_image)"
lifecycle_install_body="$(function_body install_lifecycle_artifacts)"
production_activation_body="$(function_body activate_production_services)"
production_acceptance_body="$(function_body verify_production_acceptance)"
direct_commands_body="$(function_body show_direct_container_commands)"
show_info_body="$(function_body show_info)"
cleanup_body="$(function_body cleanup_on_exit)"
main_body="$(function_body main)"

assert_contains "$production_mode_body" 'ENABLE_SYSTEMD=true' 'production mode'
assert_contains "$production_mode_body" 'ENABLE_MAILRISE=true' 'production mode'
assert_contains "$production_mode_body" 'INSTALL_LIFECYCLE=true' 'production mode'
assert_contains "$production_mode_body" "validate_exact_digest \"\$APPRISE_DIGEST\"" 'production mode'
assert_contains "$production_mode_body" "validate_exact_digest \"\$MAILRISE_DIGEST\"" 'production mode'
assert_contains "$production_mode_body" 'your_apprise_config_key' 'production mode'
assert_contains "$production_mode_body" '--production requires an explicit APPRISE_USER' 'production mode'
assert_contains "$production_mode_body" '--production requires an explicit TZ' 'production mode'
assert_contains "$production_config_body" 'APPRISE_PLATFORM_DIGEST)' 'production config parser'
assert_contains "$production_config_body" 'MAILRISE_PLATFORM_DIGEST)' 'production config parser'
assert_contains "$production_config_body" 'MAILRISE_APPRISE_CONFIG_KEY)' 'production config parser'
assert_contains "$production_config_body" 'APPRISE_USER)' 'production config parser'
assert_contains "$production_config_body" 'TZ)' 'production config parser'
assert_contains "$production_config_body" 'MAILRISE_CONFIG_NAME)' 'production config parser'
assert_contains "$production_config_body" 'Unsupported production config key' 'production config parser'
assert_not_contains "$production_config_body" 'source ' 'production config parser'
assert_contains "$fresh_host_body" '--production is fresh-host-only' 'fresh-host preflight'
assert_contains "$fresh_host_body" '/var/lib/apprise' 'fresh-host preflight'
assert_contains "$fresh_host_body" '/etc/mailrise.conf' 'fresh-host preflight'
assert_contains "$fresh_host_body" 'update-rootful-systemd-containers.sh' 'fresh-host preflight'
assert_contains "$production_pull_body" "podman pull \"\$image_reference\"" 'production image pull'
assert_contains "$production_pull_body" "podman info --format '{{.Host.Arch}}'" 'production image pull'
assert_contains "$production_pull_body" "--format '{{.Architecture}}'" 'production image pull'
assert_contains "$production_pull_body" \
    "podman tag \"\$image_reference\" \"\$image_tag\"" 'production image pull'
assert_contains "$lifecycle_install_body" '/usr/local/libexec/apprise-api' 'lifecycle installer'
assert_contains "$lifecycle_install_body" '/etc/apprise-container-update-check.conf' 'lifecycle installer'
assert_contains "$lifecycle_install_body" "config_key=\"\$MAILRISE_APPRISE_CONFIG_KEY\"" 'lifecycle installer'
assert_contains "$lifecycle_install_body" 'apprise-container-update-check.timer' 'lifecycle installer'
assert_contains "$lifecycle_install_body" '/etc/containers/networks/netavark.lock' 'lifecycle installer'
assert_contains "$production_activation_body" 'systemctl enable apprise-api.service mailrise.service' 'production activation'
assert_not_contains "$production_activation_body" 'enable apprise-container-update-check.timer' 'production activation'
assert_contains "$production_activation_body" 'verify_production_acceptance' 'production activation'
assert_contains "$production_acceptance_body" 'systemctl is-enabled --quiet apprise-api.service' 'production acceptance'
assert_contains "$production_acceptance_body" 'systemctl is-enabled --quiet mailrise.service' 'production acceptance'
assert_contains "$production_acceptance_body" 'apprise-container-update-check.timer' 'production acceptance'
assert_contains "$production_acceptance_body" "--format '{{.Image}}'" 'production acceptance'
assert_contains "$production_acceptance_body" "--format '{{.Config.User}}'" 'production acceptance'
assert_contains "$production_acceptance_body" 'APPRISE_STATEFUL_MODE=' 'production acceptance'
assert_contains "$production_acceptance_body" 'TZ=' 'production acceptance'
assert_contains "$direct_commands_body" 'podman stop' 'direct-container command summary'
assert_contains "$show_info_body" 'show_direct_container_commands' 'installer command summary'
assert_not_contains "$show_info_body" 'podman stop' 'systemd-aware command summary'
assert_contains "$show_info_body" 'sudo systemctl stop apprise-api' 'rootful systemd command summary'
assert_contains "$cleanup_body" "\$APPRISE_DATA_DIR == /var/lib/apprise" 'production failure cleanup'
assert_contains "$cleanup_body" 'rm -rf -- /var/lib/apprise' 'production failure cleanup'
assert_contains "$main_body" 'PREFLIGHT_OK:' 'production preflight'
assert_before "$main_body" 'PREFLIGHT_OK:' 'install_dependencies' 'production preflight mutation boundary'

help_text="$("$installer" --help)"
assert_contains "$help_text" '--production' 'installer help'
assert_contains "$help_text" '--production-config FILE' 'installer help'
assert_contains "$help_text" '--preflight-only' 'installer help'
assert_contains "$help_text" '--apprise-digest SHA256' 'installer help'
assert_contains "$help_text" '--mailrise-digest SHA256' 'installer help'

invalid_mode_output=''
if invalid_mode_output="$("$installer" --rootless --production 2>&1)"; then
    fail 'rootless production mode unexpectedly succeeded'
fi
assert_contains "$invalid_mode_output" '--production supports only the rootful systemd deployment' \
    'rootless production rejection'

invalid_mode_output=''
if invalid_mode_output="$("$installer" --rootless --production \
    --production-config "$production_config" 2>&1)"; then
    fail 'rootless production config mode unexpectedly succeeded'
fi
assert_contains "$invalid_mode_output" '--production supports only the rootful systemd deployment' \
    'production config parsing and rootless rejection'

printf 'PASS: generated Podman systemd lifecycle contract\n'
