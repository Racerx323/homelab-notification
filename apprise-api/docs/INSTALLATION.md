# Apprise API Installation Guide

Install Apprise API, with optional Mailrise SMTP relay, on Debian 12 using
Podman. Examples assume a Raspberry Pi 5, but the upstream image also supports
`amd64`, `arm/v7`, and `arm64`.

## Prerequisites

- Debian 12 or a compatible Debian-based system
- A regular user with `sudo` access
- Internet access to Docker Hub
- Approximately 2 GB of free disk space
- Port `8000` available for Apprise API
- Port `8025` available if Mailrise is enabled

Check the system before installation:

```bash
cat /etc/os-release
uname -m
df -h
free -h
```

Copy the entire reviewed `apprise-api` directory. Flexible modes can run from
the installer alone, but `--production` requires the repository configuration,
lifecycle scripts, and unit templates. The directory also provides interactive
health, backup, and logging helpers.

## Reproducible Production Installation

Use `--production` to create the complete rootful systemd environment on a
fresh host. This mode:

- requires exact reviewed ARM64 platform digests for both images;
- installs Apprise API and Mailrise with the lifecycle-compatible canonical
  local tags;
- creates and enables both application services;
- installs the comparator, notifier, rollback-capable updater, notification
  configuration, timer units, and the narrow netavark lock path;
- validates service files, container architecture, HTTP health, Mailrise port
  publication, and enabled service state; and
- leaves `apprise-container-update-check.timer` disabled so recurring registry
  access and notifications remain a separate authorization.

It fails closed if any managed data, configuration, unit, helper, container, or
network already exists. It is not an upgrade or repair command. Restore data
only after completing and validating a fresh installation, following the
documented stopped-service restore procedure.

### Production Artifact Inventory

| Desired-state source | Installed result | Mode or state |
| -------------------- | ---------------- | ------------- |
| Installer unit generators | `/etc/systemd/system/apprise-api.service` and `mailrise.service` | `0644`, enabled and active |
| Installer directory setup | `/var/lib/apprise/{config,plugin,attach}` | `0755`, container UID/GID |
| `MAILRISE_APPRISE_CONFIG_KEY` | `/etc/mailrise.conf` | `0644`, root-owned |
| `scripts/check-container-updates.sh` | `/usr/local/libexec/apprise-api/check-container-updates.sh` | `0755`, root-owned |
| `scripts/notify-container-updates.sh` | `/usr/local/libexec/apprise-api/notify-container-updates.sh` | `0755`, root-owned |
| `scripts/update-rootful-systemd-containers.sh` | `/usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh` | `0755`, root-owned |
| `configs/container-update-check.conf.example` plus the selected config key | `/etc/apprise-container-update-check.conf` | `0600`, root-owned |
| `templates/apprise-container-update-check.*` | `/etc/systemd/system/apprise-container-update-check.*` | `0644`, timer disabled |
| Netavark compatibility setup | `/etc/containers/networks/netavark.lock` | regular file, `0644`, root-owned |
| `configs/svmf-production.env` | Image content, container identity, timezone, and Mailrise routing inputs | immutable reviewed values |

The installer creates the `notify-network` Podman network and verifies both
application services. Repository utilities such as interactive logs, backup,
and health wrappers remain in the reviewed deployment directory; systemd does
not call them at runtime.

If production installation fails after host mutation begins, the failure trap
disables the application units and removes the managed units, helpers, network,
generated Mailrise configuration, and newly created `/var/lib/apprise` data.
Downloaded OS packages and exact image blobs remain as reusable host cache;
the installer does not attempt a risky package downgrade or image prune.

The reviewed J1-SVMF desired state is stored in
[`configs/svmf-production.env`](../configs/svmf-production.env). It contains no
notification URLs or credentials. Update an image digest in that file only
after the exact platform image is accepted in production. The registry
comparator on an existing ARM64 deployment prints the required
`REMOTE_PLATFORM_DIGEST` values. Do not record a tag or manifest-list digest.

From the complete reviewed `apprise-api` directory staged on the new host:

```bash
sudo ./install-apprise-podman.sh \
  --production \
  --preflight-only \
  --production-config configs/svmf-production.env
```

