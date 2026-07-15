# Homelab Notification Services

![License](https://badgen.net/github/license/Racerx323/homelab-notification)
![Last commit](https://badgen.net/github/last-commit/Racerx323/homelab-notification)
[![Open issues](https://badgen.net/github/open-issues/Racerx323/homelab-notification)](https://github.com/Racerx323/homelab-notification/issues?q=is%3Aissue%20state%3Aopen)
[![Pull requests](https://badgen.net/github/prs/Racerx323/homelab-notification)](https://github.com/Racerx323/homelab-notification/pulls)
<!-- markdownlint-disable MD013 MD033 -->
<a href="https://app.thecoderegistry.com/verify/vault/a2422c00-1258-4462-998d-c93bc5d54e4c" target="_blank" rel="noopener noreferrer">
  <img src="https://thecoderegistryprod.blob.core.windows.net/public-web/verification-badges/level-1/vault/a2422c00-1258-4462-998d-c93bc5d54e4c/default-style_1-2ff3a6964bbc.png?v=1784054836" alt="The Code Registry Verification Badge" width="100" />
</a>
<!-- markdownlint-enable MD013 MD033 -->

Deployment documentation, scripts, and configuration examples for centralized
homelab notifications.

## About the Project

The repository provides a maintained Apprise API deployment for Debian 12 with
Podman. It supports rootful and rootless containers, system and user systemd
services, persistent storage, helper scripts, and an optional Mailrise SMTP
relay for applications that can send email but do not support Apprise directly.

The `email/` directory also reserves provider-specific scaffolding for future
Mailgun and SMTP2GO configurations. Those directories currently contain
placeholders, not ready-to-deploy provider configurations.

## Included Services

- **[Apprise API](../apprise-api/README.md):** A centralized REST API for
  sending notifications through Apprise-supported services.
- **[Mailrise](../apprise-api/docs/CONFIGURATION.md#configure-local-applications-and-services):**
  An optional SMTP-to-Apprise relay included with the Apprise API installer.
- **[Mailgun scaffolding](../email/Mailgun/):** Reserved directories for future
  Mailgun configuration, scripts, and templates.
- **[SMTP2GO scaffolding](../email/SMTP2GO/):** Reserved directories for future
  SMTP2GO configuration, scripts, and templates.

## Project Structure

```text
homelab-notification/
├── .github/
│   ├── README.md
│   ├── CONTRIBUTING.md
│   ├── SECURITY.md
│   └── ISSUE_TEMPLATE/
├── apprise-api/
│   ├── README.md
│   ├── install-apprise-podman.sh
│   ├── podman-compose.yml
│   ├── configuration/
│   │   └── mailrise.conf
│   ├── docs/
│   │   ├── INDEX.md
│   │   ├── QUICK_START.md
│   │   ├── INSTALLATION.md
│   │   ├── CONFIGURATION.md
│   │   ├── ROOTLESS.md
│   │   └── TROUBLESHOOTING.md
│   ├── examples/
│   │   ├── api-examples.json
│   │   ├── notification-urls.txt
│   │   └── send-notification.sh
│   └── scripts/
│       ├── backup-config.sh
│       ├── health-check.sh
│       └── logs.sh
├── email/
│   ├── Mailgun/
│   │   ├── configs/
│   │   ├── scripts/
│   │   └── templates/
│   └── SMTP2GO/
│       ├── configs/
│       ├── scripts/
│       └── templates/
└── LICENSE.md
```

## Apprise API Quick Start

Run commands from the repository root.

### Rootful Systemd Service

```bash
cd apprise-api
sudo ./install-apprise-podman.sh --systemd
sudo systemctl enable --now apprise-api
curl -fsS -H 'Accept: application/json' http://localhost:8000/status | jq .
```

The installer creates systemd units but does not enable or start them. Review
the generated unit before running the explicit `enable --now` command.

### Rootless Systemd Service

```bash
cd apprise-api
./install-apprise-podman.sh --rootless --systemd
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
curl -fsS -H 'Accept: application/json' http://localhost:8000/status | jq .
```

Install the rootless prerequisites first as described in the
[rootless guide](../apprise-api/docs/ROOTLESS.md).

### Apprise API with Mailrise

```bash
cd apprise-api
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

sudo systemctl enable --now apprise-api mailrise
```

Mailrise listens on host port `8025` by default. Local applications select a
Mailrise route by sending to a recipient such as `notify@mailrise.xyz`. See
[Configure Local Applications and Services](../apprise-api/docs/CONFIGURATION.md#configure-local-applications-and-services)
for DNS, SMTP client, routing, and network-security guidance.

The Apprise API configuration interface is available at
`http://localhost:8000/`. The standard container does not expose Swagger at
`/docs` or ReDoc at `/redoc`.

## Send a Test Notification

A stateless request supplies an Apprise notification URL in the payload:

```bash
curl -X POST http://localhost:8000/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Hello from Apprise",
    "body": "Test notification",
    "urls": ["discord://webhook_id/webhook_token"]
  }'
```

For persistent configurations, add a configuration key and send through it:

```bash
curl -X POST http://localhost:8000/add/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"urls":["discord://webhook_id/webhook_token"]}'

curl -X POST http://localhost:8000/notify/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"title":"Alert","body":"System alert"}'
```

The value after `/add` or `/notify` is a configuration key. Apprise tags are
optional filters within a configuration and are not API keys.

## Documentation

- [Apprise API overview](../apprise-api/README.md)
- [Documentation index](../apprise-api/docs/INDEX.md)
- [Quick start](../apprise-api/docs/QUICK_START.md)
- [Installation guide](../apprise-api/docs/INSTALLATION.md)
- [Configuration and Mailrise guide](../apprise-api/docs/CONFIGURATION.md)
- [Rootless Podman guide](../apprise-api/docs/ROOTLESS.md)
- [Troubleshooting guide](../apprise-api/docs/TROUBLESHOOTING.md)

## Support

Route issues according to which project owns the affected material:

- Problems with information, documentation, scripts, configurations, examples,
  or other files provided by this repository belong in the
  [homelab-notification issue tracker](https://github.com/Racerx323/homelab-notification/issues/new/choose).
- Upstream Apprise API defects belong in the
  [Apprise API issue tracker](https://github.com/caronc/apprise-api/issues).
- Notification-service, Apprise URL, or core Apprise defects belong in the
  [Apprise issue tracker](https://github.com/caronc/apprise/issues).
- Upstream Mailrise SMTP processing or routing defects belong in the
  [Mailrise issue tracker](https://github.com/YoRyan/mailrise/issues).

If a repository-provided script or configuration causes an Apprise API or
Mailrise problem, report it to `homelab-notification`.

## Security

Do not report security vulnerabilities through a public issue. Review the
[Security Policy](SECURITY.md) for supported versions and confidential
reporting instructions.

## Contributing

Contributions to scripts, documentation, configuration examples, and provider
scaffolding are welcome. Review the [contributing guidelines](CONTRIBUTING.md),
then use an appropriate issue template or open a focused pull request.

## License

This repository is licensed under the GNU General Public License v3.0. See
[LICENSE.md](../LICENSE.md). Apprise API, Apprise, Mailrise, Podman, and other
integrated services retain their respective upstream licenses.
