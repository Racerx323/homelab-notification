#!/bin/bash

set -Eeuo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly test_dir
readonly installer="$test_dir/../install-apprise-podman.sh"

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
    assert_contains "$body" '    -d ' "$label"
    assert_contains "$body" 'ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id -t 10' "$label"
    assert_contains "$body" 'ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile=%t/%n.ctr-id' "$label"
    assert_not_contains "$body" 'KillMode=none' "$label"
}

check_service_generator create_systemd_service 'Apprise API service'
check_service_generator create_mailrise_systemd_service 'Mailrise service'

printf 'PASS: generated Podman systemd lifecycle contract\n'
