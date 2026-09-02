#!/bin/bash

set -Eeuo pipefail
umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly checker="$script_dir/check-container-updates.sh"
readonly state_schema='apprise-container-update-state/v1'
readonly default_state_directory='/var/lib/apprise-container-lifecycle'
readonly default_apprise_base_url='http://127.0.0.1:8000'
readonly default_apprise_config_key='apprise'
readonly max_message_bytes=12000

state_directory="${CONTAINER_UPDATE_STATE_DIRECTORY:-$default_state_directory}"
apprise_base_url="${APPRISE_BASE_URL:-$default_apprise_base_url}"
apprise_config_key="${APPRISE_CONFIG_KEY:-$default_apprise_config_key}"
retry_attempts="${CONTAINER_UPDATE_RETRY_ATTEMPTS:-4}"
retry_delay_seconds="${CONTAINER_UPDATE_RETRY_DELAY_SECONDS:-900}"
reminder_seconds="${CONTAINER_UPDATE_REMINDER_SECONDS:-518400}"
dry_run=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: notify-container-updates.sh [--dry-run]

Evaluate the rootful Apprise API and Mailrise images. Normal mode records
bounded state and sends only required notifications. --dry-run performs the
comparison and prints the decision without changing state or contacting
Apprise API.
USAGE
}

