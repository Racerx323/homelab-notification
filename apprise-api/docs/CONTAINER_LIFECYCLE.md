# Production Container Lifecycle

Use systemd as the sole lifecycle owner for the rootful Apprise API and
Mailrise containers. Use Podman to inspect images and containers, but do not
run `podman restart`, `podman stop`, or `podman rm` against a container owned by
these services.

## J1-SVMF baseline

Read-only inspection on September 2, 2026 found both services active and
enabled under rootful Podman 4.3.1:

- Apprise API runs image ID `a5c9c73c34f2...`. Registry ARM64 digest
  `sha256:2ca897b667ebb76c467f5585dc7eb5fc2cb37a8189ed3208b41a52fa8f89dd55`
  is current.
- Mailrise runs image ID `be669e7e5004...`. Registry ARM64 digest
  `sha256:203cb830a666ee3d0afb1721144d66577467eeb9d821ca2074beffa31766dbc9`
  is current.

The registry digest is architecture-specific. Do not compare image creation
dates or the text `latest`; neither proves that the running ARM64 image matches
the current registry content.

## Check for updates without pulling

Run the comparator on the container host as the owner of the Podman storage.
For J1-SVMF, first connect from the operator workstation with
`ssh pi@svmf.local.theama.co`; do not run the rootful command in WSL:

```bash
# Rootful production
sudo /usr/local/libexec/apprise-api/check-container-updates.sh

# Rootless installation, from its repository checkout
./scripts/check-container-updates.sh
```

The script uses `podman manifest inspect` to read the registry manifest list,
selects exactly one host-architecture digest, and checks whether that digest is
among the running image's local repository digests. It does not pull an image,
move a tag, or restart a service.

Exit status `0` means both images are current. Exit status `10` means at least
one update is available. Any other nonzero status means the comparison could
not be completed safely.

