#!/bin/bash

set -Eeuo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly test_dir
component_dir="$(cd -- "$test_dir/.." && pwd)"
readonly component_dir
readonly checker="$component_dir/scripts/check-container-updates.sh"
readonly updater="$component_dir/scripts/update-rootful-systemd-containers.sh"
readonly installer="$component_dir/install-apprise-podman.sh"
readonly lifecycle_doc="$component_dir/docs/CONTAINER_LIFECYCLE.md"
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

for required_file in "$checker" "$updater" "$installer" "$lifecycle_doc"; do
    [[ -f $required_file && ! -L $required_file ]] || fail "missing or unsafe lifecycle artifact: $required_file"
done

require_fixed 'podman manifest inspect' "$checker"
require_fixed "--format '{{range .RepoDigests}}{{println .}}{{end}}'" "$checker"
require_fixed 'exit 10' "$checker"
require_fixed 'sha256:[0-9a-f]{64}' "$updater"
require_fixed 'trap rollback ERR' "$updater"
require_fixed '--preflight-only' "$updater"
require_fixed 'candidate_is_current' "$updater"
require_fixed "any(.manifests[]?; .digest == \$digest)" "$updater"
require_fixed "systemctl stop \"\$mailrise_service\" \"\$apprise_service\"" "$updater"
require_fixed 'apprise-data.snapshot' "$updater"
require_fixed "podman tag \"\$prior_apprise_image_id\" \"\$apprise_tag\"" "$updater"
require_fixed 'wait_for_services' "$updater"
require_fixed "MAILRISE_IMAGE=\"\${MAILRISE_IMAGE:-docker.io/yoryan/mailrise:latest}\"" "$installer"
[[ $(grep -Fc -- '--pull=never' "$installer") -eq 4 ]] || fail 'installer must emit four explicit no-pull controls'
require_fixed 'Use systemd as the sole lifecycle owner' "$lifecycle_doc"
require_fixed 'Why auto-update is not enabled' "$lifecycle_doc"
require_fixed 'a5c9c73c34f2cea5d2c86a5542d2d438709966f0635935296133276fa94a503c' "$lifecycle_doc"

if grep -Eq 'podman pull [^"$]*:latest' "$updater"; then
    fail 'controlled updater pulls a moving latest tag'
fi

fixture_dir="$(mktemp -d)"
fixture_bin="$fixture_dir/bin"
readonly fixture_bin
install -d -m 0700 -- "$fixture_bin"
cat >"$fixture_bin/podman" <<'PODMAN_FIXTURE'
#!/bin/bash
set -Eeuo pipefail

readonly apprise_id='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
readonly mailrise_id='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
readonly apprise_digest='sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
readonly mailrise_digest='sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

case "${1:-}:${2:-}" in
    info:--format)
        printf 'arm64\n'
        ;;
    container:exists)
        ;;
    container:inspect)
        case "${3:-}" in
            apprise-api) printf '%s\n' "$apprise_id" ;;
            mailrise) printf '%s\n' "$mailrise_id" ;;
            *) exit 1 ;;
        esac
        ;;
    manifest:inspect)
        case "${3:-}" in
            docker.io/caronc/apprise:latest)
                printf '{"manifests":[{"digest":"%s","platform":{"architecture":"arm64"}}]}\n' "$apprise_digest"
                ;;
            docker.io/yoryan/mailrise:latest)
                printf '{"manifests":[{"digest":"%s","platform":{"architecture":"arm64"}}]}\n' "$mailrise_digest"
                ;;
            *) exit 1 ;;
        esac
        ;;
    image:inspect)
        case "${3:-}" in
            "$apprise_id")
                if [[ ${FIXTURE_APPRISE_CURRENT:-false} == true ]]; then
                    printf 'docker.io/caronc/apprise@%s\n' "$apprise_digest"
                else
                    printf 'docker.io/caronc/apprise@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\n'
                fi
                ;;
            "$mailrise_id") printf 'docker.io/yoryan/mailrise@%s\n' "$mailrise_digest" ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
PODMAN_FIXTURE
chmod 0700 -- "$fixture_bin/podman"

comparison_output=''
comparison_status=0
comparison_output="$(PATH="$fixture_bin:/usr/bin:/bin" \
    FIXTURE_APPRISE_CURRENT=false \
    CONTAINER_LIFECYCLE_LOCK_FILE="$fixture_dir/lifecycle.lock" \
    "$checker")" ||
    comparison_status=$?
[[ $comparison_status -eq 10 ]] || fail "pending comparison returned $comparison_status"
grep -Fq $'apprise-api\tdocker.io/caronc/apprise:latest\tcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\tsha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tupdate-available' \
    <<<"$comparison_output" || fail 'pending Apprise result was not reported'
grep -Fq $'mailrise\tdocker.io/yoryan/mailrise:latest\tdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\tsha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\tcurrent' \
    <<<"$comparison_output" || fail 'current Mailrise result was not reported'

comparison_status=0
comparison_output="$(PATH="$fixture_bin:/usr/bin:/bin" \
    FIXTURE_APPRISE_CURRENT=true \
    CONTAINER_LIFECYCLE_LOCK_FILE="$fixture_dir/lifecycle.lock" \
    "$checker")" ||
    comparison_status=$?
[[ $comparison_status -eq 0 ]] || fail "current comparison returned $comparison_status"
grep -Fq 'UPDATE_COUNT=0' <<<"$comparison_output" || fail 'all-current result was not reported'

printf 'PASS: digest comparison and controlled container update policy\n'
