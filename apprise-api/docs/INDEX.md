# Apprise API Deployment Documentation

Documentation and utilities for deploying Apprise API with Podman on Debian 12,
with optional rootless operation and Mailrise SMTP relay.

## Start Here

- [Quick start](QUICK_START.md) — deploy and send a first notification
- [Installation guide](INSTALLATION.md) — complete rootful and rootless setup
- [Project overview](../README.md) — package contents and design

## Core Documentation

### [Configuration Guide](CONFIGURATION.md)

- Environment variables and persistent storage
- Rootful and rootless paths
- Network and firewall configuration
- Mailrise installation and routing
- Local DNS and SMTP client settings for self-hosted applications
- TLS reverse proxies and systemd resource controls
- Apprise API configuration keys and tags
- Notification-service examples

Go directly to
[Configure Local Applications and Services](CONFIGURATION.md#configure-local-applications-and-services)
to connect SMTP-capable applications to Mailrise.

### [Rootless Podman Guide](ROOTLESS.md)

- Rootless packages and subordinate-ID requirements
- `keep-id` bind-mount behavior
- User systemd services and lingering
- Rootless Mailrise setup
- Storage, backup, restore, and remote deployment

### [Troubleshooting Guide](TROUBLESHOOTING.md)

- Rootful versus rootless command conventions
- Container, systemd, image-pull, and permission issues
- Current Apprise API endpoints
- Network, notification, and Mailrise diagnostics
- Safe backup, restore, cleanup, and issue reporting

## Installer

The main installer is
[install-apprise-podman.sh](../install-apprise-podman.sh).

### Rootful Systemd Installation

```bash
sudo ./install-apprise-podman.sh --systemd
sudo systemctl enable --now apprise-api
```

### Rootful Installation with Mailrise

```bash
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

sudo systemctl enable --now apprise-api mailrise
```

### Rootless Systemd Installation

```bash
./install-apprise-podman.sh --rootless --systemd
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
```

The installer creates systemd units but does not enable or start them. The
explicit `enable --now` step is required.

## Utility Scripts

### [logs.sh](../scripts/logs.sh)

```bash
# Rootful containers
sudo ./scripts/logs.sh --follow
sudo ./scripts/logs.sh --mailrise --follow

# Rootless containers or user journal
./scripts/logs.sh --follow
./scripts/logs.sh --user --mailrise --follow
```

### [health-check.sh](../scripts/health-check.sh)

```bash
# Rootful container inspection
sudo ./scripts/health-check.sh --mailrise

# Rootless container inspection
./scripts/health-check.sh --mailrise
```

### [backup-config.sh](../scripts/backup-config.sh)

```bash
./scripts/backup-config.sh "$HOME/backups"
```

The backup script creates a compressed archive and matching SHA-256 checksum.
Stop managed services and verify the checksum before restoring.

## Examples

- [API examples](../examples/api-examples.json) — current request methods,
  endpoints, and payloads
- [Notification URL examples](../examples/notification-urls.txt) — placeholder
  Apprise service URLs
- [Notification helper](../examples/send-notification.sh) — send through an
  existing configuration key

Example:

```bash
./examples/send-notification.sh home-alerts "Title" "Body" success
```

## API Quick Reference

| Method | Endpoint | Purpose |
| ------ | -------- | ------- |
| `GET` | `/status` | Health and persistent-storage status |
| `POST` | `/notify` | Stateless notification using supplied URLs |
| `POST` | `/add/{KEY}` | Save a persistent configuration |
| `POST` | `/notify/{KEY}` | Notify through a saved configuration |
| `POST` | `/get/{KEY}` | Retrieve a saved configuration |
| `POST` | `/del/{KEY}` | Delete a saved configuration |
| `GET` | `/json/urls/{KEY}?privacy=1` | List URLs and tags while masking secrets |
| `GET` | `/details` | List supported Apprise services |
| `GET` | `/metrics` | Prometheus metrics |

The standard container serves its configuration interface at
`http://localhost:8000/`. It does not expose Swagger at `/docs` or ReDoc at
`/redoc`.

## Container and Service Commands

Rootful containers belong to root:

```bash
sudo podman ps
sudo podman logs -f apprise-api
sudo systemctl status apprise-api
sudo journalctl -u apprise-api -f
```

Rootless containers belong to the installing user:

```bash
podman ps
podman logs -f apprise-api
systemctl --user status apprise-api
journalctl --user -u apprise-api -f
```

## Package Layout

```text
apprise-api/
├── README.md
├── install-apprise-podman.sh
├── podman-compose.yml
├── configuration/
│   └── mailrise.conf
├── docs/
│   ├── INDEX.md
│   ├── QUICK_START.md
│   ├── INSTALLATION.md
│   ├── CONFIGURATION.md
│   ├── ROOTLESS.md
│   └── TROUBLESHOOTING.md
├── examples/
│   ├── api-examples.json
│   ├── notification-urls.txt
│   └── send-notification.sh
└── scripts/
    ├── backup-config.sh
    ├── health-check.sh
    └── logs.sh
```

## External Resources

- [Apprise API](https://github.com/caronc/apprise-api)
- [Apprise service documentation](https://appriseit.com/services/)
- [Mailrise](https://github.com/YoRyan/mailrise)
- [Podman documentation](https://podman.io/docs)

## Support

Start with the relevant installation, configuration, or troubleshooting guide.
When an issue remains, route it according to ownership.

### Where to Open an Issue

- **This deployment package:** Open an issue in the
  [homelab-notification issue tracker](https://github.com/Racerx323/homelab-notification/issues)
  for problems with information, documentation, installation or utility
  scripts, configurations, examples, and other files provided by this
  repository.
- **Apprise API:** Report upstream API application defects in the
  [Apprise API issue tracker](https://github.com/caronc/apprise-api/issues).
- **Apprise:** Report notification-service, Apprise URL, or core notification
  defects in the [Apprise issue tracker](https://github.com/caronc/apprise/issues).
- **Mailrise:** Report upstream SMTP processing or routing defects in the
  [Mailrise issue tracker](https://github.com/YoRyan/mailrise/issues).

If a problem is caused by a script or configuration supplied here, open it with
`homelab-notification` even when Apprise API or Mailrise is the affected service.

## Verification Checklist

- [ ] The appropriate rootful or rootless service is enabled and active
- [ ] `GET /status` returns HTTP `200`
- [ ] Persistent storage is writable according to the status response
- [ ] A stateless test notification succeeds
- [ ] A persistent configuration key can be added and notified
- [ ] Mailrise accepts SMTP for a configured recipient, if installed
- [ ] A backup and checksum can be created

**Last reviewed:** July 2026
