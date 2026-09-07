#!/bin/bash

set -Eeuo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly test_dir
component_dir="$(cd -- "$test_dir/.." && pwd)"
readonly component_dir
readonly notifier="$component_dir/scripts/notify-container-updates.sh"
readonly checker="$component_dir/scripts/check-container-updates.sh"
readonly updater="$component_dir/scripts/update-rootful-systemd-containers.sh"
readonly installer="$component_dir/install-apprise-podman.sh"
readonly service_template="$component_dir/templates/apprise-container-update-check.service"
readonly timer_template="$component_dir/templates/apprise-container-update-check.timer"
readonly config_example="$component_dir/configs/container-update-check.conf.example"
fixture_dir=''

cleanup() {
    [[ -z $fixture_dir ]] || rm -rf -- "$fixture_dir"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_fixed() {
    local required_text="$1"
    local checked_file="$2"

    grep -Fq -- "$required_text" "$checked_file" ||
        fail "$checked_file missing required text: $required_text"
}

for required_file in "$notifier" "$checker" "$updater" "$installer" "$service_template" \
    "$timer_template" "$config_example"; do
    [[ -f $required_file && ! -L $required_file ]] ||
        fail "missing or unsafe notification artifact: $required_file"
done

require_fixed 'flock --shared 9' "$checker"
require_fixed 'flock --exclusive 9' "$updater"
require_fixed '/run/lock/apprise-container-lifecycle.lock' "$checker"
require_fixed '/run/lock/apprise-container-lifecycle.lock' "$updater"
require_fixed 'StateDirectory=apprise-container-lifecycle' "$service_template"
require_fixed 'EnvironmentFile=/etc/apprise-container-update-check.conf' "$service_template"
require_fixed 'TimeoutStartSec=1h' "$service_template"
require_fixed 'ProtectSystem=full' "$service_template"
require_fixed 'ReadWritePaths=/etc/containers/networks/netavark.lock' "$service_template"
require_fixed 'OnCalendar=Mon *-*-* 09:00:00' "$timer_template"
require_fixed 'RandomizedDelaySec=1h' "$timer_template"
require_fixed 'Persistent=true' "$timer_template"
require_fixed 'APPRISE_BASE_URL=http://127.0.0.1:8000' "$config_example"
require_fixed 'APPRISE_CONFIG_KEY=apprise' "$config_example"
require_fixed 'CONTAINER_UPDATE_RETRY_ATTEMPTS=4' "$config_example"
require_fixed 'CONTAINER_UPDATE_RETRY_DELAY_SECONDS=900' "$config_example"

[[ $(grep -c '^ReadWritePaths=' "$service_template") -eq 1 ]] ||
    fail 'service must define exactly one writable-path exception'
if grep -Eq '^ReadWritePaths=/(etc|etc/containers|etc/containers/networks)/?$' "$service_template"; then
    fail 'service grants a broader writable /etc path than Podman requires'
fi

for checked_shell_file in "$checker" "$notifier" "$updater" "$installer"; do
    global_names="$(sed -nE 's/^readonly ([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$checked_shell_file" | sort -u)"
    local_names="$(sed -nE 's/^[[:space:]]+local ([A-Za-z_][A-Za-z0-9_]*).*/\1/p' "$checked_shell_file" | sort -u)"
    collisions="$(comm -12 <(printf '%s\n' "$global_names") <(printf '%s\n' "$local_names"))"
    [[ -z $collisions ]] ||
        fail "$checked_shell_file reuses readonly globals as locals: $collisions"
done

fixture_dir="$(mktemp -d)"
fixture_app="$fixture_dir/app"
fixture_bin="$fixture_dir/bin"
fixture_state="$fixture_dir/state"
readonly fixture_app fixture_bin fixture_state
install -d -m 0700 -- "$fixture_app" "$fixture_bin" "$fixture_state"
cp -- "$notifier" "$fixture_app/notify-container-updates.sh"
chmod 0700 -- "$fixture_app/notify-container-updates.sh"

cat >"$fixture_app/check-container-updates.sh" <<'CHECKER_FIXTURE'
#!/bin/bash
set -Eeuo pipefail

readonly apprise_id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
readonly mailrise_id='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
readonly digest_a='sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
readonly digest_b='sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

printf 'CONTAINER\tIMAGE\tRUNNING_IMAGE_ID\tREMOTE_PLATFORM_DIGEST\tSTATUS\n'
case "$(<"$FIXTURE_MODE_FILE")" in
    current)
        printf 'apprise-api\tdocker.io/caronc/apprise:latest\t%s\t%s\tcurrent\n' "$apprise_id" "$digest_a"
        printf 'mailrise\tdocker.io/yoryan/mailrise:latest\t%s\t%s\tcurrent\n' "$mailrise_id" "$digest_b"
        printf 'UPDATE_COUNT=0\n'
        ;;
    pending-a)
        printf 'apprise-api\tdocker.io/caronc/apprise:latest\t%s\t%s\tupdate-available\n' "$apprise_id" "$digest_a"
        printf 'mailrise\tdocker.io/yoryan/mailrise:latest\t%s\t%s\tcurrent\n' "$mailrise_id" "$digest_b"
        printf 'UPDATE_COUNT=1\n'
        exit 10
        ;;
    pending-b)
        printf 'apprise-api\tdocker.io/caronc/apprise:latest\t%s\t%s\tupdate-available\n' "$apprise_id" "$digest_b"
        printf 'mailrise\tdocker.io/yoryan/mailrise:latest\t%s\t%s\tcurrent\n' "$mailrise_id" "$digest_b"
        printf 'UPDATE_COUNT=1\n'
        exit 10
        ;;
    failure)
        exit 1
        ;;
    *) exit 2 ;;
