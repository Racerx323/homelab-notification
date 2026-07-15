# Apprise API Configuration Guide

Complete reference for configuring Apprise API after installation.

## Table of Contents

- [Environment Variables](#environment-variables)
- [Persistent Data Storage](#persistent-data-storage)
- [Network Configuration](#network-configuration)
- [Mailrise SMTP Relay](#mailrise-smtp-relay)
- [SSL/TLS Setup](#ssltls-setup)
- [Advanced Configuration](#advanced-configuration)
- [Notification Service Integration](#notification-service-integration)
- [Configuration Keys and Tags](#configuration-keys-and-tags)

## Environment Variables

### Setting Environment Variables

#### For Systemd Service

Edit `/etc/systemd/system/apprise-api.service`:

```bash
sudo nano /etc/systemd/system/apprise-api.service
```

Add environment variables in the `[Service]` section:

```ini
[Service]
Environment="APPRISE_STORAGE_DIR=/config"
Environment="APPRISE_STORAGE_MODE=auto"
```

Then reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

#### For Direct Podman Run

```bash
sudo podman run -d \
  --name apprise-api \
  --user 1000:1000 \
  -p 8000:8000 \
  -e APPRISE_STORAGE_DIR=/config \
  -v /var/lib/apprise/config:/config \
  -v /var/lib/apprise/plugin:/plugin \
  -v /var/lib/apprise/attach:/attach \
  docker.io/caronc/apprise:latest
```

### Common Environment Variables

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `APPRISE_IMAGE` | `docker.io/caronc/apprise:latest` | Apprise API image |
| `APPRISE_STORAGE_DIR` | `/config` | Storage directory inside the container |
| `APPRISE_STORAGE_MODE` | `auto` | Apprise storage mode |
| `APPRISE_STATEFUL_MODE` | `simple` | Stateful mode |
| `APPRISE_WORKER_COUNT` | `1` | Worker count |
| `APPRISE_ADMIN` | `y` | Enable admin mode |
| `APPRISE_INTERPRET_EMOJIS` | `yes` | Interpret emoji shortcodes |
| `PUID`, `PGID` | `1000`, `1000` rootful | Container user/group |
| `APPRISE_USER` | derived | Override container user as `uid:gid` |
| `TZ` | OS timezone | Container timezone |

## Persistent Data Storage

### Default Configuration

- **Rootful data directory**: `/var/lib/apprise`
- **Rootless data directory**: `~/.apprise`
- **Container paths**: `/config`, `/plugin`, `/attach`
- **Permissions**: `755` (rwxr-xr-x)

When Mailrise is enabled:

- **System Mailrise Config**: `/etc/mailrise.conf`
- **Rootless Mailrise Config**: `~/.config/mailrise/mailrise.conf`
- **Existing Config Behavior**: existing configs are preserved; generated starter configs are written to `mailrise.conf.example`
- **Container Path**: `/etc/mailrise.conf`

### Directory Structure

```text
/var/lib/apprise/
├── config/                 # Apprise configuration and state
├── plugin/                 # Custom Apprise plugins
└── attach/                 # Attachments
```

### Backup and Restore

#### Backup Configuration

```bash
BACKUP_DIR="$HOME/backups"
mkdir -p "$BACKUP_DIR"
./scripts/backup-config.sh "$BACKUP_DIR"
```

#### Restore Configuration

```bash
cd "$HOME/backups"
sha256sum -c apprise-backup-YYYYMMDD_HHMMSS.tar.gz.sha256

sudo systemctl stop mailrise apprise-api
sudo tar xzf apprise-backup-YYYYMMDD_HHMMSS.tar.gz -C /
sudo systemctl start apprise-api mailrise
```

Omit Mailrise commands when it is not installed. For rootless restore, stop and
start user services with `systemctl --user` and extract as the rootless user.

### Change Storage Location

To use a different storage directory:

1. Create the new directory:

    ```text
    sudo mkdir -p /mnt/apprise-storage/{config,plugin,attach}
    sudo chmod 755 /mnt/apprise-storage /mnt/apprise-storage/{config,plugin,attach}
    ```

2. Migrate data:

    ```text
    sudo cp -r /var/lib/apprise/* /mnt/apprise-storage/
    sudo chown -R 1000:1000 /mnt/apprise-storage
    ```

3. Update systemd service:

    ```text
    sudo nano /etc/systemd/system/apprise-api.service
    ```

4. Change the volume line:

    ```text
    ExecStart=/usr/bin/podman run --rm \
    --name apprise-api \
    --user 1000:1000 \
    -p 8000:8000 \
    -v /mnt/apprise-storage/config:/config \
    -v /mnt/apprise-storage/plugin:/plugin \
    -v /mnt/apprise-storage/attach:/attach \
    docker.io/caronc/apprise:latest
    ```

5. Reload and restart:

    ```text
    sudo systemctl daemon-reload
    sudo systemctl restart apprise-api
    ```

## Network Configuration

### Access from Network

#### Find Pi's IP Address

```bash
# Get all network interfaces
hostname -I

# or using ip command
ip addr show

# or using ifconfig (if installed)
ifconfig
```

#### Test Network Connectivity

```bash
# From another machine on network
curl http://SERVER_IP:8000/status

# From the Pi itself
curl http://localhost:8000/status
```

### Firewall Configuration

#### If using UFW

```bash
# Allow port 8000
sudo ufw allow 8000/tcp

# Allow from specific IP only
sudo ufw allow from 192.168.1.100 to any port 8000

# Check rules
sudo ufw status
```

#### If using Firewalld

```text
# Add port
sudo firewall-cmd --permanent --add-port=8000/tcp

# Reload firewall
sudo firewall-cmd --reload

# Check rules
sudo firewall-cmd --list-all
```

### Port Configuration

Regenerate the service with the desired host port so all installer-managed
runtime options remain intact:

```bash
sudo ./install-apprise-podman.sh --systemd --port 9000
sudo systemctl restart apprise-api
curl http://localhost:9000/status
```

Include the original Mailrise options when Mailrise is installed.

### Shared Podman Network for Mailrise

When the installer runs with `--mailrise`, it creates a Podman network named `notify-network`:

```bash
# Rootful
sudo podman network inspect notify-network

# Rootless
podman network inspect notify-network
```

Both containers join this network so Mailrise can call Apprise API by container name:

```text
apprise://apprise-api:8000/your_apprise_config_key
```

The Apprise API container always listens on port `8000` inside the container. The `--port` option only changes the host port mapping.

## Mailrise SMTP Relay

Mailrise is optional and installed with:

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
sudo systemctl enable --now apprise-api mailrise
```

Rootless:

```bash
./install-apprise-podman.sh --rootless --systemd --mailrise --mailrise-apprise-key your_apprise_config_key
systemctl --user enable --now apprise-api mailrise
```

### Generated Mailrise Configuration

System-wide installs write `/etc/mailrise.conf`. Rootless installs write `~/.config/mailrise/mailrise.conf`. If the config already exists, the installer leaves it unchanged and writes the generated starter config as `mailrise.conf.example` in the same directory.

Default generated config:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
```

Send email to `notify@mailrise.xyz` to use this config. You can edit the config name or add more configs later:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
  critical:
    urls:
      - apprise://apprise-api:8000/critical-alerts
```

Restart Mailrise after editing:

```bash
sudo systemctl restart mailrise

# Rootless
systemctl --user restart mailrise
```

### Mailrise Ports

Mailrise listens on container port `8025`. Use `--mailrise-port` to change the host port:

```bash
sudo ./install-apprise-podman.sh --systemd --mailrise --mailrise-port 2525 --mailrise-apprise-key your_apprise_config_key
```

Point SMTP clients at:

- Host: `SERVER_IP`
- Port: `8025` or your `--mailrise-port`
- Recipient: `notify@mailrise.xyz`

### Configure Local Applications and Services

Configure each self-hosted application as an SMTP client of Mailrise. A local
DNS name is optional, but it is easier to remember and allows the Mailrise host
to move to a different IP address without reconfiguring every application.

#### Optional Local DNS Record

Add a record to your local DNS server, such as Pi-hole, AdGuard Home, or your
router:

| Setting | Example |
| ---------- | --------- |
| Record type | `A` |
| Name | `mailrise.home.arpa` |
| Address | `10.0.0.10` |

Use an `A` record when pointing directly to the Mailrise server's IP address.
If the server already has a DNS name, you can instead create a `CNAME` that
points `mailrise.home.arpa` to that hostname. Ensure the sending applications
use your local DNS server and can resolve the name. Otherwise, use the server's
IP address directly.

`home.arpa` is reserved for home-network naming. You can instead use a
subdomain of a domain you own if your local DNS server resolves it internally.

Mailrise accepts SMTP connections directly and converts messages to Apprise
notifications; it does not deliver these messages to public email providers.
An internal-only deployment therefore does not require public MX, SPF, DKIM,
or DMARC records. The `mailrise.xyz` recipient domain is a Mailrise routing
convention and does not need to resolve to your server.

#### SMTP Client Settings

Use the following settings in each sending application:

| Setting | Value |
| ---------- | --------- |
| SMTP server or host | `mailrise.home.arpa` or the Mailrise server's IP address |
| SMTP port | `8025` or your `--mailrise-port` value |
| Connection security | None |
| SMTP authentication | None |
| Username and password | Leave blank |
| From address | Any valid address, such as `notifications@home.arpa` |
| Recipient | `<config-name>@mailrise.xyz` |

These security settings match the default generated Mailrise configuration.
If you manually enable TLS or SMTP authentication in `mailrise.conf`, configure
the application to use the same settings. Do not use basic authentication over
an unencrypted connection.

The recipient username selects a key under `configs` in `mailrise.conf`. For
example, this configuration defines the recipients `notify@mailrise.xyz` and
`critical@mailrise.xyz`:

```yaml
configs:
  notify:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
  critical:
    urls:
      - apprise://apprise-api:8000/critical-alerts
```

If a config key is a complete email address, send to that exact address instead
of appending `@mailrise.xyz`.

Because the default SMTP listener has no encryption or authentication, expose
the Mailrise port only to trusted hosts and networks. If applications are on a
different VLAN, allow the configured SMTP port through the firewall between
that VLAN and the Mailrise server.

### Test Mailrise with curl

Create a simple email body:

```bash
printf 'Subject: Mailrise curl test\n\nHello from curl via Mailrise\n' > /tmp/mailrise-test.eml
```

Test the default generated Mailrise account:

```bash
curl -v smtp://127.0.0.1:8025 \
  --mail-from test@localhost \
  --mail-rcpt notify@mailrise.xyz \
  --upload-file /tmp/mailrise-test.eml
```

For a custom Mailrise host port, change the SMTP URL:

```bash
curl -v smtp://127.0.0.1:2525 \
  --mail-from test@localhost \
  --mail-rcpt notify@mailrise.xyz \
  --upload-file /tmp/mailrise-test.eml
```

If you changed the config name to a full address, use that exact address:

```yaml
configs:
  notify@localhost:
    urls:
      - apprise://apprise-api:8000/your_apprise_config_key
```

```bash
curl -v smtp://127.0.0.1:8025 \
  --mail-from test@localhost \
  --mail-rcpt notify@localhost \
  --upload-file /tmp/mailrise-test.eml
```

Successful SMTP delivery shows `250 OK` after `MAIL FROM`, `RCPT TO`, and `DATA`. Then check delivery logs:

```bash
# Rootful
sudo podman logs --tail 50 mailrise
sudo podman logs --tail 50 apprise-api

# Rootless
podman logs --tail 50 mailrise
podman logs --tail 50 apprise-api
```

### Mailrise Service Management

```bash
sudo systemctl enable --now mailrise
sudo systemctl status mailrise
sudo journalctl -u mailrise -f
```

Rootless:

```bash
systemctl --user enable mailrise
systemctl --user start mailrise
systemctl --user status mailrise
journalctl --user -u mailrise -f
```

## SSL/TLS Setup

### Option 1: Reverse Proxy with Nginx

1. Install nginx:

    ```text
    sudo apt-get install -y nginx
    ```

2. Create SSL certificate:

    ```text
    sudo apt-get install -y certbot python3-certbot-nginx
    sudo certbot certonly --standalone -d your-domain.com
    ```

3. Configure nginx reverse proxy:

    ```text
    sudo nano /etc/nginx/sites-available/apprise
    ```

4. Add configuration:

    ```nginx
    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

        # Security headers
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;

        location / {
            proxy_pass http://localhost:8000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$host$request_uri;
    }
    ```

5. Enable site and test:

    ```text
    sudo ln -s /etc/nginx/sites-available/apprise /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx
    ```

### Option 2: Caddy Reverse Proxy

1. Install Caddy:

    ```bash
    sudo apt-get install -y caddy
    ```

2. Configure Caddyfile:

    ```bash
    sudo nano /etc/caddy/Caddyfile
    ```

    Add:

    ```text
    your-domain.com {
        reverse_proxy localhost:8000 {
            header_up X-Forwarded-For {http.request.remote}
            header_up X-Forwarded-Proto {http.request.proto}
            header_up Host {http.request.host}
        }
    }
    ```

3. Enable and restart:

    ```bash
    sudo systemctl enable caddy
    sudo systemctl restart caddy
    ```

## Advanced Configuration

### Enable Debug Logging

```bash
# Edit systemd service
sudo nano /etc/systemd/system/apprise-api.service

# Add to [Service] section:
# Environment="APPRISE_DEBUG=1"

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart apprise-api

# View debug logs
sudo journalctl -u apprise-api -f
```

### Memory and CPU Limits

Limit resource usage in systemd:

```bash
sudo nano /etc/systemd/system/apprise-api.service
```

Add to `[Service]` section:

```text
# Memory limit: 512MB
MemoryLimit=512M

# CPU quota: 50% of one core
CPUQuota=50%
```

Reload and restart:

```text
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

Monitor rootful resources:

```text
sudo podman stats apprise-api
```

### Increase Request Size

Edit systemd service to increase max content length:

```text
Environment="MAX_CONTENT_LENGTH=10485760"  # 10MB
```

### Custom Plugins

To add custom notification plugins:

1. Create plugins directory:

    ```text
    mkdir -p /var/lib/apprise/plugin
    ```

2. Add plugin files. The installer mounts this directory at `/plugin`.

3. Restart service:

    ```text
    sudo systemctl restart apprise-api
    ```

## Notification Service Integration

### Discord

```json
{
  "urls": ["discord://webhook_id/webhook_token"]
}
```

Get webhook from Discord server → Settings → Webhooks

### Telegram

```json
{
  "urls": ["tgram://bot-token/chat-id"]
}
```

Create bot with BotFather on Telegram

### Slack

```json
{
  "urls": ["slack://token-a/token-b/token-c"]
}
```

Get tokens from Slack app configuration

### Email (SMTP)

```json
{
  "urls": ["mailto://user:google_app_password@gmail.com"]
}
```

Gmail requires 2-Step Verification and an App Password. For Microsoft 365,
use the Microsoft Graph-based `o365://` service rather than basic SMTP:

```text
o365://TenantID:AccountEmail/ClientID/ClientSecret/TargetEmail
```

### PagerDuty

```json
{
  "urls": ["pagerduty://integration-key"]
}
```

### Webhooks (Generic)

```json
{
  "urls": ["json://your-webhook-url"]
}
```

### Multiple Services (Configuration Key)

```bash
curl -X POST http://localhost:8000/add/alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token",
      "tgram://bot-token/chat-id",
      "slack://token-a/token-b/token-c"
    ]
  }'
```

## Configuration Keys and Tags

Apprise API stores persistent configurations under a key. The key appears in
paths such as `/add/{KEY}` and `/notify/{KEY}`. Apprise tags are optional
filters defined inside the saved configuration; they are not API keys.

### Create a Configuration Key

```bash
curl -X POST http://localhost:8000/add/critical-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "discord://webhook_id/webhook_token"
    ]
  }'
```

### List URLs and Tags for a Key

```bash
curl 'http://localhost:8000/json/urls/critical-alerts?privacy=1'
```

### Send to a Configuration Key

```bash
curl -X POST http://localhost:8000/notify/critical-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Critical system event detected",
    "title": "Critical Alert",
    "type": "failure"
  }'
```

### Retrieve a Saved Configuration

```bash
curl -X POST http://localhost:8000/get/critical-alerts
```

### Delete a Configuration Key

```bash
curl -X POST http://localhost:8000/del/critical-alerts
```

### Notification Types

When sending notifications, use these types for icons:

- `info` - Information (default)
- `success` - Successful action
- `warning` - Warning
- `failure` - Error/failure

Example:

```bash
curl -X POST http://localhost:8000/notify \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Database backup completed",
    "title": "Backup Status",
    "type": "success",
    "urls": ["discord://webhook_id/webhook_token"]
  }'
```

## Performance Tuning

### For Raspberry Pi 5

Use a systemd drop-in so installer-generated units can be refreshed safely:

```bash
sudo systemctl edit apprise-api
```

Example drop-in:

```ini
[Service]
MemoryMax=768M
CPUQuota=100%
```

Apply the change:

```bash
sudo systemctl daemon-reload
sudo systemctl restart apprise-api
```

### Monitor Performance

```bash
# Real-time stats
sudo podman stats apprise-api

# Check container resource limits
sudo podman inspect apprise-api --format '{{json .HostConfig.Resources}}' | jq .
```

---

See [the project overview](../README.md) and
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) for additional guidance.