Require `PREFLIGHT_OK`. This phase validates the configuration, repository
artifacts, privilege policy, and absence of managed production targets. It does
not install packages, contact a registry, write host files, or create Podman or
systemd objects.

Run the installation with the identical desired-state file:

```bash
sudo ./install-apprise-podman.sh \
  --production \
  --production-config configs/svmf-production.env
```

The parser accepts only `APPRISE_PLATFORM_DIGEST`,
`MAILRISE_PLATFORM_DIGEST`, `MAILRISE_APPRISE_CONFIG_KEY`, `APPRISE_USER`,
`TZ`, and `MAILRISE_CONFIG_NAME`; it does not source or execute the file. The
first three values may instead be provided explicitly with
`--apprise-digest`, `--mailrise-digest`, and `--mailrise-apprise-key`.
Environment-specific `APPRISE_USER`, `TZ`, and `MAILRISE_CONFIG_NAME` values
must then be exported for that invocation. Prefer a reviewed configuration file
so all six inputs remain versioned together.

`--production` implies `--systemd` and `--mailrise`; do not add them. The
installer requires the production ports `8000` and `8025`, the canonical image
names, and the documented Apprise runtime policy so the installed updater and
health checks remain compatible. The non-placeholder
`--mailrise-apprise-key` value is written to both Mailrise routing and the
disabled update-check notifier configuration.

Validate the resulting environment:

```bash
sudo systemctl is-active apprise-api mailrise
sudo systemctl is-enabled apprise-api mailrise
timer_state="$(sudo systemctl is-enabled apprise-container-update-check.timer 2>/dev/null || true)"
printf 'Update-check timer state: %s\n' "$timer_state"
test "$timer_state" = disabled
curl -fsS http://127.0.0.1:8000/status
sudo podman inspect apprise-api mailrise \
  --format '{{.Name}} {{.Image}} {{.State.Status}} {{.ImageName}}'
sudo stat -c '%a %U:%G %n' \
  /usr/local/libexec/apprise-api/check-container-updates.sh \
  /usr/local/libexec/apprise-api/notify-container-updates.sh \
  /usr/local/libexec/apprise-api/update-rootful-systemd-containers.sh
sudo /usr/local/libexec/apprise-api/check-container-updates.sh
```

Require active and enabled application services, a disabled update-check timer,
HTTP success, two running containers, `755 root:root` for all three helpers,
the configured container user and environment, exact running image IDs, and a
successful comparator result. A comparator exit `10` means the exact
installation remains reproducible but a newer candidate is available for
separate review; it is not an installation failure.

This mode pins application content and generated deployment artifacts. Debian
package versions still come from the host's configured APT repositories; use a
separately managed Debian snapshot or golden image when operating-system-level
bit-for-bit reproduction is required.

Saved Apprise notification URLs are runtime data under `/var/lib/apprise` and
may contain credentials. They are intentionally not stored in this repository
or accepted through the privileged installer. Restore that directory from a
verified backup, or create the saved key named by
`MAILRISE_APPRISE_CONFIG_KEY`, before testing real notification delivery. The
installer proves infrastructure health, not delivery through an external
notification provider.

## Installer Modes

The installer supports two container-management modes:

- Without `--systemd`, it starts directly managed containers immediately.
- With `--systemd`, it writes service units but deliberately does not enable or
  start them. This allows the generated units to be reviewed first.
- With `--production`, it performs the fresh-host rootful systemd installation
  described above and activates only the two application services.

It also supports two privilege modes:

- Rootful commands use `sudo` and store data in `/var/lib/apprise`.
- Rootless commands run as a regular user and store data in `~/.apprise`.

Do not run `--rootless` with `sudo`.

## Rootful Installation

### Direct Container Management

Install dependencies and start Apprise API immediately:

```bash
sudo ./install-apprise-podman.sh
```

Manage this root-owned container with `sudo podman`:

```bash
sudo podman ps
sudo podman logs -f apprise-api
sudo podman restart apprise-api
```

### Systemd Service

Create the service:

```bash
sudo ./install-apprise-podman.sh --systemd
```

Review and validate the generated unit:

```bash
sudo systemctl cat apprise-api
sudo systemd-analyze verify /etc/systemd/system/apprise-api.service
```

Then enable and start it:

```bash
sudo systemctl enable --now apprise-api
```

The service is written to `/etc/systemd/system/apprise-api.service`.

