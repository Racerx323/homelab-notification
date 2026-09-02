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

Run the comparator as the owner of the Podman storage:

```bash
# Rootful production
sudo ./scripts/check-container-updates.sh

# Rootless installation
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

### Install the timer

Installing and enabling the timer grants recurring registry reads and
conditional notification delivery. Review those effects before running these
commands. Use the comparator, notifier, and updater from the same reviewed
repository revision; do not enable the timer while an older updater without
the exclusive lifecycle lock remains in the production procedure.

Before overwriting an existing timer deployment, copy its two units, two helper
scripts, and configuration to a new root-only operation backup. On a first
installation, verify that those targets do not already exist. Then install:

```bash
sudo install -d -m 0755 /usr/local/libexec/apprise-api
sudo install -m 0755 \
  scripts/check-container-updates.sh \
  scripts/notify-container-updates.sh \
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

Confirm the installed schedule without triggering a notification:

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

If this replaced an earlier timer revision, restore all five backed-up files
and reload systemd instead of leaving mixed versions. The two helper scripts
and `/etc/apprise-container-update-check.conf` may remain inert after a
first-install rollback. Removing them is safe after review, but deleting
`/var/lib/apprise-container-lifecycle` is a separate evidence-purge decision.
Disabling the timer does not affect `apprise-api` or `mailrise`.

## Controlled rootful update

The production updater accepts only exact `sha256:` platform digests printed by
the comparator. It never accepts `latest` as an update input.

Use a new, descriptive backup path for every operation. This example updates
only Apprise API because the observed Mailrise digest is already current:

```bash
sudo ./scripts/update-rootful-systemd-containers.sh \
  --preflight-only \
  --backup-dir /var/backups/apprise-container-update/2026-09-02-apprise \
  --apprise-digest sha256:2ca897b667ebb76c467f5585dc7eb5fc2cb37a8189ed3208b41a52fa8f89dd55

sudo ./scripts/update-rootful-systemd-containers.sh \
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
sudo ./scripts/check-container-updates.sh
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
| `install-apprise-podman.sh` | Supports rootless, direct, and systemd modes | Do not implicitly install the rootful timer |
| `health-check.sh`, `logs.sh` | Read-only operational inspection | No change |
| `backup-config.sh` | Backs up app config, not timer state | Timer state has separate retention |
| `examples/send-notification.sh` | General interactive helper | Timer uses bounded dedicated payloads |
| `podman-compose.yml` | Alternative without Mailrise/systemd ownership | Timer unsupported; no change |

Uptime Kuma is reserved as a future external monitor for complete host,
filesystem, or local notification-stack loss. It is not part of this timer or
the durable-apprise pilot.
