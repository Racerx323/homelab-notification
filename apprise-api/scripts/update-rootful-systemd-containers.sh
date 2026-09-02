#!/bin/bash

set -Eeuo pipefail
umask 077

readonly apprise_service='apprise-api.service'
readonly apprise_container='apprise-api'
readonly apprise_tag='docker.io/caronc/apprise:latest'
readonly apprise_repository='docker.io/caronc/apprise'
readonly mailrise_service='mailrise.service'
readonly mailrise_container='mailrise'
readonly mailrise_tag='docker.io/yoryan/mailrise:latest'
readonly mailrise_repository='docker.io/yoryan/mailrise'
readonly apprise_data_path='/var/lib/apprise'
readonly mailrise_config_path='/etc/mailrise.conf'
readonly health_url='http://127.0.0.1:8000/status'
readonly lifecycle_lock_file='/run/lock/apprise-container-lifecycle.lock'

candidate_apprise_digest=''
candidate_mailrise_digest=''
transaction_backup_dir=''
prior_apprise_image_id=''
prior_mailrise_image_id=''
candidate_apprise_image_id=''
candidate_mailrise_image_id=''
mutation_started=0
snapshot_ready=0
rollback_running=0
preflight_only=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}

usage() {
    cat <<'USAGE'
Usage: update-rootful-systemd-containers.sh \
  --backup-dir /var/backups/apprise-container-update/CHANGE_ID \
  [--apprise-digest sha256:HEX] [--mailrise-digest sha256:HEX] \
  [--preflight-only]

At least one exact platform digest is required. Obtain reviewed digests from
check-container-updates.sh; do not pass a tag or manifest-list digest.
USAGE
}

container_image_id() {
    podman container inspect "$1" --format '{{.Image}}'
}

image_id() {
    podman image inspect "$1" --format '{{.Id}}'
}

candidate_is_current() {
    local checked_tag="$1"
    local checked_digest="$2"
    local manifest_json

    manifest_json="$(podman manifest inspect "$checked_tag")" || return 1
    jq -e --arg digest "$checked_digest" \
        'any(.manifests[]?; .digest == $digest)' <<<"$manifest_json" >/dev/null
}

apprise_healthy() {
    systemctl is-active --quiet "$apprise_service" || return 1
    [[ $(podman container inspect "$apprise_container" --format '{{.State.Status}}' 2>/dev/null) == running ]] ||
        return 1
    curl --silent --show-error --fail --max-time 5 "$health_url" >/dev/null
}

mailrise_healthy() {
    systemctl is-active --quiet "$mailrise_service" || return 1
    [[ $(podman container inspect "$mailrise_container" --format '{{.State.Status}}' 2>/dev/null) == running ]] ||
        return 1
    [[ -n $(podman port "$mailrise_container" 8025/tcp 2>/dev/null) ]]
}

wait_for_services() {
    local health_attempt

    for ((health_attempt = 1; health_attempt <= 30; health_attempt++)); do
        if apprise_healthy && mailrise_healthy; then
            return 0
        fi
        sleep 1
    done
    return 1
}

restore_apprise_data() {
    local failed_data_path="$transaction_backup_dir/failed-apprise-data"

    if [[ -e $apprise_data_path || -L $apprise_data_path ]]; then
        mv -- "$apprise_data_path" "$failed_data_path"
    fi
    cp -a -- "$transaction_backup_dir/apprise-data.snapshot" "$apprise_data_path"
}

rollback() {
    local original_status=$?

    [[ $rollback_running -eq 0 ]] || exit "$original_status"
    rollback_running=1
    trap - ERR
    [[ $mutation_started -eq 1 ]] || exit "$original_status"
    printf 'ROLLBACK: restoring prior images and persistent Apprise state\n' >&2

    systemctl stop "$mailrise_service" "$apprise_service" || true
    if [[ $snapshot_ready -eq 1 ]]; then
        restore_apprise_data
    fi
    podman tag "$prior_apprise_image_id" "$apprise_tag"
    podman tag "$prior_mailrise_image_id" "$mailrise_tag"
    systemctl start "$apprise_service"
    systemctl start "$mailrise_service"

    if wait_for_services &&
        [[ $(container_image_id "$apprise_container") == "$prior_apprise_image_id" ]] &&
        [[ $(container_image_id "$mailrise_container") == "$prior_mailrise_image_id" ]]; then
        printf 'ROLLBACK_OK: prior images and data restored from %s\n' "$transaction_backup_dir" >&2
        exit "$original_status"
    fi
    printf 'MANUAL_INTERVENTION_REQUIRED: rollback acceptance failed\n' >&2
    exit 125
}

