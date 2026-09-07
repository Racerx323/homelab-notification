# Apprise API Deployment for Podman

Deploy the official [Apprise API](https://github.com/caronc/apprise-api) image
on Debian 12 with Podman. The package supports rootful or rootless containers,
systemd services, persistent data, hardened runtime settings, and an optional
[Mailrise](https://github.com/YoRyan/mailrise) SMTP-to-Apprise relay.

## Features

- Official `docker.io/caronc/apprise:latest` image in flexible modes
- Optional `docker.io/yoryan/mailrise:latest` relay in flexible modes
- Rootful and rootless Podman workflows
- System and user systemd units
- Reboot-safe systemd lifecycle with PID/CID tracking and explicit cleanup
- Persistent `/config`, `/plugin`, and `/attach` storage
- Read-only container root filesystem and dropped capabilities
- Backup, health-check, logging, and notification helper scripts
- Read-only registry comparison and digest-bound systemd updates with rollback
- Optional weekly update warnings through a local saved Apprise configuration
- Failure cleanup that preserves pre-existing configuration and services
- Fresh-host production mode with exact platform digests and complete lifecycle
  artifacts

## Requirements

- Debian 12 or a compatible Debian-based system
- A supported upstream image architecture (`amd64`, `arm/v7`, or `arm64`)
- A regular user with `sudo` access for package installation or rootful mode
- Approximately 2 GB of free disk space
- Port `8000`, or a custom API host port
- Port `8025`, or a custom Mailrise host port when Mailrise is enabled

## Quick Start

Run commands from this directory.

### Reproducible Rootful Production Environment

On a fresh production host, supply reviewed platform digests rather than
installing whatever the moving `latest` tags contain:

```bash
sudo ./install-apprise-podman.sh \
  --production \
  --preflight-only \
  --production-config configs/svmf-production.env

sudo ./install-apprise-podman.sh \
  --production \
  --production-config configs/svmf-production.env
```

This creates and starts the rootful Apprise API and Mailrise systemd services,
installs the comparator, notifier, updater, notification configuration, and
timer units, and leaves the recurring timer disabled. It is fresh-host-only;
use the lifecycle updater for an existing production environment. The reviewed
configuration also fixes the container UID/GID, timezone, and Mailrise account
name instead of inheriting them from the new host. See the
[installation guide](docs/INSTALLATION.md#reproducible-production-installation)
for inputs, safety boundaries, and acceptance checks.

### Rootful Systemd Service

```bash
sudo ./install-apprise-podman.sh --systemd
sudo systemctl enable --now apprise-api
```

### Rootful Apprise API and Mailrise

```bash
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

sudo systemctl enable --now apprise-api mailrise
```

### Rootless Systemd Service

```bash
sudo apt-get update
sudo apt-get install -y \
  podman uidmap slirp4netns fuse-overlayfs ca-certificates curl jq

./install-apprise-podman.sh --rootless --systemd
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
```

Except for `--production`, the installer creates systemd units but does not
enable or start them. Review the generated units before running the explicit
`enable --now` step. Generated units require Podman's discovered storage
mounts, use container ID files, track conmon readiness through systemd
notifications, and explicitly remove containers after stopping so a stale name
cannot block the next boot.

## Verify

```bash
curl -fsS -H 'Accept: application/json' http://localhost:8000/status | jq .
```

Rootful container inspection:

```bash
sudo podman ps
sudo podman logs --tail 50 apprise-api
```

Rootless container inspection:

```bash
podman ps
podman logs --tail 50 apprise-api
```

The built-in Apprise API configuration interface is available at
`http://localhost:8000/`. The standard container does not provide Swagger at
`/docs` or ReDoc at `/redoc`.

For production image checks, updates, rollback, and service ownership, follow
the [container lifecycle guide](docs/CONTAINER_LIFECYCLE.md). Do not update an
active systemd deployment by rerunning the installer or pulling `latest`.
The same guide documents the rootful notification timer. `--production`
installs it disabled; other modes do not install it. No installer mode enables
recurring registry checks implicitly.

For copyable Apprise-only, Mailrise-only, and combined update commands, use the
[container update runbook](docs/CONTAINER_UPDATES.md).

## Send a Notification

Stateless request:

```bash
curl -X POST http://localhost:8000/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Hello from Apprise",
    "body": "Test notification",
    "urls": ["discord://webhook_id/webhook_token"]
  }'
```

Persistent configuration key:

```bash
curl -X POST http://localhost:8000/add/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"urls":["discord://webhook_id/webhook_token"]}'

curl -X POST http://localhost:8000/notify/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"title":"Alert","body":"System alert"}'
```

The value after `/add` or `/notify` is a configuration key. Apprise tags are
optional filters within a saved configuration and are not API keys.

## Installer Behavior

The installer:

1. Validates rootful or rootless privilege usage.
2. Installs rootful dependencies, including Podman, curl, and `jq`.
3. Pulls fully qualified Docker Hub image names without modifying registry
   search configuration.
4. Creates persistent data directories.
5. Uses `--userns=keep-id` for writable rootless bind mounts.
6. Creates `notify-network` and Mailrise configuration when requested.
7. Starts containers immediately in direct mode, or writes inactive systemd
   units in `--systemd` mode.

With `--production`, the installer instead requires exact reviewed platform
digests, rejects existing managed state, installs the complete rootful systemd
and lifecycle artifact set, activates and verifies both application services,
and leaves the update-check timer disabled.

Rootful data is stored in `/var/lib/apprise`; rootless data is stored in
`~/.apprise`. Rootful and rootless Podman use separate container storage.

## Mailrise

The generated Mailrise configuration routes the default recipient
`notify@mailrise.xyz` through:

```text
apprise://apprise-api:8000/your_apprise_config_key
```

Mailrise and Apprise API share the `notify-network` Podman network. The internal
Apprise API port remains `8000` even when the published host port is changed.

See
[Configure Local Applications and Services](docs/CONFIGURATION.md#configure-local-applications-and-services)
for local DNS, SMTP client settings, routing, and network security.

## Utilities

```bash
# Logs
sudo ./scripts/logs.sh --follow
sudo ./scripts/logs.sh --mailrise --follow

# Rootless logs
./scripts/logs.sh --follow

# Rootful health check
sudo ./scripts/health-check.sh --mailrise

# Rootless health check
./scripts/health-check.sh --mailrise

# Backup and checksum
./scripts/backup-config.sh "$HOME/backups"

# Notify through an existing configuration key
./examples/send-notification.sh home-alerts "Title" "Body" success
```

## Podman Compose

The included compose file provides an alternative rootful Apprise API
deployment:

```bash
sudo install -d -m 0755 -o 1000 -g 1000 \
  /var/lib/apprise/config \
  /var/lib/apprise/plugin \
  /var/lib/apprise/attach
sudo podman-compose -f podman-compose.yml up -d
```

It does not include Mailrise. Use the installer when Mailrise or generated
systemd units are required.

## Package Layout

```text
apprise-api/
├── README.md
├── install-apprise-podman.sh
├── podman-compose.yml
├── configs/
│   ├── container-update-check.conf.example
│   ├── mailrise.conf.example
│   └── svmf-production.env
├── docs/
│   ├── INDEX.md
│   ├── QUICK_START.md
│   ├── CONTAINER_LIFECYCLE.md
│   ├── CONTAINER_UPDATES.md
│   ├── INSTALLATION.md
│   ├── CONFIGURATION.md
│   ├── ROOTLESS.md
│   └── TROUBLESHOOTING.md
├── examples/
│   ├── api-examples.json
│   ├── notification-urls.txt
│   └── send-notification.sh
├── scripts/
    ├── backup-config.sh
    ├── check-container-updates.sh
    ├── health-check.sh
    ├── logs.sh
    ├── notify-container-updates.sh
    └── update-rootful-systemd-containers.sh
├── templates/
│   ├── apprise-container-update-check.service
│   └── apprise-container-update-check.timer
└── tests/
    ├── container-update-notification-policy.sh
    ├── container-update-policy.sh
    └── systemd-lifecycle-regression.sh
```

## Documentation

- [Documentation index](docs/INDEX.md)
- [Quick start](docs/QUICK_START.md)
- [Installation guide](docs/INSTALLATION.md)
- [Configuration guide](docs/CONFIGURATION.md)
- [Rootless guide](docs/ROOTLESS.md)
- [Troubleshooting guide](docs/TROUBLESHOOTING.md)
- [Production container lifecycle](docs/CONTAINER_LIFECYCLE.md)
- [Container update runbook](docs/CONTAINER_UPDATES.md)

## Support

- Problems with this repository's documentation, scripts, configurations, or
  examples belong in the
  [homelab-notification issue tracker](https://github.com/Racerx323/homelab-notification/issues).
- Upstream Apprise API defects belong in the
  [Apprise API issue tracker](https://github.com/caronc/apprise-api/issues).
- Notification-service or Apprise URL defects belong in the
  [Apprise issue tracker](https://github.com/caronc/apprise/issues).
- Upstream Mailrise defects belong in the
  [Mailrise issue tracker](https://github.com/YoRyan/mailrise/issues).

## License

See [LICENSE.md](../LICENSE.md) for this repository's license. Apprise API,
Apprise, Mailrise, and Podman retain their respective upstream licenses.