esac
CHECKER_FIXTURE
chmod 0700 -- "$fixture_app/check-container-updates.sh"

cat >"$fixture_bin/curl" <<'CURL_FIXTURE'
#!/bin/bash
set -Eeuo pipefail

notification_payload=''
while (($# > 0)); do
    case "$1" in
        --data-binary)
            notification_payload="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done
[[ -n $notification_payload ]]
printf '%s\n' "$notification_payload" >>"$FIXTURE_PAYLOAD_LOG"
printf 'delivery\n' >>"$FIXTURE_CURL_LOG"
if [[ ${FIXTURE_CURL_FAILURE:-false} == true ]]; then
    printf '503'
else
    printf '200'
fi
CURL_FIXTURE
chmod 0700 -- "$fixture_bin/curl"

mode_file="$fixture_dir/mode"
curl_log="$fixture_dir/curl.log"
payload_log="$fixture_dir/payload.jsonl"
readonly mode_file curl_log payload_log
printf 'current\n' >"$mode_file"

run_notifier() {
    PATH="$fixture_bin:/usr/bin:/bin" \
        FIXTURE_MODE_FILE="$mode_file" \
        FIXTURE_CURL_LOG="$curl_log" \
        FIXTURE_PAYLOAD_LOG="$payload_log" \
        CONTAINER_UPDATE_STATE_DIRECTORY="$fixture_state" \
        CONTAINER_UPDATE_RETRY_DELAY_SECONDS=0 \
        "$fixture_app/notify-container-updates.sh"
}

run_notifier >/dev/null
[[ ! -e $curl_log ]] || fail 'initial current state sent a notification'

printf 'pending-a\n' >"$mode_file"
run_notifier >/dev/null
[[ $(wc -l <"$curl_log") -eq 1 ]] || fail 'first pending digest did not send exactly once'
first_title="$(sed -n '1p' "$payload_log" | jq -r '.title')"
first_body="$(sed -n '1p' "$payload_log" | jq -r '.body')"
readonly first_title first_body
[[ $first_title == 'Container update available - '* ]] ||
    fail "unexpected update title: $first_title"
expected_first_body="$(printf '%s\n' \
    'Container: apprise-api' \
    'Current image ID: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'Available registry digest: sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    '' \
    'Next step:' \
    'Review the upstream release notes, then follow the exact-digest update procedure:' \
    'docs/CONTAINER_LIFECYCLE.md' \
    '' \
    'Safety:' \
    'No image was pulled or deployed.')"
readonly expected_first_body
[[ $first_body == "$expected_first_body" ]] || fail 'update body does not match the readable contract'
if grep -Fq '\n' <<<"$first_body"; then
    fail 'decoded update body contains a literal newline escape'
fi

run_notifier >/dev/null
[[ $(wc -l <"$curl_log") -eq 1 ]] || fail 'unchanged pending digest sent an early reminder'

jq '.notification_epoch = 0' "$fixture_state/state.json" >"$fixture_state/state.next"
mv -- "$fixture_state/state.next" "$fixture_state/state.json"
run_notifier >/dev/null
[[ $(wc -l <"$curl_log") -eq 2 ]] || fail 'due pending reminder did not send exactly once'

printf 'pending-b\n' >"$mode_file"
run_notifier >/dev/null
[[ $(wc -l <"$curl_log") -eq 3 ]] || fail 'changed pending digest did not send a new warning'

printf 'current\n' >"$mode_file"
run_notifier >/dev/null
[[ $(wc -l <"$curl_log") -eq 4 ]] || fail 'recovery did not send exactly once'

comparison_status=0
printf 'failure\n' >"$mode_file"
run_notifier >/dev/null 2>&1 || comparison_status=$?
[[ $comparison_status -eq 1 ]] || fail "comparison failure returned $comparison_status"
[[ $(wc -l <"$curl_log") -eq 5 ]] || fail 'comparison failure did not notify once'
[[ $(jq -r '.status' "$fixture_state/state.json") == failure ]] ||
    fail 'comparison failure state was not persisted'
failure_body="$(sed -n '5p' "$payload_log" | jq -r '.body')"
readonly failure_body
grep -Fq $'Status: Registry comparison failed.\nExit status: 1' <<<"$failure_body" ||
    fail 'failure payload lacks readable status lines'
grep -Fq $'Next step:\nsudo journalctl -u apprise-container-update-check.service -n 50 --no-pager' \
    <<<"$failure_body" || fail 'failure payload lacks the evidence command'
grep -Fq $'Safety:\nNo container update was attempted.' <<<"$failure_body" ||
    fail 'failure payload lacks the safety status'

printf 'current\n' >"$mode_file"
run_notifier >/dev/null
printf 'pending-a\n' >"$mode_file"
delivery_status=0
PATH="$fixture_bin:/usr/bin:/bin" \
    FIXTURE_MODE_FILE="$mode_file" \
    FIXTURE_CURL_LOG="$curl_log" \
    FIXTURE_PAYLOAD_LOG="$payload_log" \
    FIXTURE_CURL_FAILURE=true \
    CONTAINER_UPDATE_STATE_DIRECTORY="$fixture_state" \
    CONTAINER_UPDATE_RETRY_ATTEMPTS=2 \
    CONTAINER_UPDATE_RETRY_DELAY_SECONDS=0 \
    "$fixture_app/notify-container-updates.sh" >/dev/null 2>&1 || delivery_status=$?
[[ $delivery_status -eq 75 ]] || fail "delivery exhaustion returned $delivery_status"
[[ $(jq -r '.status' "$fixture_state/state.json") == current ]] ||
    fail 'failed delivery incorrectly committed pending state'

printf 'PASS: scheduled container update notification policy\n'