Run this check weekly and before a maintenance window. A pending digest is only
a candidate: review the corresponding
[Apprise API](https://github.com/caronc/apprise-api) or
[Mailrise](https://github.com/YoRyan/mailrise) changes before authorizing it.

The comparator takes a shared lock at
`/run/lock/apprise-container-lifecycle.lock`. The controlled updater takes the
matching exclusive lock for its complete transaction. A scheduled or manual
comparison therefore cannot observe partially retagged or restarting
containers.

## Weekly update notification timer

The optional rootful timer runs every Monday at 09:00 local time with up to one
hour of randomized delay. `Persistent=true` causes systemd to run a missed
check after the host returns. It compares registry state but does not pull,
retag, restart, or update a container.

The notifier interprets comparator results as follows:

| Result | Behavior |
| ------ | -------- |
| Both images current | Journal only, except one recovery after pending/failure |
| Candidate digest first seen or changed | Warning through saved key `apprise` |
| Candidate remains pending | Reminder no sooner than six days |
| Comparison fails | Failure notification when reachable and failed unit result |
| Apprise delivery fails | Four bounded attempts, 15 minutes apart, then failure |

State is atomically stored as root-only JSON under
`/var/lib/apprise-container-lifecycle`. It contains only the prior state, a
digest signature, and the last successful notification time. Failed delivery
does not acknowledge the transition, so the next run can retry it. Journald
records decisions and HTTP status codes but not response bodies, notification
URLs, saved configuration contents, or credentials.

The direct endpoint is `http://127.0.0.1:8000/notify/apprise`. The final path
component is an Apprise saved-configuration name, not an API credential. This
same-host first phase cannot deliver while Apprise API is down; bounded retry
reduces short-outage loss. The planned durable-apprise pilot will replace only
network delivery with persistent enqueue and worker retry.

### Alert format

Alerts use plain text and real line breaks so downstream services do not need
Markdown to separate operational fields. Update warnings follow this layout:

```text
Container update available - J1-SVMF

Container: apprise-api
Current image ID: FULL_IMAGE_ID
Available registry digest: sha256:FULL_PLATFORM_DIGEST

Next step:
Review the upstream release notes, then follow the exact-digest update procedure:
/home/aaron/code/homelab-notification/apprise-api/docs/CONTAINER_LIFECYCLE.md

Safety:
No image was pulled or deployed.
```

Failure alerts separate the exit status, journal command, and confirmation that
no update was attempted. A check returning to current status uses the title
`Container update check successful - HOST`, states the successful comparison,
and includes the full operator-workstation lifecycle-document path. The path is
set by `CONTAINER_UPDATE_REFERENCE_PATH` in
`/etc/apprise-container-update-check.conf`; it is a reference for the operator
and does not need to exist on J1-SVMF. Full image IDs and digests are retained
so the alert remains usable as maintenance evidence.

On September 7, 2026, J1-SVMF accepted the readable alert formatter in bundle
SHA-256
`b95d891c92718af51ae2f158c5808232ee44f261c3c9c44943650a52b1fe0105`.
The installed notifier SHA-256 is
`eb5f2f50cc153a9da8e95b27868009ce7259c3005840783f7d52dff1a3aafbd2`.
A no-notification dry run detected the existing pending Apprise update while
leaving the notification state checksum unchanged. The timer and both
application services remained healthy and enabled. Root-only rollback evidence
is retained under
`/var/backups/apprise-container-update/2026-09-07-alert-format`.

On September 14, 2026, J1-SVMF accepted the successful-check title and full
operator-reference-path update. The title changed from
`Container update check recovered` to
`Container update check successful`. The validated
`CONTAINER_UPDATE_REFERENCE_PATH` setting applies the full operator path to
both successful and update-available alerts. The installed notifier SHA-256 is
`4842a82a61145122c37637ca3bc953dcf04e240c6ff7b4140b33fc81a68cf12c`,
and the installed update-check configuration SHA-256 is
`cdb8d606648b41211c10eb37e309dd9819bfe72c4c41d33647afca593c91795b`.
A live dry run returned both containers as current, sent no notification, and
left the notification state unchanged. The timer and both application services
remained enabled and active, and the Apprise status endpoint returned `OK`.
Root-only rollback evidence is retained under
`/var/backups/apprise-container-update/2026-09-14-success-title-reference`.

### Install the timer

Installing and enabling the timer grants recurring registry reads and
conditional notification delivery. Review those effects before running these
commands. Use the comparator, notifier, and updater from the same reviewed
repository revision; do not enable the timer while an older updater without
the exclusive lifecycle lock remains in the production procedure.

The fresh-host `--production` installer installs this complete artifact set but
leaves the timer disabled. Use the manual procedure below to retrofit or replace
the lifecycle artifacts on an existing rootful systemd deployment. Flexible
and rootless installer modes do not install these rootful artifacts.

Before overwriting an existing timer deployment, copy its two units, three
helper scripts, and configuration to a new root-only operation backup. On a
first installation, verify that those targets do not already exist.

These installation commands run on J1-SVMF from a separately reviewed and
authorized deployment bundle staged on that host. Files in the WSL repository
are not directly visible to J1-SVMF. Then install:

```bash
sudo install -d -m 0755 /usr/local/libexec/apprise-api
sudo install -m 0755 \
  scripts/check-container-updates.sh \
  scripts/notify-container-updates.sh \
  scripts/update-rootful-systemd-containers.sh \
  /usr/local/libexec/apprise-api/
sudo install -m 0600 \
  configs/container-update-check.conf.example \
  /etc/apprise-container-update-check.conf
sudo install -m 0644 \
  templates/apprise-container-update-check.service \
  templates/apprise-container-update-check.timer \
  /etc/systemd/system/

sudo systemd-analyze verify \
  /etc/systemd/system/apprise-container-update-check.service \
  /etc/systemd/system/apprise-container-update-check.timer
sudo systemctl daemon-reload
sudo systemctl enable --now apprise-container-update-check.timer
```

Confirm the installed helper ownership, mode, and checksums. Require
`755 root:root` for all three helpers, and compare each checksum with its
reviewed deployment artifact:

```bash
sudo stat -c '%a %U:%G %n' \
  /usr/local/libexec/apprise-api/check-container-updates.sh \
  /usr/local/libexec/apprise-api/notify-container-updates.sh \
  /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh
sudo sha256sum \
  /usr/local/libexec/apprise-api/check-container-updates.sh \
  /usr/local/libexec/apprise-api/notify-container-updates.sh \
  /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh --help
```

Then confirm the installed schedule without triggering a notification:

```bash
sudo systemctl status apprise-container-update-check.timer
sudo systemctl list-timers apprise-container-update-check.timer
sudo /usr/local/libexec/apprise-api/notify-container-updates.sh --dry-run
```

Starting `apprise-container-update-check.service` performs a real check and may
send a warning or recovery. It never applies the available update.

### Accepted J1-SVMF timer installation

On September 2, 2026, J1-SVMF accepted deployment bundle SHA-256
`67ac021649b26b1378ee7fda6a958ea5330eb57eb05025d06dcf5356a98b1829`.
The rootful timer is enabled and active, with its first scheduled run on
Monday, September 7, 2026 at 09:00 CDT plus its deterministic randomized
delay. Installation validation found both images current, planned no
notification, and did not create persistent notification state.

Both application services remained active and enabled, Apprise HTTP health
passed, and the timer service had no journal entries or failed state. The exact
deployment archive is retained root-only at
`/var/backups/apprise-container-update/2026-09-02-weekly-check/deployment-bundle.tar.gz`.
The two temporary upload files were removed after acceptance.

### Accepted J1-SVMF updater helper installation

On September 7, 2026, J1-SVMF accepted the missing production updater from
bundle SHA-256
`b43c899023108a1b3e4543e9bdb24d109ecf21c001bd6ed3f849226382948191`.
The installed root-owned mode `0755` helper is
`/usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh`, with
SHA-256
`c26da7332468a629160b4bfa71d638bf14c6207e77c0f87060931efb751f10de`.

The deployment did not invoke the updater, pull an image, restart a service, or
change either running image ID. Both application services remained active and
enabled. The unique remote staging directory and its uploaded archive were
removed after validation.

### Podman netavark lock compatibility

Podman 4.3.1 opens `/etc/containers/networks/netavark.lock` while initializing
rootful state, including for read-only inspection. `ProtectSystem=full` makes
all of `/etc` read-only, so the service grants one exact exception:

```ini
ProtectSystem=full
ReadWritePaths=/etc/containers/networks/netavark.lock
```

Do not replace this with a writable `/etc`, `/etc/containers`, or
`/etc/containers/networks`. The single empty root-owned lock file is sufficient
for the comparator, while registry configuration and Podman network definitions
remain read-only. The notification policy test requires exactly this exception
and rejects those broader alternatives.

On September 7, 2026, the first scheduled invocation exposed the missing
exception and exited `125` with `netavark.lock: read-only file system`. The
notifier delivered the failure alert and persisted failure state as designed.
J1-SVMF then accepted repair bundle SHA-256
`66a17ea9cf3eb8eb31efc0c596ef7c7ff4ce952305776d881770514ad2c2e0ef`
and unit SHA-256
`92d8efc78240b29954513d01ff62510744ed014f0495d66982d01044d21b11dc`.

Controlled invocation `f5fe386bc704433cbeb27f3fe6c92d3a` completed with
exit `0`, delivered one warning on its first attempt, and transitioned state to
`pending`. The warning reported Apprise candidate ARM64 digest
`sha256:987dc8724b9e03c50689c52f8eac3f0fe45a78bad650b62637dbe1e575068b03`;
no image update was applied. Both application services remained healthy and
enabled, the timer remained active, and its next scheduled run was September
14, 2026. Root-only rollback evidence is retained under
`/var/backups/apprise-container-update/2026-09-07-netavark-lock-fix`.

### Disable or roll back the timer

The ordinary rollback preserves state evidence:

```bash
sudo systemctl disable --now apprise-container-update-check.timer
sudo systemctl stop apprise-container-update-check.service
sudo rm -f \
  /etc/systemd/system/apprise-container-update-check.service \
  /etc/systemd/system/apprise-container-update-check.timer
sudo systemctl daemon-reload
```

If this replaced an earlier timer revision, restore all six backed-up files
and reload systemd instead of leaving mixed versions. The comparator and
notifier used by the timer, the updater, and
`/etc/apprise-container-update-check.conf` may remain inert after a first-install
rollback. Removing them is safe after review, but deleting
`/var/lib/apprise-container-lifecycle` is a separate evidence-purge decision.
Disabling the timer does not affect `apprise-api` or `mailrise`.

## Controlled rootful update

Use the concise [container update runbook](CONTAINER_UPDATES.md) for the
repeatable Apprise-only, Mailrise-only, and combined procedures. The dated
digests below are accepted-live history and must not be reused as current
update inputs.

The production updater accepts only exact `sha256:` platform digests printed by
the comparator. It never accepts `latest` as an update input.

Use a new, descriptive backup path for every operation. This example updates
only Apprise API because the observed Mailrise digest is already current:

```bash
sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --preflight-only \
  --backup-dir /var/backups/apprise-container-update/2026-09-02-apprise \
  --apprise-digest sha256:2ca897b667ebb76c467f5585dc7eb5fc2cb37a8189ed3208b41a52fa8f89dd55

sudo /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh \
  --backup-dir /var/backups/apprise-container-update/2026-09-02-apprise \
  --apprise-digest sha256:2ca897b667ebb76c467f5585dc7eb5fc2cb37a8189ed3208b41a52fa8f89dd55
```

To update both images in one maintenance transaction, add
`--mailrise-digest sha256:REVIEWED_ARM64_DIGEST`.

The updater:

1. requires root, active and enabled services, running containers, safe
   persistent paths, and passing pre-update health checks;
2. pulls candidates by their exact repository and platform digest while the
   current services remain online;
3. records both prior image IDs in a new root-only backup directory;
4. stops Mailrise and then Apprise API through systemd;
5. snapshots `/var/lib/apprise` and `/etc/mailrise.conf` while stopped;
6. moves only the requested local `latest` tags to the reviewed images;
7. starts Apprise API and then Mailrise; and
8. requires Apprise HTTP health, both container states, the Mailrise published
   port, and exact running image IDs.

It holds the exclusive lifecycle lock from preflight through acceptance or
rollback. A running notification comparison finishes first; a new comparison
waits until the update transaction releases the lock.

`--preflight-only` validates the services, containers, persistent paths,
candidate registry digest, health, and unused backup path without pulling an
image or changing the host.

### Accepted J1-SVMF update

On September 2, 2026, J1-SVMF accepted the Apprise API ARM64 digest shown
above. The resulting image ID is
`a5c9c73c34f2cea5d2c86a5542d2d438709966f0635935296133276fa94a503c`.
Mailrise retained image ID
`be669e7e50040fd26b2b4d7740e87fabe5c0b73d81c949725d6442d323f0bf2d`.

Both services remained active and enabled. Local and controller HTTP checks
returned `OK`, Mailrise published port 8025, and no failed systemd unit
remained. The root-only stopped-state snapshot and prior image IDs are stored
at `/var/backups/apprise-container-update/2026-09-02-apprise`.

On September 7, 2026, Apprise API was updated to reviewed ARM64 platform digest
`sha256:987dc8724b9e03c50689c52f8eac3f0fe45a78bad650b62637dbe1e575068b03`.
The resulting image ID is
`039aa271078c8c8502c993eb1e4513ae299de6958016fddb46d5d4bff767fe61`.
Mailrise remained on image ID
`be669e7e50040fd26b2b4d7740e87fabe5c0b73d81c949725d6442d323f0bf2d`.
The updater accepted the transaction at
`/var/backups/apprise-container-update/20260907-apprise`.

Two refused HTTP connections and one transient `502` occurred while Nginx and
Gunicorn initialized; the bounded health loop then succeeded. Independent
read-only validation found both services active and enabled, HTTP status `OK`,
Mailrise port `8025` published, both containers running, and comparator
`UPDATE_COUNT=0`.

The scheduled notification state still records `pending` because the recovery
notification service has not been invoked since this update. Starting
`apprise-container-update-check.service` would send and persist that recovery;
that notification-producing action remains a separate operation.

If an error occurs after shutdown begins, the updater stops both services,
preserves candidate-mutated Apprise data, restores the stopped-state snapshot,
retags both prior image IDs, restarts both services, and requires rollback
health. It exits `125` when it cannot prove recovery.

After acceptance, independently verify:

```bash
sudo systemctl is-active apprise-api mailrise
sudo systemctl is-enabled apprise-api mailrise
curl -fsS http://127.0.0.1:8000/status
sudo podman inspect apprise-api mailrise \
  --format '{{.Name}} {{.Image}} {{.State.Status}}'
sudo podman port mailrise 8025/tcp
sudo journalctl -u apprise-api -u mailrise --since '10 minutes ago' --no-pager
sudo /usr/local/libexec/apprise-api/check-container-updates.sh
```

Retain the transaction backup and prior images until the selected observation
period has passed. Do not run broad image cleanup or `podman system prune -a`
during that window.

## Lifecycle commands

For J1-SVMF's rootful services:

```bash
# Status and logs
sudo systemctl status apprise-api mailrise
sudo journalctl -u apprise-api -u mailrise -n 100 --no-pager

# Start in dependency order
sudo systemctl start apprise-api
sudo systemctl start mailrise

# Stop in reverse dependency order
sudo systemctl stop mailrise
sudo systemctl stop apprise-api

# Controlled ordinary restart
sudo systemctl restart apprise-api
sudo systemctl restart mailrise

# Boot persistence
sudo systemctl enable apprise-api mailrise
```

Installer-generated units now specify `--pull=never`. Service start and reboot
therefore use the locally accepted tag and cannot silently move production to a
new registry image. Existing units should receive that change through a
separately reviewed unit deployment; do not rerun the installer against active
production merely to update an image.

## Why auto-update is not enabled

Podman supports registry-based auto-update and a dry-run mode for systemd-owned
containers. This deployment deliberately keeps automatic mutation disabled.
The production policy requires an exact reviewed platform digest, a
stopped-state application-data snapshot, ordered restart, and application
health acceptance. The read-only comparator can be scheduled, but applying an
update remains an authorized maintenance operation.

The controlled updater currently targets the rootful two-service production
layout. Rootless users can run the comparator as their service account, but
must use a separately reviewed rootless update procedure and `systemctl --user`.

## Production script interaction audit

| Artifact | Phase 1 interaction | Required action |
| -------- | ------------------- | --------------- |
| `check-container-updates.sh` | Registry reader used by timer | Shared lifecycle lock added |
| `update-rootful-systemd-containers.sh` | Could overlap a timer check | Exclusive lifecycle lock added |
| `install-apprise-podman.sh` | Adds fresh-host production mode | Installs full lifecycle set; leaves timer disabled |
| `health-check.sh`, `logs.sh` | Read-only operational inspection | No change |
| `backup-config.sh` | Backs up app config, not timer state | Timer state has separate retention |
| `examples/send-notification.sh` | General interactive helper | Timer uses bounded dedicated payloads |
| `podman-compose.yml` | Alternative without Mailrise/systemd ownership | Timer unsupported; no change |

Uptime Kuma is reserved as a future external monitor for complete host,
filesystem, or local notification-stack loss. It is not part of this timer or
the durable-apprise pilot.