while (($# > 0)); do
    case "$1" in
        --dry-run)
            dry_run=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown argument: $1"
            ;;
    esac
done

[[ $EUID -eq 0 || $state_directory != "$default_state_directory" ]] ||
    fail 'must run as root for the rootful production check'
[[ -x $checker && ! -L $checker ]] || fail "missing or unsafe comparator: $checker"
[[ $state_directory == /* && $state_directory != / && $state_directory != *$'\n'* ]] ||
    fail 'state directory must be a safe absolute path'
[[ $apprise_base_url == "$default_apprise_base_url" ]] ||
    fail "APPRISE_BASE_URL must be $default_apprise_base_url"
[[ $apprise_config_key =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] ||
    fail 'APPRISE_CONFIG_KEY is invalid'
[[ $retry_attempts =~ ^[1-4]$ ]] || fail 'retry attempts must be between 1 and 4'
[[ $retry_delay_seconds =~ ^[0-9]+$ && $retry_delay_seconds -le 3600 ]] ||
    fail 'retry delay must be between 0 and 3600 seconds'
[[ $reminder_seconds =~ ^[0-9]+$ && $reminder_seconds -ge 3600 ]] ||
    fail 'reminder interval must be at least 3600 seconds'

for required_command in awk chmod curl date hostname install jq mktemp mv sha256sum sleep sort; do
    command -v "$required_command" >/dev/null || fail "required command not found: $required_command"
done

state_file="$state_directory/state.json"
readonly state_file
prior_status='unknown'
prior_digest_signature=''
prior_notification_epoch=0

read_state() {
    [[ -e $state_file || -L $state_file ]] || return 0
    [[ -f $state_file && ! -L $state_file ]] || fail 'state file is not a safe regular file'
    jq -e --arg schema "$state_schema" '
        type == "object" and
        .schema == $schema and
        (.status | type == "string" and test("^(current|pending|failure)$")) and
        (.digest_signature | type == "string" and test("^$|^sha256:[0-9a-f]{64}$")) and
        (.notification_epoch | type == "number" and floor == . and . >= 0)
    ' "$state_file" >/dev/null || fail 'state file failed schema validation'
    prior_status="$(jq -r '.status' "$state_file")"
    prior_digest_signature="$(jq -r '.digest_signature' "$state_file")"
    prior_notification_epoch="$(jq -r '.notification_epoch' "$state_file")"
}

write_state() {
    local observed_status="$1"
    local observed_digest_signature="$2"
    local notification_epoch="$3"
    local temporary_state

    install -d -m 0700 -- "$state_directory"
    [[ ! -L $state_directory ]] || fail 'state directory must not be a symlink'
    temporary_state="$(mktemp "$state_directory/.state.json.XXXXXX")"
    jq -n \
        --arg schema "$state_schema" \
        --arg status "$observed_status" \
        --arg digest_signature "$observed_digest_signature" \
        --argjson notification_epoch "$notification_epoch" \
        '{schema: $schema, status: $status, digest_signature: $digest_signature,
          notification_epoch: $notification_epoch}' >"$temporary_state"
    chmod 0600 -- "$temporary_state"
    mv -- "$temporary_state" "$state_file"
}

send_notification() {
    local notification_type="$1"
    local notification_title="$2"
    local notification_body="$3"
    local notification_payload
    local delivery_attempt
    local http_status

    ((${#notification_title} + ${#notification_body} <= max_message_bytes)) ||
        fail 'notification content exceeds the configured bound'
    notification_payload="$(jq -cn \
        --arg title "$notification_title" \
        --arg body "$notification_body" \
        --arg type "$notification_type" \
        '{title: $title, body: $body, type: $type}')"

    for ((delivery_attempt = 1; delivery_attempt <= retry_attempts; delivery_attempt++)); do
        http_status="$(curl --silent --show-error \
            --connect-timeout 5 --max-time 15 \
            --output /dev/null --write-out '%{http_code}' \
            --request POST \
            --header 'Content-Type: application/json' \
            --data-binary "$notification_payload" \
            "$apprise_base_url/notify/$apprise_config_key")" || http_status='transport-error'
        if [[ $http_status == 200 ]]; then
            printf 'NOTIFICATION_DELIVERED: type=%s attempt=%s\n' "$notification_type" "$delivery_attempt"
            return 0
        fi
        printf 'NOTIFICATION_RETRY: type=%s attempt=%s result=%s\n' \
            "$notification_type" "$delivery_attempt" "$http_status" >&2
        if ((delivery_attempt < retry_attempts)); then
            sleep "$retry_delay_seconds"
        fi
    done
    return 1
}

comparison_output=''
comparison_status=0
comparison_output="$($checker)" || comparison_status=$?
current_epoch="$(date +%s)"
readonly current_epoch
host_name="$(hostname --fqdn 2>/dev/null || hostname)"
readonly host_name

if [[ $dry_run -eq 0 ]]; then
    install -d -m 0700 -- "$state_directory"
    [[ ! -L $state_directory ]] || fail 'state directory must not be a symlink'
    read_state
fi

notification_type=''
notification_title=''
notification_body=''
observed_status='failure'
observed_digest_signature=''

case "$comparison_status" in
    0)
        observed_status='current'
        if [[ $prior_status == pending || $prior_status == failure ]]; then
            notification_type='success'
            notification_title="Container image check recovered on $host_name"
            notification_body="Apprise API and Mailrise now match the current registry platform digests. Review: docs/CONTAINER_LIFECYCLE.md"
        fi
        ;;
    10)
        observed_status='pending'
        pending_rows="$(awk -F '\t' '$5 == "update-available" {print}' <<<"$comparison_output")"
        [[ -n $pending_rows ]] || fail 'comparator returned update status without an affected container'
        digest_material="$(awk -F '\t' '$5 == "update-available" {print $1 "=" $4}' <<<"$comparison_output" | sort)"
        observed_digest_signature="sha256:$(sha256sum <<<"$digest_material" | awk '{print $1}')"
        if [[ $prior_status != pending || $prior_digest_signature != "$observed_digest_signature" ]]; then
            notification_type='warning'
            notification_title="Container update available on $host_name"
        elif ((current_epoch - prior_notification_epoch >= reminder_seconds)); then
            notification_type='warning'
            notification_title="Container update reminder for $host_name"
        fi
        if [[ -n $notification_type ]]; then
            update_details="$(awk -F '\t' '$5 == "update-available" {
                printf "%s: running image %s, candidate %s\\n", $1, $3, $4
            }' <<<"$comparison_output")"
            notification_body="${update_details}Review upstream changes, then use the exact-digest procedure in docs/CONTAINER_LIFECYCLE.md. No update was applied."
        fi
        ;;
    *)
        observed_status='failure'
        if [[ $prior_status != failure ]] || ((current_epoch - prior_notification_epoch >= reminder_seconds)); then
            notification_type='failure'
            notification_title="Container update check failed on $host_name"
            notification_body="The registry comparison could not be completed safely (exit $comparison_status). Inspect: journalctl -u apprise-container-update-check.service"
        fi
        ;;
esac

if [[ $dry_run -eq 1 ]]; then
    printf 'DRY_RUN: comparison_status=%s observed_status=%s notification=%s\n' \
        "$comparison_status" "$observed_status" "${notification_type:-none}"
    printf '%s\n' "$comparison_output"
    exit 0
fi

notification_epoch="$prior_notification_epoch"
if [[ -n $notification_type ]]; then
    if ! send_notification "$notification_type" "$notification_title" "$notification_body"; then
        printf 'FAIL: notification delivery exhausted bounded retries\n' >&2
        if [[ $comparison_status -eq 0 || $comparison_status -eq 10 ]]; then
            exit 75
        fi
        exit "$comparison_status"
    fi
    notification_epoch="$current_epoch"
fi

write_state "$observed_status" "$observed_digest_signature" "$notification_epoch"
printf 'CHECK_COMPLETE: status=%s notification=%s\n' \
    "$observed_status" "${notification_type:-none}"

if [[ $comparison_status -ne 0 && $comparison_status -ne 10 ]]; then
    exit "$comparison_status"
fi