The generated unit follows Podman 4.3's systemd lifecycle pattern: it requires
the graph and run storage paths reported by `podman info`, tracks conmon
readiness with `Type=notify`, records the exact container in a CID file, and
uses `ExecStopPost` to remove that container. `--replace` provides a final
startup recovery path if an abrupt power loss left the prior container record
behind.

The optional weekly image-check notification timer is installed, but not
enabled, by `--production`. Flexible rootful, rootless, and direct-container
installations do not install it. No installer mode silently enables recurring
registry access or notification behavior. Follow
[Weekly update notification timer](CONTAINER_LIFECYCLE.md#weekly-update-notification-timer)
after the rootful Apprise API and Mailrise services are accepted.

The timer service retains `ProtectSystem=full` and grants Podman write access
only to `/etc/containers/networks/netavark.lock`. This is required by rootful
Podman 4.3.1 even during read-only inspection; it does not make registry or
network configuration writable. See
[Podman netavark lock compatibility](CONTAINER_LIFECYCLE.md#podman-netavark-lock-compatibility).

## Installation with Mailrise

Create Apprise API and Mailrise system services:

```bash
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key
```

Review and start both units:

```bash
sudo systemd-analyze verify \
  /etc/systemd/system/apprise-api.service \
  /etc/systemd/system/mailrise.service

sudo systemctl enable --now apprise-api mailrise
```

This installation:

- Pulls the moving `docker.io/caronc/apprise:latest` tag
- Pulls the moving `docker.io/yoryan/mailrise:latest` tag
- Creates the Podman network `notify-network`
- Creates `/etc/mailrise.conf`, or writes `/etc/mailrise.conf.example` when an
  existing config must be preserved
- Routes the generated Mailrise config through
  `apprise://apprise-api:8000/your_apprise_config_key`
- Generates reboot-safe units with explicit CID-based stop and removal actions

This flexible installation is not digest-reproducible. Use `--production` for
a new production host.

Mailrise uses the Apprise API container name and internal port `8000`. A custom
Apprise host port does not change this internal URL.

## Custom Ports

Change the Apprise API host port:

```bash
sudo ./install-apprise-podman.sh --systemd --port 8080
sudo systemctl enable --now apprise-api
```

Change the Mailrise SMTP host port:

```bash
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-port 2525 \
  --mailrise-apprise-key your_apprise_config_key

sudo systemctl enable --now apprise-api mailrise
```

## Rootless Installation

Install rootless prerequisites:

```bash
sudo apt-get update
sudo apt-get install -y \
  podman \
  uidmap \
  slirp4netns \
  fuse-overlayfs \
  ca-certificates \
  curl \
  jq
```

Verify subordinate UID and GID ranges exist for the current user:

```bash
getent subuid "$USER"
getent subgid "$USER"
podman info
```

Create and start a rootless service:

```bash
./install-apprise-podman.sh --rootless --systemd
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
```

For rootless Mailrise:

```bash
./install-apprise-podman.sh \
  --rootless \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

systemctl --user enable --now apprise-api mailrise
loginctl enable-linger "$USER"
```

See [ROOTLESS.md](ROOTLESS.md) for the complete rootless workflow.

## Verify Installation

### API Health

Use the supported health endpoint:

```bash
curl -fsS -H 'Accept: application/json' http://localhost:8000/status | jq .
```

For a custom host port, replace `8000` in the URL.

### Container and Service Status

Rootful:

```bash
sudo podman ps
sudo podman logs --tail 50 apprise-api
sudo systemctl status apprise-api

# If Mailrise is installed
sudo podman logs --tail 50 mailrise
sudo systemctl status mailrise
```

Rootless:

```bash
podman ps
podman logs --tail 50 apprise-api
systemctl --user status apprise-api

# If Mailrise is installed
podman logs --tail 50 mailrise
systemctl --user status mailrise
```

After a reboot, confirm both service units are active and no exited deployment
container is retaining either managed name:

```bash
# Rootful
sudo systemctl is-active apprise-api mailrise
sudo podman ps -a --filter name=apprise-api --filter name=mailrise

# Rootless
systemctl --user is-active apprise-api mailrise
podman ps -a --filter name=apprise-api --filter name=mailrise
```

### Network Access

Find the server IP and test from another host:

```bash
hostname -I
curl -fsS http://SERVER_IP:8000/status
```

The built-in configuration interface is at `http://SERVER_IP:8000/`. The
standard deployment does not expose Swagger at `/docs` or ReDoc at `/redoc`.

## Configure Notifications

### Stateless Request

```bash
curl -X POST http://localhost:8000/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Apprise API Test",
    "body": "This is a test notification",
    "urls": ["discord://webhook_id/webhook_token"]
  }'
```

### Persistent Configuration Key

Save URLs under a key:

```bash
curl -X POST http://localhost:8000/add/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token",
      "mailto://user:app-password@gmail.com"
    ]
  }'
```

Send through that key:

```bash
curl -X POST http://localhost:8000/notify/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"title":"Home Alert","body":"Test message"}'
```

Inspect the key while masking credentials:

```bash
curl 'http://localhost:8000/json/urls/home-alerts?privacy=1' | jq .
```

Delete it:

```bash
curl -X POST http://localhost:8000/del/home-alerts
```

The path component after `/add`, `/notify`, and `/del` is a configuration key,
not an Apprise tag. Tags are optional filters contained within a configuration.

## Back Up and Restore

Create a backup and checksum:

```bash
./scripts/backup-config.sh "$HOME/backups"
```

Before restoring, stop the managed services and verify the checksum:

```bash
cd "$HOME/backups"
sha256sum -c apprise-backup-YYYYMMDD_HHMMSS.tar.gz.sha256

sudo systemctl stop mailrise apprise-api
sudo tar xzf apprise-backup-YYYYMMDD_HHMMSS.tar.gz -C /
sudo systemctl start apprise-api mailrise
```

Omit Mailrise commands when it is not installed. Rootless restore instructions
are in [ROOTLESS.md](ROOTLESS.md#backup-and-restore).

## Update an Installation

Do not rerun the installer or pull `latest` directly against an active
production installation. Use the read-only digest comparator and controlled,
rollback-capable procedure in the
[production container lifecycle guide](CONTAINER_LIFECYCLE.md). The
`--production` mode is fresh-host-only and deliberately rejects an existing
installation.

## Uninstall

### Preserve Persistent Data

```bash
sudo systemctl disable --now apprise-api
sudo systemctl disable --now mailrise
sudo systemctl disable --now apprise-container-update-check.timer
sudo rm -f /etc/systemd/system/apprise-api.service
sudo rm -f /etc/systemd/system/mailrise.service
sudo rm -f \
  /etc/systemd/system/apprise-container-update-check.service \
  /etc/systemd/system/apprise-container-update-check.timer
sudo rm -f /etc/apprise-container-update-check.conf
sudo rm -f /usr/local/libexec/apprise-api/{check-container-updates.sh,notify-container-updates.sh,update-rootful-systemd-containers.sh}
sudo rmdir /usr/local/libexec/apprise-api 2>/dev/null || true
sudo systemctl daemon-reload

sudo podman rm -f apprise-api mailrise
sudo podman network rm notify-network
```

Ignore commands for components that were not installed. This preserves
`/var/lib/apprise`, `/etc/mailrise.conf`, and the update-check evidence under
`/var/lib/apprise-container-lifecycle`. It also deliberately preserves
`/etc/containers/networks/netavark.lock`, which is a shared Podman runtime path
rather than application-owned state.

### Complete Removal

Create and verify a backup first. Then, in addition to the preceding commands:

```bash
sudo podman rmi docker.io/caronc/apprise:latest
sudo podman rmi docker.io/yoryan/mailrise:latest
sudo rm -rf /var/lib/apprise
sudo rm -rf /var/lib/apprise-container-lifecycle
sudo rm -f /etc/mailrise.conf /etc/mailrise.conf.example
```

These commands remove only this deployment's named containers, network, images,
and data. Removing `/var/lib/apprise-container-lifecycle` permanently deletes
the checker state and delivery evidence; inspect or archive it first if that
history matters. These commands do not prune unrelated Podman resources.

## Next Steps

- [Quick start](QUICK_START.md)
- [Configuration guide](CONFIGURATION.md)
- [Rootless guide](ROOTLESS.md)
- [Troubleshooting guide](TROUBLESHOOTING.md)
- [API examples](../examples/api-examples.json)
