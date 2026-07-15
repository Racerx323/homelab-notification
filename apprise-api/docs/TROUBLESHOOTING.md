# Apprise API Troubleshooting Guide

Diagnose the Apprise API and optional Mailrise deployment supplied by this
repository.

## Command Conventions

Rootful Podman containers belong to root. Rootless containers belong to the
user that installed them:

| Deployment | Podman commands | Systemd commands |
| ---------- | --------------- | ---------------- |
| Rootful | `sudo podman ...` | `sudo systemctl ...` |
| Rootless | `podman ...` | `systemctl --user ...` |

Examples in general sections show rootful commands. Remove `sudo` from Podman
commands and use `systemctl --user` or `journalctl --user` for rootless
deployments.

## Table of Contents

- [Initial Diagnostics](#initial-diagnostics)
- [Installation and Container Issues](#installation-and-container-issues)
- [Systemd Issues](#systemd-issues)
- [Network and API Issues](#network-and-api-issues)
- [Persistent Storage Issues](#persistent-storage-issues)
- [Notification Delivery](#notification-delivery)
- [Mailrise Issues](#mailrise-issues)
- [Backup and Restore](#backup-and-restore)
- [Resource Issues](#resource-issues)
- [Reporting Issues](#reporting-issues)

## Initial Diagnostics

Start with the supported status endpoint:

```bash
curl -v -H 'Accept: application/json' http://localhost:8000/status
```

A healthy API returns HTTP `200`. Its JSON status also reports whether
persistent storage and attachment directories are writable.

Rootful deployment:

```bash
sudo podman ps -a
sudo podman logs --tail 100 apprise-api
sudo systemctl status apprise-api
sudo journalctl -u apprise-api -n 100
```

Rootless deployment:

```bash
podman ps -a
podman logs --tail 100 apprise-api
systemctl --user status apprise-api
journalctl --user -u apprise-api -n 100
```

## Installation and Container Issues

### Container Is Missing After `--systemd` Installation

The installer creates service units but does not enable or start them. This is
expected. Start the generated service:

```bash
# Rootful
sudo systemctl enable --now apprise-api

# Rootless
systemctl --user enable --now apprise-api
```

If Mailrise was installed, include `mailrise` in the command.

### Container Exits Immediately

```bash
sudo podman ps -a
sudo podman logs apprise-api
sudo podman inspect apprise-api --format '{{json .State}}' | jq .
```

Common causes include an unwritable bind mount, a port conflict, or invalid
container options. Check the API host port:

```bash
sudo ss -ltnp | awk '$4 ~ /:8000$/ {print}'
sudo podman port apprise-api
```

Use the configured custom port instead of `8000` when applicable.

### Image Pull Failure

The installer uses fully qualified image names and does not require an
unqualified registry search configuration:

```bash
sudo podman pull docker.io/caronc/apprise:latest
sudo podman pull docker.io/yoryan/mailrise:latest
```

Do not add the obsolete `[registries.search]` format to
`/etc/containers/registries.conf`. Current registry configuration uses TOML,
but no registry change is needed for these fully qualified images.

For TLS or certificate errors:

```bash
sudo apt-get update
sudo apt-get install -y --reinstall ca-certificates
sudo update-ca-certificates --fresh
curl -I https://registry-1.docker.io/v2/
```

An HTTP `401 Unauthorized` response from the registry endpoint confirms that
the TLS connection succeeded; registry authentication is a separate concern.

### Short Image Names Fail

Use the complete image name rather than changing global registry policy:

```bash
podman pull docker.io/caronc/apprise:latest
```

### Rootless Podman Fails Before Starting a Container

Check required packages and subordinate IDs:

```bash
command -v podman newuidmap newgidmap
getent subuid "$USER"
getent subgid "$USER"
podman info --debug
```

Rootless Podman does not require membership in a `podman` group. If subordinate
IDs are missing, an administrator must assign unique ranges. After changing
them, stop the user's containers and run:

```bash
podman system migrate
```

### Rootless Bind Mount Is Not Writable

Verify the generated container uses `keep-id` and the data belongs to the
current user:

```bash
podman inspect apprise-api --format '{{.HostConfig.UsernsMode}} {{.Config.User}}'
ls -ld ~/.apprise ~/.apprise/config ~/.apprise/plugin ~/.apprise/attach
```

The namespace mode should be `keep-id`. Back up locally modified service files,
then re-run the current installer to regenerate an older unit.

### Avoid Broad Podman Cleanup

Do not use `podman system prune -a` as a routine fix; it affects every unused
container and image owned by that Podman user. Remove only this deployment's
known resources after reviewing them:

```bash
sudo podman ps -a --filter name=apprise-api --filter name=mailrise
sudo podman rm -f apprise-api mailrise
```

Ignore a missing Mailrise container when Mailrise is not installed.

## Systemd Issues

### Service Does Not Start

Rootful:

```bash
sudo systemctl status -l apprise-api
sudo journalctl -u apprise-api -n 100 -p warning
sudo systemd-analyze verify /etc/systemd/system/apprise-api.service
```

Rootless:

```bash
systemctl --user status -l apprise-api
journalctl --user -u apprise-api -n 100 -p warning
systemd-analyze --user verify ~/.config/systemd/user/apprise-api.service
```

Use `systemctl`, not `sysctl`, to manage services. Podman runs containers
without a persistent daemon, so restarting `podman.service` is not a general
container repair step.

### Service Is Not Enabled After Installation

This is intentional. Enable it after reviewing the generated unit:

```bash
# Rootful
sudo systemctl enable --now apprise-api

# Rootless
systemctl --user enable --now apprise-api
loginctl enable-linger "$USER"
```

### Rootless Service Stops After Logout

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
systemctl --user enable --now apprise-api
```

## Network and API Issues

### API Cannot Be Reached Locally

```bash
curl -v http://localhost:8000/status
sudo podman port apprise-api
sudo ss -ltnp | awk '$4 ~ /:8000$/ {print}'
```

If a custom host port was installed, use that port. The container always listens
on `8000` internally.

### API Cannot Be Reached from Another Host

```bash
hostname -I
sudo ufw status
sudo ufw allow 8000/tcp
```

From the client:

```bash
curl -v http://SERVER_IP:8000/status
```

Restrict firewall access to trusted networks whenever possible.

### Local DNS Name Does Not Resolve

Use a local DNS record such as `apprise.home.arpa` or the server IP directly:

```bash
getent hosts apprise.home.arpa
curl http://apprise.home.arpa:8000/status
```

The `.local` suffix is reserved for multicast DNS. Use `home.arpa` for ordinary
home-network DNS records unless an existing local naming plan is already in
place.

### Status Returns a Storage Error

Request the JSON response and inspect the detail fields:

```bash
curl -sS -H 'Accept: application/json' http://localhost:8000/status | jq .
```

Continue with [Persistent Storage Issues](#persistent-storage-issues) if
configuration or attachment paths are not writable.

### Notification Request Returns HTTP 400

A stateless `/notify` request requires a body and normally one or more URLs:

```bash
curl -X POST http://localhost:8000/notify \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Test",
    "body": "Test message",
    "urls": ["discord://webhook_id/webhook_token"]
  }'
```

A persistent request uses an existing configuration key:

```bash
curl -X POST http://localhost:8000/notify/home-alerts \
  -H 'Content-Type: application/json' \
  -d '{"title":"Test","body":"Test message"}'
```

HTTP `204` from `/notify/{KEY}` means the key was not found or contained no
usable configuration.

### Current API Endpoint Reference

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

The standard container serves its configuration interface at `/`. It does not
serve Swagger at `/docs` or ReDoc at `/redoc`.

## Persistent Storage Issues

### Rootful Permissions

The installer runs Apprise as `1000:1000` by default, or the value configured
through `APPRISE_USER`, `PUID`, and `PGID`. Do not change the storage to
`root:root` unless the container is also configured to run as root.

Inspect the configured user:

```bash
sudo podman inspect apprise-api --format '{{.Config.User}}'
sudo ls -ld /var/lib/apprise /var/lib/apprise/{config,plugin,attach}
```

For the default installer settings, repair ownership with:

```bash
sudo chown 1000:1000 /var/lib/apprise
sudo chown -R 1000:1000 \
  /var/lib/apprise/config \
  /var/lib/apprise/plugin \
  /var/lib/apprise/attach
sudo chmod 755 /var/lib/apprise /var/lib/apprise/{config,plugin,attach}
```

Replace `1000:1000` with the configured container user when customized.

### Rootless Permissions

```bash
ls -ld ~/.apprise ~/.apprise/{config,plugin,attach}
podman inspect apprise-api --format '{{.HostConfig.UsernsMode}} {{.Config.User}}'
```

The directories should belong to the current user and the namespace should use
`keep-id`.

### Configuration Appears Missing

Confirm the mounts and query the expected key:

```bash
sudo podman inspect apprise-api \
  --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
curl -X POST http://localhost:8000/get/home-alerts
curl 'http://localhost:8000/json/urls/home-alerts?privacy=1' | jq .
```

There is no supported `/urls` endpoint that lists every key. Back up the entire
persistent data directory rather than treating an API response as a complete
backup.

## Notification Delivery

### API Accepts a Request but No Notification Arrives

1. Review the Apprise API logs.
2. Inspect the saved key with privacy enabled.
3. Test the notification URL with the Apprise CLI.
4. Confirm DNS and outbound HTTPS access from the host.

```bash
sudo podman logs --tail 100 apprise-api
curl 'http://localhost:8000/json/urls/home-alerts?privacy=1' | jq .
sudo podman exec apprise-api apprise -vv \
  -t 'Test' \
  -b 'Test body' \
  'discord://webhook_id/webhook_token'
```

### Email URL Does Not Work

Current Apprise email schemes are `mailto://` and `mailtos://`, not
`mailsmtp://` or `email://`.

Gmail requires 2-Step Verification and an App Password for this use case:

```text
mailto://user:google_app_password@gmail.com
```

Microsoft 365 basic SMTP authentication is not a portable default. Use the
Microsoft Graph-based Office 365 plugin:

```text
o365://TenantID:AccountEmail/ClientID/ClientSecret/TargetEmail
```

Consult the current Apprise service documentation before placing credentials
in a URL.

## Mailrise Issues

### Mailrise Unit Does Not Exist

Re-run the installer with Mailrise enabled, then explicitly start the units:

```bash
sudo ./install-apprise-podman.sh \
  --systemd \
  --mailrise \
  --mailrise-apprise-key your_apprise_config_key

sudo systemctl enable --now apprise-api mailrise
```

For rootless mode, add `--rootless`, remove `sudo`, and use
`systemctl --user enable --now`.

### Mailrise Cannot Reach Apprise API

```bash
sudo podman ps
sudo podman network inspect notify-network
sudo podman logs --tail 100 mailrise
sudo cat /etc/mailrise.conf
```

The generated URL must use the container name and internal port:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
```

Do not substitute the server hostname or a custom published API port in this
container-to-container URL.

For rootless mode, omit `sudo` and inspect
`~/.config/mailrise/mailrise.conf`.

### Existing Mailrise Configuration Was Not Replaced

This is intentional. The installer preserves the existing file and writes a
starter example:

```bash
# Rootful
sudo cat /etc/mailrise.conf.example

# Rootless
cat ~/.config/mailrise/mailrise.conf.example
```

Merge desired changes manually and restart Mailrise.

### SMTP Client Cannot Connect

```bash
sudo podman port mailrise
sudo ss -ltnp | awk '$4 ~ /:8025$/ {print}'
sudo systemctl status mailrise
```

Use the host port supplied through `--mailrise-port`; the default is `8025`.
The default generated Mailrise configuration uses no TLS or authentication, so
expose it only to trusted networks.

### Test Mailrise

```bash
printf 'Subject: Mailrise test\n\nHello from Mailrise\n' > /tmp/mailrise-test.eml

curl -v smtp://127.0.0.1:8025 \
  --mail-from notifications@home.arpa \
  --mail-rcpt notify@mailrise.xyz \
  --upload-file /tmp/mailrise-test.eml
```

The recipient must match a config key. A username-only key such as `notify`
maps to `notify@mailrise.xyz`; `notify@localhost` is a different address.

## Backup and Restore

### Create and Verify a Backup

```bash
./scripts/backup-config.sh "$HOME/backups"
cd "$HOME/backups"
sha256sum -c apprise-backup-YYYYMMDD_HHMMSS.tar.gz.sha256
tar tzf apprise-backup-YYYYMMDD_HHMMSS.tar.gz
```

### Rootful Restore

Stop services before extracting over live state:

```bash
sudo systemctl stop mailrise apprise-api
sudo tar xzf apprise-backup-YYYYMMDD_HHMMSS.tar.gz -C /
sudo systemctl start apprise-api mailrise
curl -fsS http://localhost:8000/status
```

### Rootless Restore

```bash
systemctl --user stop mailrise apprise-api
tar xzf apprise-backup-YYYYMMDD_HHMMSS.tar.gz -C /
systemctl --user start apprise-api mailrise
curl -fsS http://localhost:8000/status
```

Omit Mailrise commands when it is not installed. Inspect archive paths before
restoring to a different user or host.

## Resource Issues

Inspect actual usage before changing limits:

```bash
free -h
df -h
sudo podman stats --no-stream apprise-api
sudo du -sh /var/lib/apprise
```

For rootless mode, omit `sudo` and inspect `~/.apprise`. If a systemd resource
limit is added manually, validate and restart the unit. Remember that re-running
the installer regenerates its service file, so record local overrides in a
systemd drop-in:

```bash
sudo systemctl edit apprise-api
```

Example drop-in:

```ini
[Service]
MemoryMax=768M
CPUQuota=100%
```

Then apply it:

```bash
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

## Reporting Issues

Before sharing diagnostics, remove or mask passwords, tokens, webhook URLs,
Apprise URLs, Mailrise routing keys, IP addresses, and other private data.
`podman inspect`, service units, and Mailrise configuration can contain
sensitive values.

Collect a minimal, redacted report:

```bash
uname -a
cat /etc/os-release
podman --version
curl -sS -H 'Accept: application/json' http://localhost:8000/status
sudo podman ps -a
sudo podman logs --tail 100 apprise-api
sudo systemctl status apprise-api
```

Use rootless command variants when applicable.

- Problems with this repository's documentation, scripts, configurations, or
  examples belong in the
  [homelab-notification issue tracker](https://github.com/Racerx323/homelab-notification/issues).
- Upstream Apprise API defects belong in the
  [Apprise API issue tracker](https://github.com/caronc/apprise-api/issues).
- Notification-service or Apprise URL defects belong in the
  [Apprise issue tracker](https://github.com/caronc/apprise/issues).
- Upstream Mailrise defects belong in the
  [Mailrise issue tracker](https://github.com/YoRyan/mailrise/issues).

## Additional Resources

- [Project overview](../README.md)
- [Installation guide](INSTALLATION.md)
- [Quick start](QUICK_START.md)
- [Configuration guide](CONFIGURATION.md)
- [Rootless guide](ROOTLESS.md)
- [Apprise API upstream documentation](https://github.com/caronc/apprise-api)
- [Apprise service documentation](https://appriseit.com/services/)
- [Podman documentation](https://podman.io/docs)
