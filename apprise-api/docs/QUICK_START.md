# Apprise API Quick Start

Deploy Apprise API on Debian 12 with Podman and send a notification.

## Prerequisites

- Debian 12 on a supported architecture
- A regular user with `sudo` access
- Internet access to Docker Hub
- Approximately 2 GB of free disk space

Run commands from the `apprise-api` directory unless stated otherwise.

## Rootful Installation with Systemd

Create the system service:

```bash
sudo ./install-apprise-podman.sh --systemd
```

The installer creates the service but does not enable or start it. Enable and
start it explicitly:

```bash
sudo systemctl enable --now apprise-api
```

For Apprise API plus Mailrise:

```bash
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

sudo systemctl enable --now apprise-api mailrise
```

## Rootless Installation with Systemd

Install the rootless prerequisites, then run the installer as your regular user:

```bash
sudo apt-get update
sudo apt-get install -y podman uidmap slirp4netns fuse-overlayfs ca-certificates curl jq

./install-apprise-podman.sh --rootless --systemd
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
```

For rootless Apprise API plus Mailrise:

```bash
./install-apprise-podman.sh \
  --rootless \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

systemctl --user enable --now apprise-api mailrise
loginctl enable-linger "$USER"
```

See [ROOTLESS.md](ROOTLESS.md) for subordinate-ID checks, service management,
and rootless troubleshooting.

## Direct Container Installation

Omit `--systemd` to start directly managed containers immediately:

```bash
# Rootful
sudo ./install-apprise-podman.sh

# Rootless
./install-apprise-podman.sh --rootless
```

## Verify the Deployment

Check API health:

```bash
curl -fsS -H 'Accept: application/json' http://localhost:8000/status | jq .
```

For a rootful deployment, inspect containers with root privileges:

```bash
sudo podman ps
sudo podman logs apprise-api
sudo systemctl status apprise-api
```

For a rootless deployment:

```bash
podman ps
podman logs apprise-api
systemctl --user status apprise-api
```

The built-in Apprise API configuration interface is available at
`http://localhost:8000/`. The deployed container does not provide Swagger at
`/docs` or ReDoc at `/redoc`.

## Send a Stateless Notification

A stateless request supplies its notification URL in the request:

```bash
curl -X POST http://localhost:8000/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Hello Apprise",
    "body": "My first notification",
    "type": "info",
    "urls": ["discord://webhook_id/webhook_token"]
  }'
```

## Create and Use a Configuration Key

Apprise API stores persistent configurations under a key. A key is not an
Apprise tag; tags are optional filters defined inside an Apprise configuration.

Create the key `home-alerts`:

```bash
curl -X POST http://localhost:8000/add/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"urls":["discord://webhook_id/webhook_token"]}'
```

Send through it:

```bash
curl -X POST http://localhost:8000/notify/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Disk Alert",
    "body": "Root partition is 95% full",
    "type": "failure"
  }'
```

Review its URLs without exposing secrets:

```bash
curl 'http://localhost:8000/json/urls/home-alerts?privacy=1' | jq .
```

Delete the saved key when it is no longer needed:

```bash
curl -X POST http://localhost:8000/del/home-alerts
```

## Use the Notification Helper

The helper sends through an existing configuration key:

```bash
./examples/send-notification.sh home-alerts "Hello" "Test body" info
```

The installer includes `jq`, which this helper requires. For a custom API host
or port, set `APPRISE_URL`:

```bash
APPRISE_URL=http://apprise.home.arpa:8000 \
  ./examples/send-notification.sh home-alerts "Hello" "Test body" info
```

## Use Mailrise

Mailrise listens on host port `8025` by default. Configure local SMTP clients
with:

- SMTP host: the server IP or local DNS name
- SMTP port: `8025`, or the value supplied with `--mailrise-port`
- Connection security: none, unless manually enabled in `mailrise.conf`
- Authentication: none, unless manually enabled in `mailrise.conf`
- Recipient: `notify@mailrise.xyz` for the default `notify` config

Test the default recipient locally:

```bash
printf 'Subject: Mailrise test\n\nHello from Mailrise\n' > /tmp/mailrise-test.eml

curl -v smtp://127.0.0.1:8025 \
  --mail-from notifications@home.arpa \
  --mail-rcpt notify@mailrise.xyz \
  --upload-file /tmp/mailrise-test.eml
```

See [CONFIGURATION.md](CONFIGURATION.md#configure-local-applications-and-services)
for local DNS, SMTP client settings, and recipient routing.

## Common Operations

### Logs

```bash
# Rootful
sudo journalctl -u apprise-api -f
sudo journalctl -u mailrise -f

# Rootless
journalctl --user -u apprise-api -f
journalctl --user -u mailrise -f
```

### Health Check

```bash
# Rootful
sudo ./scripts/health-check.sh --mailrise

# Rootless
./scripts/health-check.sh --mailrise
```

### Backup

```bash
./scripts/backup-config.sh "$HOME/backups"
```

If rootful and rootless data both exist, select the intended source explicitly:

```bash
APPRISE_DATA_DIR="$HOME/.apprise" \
MAILRISE_CONFIG_FILE="$HOME/.config/mailrise/mailrise.conf" \
  ./scripts/backup-config.sh "$HOME/backups"
```

## Documentation

- [Project overview](../README.md)
- [Installation guide](INSTALLATION.md)
- [Configuration guide](CONFIGURATION.md)
- [Rootless guide](ROOTLESS.md)
- [Troubleshooting guide](TROUBLESHOOTING.md)
- [API examples](../examples/api-examples.json)
- [Notification URL examples](../examples/notification-urls.txt)

## Support

- Report problems with this repository's documentation, scripts,
  configurations, or examples to the
  [homelab-notification issue tracker](https://github.com/Racerx323/homelab-notification/issues).
- Report upstream Apprise API defects to the
  [Apprise API issue tracker](https://github.com/caronc/apprise-api/issues).
- Report notification-service or Apprise URL defects to the
  [Apprise issue tracker](https://github.com/caronc/apprise/issues).
- Report upstream Mailrise defects to the
  [Mailrise issue tracker](https://github.com/YoRyan/mailrise/issues).