while (($# > 0)); do
    case "$1" in
        --apprise-digest)
            (($# >= 2)) || fail '--apprise-digest requires a value'
            candidate_apprise_digest="$2"
            shift 2
            ;;
        --mailrise-digest)
            (($# >= 2)) || fail '--mailrise-digest requires a value'
            candidate_mailrise_digest="$2"
            shift 2
            ;;
        --backup-dir)
            (($# >= 2)) || fail '--backup-dir requires a value'
            transaction_backup_dir="$2"
            shift 2
            ;;
        --preflight-only)
            preflight_only=1
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

[[ $EUID -eq 0 ]] || fail 'must run as root for the rootful production deployment'
[[ -n $candidate_apprise_digest || -n $candidate_mailrise_digest ]] ||
    fail 'at least one candidate digest is required'
[[ -n $transaction_backup_dir && $transaction_backup_dir == /var/backups/apprise-container-update/* ]] ||
    fail 'backup directory must be an unused child of /var/backups/apprise-container-update'
[[ ! -e $transaction_backup_dir && ! -L $transaction_backup_dir ]] || fail 'backup directory already exists'
for checked_digest in "$candidate_apprise_digest" "$candidate_mailrise_digest"; do
    [[ -z $checked_digest || $checked_digest =~ ^sha256:[0-9a-f]{64}$ ]] ||
        fail "invalid candidate digest: $checked_digest"
done

for required_command in cp curl flock grep install jq mv podman sleep systemctl; do
    command -v "$required_command" >/dev/null || fail "required command not found: $required_command"
done

exec 9>"$lifecycle_lock_file"
flock --exclusive 9

for checked_service in "$apprise_service" "$mailrise_service"; do
    systemctl is-active --quiet "$checked_service" || fail "service is not active: $checked_service"
    systemctl is-enabled --quiet "$checked_service" || fail "service is not enabled: $checked_service"
done
apprise_unit_text="$(systemctl cat "$apprise_service")"
mailrise_unit_text="$(systemctl cat "$mailrise_service")"
grep -Fq -- "$apprise_tag" <<<"$apprise_unit_text" ||
    fail "service does not use the managed image tag: $apprise_service"
grep -Fq -- "$mailrise_tag" <<<"$mailrise_unit_text" ||
    fail "service does not use the managed image tag: $mailrise_service"
for checked_container in "$apprise_container" "$mailrise_container"; do
    podman container exists "$checked_container" || fail "container does not exist: $checked_container"
done
[[ -d $apprise_data_path && ! -L $apprise_data_path ]] || fail 'Apprise data path is missing or unsafe'
[[ -f $mailrise_config_path && ! -L $mailrise_config_path ]] || fail 'Mailrise config is missing or unsafe'
apprise_healthy || fail 'Apprise API preflight health failed'
mailrise_healthy || fail 'Mailrise preflight health failed'

prior_apprise_image_id="$(container_image_id "$apprise_container")"
prior_mailrise_image_id="$(container_image_id "$mailrise_container")"
[[ $prior_apprise_image_id =~ ^[0-9a-f]{64}$ ]] || fail 'Apprise API has an invalid prior image ID'
[[ $prior_mailrise_image_id =~ ^[0-9a-f]{64}$ ]] || fail 'Mailrise has an invalid prior image ID'
candidate_apprise_image_id="$prior_apprise_image_id"
candidate_mailrise_image_id="$prior_mailrise_image_id"

if [[ -n $candidate_apprise_digest ]]; then
    candidate_apprise_ref="$apprise_repository@$candidate_apprise_digest"
    candidate_is_current "$apprise_tag" "$candidate_apprise_digest" ||
        fail 'Apprise candidate is no longer in the current registry manifest'
fi
if [[ -n $candidate_mailrise_digest ]]; then
    candidate_mailrise_ref="$mailrise_repository@$candidate_mailrise_digest"
    candidate_is_current "$mailrise_tag" "$candidate_mailrise_digest" ||
        fail 'Mailrise candidate is no longer in the current registry manifest'
fi
if [[ $preflight_only -eq 1 ]]; then
    printf 'PREFLIGHT_OK: apprise_image_id=%s mailrise_image_id=%s backup_path_unused=%s\n' \
        "$prior_apprise_image_id" "$prior_mailrise_image_id" "$transaction_backup_dir"
    exit 0
fi

if [[ -n $candidate_apprise_digest ]]; then
    podman pull "$candidate_apprise_ref"
    candidate_apprise_image_id="$(image_id "$candidate_apprise_ref")"
fi
if [[ -n $candidate_mailrise_digest ]]; then
    podman pull "$candidate_mailrise_ref"
    candidate_mailrise_image_id="$(image_id "$candidate_mailrise_ref")"
fi

install -d -m 0700 -- "$transaction_backup_dir"
printf '%s\n' "$prior_apprise_image_id" >"$transaction_backup_dir/prior-apprise-image-id"
printf '%s\n' "$prior_mailrise_image_id" >"$transaction_backup_dir/prior-mailrise-image-id"
printf '%s\n' "${candidate_apprise_digest:-unchanged}" >"$transaction_backup_dir/candidate-apprise-digest"
printf '%s\n' "${candidate_mailrise_digest:-unchanged}" >"$transaction_backup_dir/candidate-mailrise-digest"

trap rollback ERR
mutation_started=1
systemctl stop "$mailrise_service" "$apprise_service"
cp -a -- "$apprise_data_path" "$transaction_backup_dir/apprise-data.snapshot"
cp -a -- "$mailrise_config_path" "$transaction_backup_dir/mailrise.conf.snapshot"
snapshot_ready=1

if [[ -n $candidate_apprise_digest ]]; then
    podman tag "$candidate_apprise_image_id" "$apprise_tag"
fi
if [[ -n $candidate_mailrise_digest ]]; then
    podman tag "$candidate_mailrise_image_id" "$mailrise_tag"
fi

systemctl start "$apprise_service"
systemctl start "$mailrise_service"
wait_for_services || fail 'post-update service health failed'
[[ $(container_image_id "$apprise_container") == "$candidate_apprise_image_id" ]] ||
    fail 'Apprise API did not start from the candidate image'
[[ $(container_image_id "$mailrise_container") == "$candidate_mailrise_image_id" ]] ||
    fail 'Mailrise did not start from the candidate image'

trap - ERR
printf 'ACCEPTED: apprise_image_id=%s mailrise_image_id=%s backup=%s\n' \
    "$candidate_apprise_image_id" "$candidate_mailrise_image_id" "$transaction_backup_dir"
