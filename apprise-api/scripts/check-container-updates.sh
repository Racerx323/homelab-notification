#!/bin/bash

set -Eeuo pipefail

readonly apprise_container='apprise-api'
readonly apprise_image='docker.io/caronc/apprise:latest'
readonly mailrise_container='mailrise'
readonly mailrise_image='docker.io/yoryan/mailrise:latest'

if [[ $EUID -eq 0 ]]; then
    lifecycle_lock_file="${CONTAINER_LIFECYCLE_LOCK_FILE:-/run/lock/apprise-container-lifecycle.lock}"
else
    lifecycle_lock_file="${CONTAINER_LIFECYCLE_LOCK_FILE:-${XDG_RUNTIME_DIR:-/run/user/$EUID}/apprise-container-lifecycle.lock}"
fi
readonly lifecycle_lock_file

update_count=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

remote_platform_digest() {
    local checked_image="$1"
    local checked_architecture="$2"
    local manifest_json
    local matching_digest

    manifest_json="$(podman manifest inspect "$checked_image")" ||
        fail "registry inspection failed: $checked_image"
    matching_digest="$(jq -er --arg architecture "$checked_architecture" '
        [.manifests[]? |
            select(.platform.architecture == $architecture) |
            .digest] |
        if length == 1 then .[0]
        elif length == 0 then error("no matching platform manifest")
        else error("multiple matching platform manifests")
        end
    ' <<<"$manifest_json")" ||
        fail "could not select one $checked_architecture manifest: $checked_image"
    [[ $matching_digest =~ ^sha256:[0-9a-f]{64}$ ]] ||
        fail "registry returned an invalid digest: $checked_image"
    printf '%s\n' "$matching_digest"
}

check_container() {
    local checked_container="$1"
    local checked_image="$2"
    local checked_architecture="$3"
    local running_image_id
    local remote_digest
    local local_repo_digests
    local update_status='update-available'

    podman container exists "$checked_container" ||
        fail "container does not exist: $checked_container"
    running_image_id="$(podman container inspect "$checked_container" --format '{{.Image}}')"
    [[ $running_image_id =~ ^[0-9a-f]{64}$ ]] ||
        fail "container has an invalid image ID: $checked_container"
    remote_digest="$(remote_platform_digest "$checked_image" "$checked_architecture")"
    local_repo_digests="$(podman image inspect "$running_image_id" \
        --format '{{range .RepoDigests}}{{println .}}{{end}}')"

    if grep -Fq -- "@$remote_digest" <<<"$local_repo_digests"; then
        update_status='current'
    else
        update_count=$((update_count + 1))
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$checked_container" "$checked_image" "$running_image_id" \
        "$remote_digest" "$update_status"
}

for required_command in flock grep jq podman; do
    command -v "$required_command" >/dev/null || fail "required command not found: $required_command"
done

exec 9>"$lifecycle_lock_file"
flock --shared 9

host_architecture="$(podman info --format '{{.Host.Arch}}')"
readonly host_architecture
case "$host_architecture" in
    amd64 | arm64) ;;
    *) fail "unsupported or ambiguous architecture: $host_architecture" ;;
esac

printf 'CONTAINER\tIMAGE\tRUNNING_IMAGE_ID\tREMOTE_PLATFORM_DIGEST\tSTATUS\n'
check_container "$apprise_container" "$apprise_image" "$host_architecture"
check_container "$mailrise_container" "$mailrise_image" "$host_architecture"

if ((update_count > 0)); then
    printf 'UPDATE_COUNT=%s\n' "$update_count"
    exit 10
fi
printf 'UPDATE_COUNT=0\n'
