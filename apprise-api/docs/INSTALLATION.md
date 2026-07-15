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

Copy the entire `apprise-api` directory when possible. The installer itself is
self-contained, but the directory also provides health, backup, logging, and
notification helper scripts.

## Installer Modes

The installer supports two container-management modes:

- Without `--systemd`, it starts directly managed containers immediately.
- With `--systemd`, it writes service units but deliberately does not enable or
  start them. This allows the generated units to be reviewed first.

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

- Pulls `docker.io/caronc/apprise:latest`
- Pulls `docker.io/yoryan/mailrise:latest`
- Creates the Podman network `notify-network`
- Creates `/etc/mailrise.conf`, or writes `/etc/mailrise.conf.example` when an
  existing config must be preserved
- Routes the generated Mailrise config through
  `apprise://apprise-api:8000/your_apprise_config_key`

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

The deployment uses `latest`, so review upstream release notes before updating.
Re-run the same installer command to pull the current image and regenerate the
service, then restart it:

```bash
sudo ./install-apprise-podman.sh --systemd
sudo systemctl restart apprise-api
```

Include the original Mailrise options when Mailrise is installed.

## Uninstall

### Preserve Persistent Data

```bash
sudo systemctl disable --now apprise-api
sudo systemctl disable --now mailrise
sudo rm -f /etc/systemd/system/apprise-api.service
sudo rm -f /etc/systemd/system/mailrise.service
sudo systemctl daemon-reload

sudo podman rm -f apprise-api mailrise
sudo podman network rm notify-network
```

Ignore commands for components that were not installed. This preserves
`/var/lib/apprise` and `/etc/mailrise.conf`.

### Complete Removal

Create and verify a backup first. Then, in addition to the preceding commands:

```bash
sudo podman rmi docker.io/caronc/apprise:latest
sudo podman rmi docker.io/yoryan/mailrise:latest
sudo rm -rf /var/lib/apprise
sudo rm -f /etc/mailrise.conf /etc/mailrise.conf.example
```

These commands remove only this deployment's named containers, network, images,
and data. They do not prune unrelated Podman resources.

## Next Steps

- [Quick start](QUICK_START.md)
- [Configuration guide](CONFIGURATION.md)
- [Rootless guide](ROOTLESS.md)
- [Troubleshooting guide](TROUBLESHOOTING.md)
- [API examples](../examples/api-examples.json)
